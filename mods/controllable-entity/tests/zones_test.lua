-- Copyright © 2026 Jalapeno Labs

-- Where the entity may not go, as the host: off the shuttle except in capture contracts, out of the game's forbidden
-- areas, and held back near the shuttle. Also which boxes the entity's machine marks.
-- Run from the repository root: lua mods/controllable-entity/tests/zones_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.world = fake.object("World")

local kits = require("entity.kits")

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")
local zones = require("entity.zones")

local function location(x, y, z)
  return { X = x, Y = y, Z = z }
end

-- The events the host sends the entity
local events = {}
links.sendEvent = function(_, kind) table.insert(events, kind) end

local gameState = fake.object("BP_MyGameState_C", {
  Contract = { ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Elimination },
})

-- Hawking's shuttle: its aboard box spans the bay between the airlocks
local function boxComponent(centre, extent, yaw)
  return fake.object("BoxComponent", nil, {
    K2_GetComponentLocation = function() return centre end,
    GetScaledBoxExtent = function() return extent end,
    K2_GetComponentRotation = function() return { Pitch = 0, Yaw = yaw, Roll = 0 } end,
  })
end
local shuttle = fake.object("BP_PlayerShip_C", {
  UseExteriorTrigger = false,
  ExtTriggerBase = fake.invalid(),
  TriggerBoxOverlap = boxComponent(location(9000, 6000, -450), location(2500, 900, 400), 0),
})

-- The lab wing's forbidden area, which the navigation knows: there, only the unfiltered query finds floor
local function inLab(point)
  return math.abs(point.X + 8450) <= 1300 and math.abs(point.Y + 3550) <= 1600
end
fake.objects["/Game/Blueprints/Monsters/IA/NavAssets/QuerryFilter_CheckForbidden.QuerryFilter_CheckForbidden_C"] =
  fake.object("QuerryFilter_CheckForbidden_C")
fake.objects["/Script/NavigationSystem.Default__NavigationSystemV1"] = fake.object("NavigationSystemV1", nil, {
  K2_ProjectPointToNavigation = function(_, _, point, projected, _, filter)
    if filter and inLab(point) then
      return false
    end
    projected.X, projected.Y, projected.Z = point.X, point.Y, point.Z - 60
    return true
  end,
})

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})

-- Standing on the ground unless a test says it's in the air
local squidMovement = fake.object("CharacterMovementComponent", { isOnGround = true }, {
  IsMovingOnGround = function(self) return self.isOnGround end,
})
local squid = fake.object("BP_Monster_Poulpi_C", {
  InVent = false,
  location = location(9000, 2000, -450),
  CharacterMovement = squidMovement,
}, {
  K2_GetActorLocation = function(self) return self.location end,
  K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  K2_TeleportTo = function(self, destination)
    self.location = destination
    return true
  end,
  -- The host's own crouch, as when the host plays the entity: it applies at once
  BPI_Monster_SetInVent = function(self, inVent) self.InVent, self.bIsCrouched = inVent, inVent end,
})
local entity = { monster = squid, kit = kits.byId.Squid, controller = fake.object("BP_MyPlayerController_C") }

local function tick(now, where)
  squid.location = where
  zones.tickHost(entity, now)
end

