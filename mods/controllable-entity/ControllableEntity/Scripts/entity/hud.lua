-- Copyright © 2026 Jalapeno Labs

-- The entity player's HUD (WBP_EntityHUD), on their own machine, laid out like the crew's own (playtests 6 and 7):
--   - bottom left, the entity's four moves stacked (kits.slots: LMB, RMB, E and Space), each its key, the move's icon
--     (its kit's) and a bar on the right while it recharges, and the health and stamina bars under them;
--   - top right, the minimap (minimap.lua) with a view cone over it and the key hints under it: C to peek, while
--     peeking would work, and F for the camera;
--   - bottom centre, the frenzy banner and short messages from the host's events;
--   - bottom right, how many respawns the crew has left (playtest 8).
-- Keys show as the game's own glyphs (its /Game/KeyIcons textures, as in its "press E" prompts).
-- Noise pings are drawn over the world. While the player is the entity, the crew HUD their parked body left behind is
-- hidden. The bars, the health and the stamina come from the player's link, which the host fills (abilities.lua).

local config = require("entity.config")
local game = require("entity.game")
local kits = require("entity.kits")
local links = require("entity.links")
local objectives = require("entity.objectives")
local vents = require("entity.vents")

local hud = {}

local PING_MARKER_COUNT = 12
-- ESlateVisibility
local COLLAPSED = 1
local HIDDEN = 2
local VISIBLE_NO_INPUT = 3
-- The crew character can rebuild its HUD (on respawn, after menus), so the entity's machine checks for it this often.
local CREW_HUD_CHECK_SECONDS = 0.5
-- Finding the grate under the entity walks every vent shaft, so the peek hint checks for one this often.
local PEEK_CHECK_SECONDS = 0.25
-- The space between the minimap's bottom edge and the key hints, in HUD units.
local HINTS_GAP = 10
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

-- A move the lair holds back (leaving the ducts before the power is on) dims.
local UNUSABLE_OPACITY = 0.35
local ultimateColor = { R = 1.0, G = 0.70, B = 0.23, A = 1 }
local frenzyColor = { R = 1.0, G = 0.29, B = 0.24, A = 1 }
-- The health bar is the crew HUD's own green while the entity stands, and red once it is down, when the crew's fire
-- can kill it (the squid only drains its stagger while standing; Mike, stunned, opens his head to their fire).
local healthColorByDowned = {
  [false] = { R = 0.025, G = 0.25, B = 0.119, A = 0.75 },
  [true] = { R = 0.8, G = 0.06, B = 0.04, A = 0.75 },
}

-- The mod's icons for the moves (T_Icon_<name>, built from art/icons): each slot shows its kit's move's icon.
local ICON_FOLDER = "/Game/Mods/ControllableEntity/Icons/"

-- What only the entity sees, hidden before the takeover (a volunteer sees only their status line).
local ENTITY_PARTS = { "Actions", "HealthBar", "StaminaBar", "ViewCone", "Hints", "VentTime", "RespawnsText" }

-- The game's glyph for each key slot, by the slot's name in WBP_EntityHUD: the game's default bindings for the actions
-- the entity reuses (control.lua), so a player who rebinds them sees the defaults.
local GLYPH_FOLDER = "/Game/KeyIcons/Custom/Keyboard/"
local glyphBySlot = {
  PrimaryKey = "T_input_mouse_leftClick",
  SecondaryKey = "T_input_mouse_rightClick",
  UltimateKey = "T_input_key_e",
  MobilityKey = "T_input_key_space",
  PeekHintKey = "T_input_key_c",
  ViewHintKey = "T_input_key_f",
}

local messageByEvent = {
  Volunteered = "You'll be the entity next mission. Only you know. F8 backs out.",
  WaitingForMonster = "You're the entity. You take the monster once the crew leaves the shuttle.",
  Unvolunteered = "You're crew again.",
  VolunteerTaken = "Someone else already claimed the entity.",
  BecameEntity = "You are the entity. Hunt by sound.",
  Leashed = "Lurk in the vents until the crew turns the power on.",
  LeashedAlone = "Lurk in the vents until the power is on. Playing alone, F8 turns it on.",
  PowerRestored = "The power is on. Hunt.",
  Dormant = "You lie powered down until the crew turns the power on.",
  DormantAlone = "You lie powered down until the power is on. Playing alone, F8 turns it on.",
  Awake = "The power is on. You wake. Hunt.",
  Lost = "The crew got you. You're out of this mission.",
  KillStarted = "Got one.",
  FrenzyStarted = "FRENZY: every grab kills.",
  FrenzyPartial = "They have the weapon. Your hunger grows faster, and the vents won't hide you for long.",
  ForcedOut = "Your time in the vents is up. Out you go.",
  ShuttleNear = "Near the shuttle: no sprinting, and no kills.",
  VentsReopened = "The vents will take you again.",
  PickedByHost = "The host picked you to be the entity next mission. Only you know.",
  PickedPlayerLeft = "The player you picked left. The entity's player is random again.",
  PickedUnfit = "The game never sends your pick on this contract (the crew has no main weapons, or it's the easiest "
    .. "difficulty), so it may be unbeatable. Your pick stands.",
  ["Denied.Down"] = "You're down: nothing until you're back up.",
  ["Denied.UnstuckCooldown"] = "Unstuck isn't ready again yet.",
  UnstuckStarted = "Keep holding F7 and keep still: unstuck in 5 seconds.",
  UnstuckCancelled = "Unstuck cancelled: hold F7, keep still and unhurt.",
  Unstuck = "Unstuck.",
  ["Denied.NoTarget"] = "Get closer to a crew member.",
  ["Denied.NoVentEntrance"] = "Stand under a vent to climb in.",
  ["Denied.NoVentExit"] = "Crawl over a vent opening to drop out, or to either end of a step to climb it.",
  ["Denied.NotInVent"] = "Peek works from inside a vent.",
  ["Denied.PowerOff"] = "The vents hold you until the power is on.",
  ["Denied.UltimateNotReady"] = "Your hunger isn't ready.",
  ["Denied.Shuttle"] = "Hunt them away from their shuttle: you can't board it.",
  ["Denied.Forbidden"] = "Hunt elsewhere: this area is forbidden to you.",
  ["Denied.ShuttleNoKill"] = "Your grab can't kill this close to the shuttle.",
  ["Denied.ShuttleZone"] = "Save your hunger: it can't kill this close to the shuttle.",
  ["Denied.NotAlone"] = "The crew turns the power on. F8 only does it when you play alone.",
  ["Denied.VentsShut"] = "The vents take you again once your vent time is half back.",
  ["Denied.HostOnly"] = "The host picks the entity.",
  ["Denied.EntityModeOff"] = "The host has the monster on AI only. The host's F9 picks a player entity.",
  ["Denied.PickInLobby"] = "Pick the entity in the lobby.",
  ["Denied.DodgeInVent"] = "Dodge out of the vents.",
  ["Denied.NoRoom"] = "No room to dodge there.",
  ["Denied.Shielded"] = "Their shield is up: get around it.",
  ["Denied.Dormant"] = "You're powered down until the power is on.",
  ["Denied.CantShoot"] = "The gatling won't fire right now.",
  ["Denied.NoThrow"] = "No clear throw there.",
  ["Denied.TooClose"] = "Too close: the blast would hit your own gatling.",
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
    -- Whether the lair holds the entity in the ducts (until the power is on).
    isLeashed = false,
    nextCrewHudCheckAt = 0,
    -- Whether the entity is in a vent over a grate it could peek through, rechecked every PEEK_CHECK_SECONDS.
    isOverGrate = false,
    nextPeekCheckAt = 0,
    -- Each command's cooldown in progress, by command: { endsAt, seconds }, as the host started it.
    cooldowns = {},
    -- The kit whose move icons the stack shows, so they're set again only when the entity changes.
    kitShown = nil,
    -- The crew's respawns left at the last draw, so the count is written only when it changes.
    respawnsShown = nil,
    pings = {},
    nextPingSlot = 1,
    widget = nil,
  }
end

local state = freshState(nil)
-- Whether the key hints under the minimap show. H switches them, and the choice holds across maps.
local hintsShown = true

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

-- Puts one of the game's key glyphs in a key slot, as large as fits the slot's space (its size box, set in the HUD's
-- layout) without stretching: the glyphs differ in shape (a letter key is square, the space bar wide, a mouse tall).
local function showGlyph(image, glyphName)
  local texture = game.loadGameAsset(GLYPH_FOLDER .. glyphName .. "." .. glyphName)
  if not texture then
    return
  end
  image:SetBrushFromTexture(texture, false)
  local space = image:GetParent()
  local width, height = texture:Blueprint_GetSizeX(), texture:Blueprint_GetSizeY()
  local scale = math.min(space.WidthOverride / width, space.HeightOverride / height)
  image:SetDesiredSizeOverride({ X = width * scale, Y = height * scale })
end

-- The widget is created on first use and again after a map change, which removes it from the viewport.
local function ensureWidget(controller)
  if state.widget and state.widget:IsValid() then
    return state.widget
  end

  local widgetClass = game.loadModAsset(game.modAssets.hud)
  if not widgetClass then
    return nil
  end

  -- There is only ever one entity HUD. One already on screen was left by an earlier run of the mod: a hot reload
  -- forgets the mod's state but not its widgets (playtest 6), and the old one would sit there frozen
  for _, leftover in ipairs(FindAllOf(game.modAssets.hud.name) or {}) do
    if leftover:IsValid() then
      leftover:RemoveFromParent()
    end
  end

  local widget = StaticFindObject(game.paths.widgetLibrary):Create(controller, widgetClass, controller)
  widget:AddToViewport(50)

  -- The view cone goes over the minimap's centre and the hints under its bottom edge, placed from the minimap's own
  -- size and margin (minimap.lua); both are anchored to the top-right corner the minimap sits in
  local minimapCentre = config.minimap.margin + config.minimap.size / 2
  widget.ViewCone.Slot:SetPosition({ X = -minimapCentre, Y = minimapCentre })
  widget.Hints.Slot:SetPosition({
    X = -config.minimap.margin,
    Y = config.minimap.margin + config.minimap.size + HINTS_GAP,
  })

  for slotName, glyphName in pairs(glyphBySlot) do
    showGlyph(widget[slotName], glyphName)
  end

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

-- A bar fills as its action recharges and hides once full (playtest 6: only while it isn't at 100%). Hidden rather
-- than collapsed, it keeps its space, so the stack never shifts.
local function drawCharge(bar, charge)
  local isCharging = charge < 1
  setShown(bar, isCharging)
  if isCharging then
    bar:SetPercent(charge)
  end
end

-- How far a command has recharged, 0 to 1: full when it hasn't been used.
local function charge(command, now)
  local cooldown = state.cooldowns[command]
  if not cooldown then
    return 1
  end
  return 1 - math.max(0, cooldown.endsAt - now) / cooldown.seconds
end

-- The stack shows the entity's own moves: each slot's icon is its kit's move's.
local function showMoveIcons(widget, kit)
  if state.kitShown == kit then
    return
  end
  state.kitShown = kit
  for _, slot in ipairs(kits.slots) do
    local iconName = "T_Icon_" .. kit.moves[slot].icon
    local icon = game.loadModAsset({ package = ICON_FOLDER .. iconName, name = iconName })
    if icon then
      widget[slot .. "Icon"]:SetBrushFromTexture(icon, false)
    end
  end
end

-- Every action shows the same way, the ultimate included (playtest 6): a bar while it charges, nothing once ready.
-- The ultimate's bar is the kill meter, or in full frenzy the re-arm between kills, in the frenzy's red. A move the
-- lair holds back dims while it does.
local function drawActions(widget, link, kit, now)
  for _, slot in ipairs(kits.slots) do
    if slot ~= "Ultimate" then
      drawCharge(widget[slot .. "Bar"], charge(slot, now))
    end
    local isHeld = state.isLeashed and kit.moves[slot].heldByLair
    widget[slot .. "Slot"]:SetRenderOpacity(isHeld and UNUSABLE_OPACITY or 1)
  end

  local inFrenzy = link.Frenzy
  drawCharge(widget.UltimateBar, link.Meter)
  widget.UltimateBar:SetFillColorAndOpacity(inFrenzy and frenzyColor or ultimateColor)
  setText(widget.FrenzyText, inFrenzy and "FRENZY" or "")
end

-- The health bar shows the pool hits are draining (playtest 6; abilities.lua), red while the entity is down. Like
-- the crew's, the stamina bar only shows once sprinting has used some, and the vent time
-- (top centre, once the crew hunts the entity) only once the vents have used some.
local function drawVitals(widget, link)
  widget.HealthBar:SetPercent(link.Health)
  widget.HealthBar:SetFillColorAndOpacity(healthColorByDowned[link.Downed == true])
  drawCharge(widget.StaminaBar, link.Stamina)
  setShown(widget.VentTime, link.VentTime < 1)
  widget.VentTimeBar:SetPercent(link.VentTime)
end

-- The peek hint shows while C would work, the way the game shows "press E" only while there is something to use
-- (playtest 6): inside a vent, over a grate (the host's own rule, abilities.lua), with peek recharged.
local function drawPeekHint(widget, monster, now)
  if now >= state.nextPeekCheckAt then
    state.nextPeekCheckAt = now + PEEK_CHECK_SECONDS
    state.isOverGrate = monster.InVent == true
      and vents.nearest(monster:K2_GetActorLocation(), config.vents.exitReach) ~= nil
  end
  local isRecharged = charge("Peek", now) >= 1
  setShown(widget.PeekHint, state.isOverGrate and isRecharged)
end

-- The crew's shared respawns left (BP_MyGameState.Respawn, replicated to every machine): the entity wins when the crew
-- is all dead with none left.
local function drawRespawns(widget)
  local gameState = FindFirstOf(game.classNames.gameState)
  local respawnsLeft = gameState and gameState:IsValid() and gameState.Respawn
  if not respawnsLeft or respawnsLeft == state.respawnsShown then
    return
  end
  state.respawnsShown = respawnsLeft
  setText(widget.RespawnsText, string.format("Human respawns remaining: %d", respawnsLeft))
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

-- The crew HUD belongs to the parked crew body, so it would stay on screen over the entity's view. It comes off the
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
      -- The entity's own objectives are the crew's overlay too (objectives.lua)
      if crewWidget:IsValid() and not objectives.owns(crewWidget) then
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
  -- Only the entity player drives the monster, so driving it is proof enough: the host's BecameEntity may never
  -- arrive in this run of the mod (a hot reload on either machine forgets it, playtest 6)
  local pawn = controller.Pawn
  local drivesMonster = game.monsterDrivenBy(controller) ~= nil
  if drivesMonster then
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

  local link = drivesMonster and links.own() or nil
  if not link then
    for _, part in ipairs(ENTITY_PARTS) do
      setShown(widget[part], false)
    end
    setText(widget.FrenzyText, "")
    return
  end

  setShown(widget.Actions, true)
  setShown(widget.HealthBar, true)
  setShown(widget.ViewCone, true)
  setShown(widget.Hints, hintsShown)
  setShown(widget.RespawnsText, true)
  drawRespawns(widget)
  local kit = kits.forMonster(pawn)
  showMoveIcons(widget, kit)
  drawActions(widget, link, kit, now)
  drawVitals(widget, link)
  drawPeekHint(widget, pawn, now)
  -- The cone turns with the player's look, the way the minimap's player icon turns with the entity (minimap.lua)
  widget.ViewCone:SetRenderTransformAngle(controller:GetControlRotation().Yaw + config.minimap.iconAngleOffset)
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
  -- Events that only change what the HUD shows (ShuttleLeft) have no message of their own
  if not message then
    return
  end
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
  WaitingForMonster = function()
    state.isVolunteer = true
    state.persistentStatus = messageByEvent.WaitingForMonster
  end,
  PickedByHost = function()
    state.isVolunteer = true
    state.persistentStatus = messageByEvent.PickedByHost
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
  LeashedAlone = function()
    state.isLeashed = true
    state.persistentStatus = messageByEvent.LeashedAlone
  end,
  PowerRestored = function()
    state.isLeashed = false
    state.persistentStatus = nil
  end,
  -- Powered down (the Terminator) until the power is on, as the ducts hold the others
  Dormant = function()
    state.isLeashed = true
    state.persistentStatus = messageByEvent.Dormant
  end,
  DormantAlone = function()
    state.isLeashed = true
    state.persistentStatus = messageByEvent.DormantAlone
  end,
  Awake = function()
    state.isLeashed = false
    state.persistentStatus = nil
  end,
  -- The hunt let the entity go early, with the power still off: the hunt's own message says why
  Released = function()
    state.isLeashed = false
    state.persistentStatus = nil
  end,
  -- The shuttle's rules hold while the entity is near it
  ShuttleNear = function()
    state.persistentStatus = messageByEvent.ShuttleNear
  end,
  ShuttleLeft = function()
    if state.persistentStatus == messageByEvent.ShuttleNear then
      state.persistentStatus = nil
    end
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

-- H: hides the key hints under the minimap, or shows them again (playtests 6 and 7).
function hud.toggleHints()
  hintsShown = not hintsShown
end

function hud.register()
  -- Every event with a message, and the few that only change what the HUD shows (ShuttleLeft)
  local eventKinds = {}
  for kind in pairs(messageByEvent) do
    eventKinds[kind] = true
  end
  for kind in pairs(stateChangeByEvent) do
    eventKinds[kind] = true
  end
  for kind in pairs(eventKinds) do
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

  -- The host says how long each cooldown it starts lasts: an entity's own moves have their own
  local commands = {}
  for _, slot in ipairs(kits.slots) do
    table.insert(commands, slot)
  end
  for command in pairs(config.cooldowns) do
    table.insert(commands, command)
  end
  for _, command in ipairs(commands) do
    links.onClientEvent("Cooldown." .. command, function(seconds)
      local controller = game.localController()
      if controller and seconds > 0 then
        state.cooldowns[command] = { endsAt = game.timeSeconds(controller) + seconds, seconds = seconds }
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
