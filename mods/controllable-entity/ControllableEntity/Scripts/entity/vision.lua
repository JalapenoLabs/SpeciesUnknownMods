-- Copyright © 2026 Jalapeno Labs

-- What only the entity player sees, on their own machine: a light around the entity (full in the unlit ducts, faint in
-- the rooms), and glowing markers at the vent openings nearby. The ducts are unlit, and much of the network is
-- invisible collision rather than modelled walls, so without these the entity can't tell where they are (playtest 4).
-- Glowing posts also stand along the edges of the places the entity may not go and of the shuttle's approach
-- (zones.lua), so it can see them before the host puts it back (playtest 6).
--
-- Everything here is created on the entity player's machine and never replicated, so no one else sees it. The
-- markers are the engine's own cylinder with the game's own unlit material (the in-game map's UnlitColor_MAT), both
-- already cooked for the game's renderer; a mod can't ship new material shaders for Windows (see docs/pak-mods.md).

local config = require("entity.config")
local game = require("entity.game")
local kits = require("entity.kits")
local vents = require("entity.vents")
local zones = require("entity.zones")

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

-- What this machine has built: { worldKey, monsterAddress, lantern, lanternInVent, markers = { actor, ... },
-- nextRefreshAt, posts = { actor, ... }, postsKey, nextZoneRefreshAt }, or nil.
local built = nil

-- The entity's light, reusing one it already has (after a hot reload of the mod) rather than stacking a second.
local function giveLantern(monster)
  local lightClass = StaticFindObject(POINT_LIGHT_CLASS)
  local lantern = monster:GetComponentByClass(lightClass)
  if not lantern or not lantern:IsValid() then
    lantern = monster:AddComponentByClass(lightClass, false, IDENTITY_TRANSFORM, false)
  end
  if not lantern or not lantern:IsValid() then
    game.log("Could not give the entity a light")
    return nil
  end

  lantern:SetIntensityUnits(CANDELAS)
  lantern:SetLightColor(config.vision.lanternColor, true)
  lantern:SetCastShadows(false)
  return lantern
end

-- A hot reload of the mod forgets its markers and posts but leaves them in the world. They are the movable engine
-- cylinders at the marker's flat scale or the posts' thin one: a level's own cylinders are static, so none of the
-- game's are touched.
local function removeLeftoverMarkers(mesh)
  local meshAddress = mesh:GetAddress()
  local removed = 0
  for _, actor in ipairs(FindAllOf(STATIC_MESH_ACTOR_CLASS_NAME) or {}) do
    local disc = actor:IsValid() and actor.StaticMeshComponent
    local scale = disc and disc:IsValid() and actor:GetActorScale3D()
    local isOurShape = scale and (math.abs(scale.Z - config.vision.markerScale.Z) < 1e-4
      or math.abs(scale.X - config.vision.postThickness) < 1e-4)
    local isMarker = isOurShape and disc.Mobility == MOVABLE and disc.StaticMesh:IsValid()
      and disc.StaticMesh:GetAddress() == meshAddress
    if isMarker then
      actor:K2_DestroyActor()
      removed = removed + 1
    end
  end
  if removed > 0 then
    game.log("Removed %d vent markers left by an earlier run of the mod", removed)
  end
end

-- One glowing cylinder: the engine's cylinder with the game's own unlit colour, never colliding or casting shadows.
local function spawnGlow(world, location, scale, color)
  local mesh = game.loadGameAsset(MARKER_MESH)
  local material = game.loadGameAsset(MARKER_MATERIAL)
  local actorClass = StaticFindObject(STATIC_MESH_ACTOR_CLASS)
  if not mesh or not material or not actorClass then
    return nil
  end
  local actor = world:SpawnActor(actorClass, location, {})
  if not actor or not actor:IsValid() then
    game.log("Could not spawn a glowing marker")
    return nil
  end
  local shape = actor.StaticMeshComponent
  shape:SetMobility(MOVABLE)
  shape:SetStaticMesh(mesh)
  shape:SetCollisionEnabled(NO_COLLISION)
  shape:SetCastShadow(false)
  local glow = shape:CreateDynamicMaterialInstance(0, material, FName("None"))
  glow:SetVectorParameterValue(FName(MARKER_COLOR_PARAMETER), color)
  actor:SetActorScale3D(scale)
  return actor
end

-- A pool of marker discs, spawned once per world and moved to the openings near the entity.
local function spawnMarkers(world)
  local mesh = game.loadGameAsset(MARKER_MESH)
  if not mesh then
    return {}
  end
  removeLeftoverMarkers(mesh)

  local markers = {}
  for _ = 1, config.vision.markerCount do
    local marker = spawnGlow(world, { X = 0, Y = 0, Z = 0 }, config.vision.markerScale, config.vision.markerColor)
    if marker then
      marker:SetActorHiddenInGame(true)
      table.insert(markers, marker)
    end
  end
  return markers
end

-- The places to mark, each a box (zones.lua), how far its edge is grown, and its colour: the shuttle's approach, the
-- shuttle itself unless the entity may board it, and the forbidden areas this machine has loaded.
local function markedZones()
  local marked = {}
  local shuttle = zones.shuttleBox()
  if shuttle then
    table.insert(marked, { box = shuttle, margin = config.zones.shuttleApproach, color = config.vision.approachColor })
    if game.contractType() ~= game.contractTypes.Capture then
      table.insert(marked, { box = shuttle, margin = 0, color = config.vision.forbiddenColor })
    end
  end
  for _, box in ipairs(zones.forbiddenBoxes()) do
    table.insert(marked, { box = box, margin = 0, color = config.vision.forbiddenColor })
  end
  return marked
end

-- Identifies a set of places, so the posts are rebuilt only when it changes.
local function zonesKey(marked)
  local parts = {}
  for _, zone in ipairs(marked) do
    local box = zone.box
    table.insert(parts, string.format("%.0f,%.0f,%.0f,%.0f,%.0f,%.0f", box.centre.X, box.centre.Y, box.centre.Z,
      box.extent.X + zone.margin, box.extent.Y + zone.margin, box.yaw))
  end
  return table.concat(parts, ";")
end

-- Posts along a box's edge, a post every postSpacing, as tall as the box and centred on it.
local function placePosts(world, zone, posts)
  local box = zone.box
  local halfX, halfY = box.extent.X + zone.margin, box.extent.Y + zone.margin
  local yaw = math.rad(box.yaw)
  local cosine, sine = math.cos(yaw), math.sin(yaw)
  local thickness = config.vision.postThickness
  -- The engine's cylinder is 100 units tall at scale 1
  local scale = { X = thickness, Y = thickness, Z = box.extent.Z * 2 / 100 }
  local corners = { { -halfX, -halfY }, { halfX, -halfY }, { halfX, halfY }, { -halfX, halfY } }
  for index, corner in ipairs(corners) do
    local nextCorner = corners[index % 4 + 1]
    local edgeX, edgeY = nextCorner[1] - corner[1], nextCorner[2] - corner[2]
    local steps = math.max(1, math.floor(math.sqrt(edgeX * edgeX + edgeY * edgeY) / config.vision.postSpacing))
    for step = 0, steps - 1 do
      local alongX, alongY = corner[1] + edgeX * step / steps, corner[2] + edgeY * step / steps
      local location = {
        X = box.centre.X + alongX * cosine - alongY * sine,
        Y = box.centre.Y + alongX * sine + alongY * cosine,
        Z = box.centre.Z,
      }
      local post = spawnGlow(world, location, scale, zone.color)
      if post then
        table.insert(posts, post)
      end
    end
  end
end

local function removePosts()
  for _, post in ipairs(built.posts) do
    if post:IsValid() then
      post:K2_DestroyActor()
    end
  end
  built.posts = {}
end

-- Rebuilds the posts when the places to mark have changed.
local function refreshPosts(world)
  local marked = markedZones()
  local key = zonesKey(marked)
  if key == built.postsKey then
    return
  end
  built.postsKey = key
  removePosts()
  for _, zone in ipairs(marked) do
    placePosts(world, zone, built.posts)
  end
  game.log("Marked %d zone(s) for the entity with %d posts", #marked, #built.posts)
end

-- The vent openings nearest the entity, closest first: the holes in the duct floor while it's in the vents, the floor
-- under each vent while it's in a room.
local function nearestOpenings(monster)
  local location = monster:K2_GetActorLocation()
  local fromInside = monster.InVent == true
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

local function placeMarkers(monster)
  local openings = nearestOpenings(monster)
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
  removePosts()
  built = nil
end

-- Runs about ten times a second on the entity player's machine while they drive the entity: builds the light and the
-- markers once per monster and world, and keeps the markers on the openings around it.
function vision.follow(controller, monster)
  local world = controller:GetWorld()
  local worldKey = world:GetAddress()
  if built and (built.worldKey ~= worldKey or built.monsterAddress ~= monster:GetAddress()) then
    forget()
  end
  if not built then
    built = {
      worldKey = worldKey,
      monsterAddress = monster:GetAddress(),
      lantern = giveLantern(monster),
      lanternInVent = nil,
      -- Only an entity that lives in the vents has openings to look for
      markers = kits.forMonster(monster).usesVents and spawnMarkers(world) or {},
      nextRefreshAt = 0,
      posts = {},
      postsKey = nil,
      nextZoneRefreshAt = 0,
    }
    game.log("The entity's light and %d vent markers are ready", #built.markers)
  end

  local now = game.timeSeconds(controller)
  if now >= built.nextZoneRefreshAt then
    built.nextZoneRefreshAt = now + config.vision.zoneRefreshSeconds
    refreshPosts(world)
  end
  if now < built.nextRefreshAt then
    return
  end
  built.nextRefreshAt = now + config.vision.markerRefreshSeconds
  placeMarkers(monster)

  -- Full in the unlit ducts, faint in the rooms: the game keeps them dark on purpose, and the entity has no flashlight
  -- (playtest 6: off in the rooms was too dark, full was more than needed)
  local inVent = monster.InVent == true
  if built.lantern and built.lantern:IsValid() and built.lanternInVent ~= inVent then
    built.lanternInVent = inVent
    built.lantern:SetIntensity(inVent and config.vision.lanternCandelas or config.vision.roomLanternCandelas)
    built.lantern:SetAttenuationRadius(inVent and config.vision.lanternRadius or config.vision.roomLanternRadius)
  end
end

-- After losing, or once the player no longer drives the entity: everything only they could see goes.
vision.forget = forget

return vision
