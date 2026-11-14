-- Copyright © 2026 Jalapeno Labs

-- What the entity hears, seen through walls, on the entity player's own machine (playtest 9: "see a red-colored skin
-- of the door through the walls pulsing in the distance ... like how some video games show see-through-wall x-ray
-- stuff"): the real body of whatever made a noise, outlined in red over everything.
--   - A gunshot flashes the shooter, fading over a second and a half; a footstep flashes the walker faintly.
--   - A door's alarm and an engine's overload pulse that door's or engine's body for as long as the host keeps telling
--     of it (senses.lua: every half-second beat of the alarm, every second of the overload).
--
-- The outline is the game's own: its spectator's post-process material (PostProcess_Outline), which draws an outline
-- around whatever renders custom depth, walls or not. A red instance of it goes on a post-process component of the
-- entity's own, which no other machine has; a body shows by rendering custom depth while its noise lasts.
--
-- The game already renders custom depth for every other crew member's body and armour on every machine (its Tab
-- overlay outlines teammates), so on the entity's machine the crew are kept out of custom depth except while a noise
-- shows them, or the outline would be a wallhack. It is one colour for everything shown at once, so its brightness
-- follows the strongest noise being shown.
--
-- What this machine doesn't have can't be drawn (a section of the ship it hasn't loaded, a crew member too far away
-- to be sent to it), and the outline might not be set up at all: the HUD then marks where the noise was (hud.lua).

local config = require("entity.config")
local game = require("entity.game")
local postprocess = require("entity.postprocess")

local silhouettes = {}

-- The game's outline materials, the spectator's first: the debug one draws the same outline.
local OUTLINE_MATERIALS = {
  "/Game/Materials/PostProcess_Outline.PostProcess_Outline",
  "/Game/Materials/PostProcess_Outline_Debug.PostProcess_Outline_Debug",
}
local PRIMITIVE_CLASS = "/Script/Engine.PrimitiveComponent"
-- A part of the source that the game keeps hidden on this machine and that must show to be outlined, by kind: the
-- engine's body (BP_Engine), hidden on every machine whose local player hasn't been near it.
local hiddenBodyFieldByKind = {
  Overload = "EngineHawking02",
}
-- Below this change in brightness, the outline's colour isn't written again.
local BRIGHTNESS_STEP = 0.02

-- The outline on this machine: { monsterAddress, effect, material, brightness }, or { failed = true } once it
-- couldn't be set up for this monster; nil before.
local outline = nil
-- What the outline shows, by actor address: { actor, kind, firstNewsAt, lastNewsAt }.
local shown = {}
-- When the crew's custom depth is next brought back in line with what's shown.
local nextCrewSweepAt = 0

-- Gives the entity its outline, or marks it failed (postprocess.lua says why).
local function setUp(monster)
  local monsterAddress = monster:GetAddress()
  if outline and outline.monsterAddress == monsterAddress then
    return
  end
  local effect = postprocess.add(monster, OUTLINE_MATERIALS, 1.0, "outline of what it hears")
  if not effect then
    outline = { monsterAddress = monsterAddress, failed = true }
    game.log("Noises show as markers")
    return
  end
  effect.material:SetScalarParameterValue(FName("OutlineTickeness"), config.silhouettes.thickness)
  effect.material:SetVectorParameterValue(FName("Color"), { R = 0, G = 0, B = 0, A = 0 })
  outline = {
    monsterAddress = monsterAddress,
    effect = effect,
    material = effect.material,
    brightness = 0,
  }
end

local function setCustomDepth(actor, isShown)
  local primitives = actor:K2_GetComponentsByClass(StaticFindObject(PRIMITIVE_CLASS))
  primitives:ForEach(function(_, element)
    local primitive = element:get()
    if primitive:IsValid() and primitive.bRenderCustomDepth ~= isShown then
      primitive:SetRenderCustomDepth(isShown)
    end
  end)
end

-- Keeps every crew member out of custom depth unless a noise shows them. Their armour joins it on every change of it
-- (BP_Character.AddArmorPart), so this runs again every crewSweepSeconds.
local function sweepCrew(now)
  if now < nextCrewSweepAt then
    return
  end
  nextCrewSweepAt = now + config.silhouettes.crewSweepSeconds
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    if crewMember:IsValid() then
      setCustomDepth(crewMember, shown[crewMember:GetAddress()] ~= nil)
    end
  end
end

-- How bright a shown body is now: its kind's strength, fading out over its seconds, or pulsing while its news keeps
-- coming.
local function brightnessOf(entry, now)
  local look = config.silhouettes.byKind[entry.kind]
  if look.pulses then
    local phase = (now - entry.firstNewsAt) / config.silhouettes.pulseSeconds * 2 * math.pi
    return look.strength * (0.6 + 0.4 * math.cos(phase))
  end
  return look.strength * (1 - (now - entry.lastNewsAt) / look.seconds)
end

-- A noise from the host: shows its source and returns true, or returns false when this machine can't show it (no
-- outline, no source, or a kind that's only ever a marker), for the HUD to mark instead.
function silhouettes.show(kind, source, now)
  local look = config.silhouettes.byKind[kind]
  if not outline or outline.failed or not look or not source or not source:IsValid() then
    return false
  end

  local address = source:GetAddress()
  local entry = shown[address]
  local isNew = entry == nil
  -- The stronger noise shows while both last (a gunshot over a footstep)
  if isNew or look.strength >= brightnessOf(entry, now) then
    local firstNewsAt = (entry and entry.kind == kind) and entry.firstNewsAt or now
    entry = { actor = source, kind = kind, firstNewsAt = firstNewsAt, lastNewsAt = now }
    shown[address] = entry
  end
  entry.lastNewsAt = now
  if isNew then
    local hiddenBodyField = hiddenBodyFieldByKind[kind]
    local body = hiddenBodyField and source[hiddenBodyField]
    if body and body:IsValid() then
      body:SetHiddenInGame(false, false)
    end
    setCustomDepth(source, true)
  end
  return true
end

-- Runs about thirty times a second on the entity player's machine while they drive the entity.
function silhouettes.follow(monster, now)
  setUp(monster)
  if outline.failed then
    return
  end

  local brightness = 0
  for address, entry in pairs(shown) do
    local look = config.silhouettes.byKind[entry.kind]
    if not entry.actor:IsValid() then
      shown[address] = nil
    elseif now - entry.lastNewsAt > look.seconds then
      shown[address] = nil
      setCustomDepth(entry.actor, false)
    else
      brightness = math.max(brightness, brightnessOf(entry, now))
    end
  end
  sweepCrew(now)

  if math.abs(brightness - outline.brightness) < BRIGHTNESS_STEP then
    return
  end
  outline.brightness = brightness
  local color = config.silhouettes.color
  outline.material:SetVectorParameterValue(FName("Color"), {
    R = color.R * brightness,
    G = color.G * brightness,
    B = color.B * brightness,
    A = brightness,
  })
end

-- Once the player no longer drives the entity: nothing stays outlined, the crew render custom depth again as the game
-- has them (for this machine's Tab overlay), and the outline goes.
function silhouettes.forget()
  for _, entry in pairs(shown) do
    if entry.actor:IsValid() then
      setCustomDepth(entry.actor, false)
    end
  end
  shown = {}
  if outline and not outline.failed then
    for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
      if crewMember:IsValid() and not crewMember:IsLocallyControlled() then
        setCustomDepth(crewMember, true)
      end
    end
    postprocess.remove(outline.effect)
  end
  outline = nil
  nextCrewSweepAt = 0
end

return silhouettes
