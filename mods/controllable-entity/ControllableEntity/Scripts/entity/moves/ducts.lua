-- Copyright © 2026 Jalapeno Labs

-- The moves of every entity that lives in the vents, on the host: venting (Space) and peeking down through a grate
-- (C). Both call the same BP_BaseMonster functions the AI's behaviour tree does, which every vent monster shares.

local config = require("entity.config")
local hunt = require("entity.hunt")
local lair = require("entity.lair")
local shared = require("entity.moves.shared")
local vents = require("entity.vents")

local ducts = {}

-- The peek through a grate in progress: { grate, location } (where the monster stood to peek), or nil.
local peeking = nil

-- Ends a peek with the game's own call, as C pressed again does. The pose otherwise outlasts the peek: the squid
-- crawled and leapt still looking down (playtest 8). Dropping out of the vent ends it on its own.
function ducts.stopPeeking(monster)
  if not peeking then
    return
  end
  if peeking.grate:IsValid() then
    monster:BPI_Monster_LookFromVent(peeking.grate, false, false)
  end
  peeking = nil
end

-- In a room, venting climbs into the shaft above. In the ducts it takes whichever is nearer: the shaft opening
-- below, dropping out onto whoever is under it, or either end of a step, climbing it up or down with the AI's own
-- climb (playtest 6: the player had no way up the elbow joints the AI climbs; playtest 8: nor back down). Dropping out
-- leaves the ducts, so it waits for the power while the lair holds the monster; climbing stays inside them, so it
-- doesn't.
function ducts.vent(monster)
  local location = monster:K2_GetActorLocation()
  if not monster.InVent then
    if hunt.areVentsShut() then
      return false, "VentsShut"
    end
    local entrance = vents.nearest(location, config.vents.enterReach)
    if not entrance then
      return false, "NoVentEntrance"
    end
    monster:BPI_Monster_JumpToVent(entrance, true)
    return true
  end

  local exit, exitDistance = vents.nearest(location, config.vents.exitReach)
  local climb, climbDistance, isFromTop = vents.nearestClimb(location)
  if climb and (not exit or climbDistance < exitDistance) then
    ducts.stopPeeking(monster)
    -- Up from the step's foot, or down from its top
    monster:BPI_Monster_ClimbVent250(climb, isFromTop)
    return true
  end
  if not exit then
    return false, "NoVentExit"
  end
  if lair.isLeashed(monster) then
    return false, "PowerOff"
  end
  -- The drop's own animation ends a peek
  peeking = nil
  local target = shared.crewInCone(monster, { X = 0, Y = 0, Z = -1 }, config.vents.exitReach, 120)
  monster:BPI_Monster_AttackFromVent(exit, target)
  return true
end

-- C: looks down through the grate under the monster, or stops looking.
function ducts.peek(monster)
  if peeking then
    ducts.stopPeeking(monster)
    return true
  end
  if not monster.InVent then
    return false, "NotInVent"
  end
  local location = monster:K2_GetActorLocation()
  local grate = vents.nearest(location, config.vents.exitReach)
  if not grate then
    return false, "NoVentExit"
  end
  peeking = { grate = grate, location = { X = location.X, Y = location.Y, Z = location.Z } }
  monster:BPI_Monster_LookFromVent(grate, true, false)
  return true
end

-- Runs about five times a second on the host: crawling away from the grate ends the peek (playtest 8); out of the
-- ducts, the drop ended it already.
function ducts.tick(monster)
  if not peeking then
    return
  end
  if not monster.InVent then
    peeking = nil
    return
  end
  local location = monster:K2_GetActorLocation()
  local offsetX, offsetY = location.X - peeking.location.X, location.Y - peeking.location.Y
  if math.sqrt(offsetX * offsetX + offsetY * offsetY) > config.vents.peekBreakDistance then
    ducts.stopPeeking(monster)
  end
end

return ducts