-- Away from the shuttle, the squid goes where it likes
tick(0, location(9000, 2000, -450))
assert(#events == 0 and not zones.isNearShuttle(squid.location), "far from the shuttle nothing holds the squid")

-- Regression (playtest 6): the entity could guard the shuttle. In its approach it can't sprint, use its ultimate or
-- kill; playtest 9: and isn't told so, to find it out by playing
tick(1, location(9000, 4000, -450))
assert(zones.isNearShuttle(squid.location) and #events == 0, "the approach is the shuttle's, unannounced")

-- Regression (playtest 6): the entity could board and camp the shuttle. Aboard, it's put back where it last stood
tick(2, location(9000, 5500, -450))
assert(squid.location.Y == 4000 and events[#events] == "Denied.Shuttle", "the squid is put back off the shuttle")

-- In capture contracts it may board: the crew may only capture it aboard (capture.lua). The shuttle's closed doors lay
-- an obstacle area the forbidden filter also excludes, and that must not count as forbidden
gameState.Contract.ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Capture
local inLabOnly = inLab
inLab = function(point) return inLabOnly(point) or math.abs(point.Y - 6000) <= 900 end
local eventsBeforeBoarding = #events
tick(10, location(9000, 5500, -450))
assert(squid.location.Y == 5500 and #events == eventsBeforeBoarding, "capture contracts let the entity aboard")
inLab = inLabOnly
gameState.Contract.ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Elimination

-- Leaving the approach lifts its rules
tick(11, location(9000, 2000, -450))
assert(not zones.isNearShuttle(squid.location), "leaving the approach lifts its rules")

-- The game's forbidden areas: the squid is put back where it last stood outside
tick(12, location(-6000, -3550, -150))
tick(20, location(-8450, -3550, -150))
assert(squid.location.X == -6000 and events[#events] == "Denied.Forbidden", "the squid is kept out of the lab wing")
local warned = #events
tick(20.5, location(-8450, -3550, -150))
assert(#events == warned and squid.location.X == -6000, "put back again, with one message every few seconds")

-- Regression (playtest 9): put back into the ducts it last stood in, a friend's squid was teleported there at once,
-- still standing, found no room, and was put back over and over. Back into the ducts, the move waits for the crouch
squid.InVent = true
tick(30, location(-6000, 2000, 200))
-- The friend's squid stands up outside the ducts and walks aboard; the host's crouch waits for the friend's machine
squid.BPI_Monster_SetInVent = function(self, inVent) self.InVent = inVent end
squid.bIsCrouched = false
squid.InVent = false
tick(32, location(9000, 5500, -450))
assert(squid.location.Y == 5500, "a friend's squid not yet crouched isn't teleported into the duct")
fake.runFrames()
assert(squid.location.Y == 5500, "it waits for the crouch")
squid.bIsCrouched = true
fake.runFrames()
assert(squid.location.X == -6000 and squid.location.Z == 200 and squid.InVent, "then goes back into the duct")
squid.BPI_Monster_SetInVent = function(self, inVent) self.InVent, self.bIsCrouched = inVent, inVent end

-- Regression (playtest 9): falling down a shaft over Polar's forbidden underground, the spot remembered was in mid-air,
-- above the hole: put back there, the squid fell in again, over and over. Only a spot it stands on is remembered
squid.InVent = false
tick(40, location(-6000, -3550, -150))
squidMovement.isOnGround = false
tick(41, location(-7000, -3550, 400))
tick(42, location(-7600, -3550, 100))
squidMovement.isOnGround = true
tick(43, location(-8450, -3550, -150))
assert(squid.location.X == -6000 and squid.location.Z == -150, "put back where it last stood, not where it fell from")

-- Playtest 9: a crew elevator won't start with a monster in its car, and a refused start leaves its call screens dead,
-- so the entity could strand the crew on Polar by standing in one. The car is a no-go area, out to a margin, and it is
-- followed as it moves
local carCentre = location(23250, 200, -65)
local carTrigger = fake.object("BoxComponent", nil, {
  K2_GetComponentLocation = function() return carCentre end,
  GetScaledBoxExtent = function() return location(250, 500, 200) end,
  K2_GetComponentRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
})
fake.object("BP_Elevator_Cargo_C", { TriggerVolume = carTrigger })
squid.InVent = false
tick(50, location(23250 + 250 + config.zones.elevatorMargin + 100, 200, -170))
tick(51, location(23250 + 250 + config.zones.elevatorMargin - 20, 200, -170))
assert(events[#events] == "Denied.Elevator" and squid.location.X == 23250 + 250 + config.zones.elevatorMargin + 100,
  "the squid is kept out of the car, short of its margin")
-- The car travels down its tunnel: its box goes with it, and the landing it left is free
carCentre = location(28000, 200, -2765)
fake.now = 60
tick(60, location(23250, 200, -170))
assert(squid.location.X == 23250, "with the car gone, its landing is free")
tick(61, location(28000, 200, -2870))
assert(squid.location.X == 23250, "and the car is kept clear where it now is")
assert(#zones.elevatorBoxes() == 1, "the elevator's box is found by its class")

-- Playtest 9: the squid got into Hawking's reactor room, where the reactor's pulse knocked it down. The AI never paths
-- into a dangerous area, and the forbidden filter doesn't exclude it, so its volume is read as a box: the entity is put
-- back out of it, and the unstuck never puts it there
local function navVolume(areaName, centre)
  local area = fake.object(areaName)
  area.GetFName = function() return fake.name(areaName) end
  return fake.object("NavModifierVolume", { AreaClass = area }, {
    GetActorBounds = function(_, onlyColliding, origin, extent)
      -- A navigation volume's brush doesn't collide: a box of only its colliding parts is empty
      if onlyColliding then
        return
      end
      origin.X, origin.Y, origin.Z = centre.X, centre.Y, centre.Z
      extent.X, extent.Y, extent.Z = 1337, 1150, 150
    end,
  })
end
navVolume("NavArea_DangerousArea_C", location(-9200, 0, -200))
navVolume("NavArea_Null", location(-20000, 0, -200))
squidMovement.isOnGround = true
-- The dangerous areas are looked for again every rescanSeconds
fake.now = 70 + config.areas.rescanSeconds
tick(fake.now, location(-6000, 0, -260))
tick(fake.now + 0.2, location(-9000, 0, -260))
assert(events[#events] == "Denied.Forbidden" and squid.location.X == -6000, "the squid is kept out of the reactor room")
tick(fake.now + 0.4, location(-20000, 0, -260))
assert(squid.location.X == -20000, "another navigation area is no bar")
assert(zones.isForbiddenAt(squid, location(-9000, 0, -260)), "and the unstuck never puts the entity in the room")

-- The entity's markings: the forbidden trigger boxes this machine has loaded, not the game's other trigger boxes
local function triggerBox(areaName, centre)
  return fake.object("TriggerBox", {
    CollisionComponent = fake.object("BoxComponent", { AreaClass = fake.object(areaName) }),
  }, {
    GetActorBounds = function(_, _, origin, extent)
      origin.X, origin.Y, origin.Z = centre.X, centre.Y, centre.Z
      extent.X, extent.Y, extent.Z = 1300, 1600, 600
    end,
  })
end
for _, area in ipairs({ "NavArea_Forbidden_C", "NavArea_Default" }) do
  local trigger = triggerBox(area, location(-8450, -3550, -150))
  trigger.CollisionComponent.AreaClass.GetFName = function() return fake.name(area) end
end
local marked = zones.forbiddenBoxes(squid)
assert(#marked == 2 and marked[1].centre.X == -9200 and marked[2].centre.X == -8450,
  "the reactor room and the forbidden trigger box are marked, and nothing else")

-- Polar's shuttle uses a volume outside it for aboard
shuttle.UseExteriorTrigger = true
shuttle.ExtTriggerBase = fake.object("TriggerVolume", nil, {
  GetActorBounds = function(_, _, origin, extent)
    origin.X, origin.Y, origin.Z = -2500, -1132, 490
    extent.X, extent.Y, extent.Z = 2285, 902, 350
  end,
})
assert(zones.isNearShuttle(location(-2500, -1132 - 902 - config.zones.shuttleApproach + 10, 490)),
  "Polar's approach is measured from its exterior trigger")

print("zones test passed")
