-- Copyright © 2026 Jalapeno Labs

-- Where the entity may not go, and where it is held back (playtest 6). The AI keeps out of the game's forbidden areas
-- and never camps the crew's shuttle; a player would do both.
--
--   - Forbidden areas are where the game's own AI may not path (NavArea_Forbidden: the genetics lab's wing on Hawking,
--     the electrical area on Polar). The host asks the navigation itself whether the entity stands in one: a point
--     projects onto the navmesh through the game's QuerryFilter_CheckForbidden only outside them. The AI also keeps out
--     of the dangerous areas (NavArea_DangerousArea: Hawking's reactor room, whose pulse knocks anything inside down),
--     which that filter doesn't exclude, so their volumes are read as boxes (playtest 9: the squid leapt in).
--   - Aboard the shuttle (BP_PlayerShip) is its own bay box, the one its launch check uses. The entity may not board,
--     except in capture contracts (capture.lua). A wider box around it takes in the approach: there the entity can't
--     sprint, use its ultimate, or kill, so the crew can get to and from their shuttle.
-- The host puts an entity that strays into a forbidden area or aboard back where it last stood outside. The entity sees
-- the edges as glowing posts (vision.lua), and a line on its HUD while it's near the shuttle.

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")
local vents = require("entity.vents")

local zones = {}

local SHUTTLE_CLASS_NAME = "BP_PlayerShip_C"
local FORBIDDEN_FILTER =
  "/Game/Blueprints/Monsters/IA/NavAssets/QuerryFilter_CheckForbidden.QuerryFilter_CheckForbidden_C"
local FORBIDDEN_AREA_CLASS_NAME = "NavArea_Forbidden_C"
local TRIGGER_BOX_CLASS_NAME = "TriggerBox"
local DYNAMIC_FORBIDDEN_CLASS_NAME = "BP_DynamicNav_Forbidden_C"
local NAV_MODIFIER_CLASS_NAME = "NavModifierVolume"
local DANGEROUS_AREA_CLASS_NAME = "NavArea_DangerousArea_C"
-- How far around the entity the navigation looks for floor under it: the entity's centre stands about its half height
-- above the floor, and a narrow reach keeps an allowed floor just outside a forbidden area from counting.
local FLOOR_PROBE_EXTENT = { X = 60, Y = 60, Z = 250 }

-- On the host, per monster: where it last stood outside every forbidden place and whether that was in the vents, when
-- it was last told to keep out, and whether it was near the shuttle at the last check.
local function freshHold(monsterAddress)
  return {
    monsterAddress = monsterAddress,
    lastAllowed = nil,
    lastAllowedInVent = false,
    lastWarnedAt = -math.huge,
  }
end

local held = freshHold(nil)

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Boxes
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- A box zone is { centre, extent, yaw }: its half extents along its own axes, turned by yaw degrees about Z. An
-- actor's bounding box (its colliding parts), as a zone square to the world.
local function boundsBox(actor, isAnyComponent)
  local origin, extent = {}, {}
  actor:GetActorBounds(isAnyComponent ~= true, origin, extent, false)
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

-- The crew's elevators (Polar's two; Hawking has none). One won't start while a monster is in its car: its trigger box
-- counts any monster it overlaps (BP_ElevatorParent.MonsterInside), and a refused start leaves the landing's call
-- screen dead until someone rides the car, so an entity standing in one strands the crew (playtest 9). Each car is a
-- no-go area for the entity: its trigger box, read again every tick since it rides with the car. The concrete classes
-- are listed, so a lookup that doesn't match subclasses still finds them.
local ELEVATOR_CLASS_NAMES = { "BP_Elevator_Cargo_C", "BP_Elevator_Simple_C" }

function zones.elevatorBoxes()
  local boxes = {}
  for _, className in ipairs(ELEVATOR_CLASS_NAMES) do
    for _, elevator in ipairs(FindAllOf(className) or {}) do
      local trigger = elevator:IsValid() and elevator.TriggerVolume
      local box = trigger and trigger:IsValid() and zones.componentBox(trigger)
      if box then
        table.insert(boxes, box)
      end
    end
  end
  return boxes
end

local function isInAnElevator(location)
  for _, box in ipairs(zones.elevatorBoxes()) do
    if zones.isInside(box, location, config.zones.elevatorMargin) then
      return true
    end
  end
  return false
end

