-- Copyright © 2026 Jalapeno Labs

-- Host side of the entity's senses: every noise the game reports to its AI becomes a blurred ping on the entity
-- player's HUD, through walls. The entity never learns more than the AI monster would hear.
--
-- A possessed squid has no AI controller, so the AI's own hearing (AIPerception on BP_Basic_AI_Controller) no longer
-- receives anything. These hooks watch the noise sources themselves and apply the same range rules:
--   gunshots   Weapon_Base.MakeNoiseAI            loudness and range set per weapon
--   footsteps  BP_ParentCharacter footsteps       range Volume^1.3 x 1100, doubled in water, when FootstepsNoise
--   the rest   BP_MyGameState.ForceSound          doors, the airlock alarm, explosions, with their own min/max

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")

local senses = {}

local lastFootstepPingAtBySource = {}

-- The spot the entity is told about: the true location pushed a random distance away, more for far noises, so a
-- distant noise gives a direction rather than a position.
local function blurred(location, distance)
  local radius = math.min(distance * config.senses.blurFraction, config.senses.blurMax)
  local angle = math.random() * 2 * math.pi
  local offset = math.sqrt(math.random()) * radius
  return { X = location.X + math.cos(angle) * offset, Y = location.Y + math.sin(angle) * offset, Z = location.Z }
end

-- Sends a heard noise to the entity player, or does nothing when the squid wouldn't have heard it.
local function hear(abilities, takeover, location, loudness, noiseRange, kind)
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

  if distance <= config.meter.noiseNearbyDistance then
    abilities.meter():noteNoiseNearby(game.timeSeconds(entity.monster))
  end
  links.sendPing(entity.controller, blurred(location, distance), loudness, kind)
end

function senses.register(abilities, takeover)
  game.hookWhenLoaded(game.paths.weaponClass, "MakeNoiseAI", function(context)
    local weapon = context:get()
    local shooter = weapon.PawnOwner
    if not weapon:HasAuthority() or not shooter:IsValid() then
      return
    end
    hear(abilities, takeover, shooter:K2_GetActorLocation(), weapon.HearingLoudness, weapon.HearingRange, "Gunshot")
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
      hear(abilities, takeover, walker:K2_GetActorLocation(), 1.0, range, "Footstep")
    end)

  game.hookWhenLoaded(game.paths.gameStateClass, "BPI_GameState_ForceSound",
    function(context, _, locationParameter, maxDistanceParameter, minDistanceParameter)
      local entity = takeover.activeEntity()
      if not entity or not context:get():HasAuthority() then
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

      if distance <= config.meter.noiseNearbyDistance then
        abilities.meter():noteNoiseNearby(game.timeSeconds(entity.monster))
      end
      links.sendPing(entity.controller, blurred(soundLocation, distance), 1.0, "Alarm")
    end)
end

return senses
