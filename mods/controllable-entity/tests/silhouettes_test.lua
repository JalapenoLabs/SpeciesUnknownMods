-- Copyright © 2026 Jalapeno Labs

-- What the entity hears, seen through walls, on the entity player's machine (#18): the game's outline material on a
-- post-process of the entity's own, and the body of whatever made a noise rendering custom depth while its noise
-- lasts. The crew are kept out of custom depth otherwise (the game puts them in it for its Tab overlay), or the outline
-- would be a wallhack. Without a source to show, or without the outline, the HUD marks the noise instead.
-- Run from the repository root: lua mods/controllable-entity/tests/silhouettes_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.isHost = false

local config = require("entity.config")
local silhouettes = require("entity.silhouettes")

-- The game's outline material and the engine's post-process class
local outlinePath = "/Game/Materials/PostProcess_Outline.PostProcess_Outline"
fake.objects[outlinePath] = fake.object("Material")
local postProcessClass = fake.object("PostProcessComponentClass")
fake.objects["/Script/Engine.PostProcessComponent"] = postProcessClass
local primitiveClass = fake.object("PrimitiveComponentClass")
fake.objects["/Script/Engine.PrimitiveComponent"] = primitiveClass

local function recording(object, method)
  object[method] = function(self, ...)
    table.insert(fake.calls, { object = self, method = method, args = { ... } })
  end
end

local createdMaterials = {}
fake.objects["/Script/Engine.Default__KismetMaterialLibrary"] = fake.object("KismetMaterialLibrary", nil, {
  CreateDynamicMaterialInstance = function(_, _, parent)
    local material = fake.object("MaterialInstanceDynamic", { parent = parent })
    recording(material, "SetVectorParameterValue")
    recording(material, "SetScalarParameterValue")
    table.insert(createdMaterials, material)
    return material
  end,
})

-- An actor made of primitive components, each rendering custom depth or not
local function body(className, isInCustomDepth, fields)
  local parts = {}
  for _ = 1, 2 do
    local part = fake.object("SkeletalMeshComponent", { bRenderCustomDepth = isInCustomDepth })
    part.SetRenderCustomDepth = function(self, value) self.bRenderCustomDepth = value end
    table.insert(parts, part)
  end
  local actor = fake.object(className, fields, {
    K2_GetComponentsByClass = function(_, class)
      assert(class == primitiveClass, "custom depth is a primitive component's")
      return fake.array(parts)
    end,
    IsLocallyControlled = function() return false end,
  })
  actor.parts = parts
  return actor
end
local function inCustomDepth(actor)
  return actor.parts[1].bRenderCustomDepth and actor.parts[2].bRenderCustomDepth
end

-- The entity, which takes runtime components
local squid = fake.object("BP_Monster_Poulpi_C")
local components = fake.acceptComponents(squid)
local addedComponents = 0
local acceptComponent = squid.AddComponentByClass
squid.AddComponentByClass = function(self, class, ...)
  addedComponents = addedComponents + 1
  local component = acceptComponent(self, class, ...)
  recording(component, "AddOrUpdateBlendable")
  recording(component, "K2_DestroyComponent")
  return component
end

-- Two crew members, in custom depth as the game puts them for its Tab overlay
local shooter = body("BP_Character_C", true)
local walker = body("BP_Character_C", true)

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The outline
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.now = 10
assert(not silhouettes.show("Gunshot", shooter, fake.now), "before the outline is up, the HUD marks the noise")
silhouettes.follow(squid, fake.now)
local outlineComponent = components[1]
local material = createdMaterials[1]
assert(addedComponents == 1 and material and material.parent == fake.objects[outlinePath],
  "a red instance of the game's outline material goes on a post-process of the entity's own")
assert(outlineComponent.bUnbound and outlineComponent.bEnabled and outlineComponent.BlendWeight == 1.0,
  "drawn on every view of this machine")
