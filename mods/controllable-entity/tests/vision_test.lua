-- Copyright © 2026 Jalapeno Labs

-- What only the entity sees, on their own machine: a light on the squid and glowing markers at the vent openings near
-- it, which follow it between the ducts and the rooms and go away when the player stops driving the squid.
-- Run from the repository root: lua mods/controllable-entity/tests/vision_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.isHost = false

local config = require("entity.config")
local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.objects["/Script/Engine.PointLightComponent"] = fake.object("PointLightComponentClass")
fake.objects["/Script/Engine.StaticMeshActor"] = fake.object("StaticMeshActorClass")
fake.objects["/Engine/BasicShapes/Cylinder.Cylinder"] = fake.object("StaticMesh")
fake.objects["/Game/Blueprints/Inventory/Map/Materials/UnlitColor_MAT.UnlitColor_MAT"] = fake.object("Material")
fake.installModPak(game.modClasses)
fake.object("GameStateBase")

local markers = {}
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local glow = fake.object("MaterialInstanceDynamic")
    local disc = fake.object("StaticMeshComponent", nil, {
      CreateDynamicMaterialInstance = function() return glow end,
    })
    local marker = fake.object("StaticMeshActor", { StaticMeshComponent = disc, glow = glow, hidden = false }, {
      SetActorHiddenInGame = function(self, hidden) self.hidden = hidden end,
      K2_SetActorLocation = function(self, location) self.location = location end,
    })
    table.insert(markers, marker)
    return marker
  end,
})

local controller = fake.object("BP_MyPlayerController_C", { Pawn = fake.invalid() }, {
  IsLocalController = function() return true end,
}, { "PlayerController" })
fake.giveView(controller)

local squid = fake.object("BP_Monster_Poulpi_C", { InVent = true, location = { X = 0, Y = 0, Z = 300 } }, {
  K2_GetActorLocation = function(self) return self.location end,
})
fake.giveMovement(squid)
local squidComponents = fake.acceptComponents(squid)

-- Two vents near the squid and one far away. Each opens into the duct at its top (Box_Up) and stands on a room's floor
local function vent(x)
  return fake.object("BP_Vent_Up_C", {
    Box_Up = fake.object("BoxComponent", nil, {
      K2_GetComponentLocation = function() return { X = x, Y = 0, Z = 300 } end,
    }),
  }, {
    K2_GetActorLocation = function() return { X = x, Y = 0, Z = 0 } end,
  })
end
vent(400)
vent(900)
vent(config.vision.markerRange * 3)

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

-- As crew, nothing is built
fake.runLoops(100)
assert(#markers == 0 and #squidComponents == 0, "the crew sees nothing extra")

-- Driving the squid inside the ducts
controller.Pawn = squid
fake.runLoops(100)
assert(#squidComponents == 1, "the squid gets a light")
local lantern = squidComponents[1]
assert(#fake.callsTo(lantern, "SetCastShadows") == 1, "a shadowless one")
local function lanternShown()
  local calls = fake.callsTo(lantern, "SetVisibility")
  return calls[#calls] and calls[#calls].args[1]
end
assert(lanternShown() == true, "lit inside the ducts")
assert(#markers == config.vision.markerCount, "the marker pool is spawned once")
assert(#fake.callsTo(markers[1].glow, "SetVectorParameterValue") == 1, "markers glow in the marker colour")

local shown = {}
for _, marker in ipairs(markers) do
  if not marker.hidden then
    table.insert(shown, marker)
  end
end
assert(#shown == 2, "only the openings within range are marked")
assert(shown[1].location.X == 400 and shown[1].location.Z == 300, "the nearest opening first, at the hole in the duct")

-- In a room, the markers move to the floor under each vent
squid.InVent = false
fake.now = 1
fake.runLoops(100)
assert(markers[1].location.Z == 0, "outside the ducts, markers sit on the floor under the vents")
-- Regression (playtest 6): the squid glowed in lit rooms too; the light is for the ducts
assert(lanternShown() == false, "and the light goes out")
fake.runLoops(100)
assert(#markers == config.vision.markerCount, "the pool is reused, not respawned")

-- Once the player stops driving the squid (they lost), everything only they could see goes
controller.Pawn = fake.invalid()
fake.runLoops(100)
for _, marker in ipairs(markers) do
  assert(marker.destroyed, "the markers are removed")
end
assert(#fake.callsTo(lantern, "K2_DestroyComponent") == 1, "and the light")

print("vision test passed")
