-- Copyright © 2026 Jalapeno Labs

-- Where the entity may not go, as the host: off the shuttle except in capture contracts, out of the game's forbidden
-- areas, and held back near the shuttle. Also which boxes the entity's machine marks.
-- Run from the repository root: lua mods/controllable-entity/tests/zones_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

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

local squid = fake.object("BP_Monster_Poulpi_C", { InVent = false, location = location(9000, 2000, -450) }, {
  K2_GetActorLocation = function(self) return self.location end,
  K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  K2_TeleportTo = function(self, destination)
    self.location = destination
    return true
  end,
  BPI_Monster_SetInVent = function(self, inVent) self.InVent = inVent end,
})
local entity = { squid = squid, controller = fake.object("BP_MyPlayerController_C") }

local function tick(now, where)
  squid.location = where
  zones.tickHost(entity, now)
end

-- Away from the shuttle, the squid goes where it likes
tick(0, location(9000, 2000, -450))
assert(#events == 0 and not zones.isNearShuttle(squid.location), "far from the shuttle nothing holds the squid")

-- Regression (playtest 6): the entity could guard the shuttle. In its approach it can't sprint, use its ultimate or
-- kill, and its HUD says so
tick(1, location(9000, 4000, -450))
assert(zones.isNearShuttle(squid.location) and events[#events] == "ShuttleNear", "the approach is the shuttle's")

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

-- Leaving the approach clears the HUD's line
tick(11, location(9000, 2000, -450))
assert(events[#events] == "ShuttleLeft", "leaving the approach lifts its rules")

-- The game's forbidden areas: the squid is put back where it last stood outside
tick(12, location(-6000, -3550, -150))
tick(20, location(-8450, -3550, -150))
assert(squid.location.X == -6000 and events[#events] == "Denied.Forbidden", "the squid is kept out of the lab wing")
local warned = #events
tick(20.5, location(-8450, -3550, -150))
assert(#events == warned and squid.location.X == -6000, "put back again, with one message every few seconds")

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
local marked = zones.forbiddenBoxes()
assert(#marked == 1 and marked[1].centre.X == -8450, "only the forbidden trigger box is marked")

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
