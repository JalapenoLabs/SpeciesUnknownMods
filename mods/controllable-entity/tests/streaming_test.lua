-- Copyright © 2026 Jalapeno Labs

-- Map sections around the entity, on their own machine: the squid's collision never overlaps the game's streaming
-- volumes, so the mod tells each volume's manager when the squid is inside it, and hands the volumes back when the
-- player stops driving the squid.
-- Run from the repository root: lua mods/controllable-entity/tests/streaming_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.isHost = false

local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
local volumeClass = fake.object("VolumeClass")
fake.objects["/Script/Engine.Volume"] = volumeClass
fake.installModPak(game.modClasses)
fake.object("GameStateBase")
fake.world = fake.object("World")

local controller = fake.object("BP_MyPlayerController_C", { Pawn = fake.invalid() }, {
  IsLocalController = function() return true end,
}, { "PlayerController" })
fake.giveView(controller)

local squid = fake.object("BP_Monster_Poulpi_C", { location = { X = 0, Y = 0, Z = 0 } }, {
  K2_GetActorLocation = function(self) return self.location end,
})

-- A volume covering X from -500 to 500, and one covering X from 1000 to 2000, each with its own manager
local function volume(minimumX, maximumX)
  return fake.object("TriggerVolume", nil, {
    IsA = function(_, class) return class == volumeClass end,
    EncompassesPoint = function(_, point) return point.X >= minimumX and point.X <= maximumX end,
  })
end
local nearVolume, farVolume = volume(-500, 500), volume(1000, 2000)
local function manager(trigger)
  return fake.object("BP_StreamingVolume_Manager_C", { TriggerVolumeList = fake.array({ trigger }) })
end
local nearManager, farManager = manager(nearVolume), manager(farVolume)

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

local function entries(target)
  local calls = fake.callsTo(target, "BPI_Streaming_AddActorToTrigger")
  local states = {}
  for _, call in ipairs(calls) do
    table.insert(states, call.args[3])
  end
  return states
end

-- As crew, the game's own overlaps do the work
fake.runLoops(250)
assert(#entries(nearManager) == 0, "nothing is entered for the crew")

-- Driving the squid: the volume it stands in is entered, once
controller.Pawn = squid
fake.runLoops(250)
fake.runLoops(250)
assert(#entries(nearManager) == 1 and entries(nearManager)[1] == true, "the squid's volume is entered once")
assert(#entries(farManager) == 0, "other volumes are left alone")

-- Moving into the far volume leaves the near one
squid.location = { X = 1500, Y = 0, Z = 0 }
fake.runLoops(250)
assert(entries(nearManager)[2] == false, "the old volume is left")
assert(entries(farManager)[1] == true, "the new one entered")

-- Once the player stops driving the squid, the volumes are handed back
controller.Pawn = fake.invalid()
fake.runLoops(250)
assert(entries(farManager)[2] == false, "the volume is left when the player stops driving the squid")

print("streaming test passed")
