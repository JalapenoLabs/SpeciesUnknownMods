-- Copyright © 2026 Jalapeno Labs

-- The game's vents, as the squid's AI sees them.
--
-- Each BP_Vent_Up is a vertical shaft from a room's ceiling up into the ducts. The actor stands on the room's floor,
-- and up to four billboard components (Point1Component to Point4Component) mark spots beside the shaft's top, inside
-- the duct. Those are the spots the AI walks to inside the ducts (BTTask_FindClosestVentpoint reads them through
-- BPI_Vent_GetAllpointLocation), so they are where the mod puts the squid too. Hawking has 265 shafts.

local config = require("entity.config")
local game = require("entity.game")

local vents = {}

local SPOT_COMPONENT_NAMES = { "Point1Component", "Point2Component", "Point3Component", "Point4Component" }
-- The steps inside the ducts, where a duct rises 250 units like an elbow joint: the AI climbs them both ways through
-- these navigation links (Nav_Link_VentPoint_Up250 calls BPI_Monster_ClimbVent250). The step's two ends, as
-- BP_BaseMonster.ClimbVent250 places the monster: the foot, 75 units to the link's left at its height, climbed up;
-- and the top, 75 units to its right and 250 up, climbed down (playtest 8: only climbing up stranded the squid).
local CLIMB_LINK_CLASS = "Nav_Link_VentPoint_Up250_C"
local STEP_END_OFFSET = 75
local stepEnds = {
  { isFromTop = false, side = -1, rise = 0 },
  { isFromTop = true, side = 1, rise = 250 },
}

-- Every vent shaft in the world that is showing. The game hides the shafts of map sections that aren't streamed in
-- (BP_Vent_Up.DispatchLevelVisible_Event), and those may lead nowhere loaded.
function vents.all()
  local found = {}
  for _, className in ipairs(game.classNames.vents) do
    for _, vent in ipairs(FindAllOf(className) or {}) do
      if vent:IsValid() and not vent.bHidden then
        table.insert(found, vent)
      end
    end
  end
  return found
end

-- The shaft nearest a location across the floor, within reach and on the same floor, and its floor distance; nil when
-- none is. The squid climbs in from the room below a shaft and drops out from the duct above it, so the floor distance
-- is what matters either way.
function vents.nearest(location, reach)
  local best, bestDistance = nil, reach
  for _, vent in ipairs(vents.all()) do
    local ventLocation = vent:K2_GetActorLocation()
    local deltaX, deltaY = ventLocation.X - location.X, ventLocation.Y - location.Y
    local floorDistance = math.sqrt(deltaX * deltaX + deltaY * deltaY)
    if floorDistance <= bestDistance and math.abs(ventLocation.Z - location.Z) <= config.vents.verticalReach then
      best, bestDistance = vent, floorDistance
    end
  end
  if not best then
    return nil
  end
  return best, bestDistance
end

-- The step whose foot or top is nearest a location across the duct floor, within climbReach and near that end's
-- height: the step, the floor distance, and whether it's the top (a climb down). Nil when none is. Navigation links
-- are hidden in game, so none is skipped for it.
function vents.nearestClimb(location)
  local best, bestDistance, bestIsFromTop = nil, config.vents.climbReach, false
  for _, link in ipairs(FindAllOf(CLIMB_LINK_CLASS) or {}) do
    if link:IsValid() then
      local base = link:K2_GetActorLocation()
      local right = link:GetActorRightVector()
      for _, stepEnd in ipairs(stepEnds) do
        local endX = base.X + right.X * STEP_END_OFFSET * stepEnd.side
        local endY = base.Y + right.Y * STEP_END_OFFSET * stepEnd.side
        local floorDistance = math.sqrt((endX - location.X) ^ 2 + (endY - location.Y) ^ 2)
        local isLevel = math.abs(base.Z + stepEnd.rise - location.Z) <= config.vents.climbVerticalReach
        if floorDistance <= bestDistance and isLevel then
          best, bestDistance, bestIsFromTop = link, floorDistance, stepEnd.isFromTop
        end
      end
    end
  end
  if not best then
    return nil
  end
  return best, bestDistance, bestIsFromTop
end

-- Where a shaft opens: the hole in the duct floor when seen from inside the ducts (its Box_Up trigger, at the top of
-- the shaft), or the floor under it when seen from the room below.
function vents.openingOf(vent, fromInside)
  if fromInside then
    local top = vent.Box_Up:K2_GetComponentLocation()
    return { X = top.X, Y = top.Y, Z = top.Z }
  end
  local floor = vent:K2_GetActorLocation()
  return { X = floor.X, Y = floor.Y, Z = floor.Z }
end

-- Frames to wait between asking the squid to crouch and teleporting it: the crouch applies on its next movement
-- update, and only the crouched capsule fits the ducts.
local CROUCH_FRAMES = 2

-- Puts the squid inside the ducts at a spot, then runs `onArrived` (optional) once it's there. SetInVent is what the
-- vents' own trigger calls: it replicates the state and crouches the squid. The teleport waits for the crouch to
-- apply; a teleport that still finds no room places the squid without the check, and says so in the log.
function vents.moveInto(squid, spot, onArrived)
  squid:BPI_Monster_SetInVent(true)
  ExecuteInGameThreadAfterFrames(CROUCH_FRAMES, function()
    if not squid:IsValid() then
      game.log("The squid was gone before it could be moved into the vents")
      return
    end
    if not squid:K2_TeleportTo(spot, squid:K2_GetActorRotation()) then
      game.log("No room to teleport the squid to %.0f, %.0f, %.0f; placing it there", spot.X, spot.Y, spot.Z)
      squid:K2_SetActorLocation(spot, false, {}, true)
    end
    if onArrived then
      onArrived()
    end
  end)
end

-- The in-duct spots beside a shaft's top, as plain vectors; empty when the shaft has none.
function vents.spotsOf(vent)
  local spots = {}
  for _, componentName in ipairs(SPOT_COMPONENT_NAMES) do
    local component = vent[componentName]
    if component and component:IsValid() then
      local location = component:K2_GetComponentLocation()
      table.insert(spots, { X = location.X, Y = location.Y, Z = location.Z })
    end
  end
  return spots
end

return vents
