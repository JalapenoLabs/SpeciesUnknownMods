-- Copyright © 2026 Jalapeno Labs

-- The entity's voice, on the host (playtest 7). The AI's cries come from its behaviour tree, which a player's monster
-- doesn't run, so only its footsteps and the sounds in its animations played. Here the entity's own cues play again,
-- through its replicated voice (BP_BaseMonster.BPI_Monster_PlayVoiceAudio), so everyone hears them from the entity:
--   - at the entity's will (the game's weapon-slot keys, 1, 2 and 3: abilities.lua): a roar, a curious call, and a
--     long call;
--   - on their own, as the AI's would: a "seen you" call when the entity first spots a crew member, and its escape
--     roar when the entity gets back up after being knocked down.

local config = require("entity.config")
local game = require("entity.game")
local kits = require("entity.kits")

local cries = {}

-- BPI_Monster_PlayVoiceAudio's mouth movement: the entity's mouth moves with the cry as it does for the AI's
local MOUTH_MULTIPLIER = 1.0

-- On the host, per monster: whether the entity saw a crew member at the last check, when it may next call out at one,
-- and whether the entity was down.
local function freshWatch(monsterAddress)
  return { monsterAddress = monsterAddress, wasSeeing = false, nextSeenAt = 0, wasDown = false }
end

local watch = freshWatch(nil)

-- Plays one of the entity's cries on every machine. One the player asks for cuts off whatever the monster was saying;
-- one of its own waits for silence. False after logging when the cue won't load.
function cries.play(monster, cry, isAsked)
  local cue = game.loadGameAsset(kits.forMonster(monster).cries[cry])
  if not cue then
    return false
  end
  monster:BPI_Monster_PlayVoiceAudio(cue, 1.0, 1.0, isAsked, MOUTH_MULTIPLIER, true, 0, not isAsked)
  return true
end

-- Whether the entity can see a crew member: near, within its view, and in its line of sight. The parked crew body
-- the entity player left behind (takeover.lua) is hidden, so it isn't seen.
local function seesCrew(entity)
  local controller = entity.controller
  local origin = entity.monster:K2_GetActorLocation()
  local look = game.rotationDirection(controller:GetControlRotation())
  local coneCosine = math.cos(math.rad(config.cries.sightConeDegrees / 2))
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    local isPresent = crewMember:IsValid() and not crewMember.bHidden
    local location = isPresent and crewMember:K2_GetActorLocation()
    local distance = location and game.distance(origin, location)
    if distance and distance > 0 and distance <= config.cries.sightRange then
      local towards = (look.X * (location.X - origin.X) + look.Y * (location.Y - origin.Y)
        + look.Z * (location.Z - origin.Z)) / distance
      if towards >= coneCosine and controller:LineOfSightTo(crewMember, { X = 0, Y = 0, Z = 0 }, false) then
        return true
      end
    end
  end
  return false
end

-- Runs five times a second on the host while there is an entity: the cries the entity makes on its own.
function cries.tickHost(entity, now)
  local monster = entity.monster
  if watch.monsterAddress ~= monster:GetAddress() then
    watch = freshWatch(monster:GetAddress())
  end

  local isSeeing = seesCrew(entity)
  if isSeeing and not watch.wasSeeing and now >= watch.nextSeenAt then
    watch.nextSeenAt = now + config.cries.seenCallSeconds
    cries.play(monster, "Seen", false)
  end
  watch.wasSeeing = isSeeing

  local isDown = monster[entity.kit.healthFields.downed] == true
  if watch.wasDown and not isDown then
    cries.play(monster, "Escape", false)
  end
  watch.wasDown = isDown
end

return cries
