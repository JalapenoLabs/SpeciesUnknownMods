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

-- The shaft nearest a location across the floor, within reach and on the same floor, or nil. The squid climbs in
-- from the room below a shaft and drops out from the duct above it, so the floor distance is what matters either way.
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
  return best
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
