-- Copyright © 2026 Jalapeno Labs

-- A screen effect of the entity's own, on the entity player's machine: a dynamic instance of one of the game's
-- post-process materials on an unbound post-process component the mod adds to the monster there, which no other
-- machine has. Unbound, it shows on every view of that machine, the mod's third-person camera and first person alike.
-- The outline of what the entity hears (silhouettes.lua) and its fear (fear.lua) are made this way.

local game = require("entity.game")

local postprocess = {}

local POST_PROCESS_CLASS = "/Script/Engine.PostProcessComponent"
local MATERIAL_LIBRARY = "/Script/Engine.Default__KismetMaterialLibrary"
local IDENTITY_TRANSFORM = {
  Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
  Translation = { X = 0, Y = 0, Z = 0 },
  Scale3D = { X = 1, Y = 1, Z = 1 },
}

-- Puts the material on the component. AddOrUpdateBlendable takes it as an interface, which UE4SS may not hand over
-- from Lua; the settings' blendables can be written directly instead. Returns how it went on, or nil.
local function attachMaterial(component, material)
  local attached = pcall(function()
    component:AddOrUpdateBlendable(material, 1.0)
  end)
  if attached then
    return "AddOrUpdateBlendable"
  end
  attached = pcall(function()
    component.Settings.WeightedBlendables = { Array = { { Weight = 1.0, Object = material } } }
  end)
  if attached then
    return "its blendables"
  end
  return nil
end

-- Adds an effect to the monster from the first of the game's materials that loads, at the given blend weight. Returns
-- { component, material }, or nil after saying why, naming the effect.
function postprocess.add(monster, materialPaths, blendWeight, effectName)
  local parent = nil
  for _, path in ipairs(materialPaths) do
    parent = parent or game.loadGameAsset(path)
  end
  local componentClass = StaticFindObject(POST_PROCESS_CLASS)
  if not parent or not componentClass or not componentClass:IsValid() then
    game.log("No %s for the entity: its material or the post-process class is missing", effectName)
    return nil
  end
  local component = monster:AddComponentByClass(componentClass, false, IDENTITY_TRANSFORM, false)
  if not component or not component:IsValid() then
    game.log("Could not give the entity a post-process for its %s", effectName)
    return nil
  end
  local material = StaticFindObject(MATERIAL_LIBRARY):CreateDynamicMaterialInstance(monster, parent, FName("None"), 0)
  if not material or not material:IsValid() then
    game.log("Could not make the entity's %s material", effectName)
    component:K2_DestroyComponent(component)
    return nil
  end
  component.bUnbound = true
  component.bEnabled = true
  component.BlendWeight = blendWeight
  local how = attachMaterial(component, material)
  if not how then
    game.log("Could not put the entity's %s on its view", effectName)
    component:K2_DestroyComponent(component)
    return nil
  end
  game.log("The entity's %s went on through %s", effectName, how)
  return { component = component, material = material }
end

-- Takes an effect off, if it's still there.
function postprocess.remove(effect)
  if effect and effect.component:IsValid() then
    effect.component:K2_DestroyComponent(effect.component)
  end
end

return postprocess
