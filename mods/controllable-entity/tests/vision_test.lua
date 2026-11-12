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
fake.installModPak(game.modAssets)
fake.object("GameStateBase")

-- Everything the entity's vision spawns: the vent markers (flat discs) and the zone posts (thin and tall)
local markers, posts = {}, {}
fake.world = fake.object("World", nil, {
  SpawnActor = function(_, _, location)
    local glow = fake.object("MaterialInstanceDynamic")
    local disc = fake.object("StaticMeshComponent", nil, {
      CreateDynamicMaterialInstance = function() return glow end,
    })
    local actor = fake.object("StaticMeshActor", { StaticMeshComponent = disc, glow = glow, hidden = false }, {
      SetActorHiddenInGame = function(self, hidden) self.hidden = hidden end,
      K2_SetActorLocation = function(self, where) self.location = where end,
    })
    actor.location = location
    actor.SetActorScale3D = function(self, scale)
      table.insert(scale.X == config.vision.postThickness and posts or markers, self)
    end
    return actor
  end,
})

-- The crew's shuttle, whose approach and bay the entity sees marked, in a kill contract
fake.object("BP_PlayerShip_C", {
  UseExteriorTrigger = false,
  ExtTriggerBase = fake.invalid(),
  TriggerBoxOverlap = fake.object("BoxComponent", nil, {
    K2_GetComponentLocation = function() return { X = 9000, Y = 6000, Z = -450 } end,
    GetScaledBoxExtent = function() return { X = 2500, Y = 900, Z = 400 } end,
    K2_GetComponentRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  }),
})
fake.object("BP_MyGameState_C", {
  Contract = { ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Elimination },
})

local controller = fake.object("BP_MyPlayerController_C", { Pawn = fake.invalid() }, {
  IsLocalController = function() return true end,
}, { "PlayerController" })
fake.giveView(controller)

local squid = fake.object("BP_Monster_Poulpi_C", { InVent = true, location = { X = 0, Y = 0, Z = 300 } }, {
  K2_GetActorLocation = function(self) return self.location end,
})
fake.giveSquidState(squid)
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

-- Polar's weather frosts the local camera's visor outside (Ultra Dynamic Weather's screen frost)
local screenFrost = fake.object("PostProcessComponent", { BlendWeight = 1 })
fake.object("Ultra_Dynamic_Weather_C", { ["Screen Frost Post Process"] = screenFrost })

-- Driving the squid inside the ducts
controller.Pawn = squid
fake.runLoops(100)
-- Regression (playtest 9): the entity saw the crew's frosting visor outside. On its machine alone, the frost is off
assert(screenFrost.BlendWeight == 0, "no visor frost for the entity")
assert(#squidComponents == 1, "the squid gets a light")
local lantern = squidComponents[1]
assert(#fake.callsTo(lantern, "SetCastShadows") == 1, "a shadowless one")
local function lanternIntensity()
  local calls = fake.callsTo(lantern, "SetIntensity")
  return calls[#calls] and calls[#calls].args[1]
end
assert(lanternIntensity() == config.vision.lanternCandelas, "fully lit inside the ducts")
assert(#markers == config.vision.markerCount, "the marker pool is spawned once")
assert(#fake.callsTo(markers[1].glow, "SetVectorParameterValue") == 1, "markers glow in the marker colour")

-- Playtest 6: glowing posts stand along the shuttle's approach (amber) and its bay (red, as the entity may not board)
assert(#posts > 0, "the shuttle's edges are marked with posts")
local colours = {}
for _, post in ipairs(posts) do
  local colour = fake.callsTo(post.glow, "SetVectorParameterValue")[1].args[2]
  colours[colour == config.vision.forbiddenColor and "red" or "amber"] = true
end
assert(colours.red and colours.amber, "red where the entity may not go, amber around the approach")
local postCount = #posts

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
-- Regression (playtest 6): full light in the rooms was too much and none too dark; the rooms get a faint glow
assert(lanternIntensity() == config.vision.roomLanternCandelas, "and the light dims to a faint glow")
fake.runLoops(100)
assert(#markers == config.vision.markerCount, "the pool is reused, not respawned")
assert(#posts == postCount, "and the posts stay while the zones don't change")

-- Once the player stops driving the squid (they lost), everything only they could see goes
controller.Pawn = fake.invalid()
fake.runLoops(100)
for _, marker in ipairs(markers) do
  assert(marker.destroyed, "the markers are removed")
end
for _, post in ipairs(posts) do
  assert(post.destroyed, "and the posts")
end
assert(#fake.callsTo(lantern, "K2_DestroyComponent") == 1, "and the light")

assert(screenFrost.BlendWeight == 1, "and the frost is back once the player no longer drives the squid")

print("vision test passed")
