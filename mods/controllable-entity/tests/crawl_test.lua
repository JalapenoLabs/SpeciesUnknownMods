-- Copyright © 2026 Jalapeno Labs

-- The floor-level openings the crew crouch through, as the host: the squid heading into one crouches into its vent
-- state; coming back out, the game's own trigger stands it up, and the mod leaves it standing.
-- Run from the repository root: lua mods/controllable-entity/tests/crawl_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local kits = require("entity.kits")

local crawl = require("entity.crawl")
local hunt = require("entity.hunt")

local function location(x, y, z)
  return { X = x, Y = y, Z = z }
end

-- A crew-quarters opening: its trigger is thin along its forward (+X, into the duct)
local function opening(isEntrance)
  return fake.object("BP_Trigger_Crouch_C", {
    VentEnter = isEntrance,
    CollisionComponent = fake.object("BoxComponent", nil, {
      K2_GetComponentLocation = function() return location(300, 6150, -210) end,
      GetScaledBoxExtent = function() return location(30, 150, 150) end,
      K2_GetComponentRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
    }),
  }, {
    GetActorForwardVector = function() return location(1, 0, 0) end,
  })
end
opening(true)

local squid = fake.object("BP_Monster_Poulpi_C", { InVent = false, velocity = location(0, 0, 0) }, {
  K2_GetActorLocation = function() return location(220, 6150, -210) end,
  GetVelocity = function(self) return self.velocity end,
  BPI_Monster_SetInVent = function(self, inVent)
    table.insert(fake.calls, { object = self, method = "BPI_Monster_SetInVent", args = { inVent } })
    self.InVent = inVent
  end,
})
local entity = { monster = squid, kit = kits.byId.Squid }
local function crouches()
  return #fake.callsTo(squid, "BPI_Monster_SetInVent")
end

-- Standing at the opening, or walking away from it (as after the game stood the squid back up), it stays standing
crawl.tickHost(entity)
squid.velocity = location(-300, 0, 0)
crawl.tickHost(entity)
assert(crouches() == 0, "the squid only crouches heading in")

-- Regression (playtest 6): the standing squid didn't fit through the openings the crew crouch through. Heading in, it
-- crouches into its vent state
squid.velocity = location(300, 0, 0)
crawl.tickHost(entity)
assert(crouches() == 1 and squid.InVent, "heading into the opening, the squid crouches into the ducts")
crawl.tickHost(entity)
assert(crouches() == 1, "once")

-- Not while the hunt has shut the vents to it
squid.InVent = false
hunt.areVentsShut = function() return true end
crawl.tickHost(entity)
assert(crouches() == 1, "the vents shut to the squid stay shut through the openings too")

print("crawl test passed")
