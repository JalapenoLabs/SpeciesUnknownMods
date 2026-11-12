-- Copyright © 2026 Jalapeno Labs

-- The areas around the entity, on their own machine: the squid's collision never overlaps the game's trigger volumes,
-- so the mod tells each volume's manager when the squid is inside it (the map sections, and the map's deck layer),
-- and hands the volumes back when the player stops driving the squid.
-- Run from the repository root: lua mods/controllable-entity/tests/areas_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.isHost = false

local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modAssets)
fake.object("GameStateBase")
fake.world = fake.object("World")

local controller = fake.object("BP_MyPlayerController_C", { Pawn = fake.invalid() }, {
  IsLocalController = function() return true end,
}, { "PlayerController" })
fake.giveView(controller)

local squid = fake.object("BP_Monster_Poulpi_C", { location = { X = 0, Y = 0, Z = 0 } }, {
  K2_GetActorLocation = function(self) return self.location end,
})
fake.giveSquidState(squid)

-- A volume around X = 0 and one around X = 1500, each 1000 units wide, each with its own manager. GetActorBounds
-- returns its box through two struct out parameters, which UE4SS fills field by field into the table passed for
-- each (playtest 5: AVolume.EncompassesPoint isn't callable from Lua, and one table for both lost the origin)
local function volume(centreX)
  return fake.object("TriggerVolume", nil, {
    GetActorBounds = function(_, _, origin, extent)
      origin.X, origin.Y, origin.Z = centreX, 0, 0
      extent.X, extent.Y, extent.Z = 500, 500, 500
    end,
  })
end
local nearVolume, farVolume = volume(0), volume(1500)
local function manager(trigger)
  return fake.object("BP_StreamingVolume_Manager_C", { TriggerVolumeList = fake.array({ trigger }) })
end
local nearManager, farManager = manager(nearVolume), manager(farVolume)

-- The map's deck layers: crew quarters' trigger around X = 1500, and the safe zone's around X = 5000, where the crew
-- start. Each trigger is an actor carrying a TriggerMap_ActorComponent
local mapManager = fake.object("BP_MapManagerExtended_C")
local function mapTrigger(centreX)
  local trigger = volume(centreX)
  fake.object("TriggerMap_ActorComponent_C", nil, { GetOwner = function() return trigger end })
  return trigger
end
local crewQuartersTrigger, safeZoneTrigger = mapTrigger(1500), mapTrigger(5000)
local function mapCalls(method, trigger)
  local count = 0
  for _, call in ipairs(fake.callsTo(mapManager, method)) do
    if call.args[1] == trigger and call.args[2] == squid then
      count = count + 1
    end
  end
  return count
end

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
-- Regression (playtest 6): the minimap stayed on the safe zone, where the player's crew body last stood: once the
-- player drives the squid, the body's own end-overlap no longer counts, so the squid leaves those triggers by hand
assert(mapCalls("EndOverlap", safeZoneTrigger) == 1, "the crew body's map triggers are left when the squid is taken")
assert(mapCalls("BeginOverlap", crewQuartersTrigger) == 0, "and no deck is entered away from its trigger")

-- Moving into the far volume leaves the near one
squid.location = { X = 1500, Y = 0, Z = 0 }
fake.runLoops(250)
assert(entries(nearManager)[2] == false, "the old volume is left")
assert(entries(farManager)[1] == true, "the new one entered")
-- Regression (playtest 6): walking into crew quarters left the minimap on the deck below
assert(mapCalls("BeginOverlap", crewQuartersTrigger) == 1, "the minimap switches to crew quarters' deck")
fake.runLoops(250)
assert(mapCalls("BeginOverlap", crewQuartersTrigger) == 1, "once")
assert(mapCalls("EndOverlap", safeZoneTrigger) == 1, "the stale triggers are left only when the squid is taken")

-- Regression (playtest 9): high in the ducts over the labs, above every map section's volume, the whole ship below
-- went invisible. A section's volume reaches higher for the entity; the deck's triggers don't, or the minimap could
-- draw the deck below
local config = require("entity.config")
local mapEntriesBefore = mapCalls("EndOverlap", crewQuartersTrigger)
squid.location = { X = 1500, Y = 0, Z = 500 + config.areas.sectionHeadroom - 50 }
fake.runLoops(250)
assert(#entries(farManager) == 1, "high over the section, the squid is still in its volume")
assert(mapCalls("EndOverlap", crewQuartersTrigger) == mapEntriesBefore + 1, "but out of the deck's trigger")
squid.location = { X = 1500, Y = 0, Z = 500 + config.areas.sectionHeadroom + 50 }
fake.runLoops(250)
assert(entries(farManager)[2] == false, "higher still, it leaves the section")
squid.location = { X = 1500, Y = 0, Z = 0 }
fake.runLoops(250)
assert(entries(farManager)[3] == true, "and back down, enters it again")

-- Once the player stops driving the squid, the volumes are handed back
local crewQuartersLeft = mapCalls("EndOverlap", crewQuartersTrigger)
controller.Pawn = fake.invalid()
fake.runLoops(250)
assert(entries(farManager)[4] == false, "the volume is left when the player stops driving the squid")
assert(mapCalls("EndOverlap", crewQuartersTrigger) == crewQuartersLeft + 1, "and so is the deck's trigger")

print("areas test passed")
