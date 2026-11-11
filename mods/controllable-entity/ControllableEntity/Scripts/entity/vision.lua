-- Copyright © 2026 Jalapeno Labs

-- What only the entity player sees, on their own machine: a light around the squid while it is in the vents (the
-- rooms have their own lights), and glowing markers at the vent openings nearby. The ducts are unlit, and much of the network is invisible collision rather than modelled walls, so
-- without these the entity can't tell where they are (playtest 4).
--
-- Everything here is created on the entity player's machine and never replicated, so no one else sees it. The
-- markers are the engine's own cylinder with the game's own unlit material (the in-game map's UnlitColor_MAT), both
-- already cooked for the game's renderer; a mod can't ship new material shaders for Windows (see docs/pak-mods.md).

local config = require("entity.config")
local game = require("entity.game")
local vents = require("entity.vents")

local vision = {}

local POINT_LIGHT_CLASS = "/Script/Engine.PointLightComponent"
local STATIC_MESH_ACTOR_CLASS = "/Script/Engine.StaticMeshActor"
local STATIC_MESH_ACTOR_CLASS_NAME = "StaticMeshActor"
local MARKER_MESH = "/Engine/BasicShapes/Cylinder.Cylinder"
local MARKER_MATERIAL = "/Game/Blueprints/Inventory/Map/Materials/UnlitColor_MAT.UnlitColor_MAT"
local MARKER_COLOR_PARAMETER = "Color"
-- ELightUnits, EComponentMobility, ECollisionEnabled
local CANDELAS = 1
local MOVABLE = 2
local NO_COLLISION = 0
local IDENTITY_TRANSFORM = {
  Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
  Translation = { X = 0, Y = 0, Z = 0 },
  Scale3D = { X = 1, Y = 1, Z = 1 },
}

-- What this machine has built: { worldKey, squidAddress, lantern, lanternOn, markers = { actor, ... }, nextRefreshAt },
-- or nil.
local built = nil

-- Engine and game assets are in the game's asset registry, so LoadAsset finds them when nothing has loaded them yet.
local function loadAsset(path)
  local asset = StaticFindObject(path)
  if asset and asset:IsValid() then
    return asset
  end
  LoadAsset(path)
  asset = StaticFindObject(path)
  if asset and asset:IsValid() then
    return asset
  end
  game.log("Could not load %s", path)
  return nil
end

-- The squid's light, reusing one it already has (after a hot reload of the mod) rather than stacking a second.
local function giveLantern(squid)
  local lightClass = StaticFindObject(POINT_LIGHT_CLASS)
  local lantern = squid:GetComponentByClass(lightClass)
  if not lantern or not lantern:IsValid() then
    lantern = squid:AddComponentByClass(lightClass, false, IDENTITY_TRANSFORM, false)
  end
  if not lantern or not lantern:IsValid() then
    game.log("Could not give the squid a light")
    return nil
  end

  lantern:SetIntensityUnits(CANDELAS)
  lantern:SetIntensity(config.vision.lanternCandelas)
  lantern:SetAttenuationRadius(config.vision.lanternRadius)
  lantern:SetLightColor(config.vision.lanternColor, true)
  lantern:SetCastShadows(false)
  return lantern
end

-- A hot reload of the mod forgets its markers but leaves them in the world. They are the movable engine cylinders at
-- the marker scale: a level's own cylinders are static, so none of the game's are touched.
local function removeLeftoverMarkers(mesh)
  local meshAddress = mesh:GetAddress()
  local removed = 0
  for _, actor in ipairs(FindAllOf(STATIC_MESH_ACTOR_CLASS_NAME) or {}) do
    local disc = actor:IsValid() and actor.StaticMeshComponent
    local isMarker = disc and disc:IsValid() and disc.Mobility == MOVABLE and disc.StaticMesh:IsValid()
      and disc.StaticMesh:GetAddress() == meshAddress
      and math.abs(actor:GetActorScale3D().Z - config.vision.markerScale.Z) < 1e-4
    if isMarker then
      actor:K2_DestroyActor()
      removed = removed + 1
    end
  end
  if removed > 0 then
    game.log("Removed %d vent markers left by an earlier run of the mod", removed)
  end
end

-- A pool of marker discs, spawned once per world and moved to the openings near the squid.
local function spawnMarkers(world)
  local mesh = loadAsset(MARKER_MESH)
  local material = loadAsset(MARKER_MATERIAL)
  local markerClass = StaticFindObject(STATIC_MESH_ACTOR_CLASS)
  if not mesh or not material or not markerClass then
    return {}
  end
  removeLeftoverMarkers(mesh)

  local markers = {}
  for _ = 1, config.vision.markerCount do
    local marker = world:SpawnActor(markerClass, { X = 0, Y = 0, Z = 0 }, {})
    if marker and marker:IsValid() then
      local disc = marker.StaticMeshComponent
      disc:SetMobility(MOVABLE)
      disc:SetStaticMesh(mesh)
      disc:SetCollisionEnabled(NO_COLLISION)
      disc:SetCastShadow(false)
      local glow = disc:CreateDynamicMaterialInstance(0, material, FName("None"))
      glow:SetVectorParameterValue(FName(MARKER_COLOR_PARAMETER), config.vision.markerColor)
      marker:SetActorScale3D(config.vision.markerScale)
      marker:SetActorHiddenInGame(true)
      table.insert(markers, marker)
    end
  end
  return markers
end

-- The vent openings nearest the squid, closest first: the holes in the duct floor while it's in the vents, the floor
-- under each vent while it's in a room.
local function nearestOpenings(squid)
  local location = squid:K2_GetActorLocation()
  local fromInside = squid.InVent == true
  local openings = {}
  for _, vent in ipairs(vents.all()) do
    local opening = vents.openingOf(vent, fromInside)
    local distance = game.distance(location, opening)
    if distance <= config.vision.markerRange then
      table.insert(openings, { location = opening, distance = distance })
    end
  end
  table.sort(openings, function(first, second) return first.distance < second.distance end)
  return openings
end

local function placeMarkers(squid)
  local openings = nearestOpenings(squid)
  for index, marker in ipairs(built.markers) do
    local opening = openings[index]
    if opening then
      marker:K2_SetActorLocation(opening.location, false, {}, true)
    end
    marker:SetActorHiddenInGame(opening == nil)
  end
end

local function forget()
  if not built then
    return
  end
  for _, marker in ipairs(built.markers) do
    if marker:IsValid() then
      marker:K2_DestroyActor()
    end
  end
  if built.lantern and built.lantern:IsValid() then
    built.lantern:K2_DestroyComponent(built.lantern)
  end
  built = nil
end

-- Runs about ten times a second on the entity player's machine while they drive the squid: builds the light and the
-- markers once per squid and world, and keeps the markers on the openings around it.
function vision.follow(controller, squid)
  local world = controller:GetWorld()
  local worldKey = world:GetAddress()
  if built and (built.worldKey ~= worldKey or built.squidAddress ~= squid:GetAddress()) then
    forget()
  end
  if not built then
    built = {
      worldKey = worldKey,
      squidAddress = squid:GetAddress(),
      lantern = giveLantern(squid),
      lanternOn = nil,
      markers = spawnMarkers(world),
      nextRefreshAt = 0,
    }
    game.log("The entity's light and %d vent markers are ready", #built.markers)
  end

  local now = game.timeSeconds(controller)
  if now < built.nextRefreshAt then
    return
  end
  built.nextRefreshAt = now + config.vision.markerRefreshSeconds
  placeMarkers(squid)

  -- The light is for the unlit ducts only (playtest 6: glowing in a lit room isn't needed)
  local inVent = squid.InVent == true
  if built.lantern and built.lantern:IsValid() and built.lanternOn ~= inVent then
    built.lanternOn = inVent
    built.lantern:SetVisibility(inVent, false)
  end
end

-- After losing, or once the player no longer drives the squid: everything only they could see goes.
vision.forget = forget

return vision
