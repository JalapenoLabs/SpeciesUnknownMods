-- Copyright © 2026 Jalapeno Labs

-- Host side of the entity's senses: every noise the game reports to its AI reaches the entity player's machine with
-- what made it, whose body flashes there through walls (silhouettes.lua). The entity never hears a noise the AI
-- monster wouldn't. When nothing has been heard for a while, it senses where the crew are, roughly (senses.tickHost).
--
-- A possessed monster has no AI controller, so the AI's own hearing (AIPerception on BP_Basic_AI_Controller) no longer
-- receives anything. These hooks watch the noise sources themselves and apply the same range rules:
--   gunshots   Weapon_Base.MakeNoiseAI            loudness and range set per weapon
--   footsteps  BP_ParentCharacter footsteps       range Volume^1.3 x 1100, doubled in water, when FootstepsNoise
--   the rest   BP_MyGameState.ForceSound          the decontamination airlock, explosions, with their own min/max
-- Two things reach the entity at any distance, for as long as they last (playtest 9: the host, as the entity, only
-- saw a door's alarm from the same room, and sprinted to the engines too late): any door's alarm (each door's
-- LightSwitchOpenning beats every half second while it sounds, on every difficulty) and the engines overloading.

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")

local senses = {}

-- The doors whose alarm the entity hears at any distance: Hawking's big doors, Polar's (the rover garage's door is a
-- child that keeps its parent's alarm) and the airlocks. Their own noise reports to the AI (ForceSound, nearby and
-- only on the harder difficulties) are left to these.
local ALARM_DOOR_CLASSES = {
  "/Game/Blueprints/PlaceHolder/Door/BP_BigDoor1.BP_BigDoor1_C",
  "/Game/Blueprints/Polar/Doors/BP_BigDoor_POLAR.BP_BigDoor_POLAR_C",
  "/Game/Blueprints/SAS/BP_SAS_Door.BP_SAS_Door_C",
}
local ALARM_DOOR_CLASS_NAMES = {
  BP_BigDoor1_C = true,
  BP_BigDoor_POLAR_C = true,
  BP_BigDoor_POLAR_Rover_C = true,
  BP_SAS_Door_C = true,
}
-- BP_Engine.EngineState: 1 starting, 2 turning while the overload builds, 3 critical (final).
local ENGINE_STARTING = 1
local ENGINE_TURNING = 2
local ENGINE_CLASS_NAME = "BP_Engine_C"

local lastFootstepPingAtBySource = {}
-- When the entity was last sent a ping of any kind, by the monster's address, for its sense of the crew.
local lastPingAt = { monsterAddress = nil, at = 0 }
-- The engines in the current world, looked for again every config.areas.rescanSeconds, when the overload was last
-- pinged, and the world whose engines' start the entity was told of.
local engines = { worldKey = nil, nextScanAt = 0, list = {}, nextPingAt = 0, announcedWorldKey = nil }

-- Where the entity senses a crew member: the true location pushed a random distance away, more the farther it is, so
-- the sense gives a direction and a rough distance rather than a position. Noises are told exactly.
local function blurred(location, distance)
  local radius = math.min(distance * config.senses.senseBlurFraction, config.senses.senseBlurMax)
  local angle = math.random() * 2 * math.pi
  local offset = math.sqrt(math.random()) * radius
  return { X = location.X + math.cos(angle) * offset, Y = location.Y + math.sin(angle) * offset, Z = location.Z }
end

-- Tells the entity player about a noise: where it was exactly and what made it. Near the entity, it also speeds up the
-- kill meter, and any noise holds off the sense of the crew.
local function tell(abilities, entity, location, loudness, kind, source)
  local now = game.timeSeconds(entity.monster)
  if game.distance(entity.monster:K2_GetActorLocation(), location) <= config.meter.noiseNearbyDistance then
    abilities.meter():noteNoiseNearby(now)
  end
  links.sendPing(entity.controller, location, loudness, kind, source)
  lastPingAt = { monsterAddress = entity.monster:GetAddress(), at = now }
end

-- Sends a heard noise to the entity player, or does nothing when the entity wouldn't have heard it.
local function hear(abilities, takeover, source, location, loudness, noiseRange, kind)
  local entity = takeover.activeEntity()
  if not entity then
    return
  end

  local distance = game.distance(entity.monster:K2_GetActorLocation(), location)
  local audibleRange = config.senses.hearingRange * loudness
  if noiseRange and noiseRange > 0 then
    audibleRange = math.min(audibleRange, noiseRange)
  end
  if distance > audibleRange then
    return
  end
  tell(abilities, entity, location, loudness, kind, source)
end

-- The engines overloading (starting, then turning faster): a ping a second for each, at any distance, so the
-- entity's machine pulses its body for as long as it lasts.
local function pingOverloads(abilities, entity, now)
  local monster = entity.monster
  local worldKey = monster:GetWorld():GetAddress()
  if worldKey ~= engines.worldKey or now >= engines.nextScanAt then
    engines.worldKey = worldKey
    engines.nextScanAt = now + config.areas.rescanSeconds
    engines.list = FindAllOf(ENGINE_CLASS_NAME) or {}
  end
  if now < engines.nextPingAt then
    return
  end
  engines.nextPingAt = now + config.senses.overloadPingSeconds
  for _, engine in ipairs(engines.list) do
    local state = engine:IsValid() and engine.EngineState
    if state == ENGINE_STARTING or state == ENGINE_TURNING then
      tell(abilities, entity, engine:K2_GetActorLocation(), 1.0, "Overload", engine)
    end
  end
end

-- Runs five times a second on the host while there is an entity. With nothing heard for senseSeconds, the entity
-- senses every living crew member, a heavily blurred pink ping each, and again every senseSeconds while the quiet
-- lasts: a lost entity always has somewhere to go, without a wallhack's precision.
local registeredAbilities = nil

function senses.tickHost(entity, now)
  local monster = entity.monster
  pingOverloads(registeredAbilities, entity, now)
  if lastPingAt.monsterAddress ~= monster:GetAddress() then
    lastPingAt = { monsterAddress = monster:GetAddress(), at = now }
    return
  end
  if now - lastPingAt.at < config.senses.senseSeconds then
    return
  end
  lastPingAt.at = now
  local origin = monster:K2_GetActorLocation()
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    local isAlive = crewMember:IsValid() and not crewMember.bHidden and crewMember.IsDead ~= true
    if isAlive then
      local location = crewMember:K2_GetActorLocation()
      local spot = blurred(location, game.distance(origin, location))
      links.sendPing(entity.controller, spot, 1.0, "Sense")
    end
  end
end

function senses.register(abilities, takeover)
  registeredAbilities = abilities
  game.hookWhenLoaded(game.paths.weaponClass, "MakeNoiseAI", function(context)
    local weapon = context:get()
    local shooter = weapon.PawnOwner
    if not weapon:HasAuthority() or not shooter:IsValid() then
      return
    end
    hear(abilities, takeover, shooter, shooter:K2_GetActorLocation(), weapon.HearingLoudness, weapon.HearingRange,
      "Gunshot")
  end)

  game.hookWhenLoaded(game.paths.characterClass, "BPI_Footsteps_PlaySound",
    function(context, _, volumeParameter, _, waterParameter)
      local walker = context:get()
      if not walker:HasAuthority() or not walker.FootstepsNoise then
        return
      end

      -- Footsteps arrive with every step of every player; one ping per walker per interval is plenty
      local entity = takeover.activeEntity()
      local now = entity and game.timeSeconds(entity.monster) or 0
      local walkerAddress = walker:GetAddress()
      if now - (lastFootstepPingAtBySource[walkerAddress] or -math.huge) < config.senses.footstepInterval then
        return
      end
      lastFootstepPingAtBySource[walkerAddress] = now

      local range = volumeParameter:get() ^ 1.3 * 1100
      if waterParameter:get() then
        range = range * 2
      end
      hear(abilities, takeover, walker, walker:K2_GetActorLocation(), 1.0, range, "Footstep")
    end)

  game.hookWhenLoaded(game.paths.gameStateClass, "BPI_GameState_ForceSound",
    function(context, heardActorParameter, locationParameter, maxDistanceParameter, minDistanceParameter)
      local entity = takeover.activeEntity()
      if not entity or not context:get():HasAuthority() then
        return
      end
      -- A door's alarm reaches the entity at any distance through its own beat (below)
      local heardActor = heardActorParameter:get()
      local source = heardActor and heardActor:IsValid() and heardActor or nil
      if source and ALARM_DOOR_CLASS_NAMES[source:GetClass():GetFName():ToString()] then
        return
      end

      -- ForceSound's own rules (BP_MyGameState): a maximum distance when set, and a minimum one when set
      local location = locationParameter:get()
      local soundLocation = { X = location.X, Y = location.Y, Z = location.Z }
      local distance = game.distance(entity.monster:K2_GetActorLocation(), soundLocation)
      local maxDistance, minDistance = maxDistanceParameter:get(), minDistanceParameter:get()
      if (maxDistance ~= 0 and distance > maxDistance) or (minDistance ~= 0 and distance < minDistance) then
        return
      end

      tell(abilities, entity, soundLocation, 1.0, "Alarm", source)
    end)

  -- Each beat of a door's alarm, on the host, where every door runs
  for _, doorClass in ipairs(ALARM_DOOR_CLASSES) do
    game.hookWhenLoaded(doorClass, "LightSwitchOpenning", function(context)
      local door = context:get()
      local entity = takeover.activeEntity()
      if entity and door:HasAuthority() then
        tell(abilities, entity, door:K2_GetActorLocation(), 1.0, "Alarm", door)
      end
    end)
  end

  -- Starting the engines (both start together) is told once a mission: a sound and a line on the entity's HUD
  game.hookWhenLoaded(game.paths.engineClass, "OnRep_EngineState", function(context)
    local engine = context:get()
    local entity = takeover.activeEntity()
    if not entity or not engine:HasAuthority() or engine.EngineState ~= ENGINE_STARTING then
      return
    end
    local worldKey = engine:GetWorld():GetAddress()
    if engines.announcedWorldKey == worldKey then
      return
    end
    engines.announcedWorldKey = worldKey
    links.sendEvent(entity.controller, "EnginesStarted")
  end)
end

return senses