-- The dangerous areas' boxes (the reactor room), cached per world and looked for again every
-- config.areas.rescanSeconds: the host checks them five times a second, each lookup walks every object in the game,
-- and a section streams its volumes in with it. A navigation volume's brush doesn't collide, so its box takes every
-- component.
local dangerous = { worldKey = nil, nextScanAt = 0, boxes = {} }

function zones.dangerousBoxes(monster)
  local worldKey = monster:GetWorld():GetAddress()
  local now = game.timeSeconds(monster)
  if worldKey == dangerous.worldKey and now < dangerous.nextScanAt then
    return dangerous.boxes
  end
  local boxes = {}
  for _, volume in ipairs(FindAllOf(NAV_MODIFIER_CLASS_NAME) or {}) do
    local area = volume:IsValid() and volume.AreaClass
    local isDangerous = area and area:IsValid() and area:GetFName():ToString() == DANGEROUS_AREA_CLASS_NAME
    local box = isDangerous and boundsBox(volume, true)
    if box then
      table.insert(boxes, box)
    end
  end
  dangerous = { worldKey = worldKey, nextScanAt = now + config.areas.rescanSeconds, boxes = boxes }
  return boxes
end

local function isInDangerousArea(monster, location)
  for _, box in ipairs(zones.dangerousBoxes(monster)) do
    if zones.isInside(box, location) then
      return true
    end
  end
  return false
end

-- Every place the entity may not go, as boxes, for the red posts that mark them (vision.lua): the dangerous areas, the
-- trigger boxes carrying the forbidden navigation area (Hawking's lab wing, in a streamed section) and the forbidden
-- blocks spawned at runtime (Polar). The host's check of forbidden floor asks the navigation, which knows them all.
function zones.forbiddenBoxes(monster)
  local boxes = {}
  for _, box in ipairs(zones.dangerousBoxes(monster)) do
    table.insert(boxes, box)
  end
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

-- Whether the entity stands on forbidden floor: on the navmesh, but not where the forbidden-area filter allows. In the
-- air (mid-leap) it stands on no floor, so it isn't.
local function isOnForbiddenFloor(monster, location)
  local navigation = StaticFindObject(game.paths.navigation)
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

-- Whether a spot is somewhere the entity may not go, for the unstuck (unstuck.lua), which mustn't put it in one.
function zones.isForbiddenAt(monster, location)
  return isInDangerousArea(monster, location) or isOnForbiddenFloor(monster, location)
end

-- Puts the entity back where it last stood allowed. Back into the ducts, the move waits for the entity to crouch,
-- which a friend's own machine applies a moment later (vents.moveInto): teleported there at once, still standing, it
-- found no room and stayed where it was, put back again and again (playtest 9). Standing, it's teleported at once.
local function putBack(entity, now, reason)
  local monster = entity.monster
  local spot = held.lastAllowed
  local location = monster:K2_GetActorLocation()
  local isPlaced = true
  if spot and held.lastAllowedInVent then
    vents.moveInto(monster, spot)
  elseif spot then
    if monster.InVent == true then
      monster:BPI_Monster_SetInVent(false)
    end
    isPlaced = monster:K2_TeleportTo(spot, monster:K2_GetActorRotation()) == true
  end
  if now - held.lastWarnedAt >= config.zones.warningInterval then
    held.lastWarnedAt = now
    links.sendEvent(entity.controller, reason)
    game.log("Put the entity back: %s, from %.0f, %.0f, %.0f%s", reason, location.X, location.Y, location.Z,
      isPlaced and "" or " (no room where it last stood)")
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
  elseif isInAnElevator(location) then
    putBack(entity, now, "Denied.Elevator")
  -- The AI never paths into a dangerous area (the reactor room), so neither does the entity
  elseif isInDangerousArea(monster, location) then
    putBack(entity, now, "Denied.Forbidden")
  -- The shuttle is never a forbidden area, but its closed doors lay an obstacle area the forbidden filter also excludes
  elseif not isAboard and isOnForbiddenFloor(monster, location) then
    putBack(entity, now, "Denied.Forbidden")
  -- Only a spot the entity stands on (the ground, or the ducts) is somewhere to put it back: one remembered in mid-air,
  -- falling down a shaft over the forbidden underground on Polar, put it back above the hole to fall in again, over
  -- and over (playtest 9)
  elseif monster.InVent == true or monster.CharacterMovement:IsMovingOnGround() then
    held.lastAllowed = { X = location.X, Y = location.Y, Z = location.Z }
    held.lastAllowedInVent = monster.InVent == true
  end
end

return zones