local blendables = fake.callsTo(outlineComponent, "AddOrUpdateBlendable")
assert(#blendables == 1 and blendables[1].args[1] == material, "with the outline as its blendable")
assert(not inCustomDepth(shooter) and not inCustomDepth(walker),
  "the crew are out of the outline while nothing's heard")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Noises
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function lastColour()
  local calls = fake.callsTo(material, "SetVectorParameterValue")
  return calls[#calls].args[2]
end

-- A gunshot flashes the shooter in full, fading over its seconds
assert(silhouettes.show("Gunshot", shooter, fake.now), "a gunshot whose shooter this machine has is seen")
assert(inCustomDepth(shooter) and not inCustomDepth(walker), "the shooter's body shows, nobody else's")
silhouettes.follow(squid, fake.now)
assert(lastColour().R == config.silhouettes.color.R, "in full red")
fake.now = 10 + config.silhouettes.byKind.Gunshot.seconds / 2
silhouettes.follow(squid, fake.now)
assert(math.abs(lastColour().R - config.silhouettes.color.R / 2) < 0.05, "fading")
-- The crew sweep keeps them in line meanwhile
fake.now = fake.now + config.silhouettes.crewSweepSeconds
silhouettes.follow(squid, fake.now)
assert(inCustomDepth(shooter) and not inCustomDepth(walker), "the sweep keeps a shown body in the outline")
fake.now = 10 + config.silhouettes.byKind.Gunshot.seconds + 0.1
silhouettes.follow(squid, fake.now)
assert(not inCustomDepth(shooter) and lastColour().R == 0, "and gone once its seconds are up")

-- A footstep flashes the walker faintly
silhouettes.show("Footstep", walker, fake.now)
silhouettes.follow(squid, fake.now)
assert(inCustomDepth(walker) and lastColour().R <= config.silhouettes.byKind.Footstep.strength + 1e-9,
  "a footstep shows the walker faintly")
fake.now = fake.now + config.silhouettes.byKind.Footstep.seconds + 0.1
silhouettes.follow(squid, fake.now)
assert(not inCustomDepth(walker), "and briefly")

-- A door's alarm pulses the door for as long as its beats keep coming
local door = body("BP_BigDoor1_C", false)
local alarmStart = fake.now
for beat = 0, 6 do
  fake.now = alarmStart + beat * 0.5
  silhouettes.show("Alarm", door, fake.now)
  silhouettes.follow(squid, fake.now)
  assert(inCustomDepth(door), "the door shows while its alarm sounds")
end
local brightest, dimmest = 0, 1
for _, call in ipairs(fake.callsTo(material, "SetVectorParameterValue")) do
  local brightness = call.args[2].A
  if call.args[1]:ToString() == "Color" and brightness > 0 then
    brightest, dimmest = math.max(brightest, brightness), math.min(dimmest, brightness)
  end
end
assert(brightest - dimmest > 0.5, "pulsing")
fake.now = fake.now + config.silhouettes.byKind.Alarm.seconds + 0.1
silhouettes.follow(squid, fake.now)
assert(not inCustomDepth(door), "and stops a moment after the last beat")

-- An engine's body, hidden on a machine whose player hasn't been near it, is shown for its overload
local engineBody = fake.object("StaticMeshComponent", { hidden = true })
engineBody.SetHiddenInGame = function(self, hidden) self.hidden = hidden end
local engine = body("BP_Engine_C", false, { EngineHawking02 = engineBody })
silhouettes.show("Overload", engine, fake.now)
assert(not engineBody.hidden and inCustomDepth(engine), "an overloading engine's body shows through walls")

-- What this machine can't show is marked on the HUD instead: no source, or the entity's sense of the crew
assert(not silhouettes.show("Gunshot", nil, fake.now), "a noise without a source this machine has is marked")
assert(not silhouettes.show("Sense", walker, fake.now), "the sense of the crew is only ever a marker")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Afterwards
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Once the player stops driving the entity, nothing stays outlined and the crew are back in custom depth for this
-- machine's Tab overlay
silhouettes.forget()
assert(not inCustomDepth(engine), "nothing stays outlined")
assert(inCustomDepth(shooter) and inCustomDepth(walker), "the crew are back as the game has them")
assert(#fake.callsTo(outlineComponent, "K2_DestroyComponent") == 1, "and the outline goes")

-- Where UE4SS can't hand the material over as an interface, the settings' blendables are written directly
local secondSquid = fake.object("BP_Monster_Poulpi_C")
local secondComponents = fake.acceptComponents(secondSquid)
local acceptSecond = secondSquid.AddComponentByClass
secondSquid.AddComponentByClass = function(self, class, ...)
  local component = acceptSecond(self, class, ...)
  component.AddOrUpdateBlendable = function() error("Value must be UInterface or nil") end
  component.Settings = {}
  return component
end
silhouettes.follow(secondSquid, fake.now)
local written = secondComponents[1].Settings.WeightedBlendables
assert(written and written.Array[1].Object == createdMaterials[2] and written.Array[1].Weight == 1.0,
  "the outline goes in through the settings' blendables")
assert(silhouettes.show("Gunshot", shooter, fake.now), "and noises show through it")
silhouettes.forget()

-- Without the game's outline material, everything is marked on the HUD
fake.objects[outlinePath] = nil
local thirdSquid = fake.object("BP_Monster_Poulpi_C")
fake.acceptComponents(thirdSquid)
silhouettes.follow(thirdSquid, fake.now)
assert(not silhouettes.show("Gunshot", shooter, fake.now), "no outline: every noise is a marker")

print("silhouettes test passed")
