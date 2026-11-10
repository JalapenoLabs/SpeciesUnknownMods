-- Copyright © 2026 Jalapeno Labs

-- The entity player's HUD (WBP_EntityHUD), on their own machine: the kill meter and frenzy from their link's
-- replicated state, ability cooldowns and short status messages from the host's events, and noise pings drawn over
-- the world.

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")

local hud = {}

local PING_MARKER_COUNT = 12
-- ESlateVisibility
local VISIBLE_NO_INPUT = 3
local HIDDEN = 2

local pingColorByKind = {
  Gunshot = { R = 1.0, G = 0.29, B = 0.24 },
  Footstep = { R = 0.37, G = 0.89, B = 1.0 },
  Alarm = { R = 1.0, G = 0.70, B = 0.23 },
}

local abilityLines = {
  { command = "Attack", label = "Shoot      Lash" },
  { command = "Leap", label = "Aim        Leap" },
  { command = "Vent", label = "Interact   Vent" },
  { command = "Peek", label = "Crouch     Peek" },
}

local messageByEvent = {
  Volunteered = "You'll be the entity next mission. Only you know. (F8 to back out)",
  Unvolunteered = "You're crew again.",
  VolunteerTaken = "Someone else already claimed the entity.",
  BecameEntity = "You are the entity. Hunt by sound.",
  Lost = "The crew got you. You're out of this mission.",
  KillStarted = "Got one.",
  FrenzyStarted = "FRENZY: every grab kills.",
  FrenzyPartial = "They have the weapon. Your hunger grows faster.",
  ["Denied.Cooldown"] = "Not yet.",
  ["Denied.NoTarget"] = "Nobody in reach.",
  ["Denied.NoVent"] = "No vent here.",
  ["Denied.NotInVent"] = "You need to be in a vent.",
  ["Denied.UltimateNotReady"] = "Your hunger isn't ready.",
}

local state = {
  isVolunteer = false,
  isEntity = false,
  message = nil,
  messageUntil = 0,
  cooldownEndsAt = {},
  pings = {},
  nextPingSlot = 1,
  widget = nil,
}

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Widget
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The widget is created on first use and again after a map change, which removes it from the viewport.
local function ensureWidget(controller)
  if state.widget and state.widget:IsValid() then
    return state.widget
  end

  LoadAsset(game.paths.hud)
  local widgetClass = StaticFindObject(game.paths.hudClass)
  if not widgetClass or not widgetClass:IsValid() then
    game.log("Could not load %s; is ControllableEntity_P.pak in Content/Paks/~mods?", game.paths.hud)
    return nil
  end

  state.widget = StaticFindObject(game.paths.widgetLibrary):Create(controller, widgetClass, controller)
  state.widget:AddToViewport(50)
  return state.widget
end

local function setText(textBlock, text)
  textBlock:SetText(FText(text))
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Drawing
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function drawMeter(widget, link)
  local readiness = link.Meter
  local inFrenzy = link.Frenzy
  widget.UltimateBar:SetPercent(readiness)
  setText(widget.FrenzyText, inFrenzy and "FRENZY" or "")

  local ready = readiness >= 1
  local label
  if inFrenzy then
    label = ready and "FRENZY KILL READY" or "FRENZY  re-arming"
  else
    label = ready and ("HEAD GRAB READY  [" .. config.keys.ultimate .. "]")
      or string.format("HEAD GRAB  %d%%", math.floor(readiness * 100))
  end
  setText(widget.UltimateText, label)
end

local function drawAbilities(widget, now)
  local lines = {}
  for _, ability in ipairs(abilityLines) do
    local remaining = (state.cooldownEndsAt[ability.command] or 0) - now
    if remaining > 0 then
      table.insert(lines, string.format("%s  %.1fs", ability.label, remaining))
    else
      table.insert(lines, ability.label)
    end
  end
  setText(widget.AbilityText, table.concat(lines, "\n"))
end

-- Each ping fades over pingSeconds. Markers are positioned in widget units: screen pixels over the DPI scale.
local function drawPings(widget, controller, now)
  local viewportScale = StaticFindObject(game.paths.widgetLayoutLibrary):GetViewportScale(controller)

  for slot = 1, PING_MARKER_COUNT do
    local marker = widget["Ping" .. (slot - 1)]
    local ping = state.pings[slot]
    local age = ping and now - ping.bornAt or math.huge
    local screen = {}
    local onScreen = age < config.senses.pingSeconds
      and controller:ProjectWorldLocationToScreen(ping.location, screen, false)

    if onScreen then
      local color = pingColorByKind[ping.kind] or pingColorByKind.Alarm
      marker.Slot:SetPosition({ X = screen.X / viewportScale, Y = screen.Y / viewportScale })
      marker:SetColorAndOpacity({ R = color.R, G = color.G, B = color.B, A = 1 - age / config.senses.pingSeconds })
      marker:SetVisibility(VISIBLE_NO_INPUT)
    else
      marker:SetVisibility(HIDDEN)
    end
  end
end

local function render()
  local controller = game.localController()
  if not controller then
    return
  end

  local now = game.timeSeconds(controller)
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

  if hasMessage then
    setText(widget.StatusText, state.message)
  elseif state.isVolunteer and not state.isEntity then
    setText(widget.StatusText, messageByEvent.Volunteered)
  else
    setText(widget.StatusText, "")
  end

  local link = state.isEntity and links.own() or nil
  if not link then
    setText(widget.UltimateText, "")
    setText(widget.FrenzyText, "")
    setText(widget.AbilityText, "")
    widget.UltimateBar:SetPercent(0)
    return
  end

  drawMeter(widget, link)
  drawAbilities(widget, now)
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
  state.message = messageByEvent[kind]
  state.messageUntil = game.timeSeconds(controller) + 3
end

-- What each host event changes beyond its message.
local stateChangeByEvent = {
  Volunteered = function() state.isVolunteer = true end,
  Unvolunteered = function() state.isVolunteer = false end,
  BecameEntity = function() state.isEntity = true end,
  Lost = function()
    state.isEntity = false
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
  -- About 30 frames a second: smooth enough for markers over a moving camera
  LoopInGameThreadWithDelay(33, render)
end

return hud
