-- Copyright © 2026 Jalapeno Labs

-- What every entity's moves aim with, on the host: the crew member a move lands on, and the swing a basic attack
-- makes when it lands on nobody.

local game = require("entity.game")

local shared = {}

-- The crew member nearest the monster inside a cone around the aim, within reach; nil when nobody qualifies.
function shared.crewInCone(monster, aim, reach, coneDegrees)
  local origin = monster:K2_GetActorLocation()
  local minimumAlignment = math.cos(math.rad(coneDegrees / 2))
  local best, bestDistance = nil, reach

  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    if crewMember:IsValid() then
      local location = crewMember:K2_GetActorLocation()
      local distance = game.distance(origin, location)
      if distance > 0 and distance <= bestDistance then
        local alignment = ((location.X - origin.X) * aim.X + (location.Y - origin.Y) * aim.Y
          + (location.Z - origin.Z) * aim.Z) / distance
        if alignment >= minimumAlignment then
          best, bestDistance = crewMember, distance
        end
      end
    end
  end
  return best, bestDistance
end

-- The aim flattened onto the ground, for moves that travel along the floor.
function shared.horizontal(aim)
  local length = math.sqrt(aim.X * aim.X + aim.Y * aim.Y)
  if length < 1e-6 then
    return { X = 1, Y = 0, Z = 0 }
  end
  return { X = aim.X / length, Y = aim.Y / length, Z = 0 }
end

-- A basic attack with nobody in reach swings at the air anyway, like a sword swung at nothing (playtest 6). The AI's
-- attack needs a target (BP_BaseMonster.SetSimpleAttack does nothing without one), so the swing's montage is played
-- through the same multicast the attack ends in. Whether the swing hurts whoever it does sweep is the montage's own
-- business (each entity's moves say).
function shared.swingAtAir(monster, montagePath)
  local swing = StaticFindObject(montagePath)
  if not swing or not swing:IsValid() then
    game.log("No swing montage at %s; the attack only lands on a crew member in reach", montagePath)
    return false, "NoTarget"
  end
  monster["AttackSimpleAnim (Clients)"](monster, swing, monster.AttackSimplePlayRate, nil)
  return true
end

return shared
