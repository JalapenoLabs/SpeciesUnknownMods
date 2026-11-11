-- Copyright © 2026 Jalapeno Labs

-- The entity player's HUD (WBP_EntityHUD), on their own machine, along the top of the screen: the abilities top left
-- in the game's own style (icon, key, and a bar while recharging), the kill meter top centre from their link's
-- replicated state, short messages from the host's events below it, and noise pings drawn over the world. While the
-- player is the squid, the crew HUD their parked body left behind is hidden.

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")

local hud = {}

local PING_MARKER_COUNT = 12
-- ESlateVisibility
local COLLAPSED = 1
local HIDDEN = 2
local VISIBLE_NO_INPUT = 3
-- The crew character can rebuild its HUD (on respawn, after menus), so the entity's machine checks for it this often.
local CREW_HUD_CHECK_SECONDS = 0.5
-- What a respawn capsule's screen shows the entity instead of the name of the crew member who took it.
local CAPSULE_NAME_MASK = "?????"
-- How long a message stays: a second, plus 300 ms a word, and never under three seconds.
local MESSAGE_BASE_SECONDS = 1
local MESSAGE_SECONDS_PER_WORD = 0.3
local MESSAGE_MINIMUM_SECONDS = 3

local pingColorByKind = {
  Gunshot = { R = 1.0, G = 0.29, B = 0.24 },
  Footstep = { R = 0.37, G = 0.89, B = 1.0 },
  Alarm = { R = 1.0, G = 0.70, B = 0.23 },
}

-- An ability that can't be used right now (peeking outside a vent, leaving the lair before the power is on) dims.
local UNUSABLE_OPACITY = 0.35
local ultimateColor = { R = 1.0, G = 0.70, B = 0.23, A = 1 }
local frenzyColor = { R = 1.0, G = 0.29, B = 0.24, A = 1 }

-- The ability slots along the top left, by their prefix in WBP_EntityHUD: the host command whose cooldown the bar
-- shows, and the key shown in the box. The keys are the game's default bindings for the input actions the squid
-- reuses (control.lua), so a player who rebinds them sees the defaults.
local abilitySlots = {
  { prefix = "Lash", command = "Attack", key = "LMB" },
  { prefix = "Leap", command = "Leap", key = "RMB" },
  { prefix = "Vent", command = "Vent", key = config.keys.vent },
  { prefix = "Peek", command = "Peek", key = "C", needsVent = true },
  { prefix = "View", key = "F" },
}

local messageByEvent = {
  Volunteered = "You'll be the entity next mission. Only you know. F8 backs out.",
  WaitingForSquid = "You're the entity. You take the squid once the crew leaves the shuttle.",
  Unvolunteered = "You're crew again.",
  VolunteerTaken = "Someone else already claimed the entity.",
  BecameEntity = "You are the entity. Hunt by sound.",
  Leashed = "Lurk in the vents until the crew turns the power on.",
  PowerRestored = "The power is on. Hunt.",
  Lost = "The crew got you. You're out of this mission.",
  KillStarted = "Got one.",
  FrenzyStarted = "FRENZY: every grab kills.",
  FrenzyPartial = "They have the weapon. Your hunger grows faster.",
  EntityModeOn = "Entity mode: ON",
  EntityModeOff = "Entity mode: OFF",
  ["Denied.Cooldown"] = "Not yet.",
  ["Denied.NoTarget"] = "Get closer to a crew member.",
  ["Denied.NoVentEntrance"] = "Stand under a vent to climb in.",
  ["Denied.NoVentExit"] = "Crawl over a vent opening to drop out.",
  ["Denied.NotInVent"] = "Peek works from inside a vent.",
  ["Denied.PowerOff"] = "The vents hold you until the power is on.",
  ["Denied.UltimateNotReady"] = "Your hunger isn't ready.",
  ["Denied.HostOnly"] = "The host turns entity mode on or off.",
  ["Denied.EntityModeOff"] = "Entity mode is off. The host can turn it on.",
}

-- Everything the HUD knows comes from the host's events in the current world; a new world starts blank and the host
-- tells this player their status again.
local function freshState(worldKey)
  return {
    worldKey = worldKey,
    isVolunteer = false,
    isEntity = false,
    message = nil,
    messageUntil = 0,
    -- A line that stays under the messages until the host's next event replaces it: the volunteer's status, or the
    -- lair's hint while the power is off.
    persistentStatus = nil,
    -- Whether the lair holds the squid in the ducts (until the power is on).
    isLeashed = false,
    nextCrewHudCheckAt = 0,
    cooldownEndsAt = {},
    pings = {},
    nextPingSlot = 1,
    widget = nil,
  }
