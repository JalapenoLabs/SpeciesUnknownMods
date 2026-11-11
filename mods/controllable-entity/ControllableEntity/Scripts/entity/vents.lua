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
-- The steps inside the ducts, where a duct rises 250 units like an elbow joint: the AI climbs them through these
-- navigation links (Nav_Link_VentPoint_Up250 calls BPI_Monster_ClimbVent250). BP_BaseMonster.ClimbVent250 starts a
-- climb up 75 units to the link's left, at its height, and a climb down 75 units to its right and 250 up, so the
-- step's foot is 75 units to the link's left.
local CLIMB_LINK_CLASS = "Nav_Link_VentPoint_Up250_C"
local CLIMB_FOOT_OFFSET = 75

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

-- The step up whose foot is nearest a location across the duct floor, within climbReach and near the foot's height,
-- and that floor distance; nil when none is. Navigation links are hidden in game, so none is skipped for it.
function vents.nearestClimb(location)
  local best, bestDistance = nil, config.vents.climbReach
  for _, link in ipairs(FindAllOf(CLIMB_LINK_CLASS) or {}) do
    if link:IsValid() then
      local base = link:K2_GetActorLocation()
      local right = link:GetActorRightVector()
      local footX, footY = base.X - right.X * CLIMB_FOOT_OFFSET, base.Y - right.Y * CLIMB_FOOT_OFFSET
      local floorDistance = math.sqrt((footX - location.X) ^ 2 + (footY - location.Y) ^ 2)
      if floorDistance <= bestDistance and math.abs(base.Z - location.Z) <= config.vents.climbVerticalReach then
        best, bestDistance = link, floorDistance
      end
    end
  end
  if not best then
    return nil
  end
  return best, bestDistance
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
