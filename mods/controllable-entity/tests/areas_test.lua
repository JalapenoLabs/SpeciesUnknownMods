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

-- Regression (playtest 9): the reactor core and the engineering water switch on only while the local player stands in
-- their own volumes, so neither ever showed for the entity. Its machine tells them, through their own overlap calls
squid.location = { X = 1500, Y = 0, Z = 0 }
local reactorVolume, reactorShakeVolume, waterVolume = volume(9000), volume(9200), volume(1500)
local reactor = fake.object("BP_CoreReactor_C", {
  TriggerVolume = reactorVolume,
  TriggerVolumeShake = reactorShakeVolume,
})
local water = fake.object("BP_Water_C", { TriggerVolume = waterVolume })
-- The entity's machine looks for the actors it follows on a new world and every rescanSeconds
fake.now = fake.now + config.areas.rescanSeconds
local function calls(target, method)
  local found = {}
  for _, call in ipairs(fake.callsTo(target, method)) do
    if call.args[2] == squid then
      table.insert(found, call.args[1])
    end
  end
  return found
end
fake.runLoops(250)
assert(#calls(water, "BeginOverlap") == 1 and calls(water, "BeginOverlap")[1] == waterVolume, "the water shows")
assert(#calls(reactor, "BeginOverlap") == 0, "a reactor far away stays dark")
squid.location = { X = 9000, Y = 0, Z = 0 }
fake.runLoops(250)
assert(#calls(water, "EndOverlap") == 1, "leaving the water's volume hides it again")
assert(#calls(reactor, "BeginOverlap") == 1 and calls(reactor, "BeginOverlap")[1] == reactorVolume,
  "the reactor core shows")
assert(#calls(reactor, "BeginOverlapShake") == 1 and calls(reactor, "BeginOverlapShake")[1] == reactorShakeVolume,
  "and its shake reaches the entity")
squid.location = { X = 1500, Y = 0, Z = 0 }
fake.runLoops(250)
assert(#calls(reactor, "EndOverlap") == 1 and #calls(reactor, "EndOverlapShake") == 1, "both end on leaving")
-- The audit (#4): Hawking's vent wall fans, Polar's control tower (its interior, switched directly) and Polar's
-- soundscape (a list of triggers it counts) switch on for the entity too
local fanVolume, towerVolume, soundVolume = volume(3000), volume(3000), volume(3000)
local fan = fake.object("BP_VentWall_C", { TriggerVolume = fanVolume })
local tower = fake.object("BP_TowerControl_C", { TriggerVolume = towerVolume })
local ambience = fake.object("BP_AmbientMain_POLAR_C", { TriggerVolumeList = fake.array({ soundVolume }) })
fake.now = fake.now + config.areas.rescanSeconds
squid.location = { X = 3000, Y = 0, Z = 0 }
fake.runLoops(250)
assert(#calls(fan, "BeginOverlap") == 1 and calls(fan, "BeginOverlap")[1] == fanVolume, "the vent fan shows")
assert(#calls(ambience, "BeginOverlap") == 1 and calls(ambience, "BeginOverlap")[1] == soundVolume,
  "the area's sound plays")
local towerSwitches = fake.callsTo(tower, "Inside")
assert(#towerSwitches == 1 and towerSwitches[1].args[1] == true, "the tower's interior shows")
squid.location = { X = 1500, Y = 0, Z = 0 }
fake.runLoops(250)
towerSwitches = fake.callsTo(tower, "Inside")
assert(#calls(fan, "EndOverlap") == 1 and #calls(ambience, "EndOverlap") == 1, "and all switch off on leaving")
assert(#towerSwitches == 2 and towerSwitches[2].args[1] == false, "the tower too")
local farEntries = #entries(farManager)

-- The rest of the audit (#4). The shuttle's inside: its trigger is a box on the ship, turned with it, and moves with
-- it, so it's read live. The crew start aboard, so the entity first leaves it, or the outside would stay silent
local function boxComponent(centre, extent, yaw)
  return fake.object("BoxComponent", { centre = centre }, {
    K2_GetComponentLocation = function(self) return self.centre end,
    K2_GetComponentRotation = function() return { Pitch = 0, Yaw = yaw, Roll = 0 } end,
    GetScaledBoxExtent = function() return extent end,
  })
end
-- A long, thin box along Y (turned 90 degrees): 100 units across X, 800 along Y
local shuttleBox = boxComponent({ X = 6000, Y = 0, Z = 0 }, { X = 400, Y = 50, Z = 200 }, 90)
local shuttle = fake.object("BP_PlayerShip_C", {
  UseExteriorTrigger = false,
  TriggerBoxOverlapVisual = shuttleBox,
  ExtTriggerVisual = fake.invalid(),
})
local function shipCalls(method)
  local found = 0
  for _, call in ipairs(fake.callsTo(shuttle, method)) do
    if call.args[2] == squid then
      found = found + 1
    end
  end
  return found
end
-- A new entity, as at the takeover
squid.destroyed = true
local newSquid = fake.object("BP_Monster_Poulpi_C", { location = { X = 6300, Y = 0, Z = 0 } }, {
  K2_GetActorLocation = function(self) return self.location end,
})
fake.giveSquidState(newSquid)
squid = newSquid
controller.Pawn = squid
fake.now = fake.now + config.areas.rescanSeconds
fake.runLoops(250)
assert(shipCalls("EndOverlapVisual") == 1, "a new entity outside the shuttle first leaves its inside")
assert(shipCalls("BeginOverlapVisual") == 0, "X + 300 is outside a box turned to run along Y")
squid.location = { X = 6000, Y = 300, Z = 0 }
fake.runLoops(250)
assert(shipCalls("BeginOverlapVisual") == 1, "Y + 300 is inside it: the shuttle's inside switches on")
shuttleBox.centre = { X = 9000, Y = 0, Z = 0 }
fake.runLoops(250)
assert(shipCalls("EndOverlapVisual") == 2, "the shuttle flew off: its box moves with it")

-- The final explosion's vortex: its sound mix while the entity is in its sphere, once the sphere collides
fake.objects["/Game/Blueprints/Player/VortexSoundMix.VortexSoundMix"] = fake.object("SoundMix")
local statics = fake.objects[game.paths.gameplayStatics]
statics.PushSoundMixModifier = function(self, worldContext, mix)
  table.insert(fake.calls, { object = self, method = "PushSoundMixModifier", args = { worldContext, mix } })
end
statics.PopSoundMixModifier = function(self, worldContext, mix)
  table.insert(fake.calls, { object = self, method = "PopSoundMixModifier", args = { worldContext, mix } })
end
local sphere = fake.object("SphereComponent", { collision = 0 }, {
  K2_GetComponentLocation = function() return { X = 0, Y = 7000, Z = 0 } end,
  GetScaledSphereRadius = function() return 800 end,
  GetCollisionEnabled = function(self) return self.collision end,
})
local explosion = fake.object("BP_FinalExplosion_C", { SphereOverlapVisual = sphere })
fake.now = fake.now + config.areas.rescanSeconds
squid.location = { X = 0, Y = 7500, Z = 0 }
fake.runLoops(250)
assert(#fake.callsTo(statics, "PushSoundMixModifier") == 0, "nothing before the explosion starts")
sphere.collision = 1
fake.runLoops(250)
local pushed = fake.callsTo(statics, "PushSoundMixModifier")
assert(#pushed == 1 and pushed[1].args[2] == fake.objects["/Game/Blueprints/Player/VortexSoundMix.VortexSoundMix"],
  "inside the vortex, its sound mix")
squid.location = { X = 0, Y = 9000, Z = 0 }
fake.runLoops(250)
assert(#fake.callsTo(statics, "PopSoundMixModifier") == 1, "and out of it, the mix comes off")
explosion.destroyed = true

-- Polar's fog parts around the entity in each of its boxes; the genetics lab shows its jars, its tables and its morays
-- for the entity, each from the trigger it was given (a moray's in its Infos)
local fog = fake.object("BP_SplineCollision_C", { Box = boxComponent({ X = 0, Y = 12000, Z = 0 },
  { X = 300, Y = 300, Z = 300 }, 0) })
local labTrigger, morayTrigger = volume(20000), volume(20000)
local lab = fake.object("BP_GeneticsLab_Manager_C", { TriggerVisual = labTrigger })
local jar = fake.object("BP_JarDeco_Vert_2-1_C", { TriggerVolume = labTrigger })
local table_ = fake.object("BP_Creature02_Deco_Table_C", { TriggerVolume = labTrigger })
local moray = fake.object("BP_Moray_C", {
  Infos = { TriggerVisual_11_6F8E28894FC858BEB604838FFB43D9B1 = morayTrigger },
})
fake.now = fake.now + config.areas.rescanSeconds
squid.location = { X = 0, Y = 12000, Z = 0 }
fake.runLoops(250)
local fogSwitches = fake.callsTo(fog, "SetIC")
assert(#fogSwitches == 1 and fogSwitches[1].args[1] == true, "the fog parts around the entity")
squid.location = { X = 20000, Y = 0, Z = 0 }
fake.runLoops(250)
fogSwitches = fake.callsTo(fog, "SetIC")
assert(#fogSwitches == 2 and fogSwitches[2].args[1] == false, "and closes behind it")
assert(#calls(lab, "BeginOverlapVisual") == 1, "the lab knows the entity is inside, for the jars it spawns later")
assert(#calls(jar, "BeginOverlap") == 1 and #calls(table_, "BeginOverlap") == 1, "its jars and tables show")
assert(#calls(moray, "BeginOverlapVisual") == 1 and calls(moray, "BeginOverlapVisual")[1] == morayTrigger,
  "and its moray")

-- The levels a map loads when the local pawn first crosses a trigger load once per world for the entity
local levelScript = fake.object("SpaceShip_C")
fake.now = fake.now + config.areas.rescanSeconds
fake.world = fake.object("World")
fake.runLoops(250)
fake.runLoops(250)
assert(#fake.callsTo(levelScript, "LoadLevel") == 1, "Hawking's triggered levels load, once")

-- Each lookup walks every object in the game: the actors are looked for every rescanSeconds, not on every pass
local lookups = 0
local findAllOf = FindAllOf
FindAllOf = function(className)
  if className == "BP_StreamingVolume_Manager_C" then
    lookups = lookups + 1
  end
  return findAllOf(className)
end
fake.runLoops(250)
fake.runLoops(250)
assert(lookups == 0, "no lookups between rescans")
fake.now = fake.now + config.areas.rescanSeconds
fake.runLoops(250)
assert(lookups > 0, "and a fresh look once it's time")
FindAllOf = findAllOf

-- Once the player stops driving the squid, the volumes are handed back
local labLeft = #calls(lab, "EndOverlapVisual")
controller.Pawn = fake.invalid()
fake.runLoops(250)
assert(#calls(lab, "EndOverlapVisual") == labLeft + 1, "the volumes are left when the player stops driving the squid")
assert(#calls(jar, "EndOverlap") == 1 and #calls(moray, "EndOverlapVisual") == 1, "every one of them")

print("areas test passed")