end

local state = freshState(nil)

-- A map change (into a mission, back to the lobby or the main menu) leaves nothing of the old world's HUD behind.
-- Checked before drawing and before every host event, so an event that lands first in a new world isn't wiped.
local function syncWorld(controller)
  local worldKey = controller:GetWorld():GetAddress()
  if worldKey == state.worldKey then
    return
  end
  if state.widget and state.widget:IsValid() then
    state.widget:RemoveFromParent()
  end
  state = freshState(worldKey)
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Widget
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The widget is created on first use and again after a map change, which removes it from the viewport.
local function ensureWidget(controller)
  if state.widget and state.widget:IsValid() then
    return state.widget
  end

  local widgetClass = game.loadModClass(game.modClasses.hud)
  if not widgetClass then
    return nil
  end

  -- There is only ever one entity HUD. One already on screen was left by an earlier run of the mod: a hot reload
  -- forgets the mod's state but not its widgets (playtest 6), and the old one would sit there frozen
  for _, leftover in ipairs(FindAllOf(game.modClasses.hud.class) or {}) do
    if leftover:IsValid() then
      leftover:RemoveFromParent()
    end
  end

  local widget = StaticFindObject(game.paths.widgetLibrary):Create(controller, widgetClass, controller)
  widget:AddToViewport(50)
  for _, ability in ipairs(abilitySlots) do
    widget[ability.prefix .. "KeyText"]:SetText(FText(ability.key))
  end
  -- The ultimate is the game's Interact action, E by default
  widget.UltimateKeyText:SetText(FText("E"))
  state.widget = widget
  return widget
end

local function setText(textBlock, text)
  textBlock:SetText(FText(text))
end

local function setShown(element, shown)
  element:SetVisibility(shown and VISIBLE_NO_INPUT or HIDDEN)
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Drawing
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The ultimate: the kill meter outside full frenzy, the re-arm progress inside it.
local function drawUltimate(widget, link)
  local readiness = link.Meter
  local inFrenzy = link.Frenzy
  local ready = readiness >= 1

  widget.UltimateBar:SetPercent(readiness)
  widget.UltimateBar:SetFillColorAndOpacity(inFrenzy and frenzyColor or ultimateColor)
  setText(widget.FrenzyText, inFrenzy and "FRENZY" or "")

  local label
  if inFrenzy then
    label = ready and "FRENZY KILL READY" or "FRENZY  re-arming"
  else
    label = ready and "HEAD GRAB READY" or string.format("HEAD GRAB  %d%%", math.floor(readiness * 100))
  end
  setText(widget.UltimateText, label)

  local held = state.isLeashed and config.lair.heldMoves.Ultimate
  widget.UltimateSlot:SetRenderOpacity((ready and not held) and 1 or UNUSABLE_OPACITY)
end

-- Each ability's bar shows the cooldown draining, and hides (keeping its space) once the ability is ready.
local function drawAbilities(widget, now, inVent)
  for _, ability in ipairs(abilitySlots) do
    local remaining = ability.command and (state.cooldownEndsAt[ability.command] or 0) - now or 0
    local bar = widget[ability.prefix .. "Bar"]
    setShown(bar, remaining > 0)
    if remaining > 0 then
      bar:SetPercent(remaining / config.cooldowns[ability.command])
    end

    local held = state.isLeashed and config.lair.heldMoves[ability.command]
    local usable = not held and (inVent or not ability.needsVent)
    widget[ability.prefix .. "Slot"]:SetRenderOpacity(usable and 1 or UNUSABLE_OPACITY)
  end
end

