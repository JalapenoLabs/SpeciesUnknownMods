-- Copyright © 2026 Jalapeno Labs

-- Where the entity may not go, and where it is held back (playtest 6). The AI keeps out of the game's forbidden areas
-- and never camps the crew's shuttle; a player would do both.
--
--   - Forbidden areas are where the game's own AI may not path (NavArea_Forbidden: the genetics lab's wing on Hawking,
--     the electrical area on Polar). The host asks the navigation itself whether the squid stands in one: a point
--     projects onto the navmesh through the game's QuerryFilter_CheckForbidden only outside them.
--   - Aboard the shuttle (BP_PlayerShip) is its own bay box, the one its launch check uses. The entity may not board,
--     except in capture contracts (capture.lua). A wider box around it takes in the approach: there the entity can't
--     sprint, use its ultimate, or kill, so the crew can get to and from their shuttle.
-- The host puts a squid that strays into a forbidden area or aboard back where it last stood outside. The entity sees
-- the edges as glowing posts (vision.lua), and a line on its HUD while it's near the shuttle.

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")

local zones = {}

local SHUTTLE_CLASS_NAME = "BP_PlayerShip_C"
local NAVIGATION = "/Script/NavigationSystem.Default__NavigationSystemV1"
local FORBIDDEN_FILTER =
  "/Game/Blueprints/Monsters/IA/NavAssets/QuerryFilter_CheckForbidden.QuerryFilter_CheckForbidden_C"
local FORBIDDEN_AREA_CLASS_NAME = "NavArea_Forbidden_C"
local TRIGGER_BOX_CLASS_NAME = "TriggerBox"
local DYNAMIC_FORBIDDEN_CLASS_NAME = "BP_DynamicNav_Forbidden_C"
-- How far around the squid the navigation looks for floor under it: the squid's centre stands about its half height
-- above the floor, and a narrow reach keeps an allowed floor just outside a forbidden area from counting.
local FLOOR_PROBE_EXTENT = { X = 60, Y = 60, Z = 250 }

-- On the host, per squid: where it last stood outside every forbidden place and whether that was in the vents, when
-- it was last told to keep out, and whether it was near the shuttle at the last check.
local function freshHold(monsterAddress)
  return {
    monsterAddress = monsterAddress,
    lastAllowed = nil,
    lastAllowedInVent = false,
    lastWarnedAt = -math.huge,
    isNearShuttle = false,
  }
end

local held = freshHold(nil)

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Boxes
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- A box zone is { centre, extent, yaw }: its half extents along its own axes, turned by yaw degrees about Z. An
-- actor's bounding box (its colliding parts), as a zone square to the world.
local function boundsBox(actor)
  local origin, extent = {}, {}
  actor:GetActorBounds(true, origin, extent, false)
  if not origin.X or not extent.X then
    return nil
  end
  return { centre = origin, extent = extent, yaw = 0 }
end

-- A box component's own box, as a zone.
function zones.componentBox(component)
  local centre = component:K2_GetComponentLocation()
  local extent = component:GetScaledBoxExtent()
  return {
    centre = { X = centre.X, Y = centre.Y, Z = centre.Z },
    extent = { X = extent.X, Y = extent.Y, Z = extent.Z },
    yaw = component:K2_GetComponentRotation().Yaw,
  }
end

