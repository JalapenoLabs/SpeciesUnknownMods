-- Copyright © 2026 Jalapeno Labs

-- The entity's fear (#23): how afraid the host weighs it (down or fleeing, low on health, burning, hunted), and the
-- crew's own fear effects its machine turns that into: the heartbeat, quicker and higher the more afraid; the red
-- vignette closing in as the health bar drains, pulsing with each beat and flashing on hits; the adrenaline blur on a
-- knockdown, a hard hit or the flight. The parked crew body's own fear stops.
-- Run from the repository root: lua mods/controllable-entity/tests/fear_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local config = require("entity.config")
local fear = require("entity.fear")
local game = require("entity.game")
local hunt = require("entity.hunt")
local kits = require("entity.kits")
local links = require("entity.links")

fake.world = fake.object("World")
local sounds = {}
fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
  PlaySound2D = function(_, _, sound, volume, pitch) table.insert(sounds, { sound = sound, volume = volume,
    pitch = pitch }) end,
})
-- A kill contract, where the crew's special weapon starts the hunt
fake.object("BP_MyGameState_C", {
  Contract = { ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Elimination },
}, nil, { "GameStateBase" })

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- How afraid, on the host
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local squid = fake.object("BP_Monster_Poulpi_C", { HeatValue = 0 }, {
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
})
local entity = { monster = squid, kit = kits.byId.Squid }
local crewMember = fake.object("BP_Character_C", { bHidden = false, IsDead = false }, {
  K2_GetActorLocation = function(self) return self.location end,
})
crewMember.location = { X = 5000, Y = 0, Z = 0 }

assert(fear.levelOnHost(entity, 1, false) == 0, "unhurt and unhunted, no fear")
assert(fear.levelOnHost(entity, 1, true) == 1, "down, wholly afraid")
assert(fear.levelOnHost(entity, config.fear.lowHealthShare, false) == 0, "at 30%, as the crew's, not yet")
assert(math.abs(fear.levelOnHost(entity, config.fear.lowHealthShare - 0.001, false) - config.fear.lowHealthFear) < 0.01,
  "just under, a quarter's fear")
assert(fear.levelOnHost(entity, config.fear.lowestHealthShare, false) == 1, "nearly dead, wholly")
squid.HeatValue = 0.5
assert(fear.levelOnHost(entity, 1, false) == config.fear.burningFear, "burning")
squid.HeatValue = 0
-- Hunted: the crew holds the weapon that can kill it, and one of them is near
hunt.register()
fake.loadClass(game.paths.weaponClass)
local weapon = fake.object("BP_SpecialGun_C", { IsObjectiveWeapon = true, IsGrabbed = true })
fake.hooks[game.paths.weaponClass .. ":BPI_Weapon_SetGrabbed"](fake.param(weapon))
assert(fear.levelOnHost(entity, 1, false) == 0, "hunted from afar, not yet")
crewMember.location = { X = 1000, Y = 0, Z = 0 }
assert(fear.levelOnHost(entity, 1, false) == config.fear.huntedFear, "hunted, a crew member near")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- What the entity feels, on its machine
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.objects["/Game/Materials/PostProcess_Player_Mat_Inst.PostProcess_Player_Mat_Inst"] = fake.object("Material")
fake.objects["/Game/Chameleon/Materials/M_RadialBlurHLSL_Inst.M_RadialBlurHLSL_Inst"] = fake.object("Material")
local heartbeat = fake.object("SoundWave")
fake.objects["/Game/Sound/Player/Heartbeat_1.Heartbeat_1"] = heartbeat
fake.objects["/Script/Engine.PostProcessComponent"] = fake.object("PostProcessComponentClass")
local materials = {}
fake.objects["/Script/Engine.Default__KismetMaterialLibrary"] = fake.object("KismetMaterialLibrary", nil, {
  CreateDynamicMaterialInstance = function()
    local material = fake.object("MaterialInstanceDynamic", { values = {} })
    material.SetScalarParameterValue = function(self, name, value) self.values[name:ToString()] = value end
    table.insert(materials, material)
    return material
  end,
})
local components = fake.acceptComponents(squid)
local vignetteAndBlur = function() return materials[1], materials[2], components[2] end

-- The crew body the player drove before, parked and hidden, still running its owner's fear
local parkedBody = fake.object("BP_Character_C", { bHidden = true, PostProcess = fake.object("PostProcessComponent",
  { bEnabled = true }) })

local link = { Health = 1, Downed = false, Fear = 0 }
fear.register()
links.registerEvents()
fake.now = 10
fear.follow(squid, link, fake.now)
local vignette, blur, blurComponent = vignetteAndBlur()
assert(vignette and blur, "the crew's vignette and blur go on the entity's view")
assert(parkedBody.PostProcess.bEnabled == false and #fake.callsTo(parkedBody, "BPI_Player_StopLifePulse") == 1,
  "the parked body's own fear stops")
assert(vignette.values.Density == 0 and #sounds == 0, "unhurt: no vignette, no heartbeat")

-- The health bar drains: the vignette closes in, and a hit flashes red
link.Health = 0.5
fake.now = 10.1
fear.follow(squid, link, fake.now)
assert(vignette.values.Density == 1.0, "half the bar: half the crew's vignette")
assert(vignette.values.HitValue > 0.75, "the hit flashes")
fake.now = 10.7
fear.follow(squid, link, fake.now)
assert(vignette.values.HitValue == 0, "and the flash fades")

-- Afraid, the heart races: a beat now, the next sooner the more afraid, higher pitched
link.Fear = 0.25
fear.follow(squid, link, fake.now)
assert(#sounds == 1 and sounds[1].sound == heartbeat, "the crew's heartbeat")
fake.now = 10.7 + 0.25
fear.follow(squid, link, fake.now)
assert(vignette.values.HeartBeat == 0.5, "the vignette pulses with it")
fake.now = 10.7 + 3.9
fear.follow(squid, link, fake.now)
assert(#sounds == 1, "a quarter's fear: one beat every 4 seconds")
fake.now = 10.7 + 4.0
fear.follow(squid, link, fake.now)
assert(#sounds == 2, "the next")
link.Fear = 1
fake.now = fake.now + 4
fear.follow(squid, link, fake.now)
fake.now = fake.now + 1
fear.follow(squid, link, fake.now)
assert(#sounds == 4 and sounds[4].pitch > sounds[2].pitch, "wholly afraid: one a second, higher")

-- Knocked down: the whole vignette, and the adrenaline blur
link.Downed = true
fear.follow(squid, link, fake.now)
fake.now = fake.now + 0.5
fear.follow(squid, link, fake.now)
assert(vignette.values.Density == 2.0, "down: the vignette closes in wholly")
assert(blurComponent.BlendWeight == 1, "the blur comes on")
fake.now = fake.now + 1.5
fear.follow(squid, link, fake.now)
assert(blurComponent.BlendWeight == 0, "and goes")

-- The flight starts: the blur again
link.Downed = false
fake.customEvents.EntityClientEvent(fake.param(fake.object("BP_EntityLink_C")), fake.param(fake.name("Fleeing")),
  fake.param(0))
fear.follow(squid, link, fake.now)
fake.now = fake.now + 0.3
fear.follow(squid, link, fake.now)
assert(blurComponent.BlendWeight == 1, "as the flight starts")

-- Once the player stops driving the entity, the effects go
fear.forget()
local vignetteRemoved = #fake.callsTo(components[1], "K2_DestroyComponent") == 1
local blurRemoved = #fake.callsTo(components[2], "K2_DestroyComponent") == 1
assert(vignetteRemoved and blurRemoved, "the effects go")

print("fear test passed")