-- Where a noise's marker goes, in widget units, and whether it is on the ring. A noise in view sits where it is, seen
-- through walls; one behind the camera or off the screen sits on a ring around the centre, in its direction, like a
-- hit indicator (straight ahead is up, behind is down).
local function pingPosition(controller, ping, viewportSize, viewportScale)
  local screen = {}
  local projected = controller:ProjectWorldLocationToScreen(ping.location, screen, false)
  if projected and screen.X >= 0 and screen.X <= viewportSize.X and screen.Y >= 0 and screen.Y <= viewportSize.Y then
    return { X = screen.X / viewportScale, Y = screen.Y / viewportScale }, false
  end

  local origin = controller.Pawn:K2_GetActorLocation()
  local bearing = math.atan(ping.location.Y - origin.Y, ping.location.X - origin.X)
  local angle = bearing - math.rad(controller:GetControlRotation().Yaw)
  local centreX, centreY = viewportSize.X / 2 / viewportScale, viewportSize.Y / 2 / viewportScale
  local radius = math.min(centreX, centreY) * config.senses.ringRadiusFraction
  return { X = centreX + math.sin(angle) * radius, Y = centreY - math.cos(angle) * radius }, true
end

-- Each ping fades over pingSeconds; louder kinds draw bigger, and ring markers bigger still so they catch the eye.
local function drawPings(widget, controller, now)
  local layoutLibrary = StaticFindObject(game.paths.widgetLayoutLibrary)
  local viewportScale = layoutLibrary:GetViewportScale(controller)
  local viewportSize = layoutLibrary:GetViewportSize(controller)

  for slot = 1, PING_MARKER_COUNT do
    local marker = widget["Ping" .. (slot - 1)]
    local ping = state.pings[slot]
    local age = ping and now - ping.bornAt or math.huge

    if age < config.senses.pingSeconds then
      local position, onRing = pingPosition(controller, ping, viewportSize, viewportScale)
      local color = pingColorByKind[ping.kind] or pingColorByKind.Alarm
      local scale = (config.senses.pingScaleByKind[ping.kind] or 1) * (onRing and config.senses.ringScale or 1)
      marker.Slot:SetPosition(position)
      marker:SetRenderScale({ X = scale, Y = scale })
      marker:SetColorAndOpacity({ R = color.R, G = color.G, B = color.B, A = 1 - age / config.senses.pingSeconds })
      marker:SetVisibility(VISIBLE_NO_INPUT)
    else
      marker:SetVisibility(HIDDEN)
    end
  end
end

-- A respawn capsule's screen names the crew member who took it, which tells the entity who can still come back. The
-- screen keeps the name in its Pseudo and writes it into TextBlock_Pseudo when the name or its step changes
-- (UMG_ScreenCapsule), so both are masked: the game's own redraws then show the mask too.
local function maskCapsuleName(capsuleScreen)
  if not capsuleScreen:IsValid() then
    return
  end
  local mask = FText(CAPSULE_NAME_MASK)
  capsuleScreen.Pseudo = mask
  capsuleScreen.TextBlock_Pseudo:SetText(mask)
end

-- The crew HUD belongs to the parked crew body, so it would stay on screen over the squid's view. It comes off the
-- screen rather than being hidden: the respawn-capsule status sets its own visibility again, and isn't reported as
-- in the viewport either, so the removal doesn't ask first (removing a widget that isn't shown does nothing).
--
-- The wall maps are blanked on the entity's screen too: they show where the mission's items are (where the crew's
-- special weapon lies), which the entity must learn by hunting, so the crew can mislead them (playtest 6). They live on
-- widget components in the world, so they're collapsed rather than lifted off a screen; for everyone else they stay.
local function hideCrewHud(now)
  if now < state.nextCrewHudCheckAt then
    return
  end
  state.nextCrewHudCheckAt = now + CREW_HUD_CHECK_SECONDS
  for _, className in ipairs(game.classNames.crewHudWidgets) do
    for _, crewWidget in ipairs(FindAllOf(className) or {}) do
      if crewWidget:IsValid() then
        crewWidget:RemoveFromParent()
      end
    end
  end
  for _, className in ipairs(game.classNames.wallMapWidgets) do
    for _, wallMap in ipairs(FindAllOf(className) or {}) do
      if wallMap:IsValid() and wallMap:GetVisibility() ~= COLLAPSED then
        wallMap:SetVisibility(COLLAPSED)
      end
    end
  end
  for _, capsuleScreen in ipairs(FindAllOf(game.classNames.capsuleScreenWidget) or {}) do
    maskCapsuleName(capsuleScreen)
  end
end

