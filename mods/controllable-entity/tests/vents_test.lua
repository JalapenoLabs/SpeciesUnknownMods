-- Copyright © 2026 Jalapeno Labs

-- Moving the entity into the ducts, on the host (vents.moveInto). Only the crouched capsule fits a duct, and the
-- game's SetInVent crouches the monster on the host alone; a monster a friend plays crouches only once their own
-- machine says so (movement.lua), a round trip later. So the move waits for the crouch, a newer move replaces one
-- still waiting, and one that never crouches is placed anyway after a while.
-- Run from the repository root: lua mods/controllable-entity/tests/vents_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local game = require("entity.game")
local vents = require("entity.vents")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})

-- A squid a friend plays: the host's SetInVent sets the vent state, but the crouch waits for their machine
local squid = fake.object("BP_Monster_Poulpi_C", { InVent = false, bIsCrouched = false }, {
  K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  BPI_Monster_SetInVent = function(self, inVent)
    table.insert(fake.calls, { object = self, method = "BPI_Monster_SetInVent", args = { inVent } })
    self.InVent = inVent
  end,
  K2_TeleportTo = function(self, destination)
    table.insert(fake.calls, { object = self, method = "K2_TeleportTo", args = { destination } })
    return true
  end,
})
local function teleports()
  return fake.callsTo(squid, "K2_TeleportTo")
end

-- Regression (playtest 9): the start teleported a friend's squid two frames after SetInVent, still standing: there
-- was no room, it was placed in the duct's floor, and it fell out of the vent over and over
local arrived = 0
vents.moveInto(squid, { X = 100, Y = 0, Z = 0 }, function() arrived = arrived + 1 end)
fake.runFrames()
assert(#teleports() == 0, "a squid not yet crouched waits")
-- The lair pulls it back again while it waits: the newer move replaces the waiting one
vents.moveInto(squid, { X = 200, Y = 0, Z = 0 }, function() arrived = arrived + 1 end)
assert(#fake.callsTo(squid, "BPI_Monster_SetInVent") == 1, "the vent state is set once")
fake.runFrames()
assert(#teleports() == 0, "still waiting")
squid.bIsCrouched = true
fake.runFrames()
assert(#teleports() == 1 and teleports()[1].args[1].X == 200, "once crouched, it moves, to the newest spot, once")
assert(arrived == 1, "and the newest move's callback runs")
fake.runFrames()
assert(#teleports() == 1, "nothing is left waiting")

-- A squid that never crouches is moved in anyway after a while, standing
squid.bIsCrouched = false
fake.now = 10
vents.moveInto(squid, { X = 300, Y = 0, Z = 0 })
fake.runFrames()
assert(#teleports() == 1, "it waits a while")
fake.now = 13.5
fake.runFrames()
assert(#teleports() == 2 and teleports()[2].args[1].X == 300, "then gives up waiting")

print("vents test passed")