-- Whether a location is inside a box grown by `margin` across the floor (not up or down: other decks aren't near).
function zones.isInside(box, location, margin)
  local grow = margin or 0
  local offsetX, offsetY = location.X - box.centre.X, location.Y - box.centre.Y
  local yaw = math.rad(box.yaw)
  local alongX = offsetX * math.cos(yaw) + offsetY * math.sin(yaw)
  local alongY = -offsetX * math.sin(yaw) + offsetY * math.cos(yaw)
  return math.abs(alongX) <= box.extent.X + grow and math.abs(alongY) <= box.extent.Y + grow
    and math.abs(location.Z - box.centre.Z) <= box.extent.Z
end

-- The shuttle's aboard box, or nil without a shuttle. Polar's shuttle uses a volume outside it instead of its own box
-- (UseExteriorTrigger, ExtTriggerBase).
function zones.shuttleBox()
  local shuttle = FindFirstOf(SHUTTLE_CLASS_NAME)
  if not shuttle or not shuttle:IsValid() then
    return nil
  end
  if shuttle.UseExteriorTrigger and shuttle.ExtTriggerBase:IsValid() then
    return boundsBox(shuttle.ExtTriggerBase)
  end
  return zones.componentBox(shuttle.TriggerBoxOverlap)
end

-- Whether a location is near the shuttle: in its approach, where the entity can't sprint, use its ultimate, or kill.
function zones.isNearShuttle(location)
  local box = zones.shuttleBox()
  return box ~= nil and zones.isInside(box, location, config.zones.shuttleApproach)
end

-- The forbidden areas this machine has loaded, as boxes: the trigger boxes carrying the forbidden navigation area
-- (Hawking's lab wing, in a streamed section) and the forbidden blocks spawned at runtime (Polar). For the markings
-- only; the host's check asks the navigation, which knows them all.
function zones.forbiddenBoxes()
  local boxes = {}
  for _, trigger in ipairs(FindAllOf(TRIGGER_BOX_CLASS_NAME) or {}) do
    local area = trigger:IsValid() and trigger.CollisionComponent.AreaClass
    local isForbidden = area and area:IsValid() and area:GetFName():ToString() == FORBIDDEN_AREA_CLASS_NAME
    local box = isForbidden and boundsBox(trigger)
    if box then
      table.insert(boxes, box)
    end
  end
  for _, block in ipairs(FindAllOf(DYNAMIC_FORBIDDEN_CLASS_NAME) or {}) do
    if block:IsValid() then
      table.insert(boxes, zones.componentBox(block.BoxBlockPawn))
    end
  end
  return boxes
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The host
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Whether the squid stands on forbidden floor: on the navmesh, but not where the forbidden-area filter allows. In the
-- air (mid-leap) it stands on no floor, so it isn't.
local function isOnForbiddenFloor(monster, location)
  local navigation = StaticFindObject(NAVIGATION)
  local filter = game.loadGameAsset(FORBIDDEN_FILTER)
  if not filter then
    return false
  end
  local allowedFloor, anyFloor = {}, {}
  if navigation:K2_ProjectPointToNavigation(monster, location, allowedFloor, nil, filter, FLOOR_PROBE_EXTENT) then
    return false
  end
  return navigation:K2_ProjectPointToNavigation(monster, location, anyFloor, nil, nil, FLOOR_PROBE_EXTENT) == true
end

local function putBack(entity, now, reason)
  local monster = entity.monster
  if held.lastAllowed then
    if (monster.InVent == true) ~= held.lastAllowedInVent then
      monster:BPI_Monster_SetInVent(held.lastAllowedInVent)
    end
    monster:K2_TeleportTo(held.lastAllowed, monster:K2_GetActorRotation())
  end
  if now - held.lastWarnedAt >= config.zones.warningInterval then
    held.lastWarnedAt = now
    links.sendEvent(entity.controller, reason)
    game.log("Put the squid back: %s", reason)
  end
end

-- Runs five times a second on the host while there is an entity.
function zones.tickHost(entity, now)
  local monster = entity.monster
  if held.monsterAddress ~= monster:GetAddress() then
    held = freshHold(monster:GetAddress())
  end

  local location = monster:K2_GetActorLocation()
  local shuttle = zones.shuttleBox()
  local isAboard = shuttle ~= nil and zones.isInside(shuttle, location)
  -- Only capture contracts let the entity aboard (capture.lua)
  if isAboard and game.contractType() ~= game.contractTypes.Capture then
    putBack(entity, now, "Denied.Shuttle")
  -- The shuttle is never a forbidden area, but its closed doors lay an obstacle area the forbidden filter also excludes
  elseif not isAboard and isOnForbiddenFloor(monster, location) then
    putBack(entity, now, "Denied.Forbidden")
  else
    held.lastAllowed = { X = location.X, Y = location.Y, Z = location.Z }
    held.lastAllowedInVent = monster.InVent == true
  end

  local isNearShuttle = shuttle ~= nil and zones.isInside(shuttle, location, config.zones.shuttleApproach)
  if isNearShuttle ~= held.isNearShuttle then
    held.isNearShuttle = isNearShuttle
    links.sendEvent(entity.controller, isNearShuttle and "ShuttleNear" or "ShuttleLeft")
  end
end

return zones