local function render()
  local controller = game.localController()
  if not controller then
    return
  end

  syncWorld(controller)
  -- Only the entity drives the squid, so driving it is proof enough: the host's BecameEntity may never arrive in this
  -- run of the mod (a hot reload on either machine forgets it, playtest 6)
  local pawn = controller.Pawn
  if not state.isEntity and pawn:IsValid() and pawn:GetClass():GetFName():ToString() == game.classNames.squid then
    state.isEntity = true
  end
  local now = game.timeSeconds(controller)
  if state.isEntity then
    hideCrewHud(now)
  end
  local hasMessage = state.message ~= nil and now < state.messageUntil
  if not state.isEntity and not state.isVolunteer and not hasMessage then
    if state.widget and state.widget:IsValid() then
      state.widget:SetVisibility(HIDDEN)
    end
    return
  end

  local widget = ensureWidget(controller)
  if not widget then
    return
  end
  widget:SetVisibility(VISIBLE_NO_INPUT)

  setText(widget.StatusText, hasMessage and state.message or state.persistentStatus or "")

  -- Before the takeover (a volunteer, or a message), only the status line shows
  local link = state.isEntity and links.own() or nil
  setShown(widget.Abilities, link ~= nil)
  setShown(widget.UltimateSlot, link ~= nil)
  if not link then
    setText(widget.UltimateText, "")
    setText(widget.FrenzyText, "")
    return
  end

  local pawn = controller.Pawn
  drawUltimate(widget, link)
  drawAbilities(widget, now, pawn:IsValid() and pawn.InVent == true)
  drawPings(widget, controller, now)
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Events from the host
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function showMessage(kind)
  local controller = game.localController()
  if not controller then
    return
  end
  local message = messageByEvent[kind]
  local _, wordCount = message:gsub("%S+", "")
  local seconds = math.max(MESSAGE_MINIMUM_SECONDS, MESSAGE_BASE_SECONDS + MESSAGE_SECONDS_PER_WORD * wordCount)
  state.message = message
  state.messageUntil = game.timeSeconds(controller) + seconds
end

-- What each host event changes beyond its message.
local stateChangeByEvent = {
  Volunteered = function()
    state.isVolunteer = true
    state.persistentStatus = messageByEvent.Volunteered
  end,
  WaitingForSquid = function()
    state.isVolunteer = true
    state.persistentStatus = messageByEvent.WaitingForSquid
  end,
  Unvolunteered = function()
    state.isVolunteer = false
    state.persistentStatus = nil
  end,
  BecameEntity = function()
    state.isEntity = true
    state.persistentStatus = nil
  end,
  Leashed = function()
    state.isLeashed = true
    state.persistentStatus = messageByEvent.Leashed
  end,
  PowerRestored = function()
    state.isLeashed = false
    state.persistentStatus = nil
  end,
  Lost = function()
    state.isEntity = false
    state.isLeashed = false
    state.persistentStatus = nil
    state.pings = {}
  end,
}

local function onPing(location, _, kind)
  local controller = game.localController()
  if not controller then
    return
  end
  state.pings[state.nextPingSlot] = { location = location, kind = kind, bornAt = game.timeSeconds(controller) }
  state.nextPingSlot = state.nextPingSlot % PING_MARKER_COUNT + 1
end

function hud.register()
  for kind in pairs(messageByEvent) do
    links.onClientEvent(kind, function()
      local controller = game.localController()
      if controller then
        syncWorld(controller)
      end
      local changeState = stateChangeByEvent[kind]
      if changeState then
        changeState()
      end
      showMessage(kind)
    end)
  end

  for command, seconds in pairs(config.cooldowns) do
    links.onClientEvent("Cooldown." .. command, function()
      local controller = game.localController()
      if controller then
        state.cooldownEndsAt[command] = game.timeSeconds(controller) + seconds
      end
    end)
  end

  links.onPing(onPing)

  -- Masked as soon as the game writes a name or redraws, so the real name never shows for a frame; the sweep in
  -- hideCrewHud covers screens that named someone before this player became the entity
  for _, functionName in ipairs({ "BPI_UI_SetText", "BPI_UI_SetStep" }) do
    game.hookWhenLoaded(game.paths.capsuleScreenClass, functionName, function(context)
      if state.isEntity then
        maskCapsuleName(context:get())
      end
    end)
  end
  -- About 30 frames a second: smooth enough for markers over a moving camera
  LoopInGameThreadWithDelay(33, render)
end

return hud
