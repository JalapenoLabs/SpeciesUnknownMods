-- Copyright © 2026 Jalapeno Labs

-- The areas of the ship the entity player's machine treats the entity as standing in.
--
-- Some of the game's actors follow the local player's pawn through trigger volumes, and decide from the volumes'
-- overlap events, which the entity's collision never fires:
--   - map sections: each BP_StreamingVolume_Manager shows its sections while the pawn stands in one of its volumes, so
--     walls and floors stayed hidden around the entity (playtest 5); Polar's BP_InsideVolume_Manager, its indoor fog,
--     works the same way;
--   - the map's deck: BP_MapManagerExtended picks which layer the minimaps draw from the map triggers the pawn stands
--     in, so the entity's minimap showed the deck below crew quarters (playtest 6);
--   - things that switch on for whoever is near: Hawking's reactor core shows, turns and shakes the camera only while
--     the pawn is in its own volumes (BP_CoreReactor), and the engineering water shows only while the pawn is in its
--     own (BP_Water), so neither was ever there for the entity, whose squid still took the reactor's pulse
--     (playtest 9). The local-player audit (#4) found the rest: the shuttle's inside, the genetics lab's jars, tables
--     and morays, the final explosion's vortex, Polar's fog, and more (managerKinds).
-- Each manager also has a way in by hand that runs the same check the overlaps do (BP_FunctionLibrairy.
-- GetOnlyVisualOverlap: the local player's pawn counts), so the mod tells them when the entity is inside a volume's
-- bounding box (AActor.GetActorBounds; AVolume's exact EncompassesPoint isn't exposed to Blueprints or Lua). A rotated
-- volume's box is a little larger than the volume, which only switches an area slightly early. A trigger that is a
-- component (a box or a sphere on its actor) is read as that shape, live, since it may move with its actor.
--
-- Two of the maps also load parts of themselves once the local pawn first crosses a trigger, which the entity's
-- collision never does either: those load as soon as the entity's machine follows it (loadTriggeredLevels).
--
-- The map sections' volumes only reach as high as the crew can climb, and the ducts climb higher: in the vents high
-- over the labs, the entity stood in no volume, and the whole ship below it went invisible (playtest 9). So a map
-- section's box counts as reaching config.areas.sectionHeadroom higher. Standing in one more volume only keeps one more
-- section showing; the map's deck is picked from exact boxes, or the minimap could draw the deck below.

local config = require("entity.config")
local game = require("entity.game")

local areas = {}

local MAP_TRIGGER_COMPONENT_CLASS = "TriggerMap_ActorComponent_C"

-- Each volume's bounding box, by address: volumes never move, so it is read once. { origin, extent }
local boundsByVolume = {}

-- UE4SS fills a struct out parameter's fields (X, Y, Z) into the table passed for it, so each needs its own table
-- (LuaUObject.cpp: struct and array out parameters reuse the table; others go in it under their names).
local function boundsOf(volume)
  local address = volume:GetAddress()
  local bounds = boundsByVolume[address]
  if bounds ~= nil then
    return bounds
  end
  local origin, extent = {}, {}
  volume:GetActorBounds(false, origin, extent, false)
  if not origin.X or not extent.X then
    game.log("A trigger volume gave no bounds; its area is left to the game")
    boundsByVolume[address] = false
    return false
  end
  bounds = { origin = origin, extent = extent }
  boundsByVolume[address] = bounds
  return bounds
end

-- Whether a location is inside a volume's box, the box reaching `headroom` higher than its top.
local function isInsideVolume(volume, location, headroom)
  local bounds = boundsOf(volume)
  if not bounds then
    return false
  end
  local bottom = bounds.origin.Z - bounds.extent.Z
  local top = bounds.origin.Z + bounds.extent.Z + headroom
  return math.abs(location.X - bounds.origin.X) <= bounds.extent.X
    and math.abs(location.Y - bounds.origin.Y) <= bounds.extent.Y
    and location.Z >= bottom and location.Z <= top
end

-- Whether a location is inside a box component's box, read live (it may move with its actor, like the shuttle's) and
-- turned with its yaw: the location is taken into the box's own frame. Pitch and roll are left out: these boxes stand
-- level.
local function isInsideBoxComponent(box, location)
  local centre = box:K2_GetComponentLocation()
  local extent = box:GetScaledBoxExtent()
  local yaw = math.rad(box:K2_GetComponentRotation().Yaw)
  local offsetX, offsetY = location.X - centre.X, location.Y - centre.Y
  local alongX = offsetX * math.cos(yaw) + offsetY * math.sin(yaw)
  local alongY = offsetY * math.cos(yaw) - offsetX * math.sin(yaw)
  return math.abs(alongX) <= extent.X and math.abs(alongY) <= extent.Y and math.abs(location.Z - centre.Z) <= extent.Z
end

-- Whether a location is inside an actor's bounding box as it stands now, for a trigger actor that moves.
local function isInsideMovingActor(actor, location)
  local origin, extent = {}, {}
  actor:GetActorBounds(false, origin, extent, false)
  if not origin.X or not extent.X then
    return false
  end
  return math.abs(location.X - origin.X) <= extent.X and math.abs(location.Y - origin.Y) <= extent.Y
    and math.abs(location.Z - origin.Z) <= extent.Z
end

local function listedVolumes(manager)
  local volumes = {}
  manager.TriggerVolumeList:ForEach(function(_, element)
    local volume = element:get()
    if volume:IsValid() then
      table.insert(volumes, volume)
    end
  end)
  return volumes
end

-- The map triggers are the actors carrying a TriggerMap_ActorComponent (its layer and priority), which register
-- themselves with the manager when they begin play (TriggerMap_ActorComponent.ReceiveBeginPlay).
local function mapTriggers()
  local triggers = {}
  for _, component in ipairs(FindAllOf(MAP_TRIGGER_COMPONENT_CLASS) or {}) do
    local trigger = component:IsValid() and component:GetOwner()
    if trigger and trigger:IsValid() then
      table.insert(triggers, trigger)
    end
  end
  return triggers
end

-- Each kind of manager, by class: where its volumes are, how it is told the entity entered or left one, and whether a
-- new entity first leaves every volume it isn't in. The map manager counts triggers, not who stands in them, so the
-- crew body the player drove before the entity stays counted in the triggers it last stood in: once the player drives
-- the entity, the body's own end-overlaps fail GetOnlyVisualOverlap (playtest 6: the minimap stuck on the safe zone
-- the crew start in). Leaving a trigger the manager doesn't count does nothing.
local sectionKind = {
  leavesStaleVolumes = false,
  contains = function(_, volume, location)
    return isInsideVolume(volume, location, config.areas.sectionHeadroom)
  end,
  volumesOf = listedVolumes,
  setInside = function(manager, volume, monster, isInside)
    manager:BPI_Streaming_AddActorToTrigger(volume, monster, isInside)
  end,
}

-- An actor that switches something on while the local player stands in one of its own trigger volumes: by the field
-- holding each volume, what its overlap events call. Either the overlap handlers themselves, { enter, leave }, which
-- run the game's own check (GetOnlyVisualOverlap) and pass the entity as this machine's pawn; or, where the handlers
-- are generated stubs, the switch they end in, { switch }, called with whether the entity is inside.
--
-- A field may be a path through a struct ("Infos.TriggerVisual_..." on a moray).
local function fieldAt(actor, fieldPath)
  local value = actor
  for name in fieldPath:gmatch("[^.]+") do
    value = value[name]
  end
  return value
end

local function ownVolumesKind(handlersByVolumeField, leavesStaleVolumes)
  return {
    leavesStaleVolumes = leavesStaleVolumes == true,
    contains = function(_, volume, location)
      return isInsideVolume(volume, location, 0)
    end,
    volumesOf = function(actor)
      local volumes = {}
      for field in pairs(handlersByVolumeField) do
        local volume = fieldAt(actor, field)
        if volume and volume:IsValid() then
          table.insert(volumes, volume)
        end
      end
      return volumes
    end,
    setInside = function(actor, volume, monster, isInside)
      for field, handlers in pairs(handlersByVolumeField) do
        local ownVolume = fieldAt(actor, field)
        if ownVolume:IsValid() and ownVolume:GetAddress() == volume:GetAddress() then
          if handlers.switch then
            actor[handlers.switch](actor, isInside)
            return
          end
          actor[isInside and handlers.enter or handlers.leave](actor, volume, monster)
          return
        end
      end
    end,
  }
end

-- A trigger list whose overlaps the actor counts (Polar's soundscape): the triggers are the volumes, entered and left
-- through its own overlap handlers.
local function triggerListKind(listField)
  return {
    leavesStaleVolumes = true,
    contains = function(_, volume, location)
      return isInsideVolume(volume, location, 0)
    end,
    volumesOf = function(actor)
      local volumes = {}
      actor[listField]:ForEach(function(_, element)
        local volume = element:get()
        if volume:IsValid() then
          table.insert(volumes, volume)
        end
      end)
      return volumes
    end,
    setInside = function(actor, volume, monster, isInside)
      if isInside then
        actor:BeginOverlap(volume, monster)
        return
      end
      actor:EndOverlap(volume, monster)
    end,
  }
end

local overlapHandlers = { enter = "BeginOverlap", leave = "EndOverlap" }
local shakeHandlers = { enter = "BeginOverlapShake", leave = "EndOverlapShake" }
local visualHandlers = { enter = "BeginOverlapVisual", leave = "EndOverlapVisual" }

-- The shuttle's inside (BP_PlayerShip.PlayerLocalInside): while the local player is aboard, the ship's interior engine
-- sound and low-pass, its room light and steam, and the emergency light's in-ship state; Polar's soundscape goes quiet
-- meanwhile (BP_AmbientMain_POLAR follows the ship's LocalInsideDispatch). The crew start a mission aboard, so the crew
-- body a player drove before becoming the entity left the ship "inside" for the entity, the outside soundscape silent:
-- a new entity first leaves it. Its trigger is its own box (TriggerBoxOverlapVisual) or, on a map that sets
-- UseExteriorTrigger, an actor placed outside it (ExtTriggerVisual); either moves with the ship, so each is read live.
-- Its visual overlap handlers run the game's own local-pawn check.
local shuttleKind = {
  leavesStaleVolumes = true,
  contains = function(ship, trigger, location)
    if ship.UseExteriorTrigger then
      return isInsideMovingActor(trigger, location)
    end
    return isInsideBoxComponent(trigger, location)
  end,
  volumesOf = function(ship)
    local trigger = ship.UseExteriorTrigger and ship.ExtTriggerVisual or ship.TriggerBoxOverlapVisual
    if not trigger:IsValid() then
      return {}
    end
    return { trigger }
  end,
  setInside = function(ship, _, monster, isInside)
    ship[isInside and "BeginOverlapVisual" or "EndOverlapVisual"](ship, nil, monster)
  end,
}

-- The final explosion's vortex (BP_FinalExplosion): its sound mix while the local player stands in its sphere, which
-- grows once the explosion starts and only collides from then on (SphereOverlapVisual). Of what its overlap does, only
-- the mix is for anyone but the crew (BPI_Player_InFinalExplosion is the crew character's), so the mix is pushed
-- directly.
local VORTEX_SOUND_MIX = "/Game/Blueprints/Player/VortexSoundMix.VortexSoundMix"
-- ECollisionEnabled
local NO_COLLISION = 0
local finalExplosionKind = {
  leavesStaleVolumes = false,
  contains = function(_, sphere, location)
    return game.distance(sphere:K2_GetComponentLocation(), location) <= sphere:GetScaledSphereRadius()
  end,
  volumesOf = function(explosion)
    local sphere = explosion.SphereOverlapVisual
    if not sphere:IsValid() or sphere:GetCollisionEnabled() == NO_COLLISION then
      return {}
    end
    return { sphere }
  end,
  setInside = function(_, _, monster, isInside)
    local mix = game.loadGameAsset(VORTEX_SOUND_MIX)
    if not mix then
      return
    end
    local statics = StaticFindObject(game.paths.gameplayStatics)
    statics[isInside and "PushSoundMixModifier" or "PopSoundMixModifier"](statics, monster, mix)
  end,
}

-- Polar's volumetric fog parts around the local player inside each of its boxes (BP_SplineCollision: its Box's
-- overlaps compare the actor with the local pawn, then SetIC switches the fog's interaction on or off).
local fogKind = {
  leavesStaleVolumes = false,
  contains = function(_, box, location)
    return isInsideBoxComponent(box, location)
  end,
  volumesOf = function(fog)
    if not fog.Box:IsValid() then
      return {}
    end
    return { fog.Box }
  end,
  setInside = function(fog, _, _, isInside)
    fog:SetIC(isInside)
  end,
}

-- The genetics lab's jars and creature tables are shown only while the local player is in the lab's visual trigger,
-- which BP_GeneticsLab_Manager hands each of them as their TriggerVolume when it spawns them (several jar shapes, each
-- its own class); the manager itself remembers whether the player is inside (InsideVisual) for the ones it spawns
-- later. Each moray is shown only while the player is in the trigger its spawner gave it (its Infos).
local labVisualKind = ownVolumesKind({ TriggerVisual = visualHandlers }, true)
local labDecorKind = ownVolumesKind({ TriggerVolume = overlapHandlers }, true)
local morayKind = ownVolumesKind({ ["Infos.TriggerVisual_11_6F8E28894FC858BEB604838FFB43D9B1"] = visualHandlers }, true)

-- Every kind by class. Subclasses are listed on their own (the vent wall's gas tank, the electrical reactor's child):
-- a lookup by class name may not find them through their parent.
local managerKinds = {
  BP_StreamingVolume_Manager_C = sectionKind,
  BP_InsideVolume_Manager_C = sectionKind,
  BP_CoreReactor_C = ownVolumesKind({ TriggerVolume = overlapHandlers, TriggerVolumeShake = shakeHandlers }),
  BP_Water_C = ownVolumesKind({ TriggerVolume = overlapHandlers }),
  -- Found by the local-player audit (#4): Hawking's wall fans in the vents, its engines (shown, lit, turning, and a
  -- camera shake nearby), its electrical reactors and Polar's generators (their loop sound and spin), Polar's control
  -- tower (its interior), its rovers (the engine heard from inside) and its soundscape (each area's sound and the
  -- inside music, from the triggers the pawn stands in)
  BP_VentWall_C = ownVolumesKind({ TriggerVolume = overlapHandlers }),
  BP_VentWall_GazTank_Child_C = ownVolumesKind({ TriggerVolume = overlapHandlers }),
  BP_Engine_C = ownVolumesKind({ TriggerVolume = overlapHandlers, TriggerVolumeShake = shakeHandlers }),
  BP_Electrical_Reactor_C = ownVolumesKind({ TriggerVolume = overlapHandlers }),
  BP_Electrical_Reactor_Child_C = ownVolumesKind({ TriggerVolume = overlapHandlers }),
  BP_Electrical_Generator_POLAR_C = ownVolumesKind({ TriggerVolume = overlapHandlers }),
  BP_TowerControl_C = ownVolumesKind({ TriggerVolume = { switch = "Inside" } }),
  BP_Rover_C = ownVolumesKind({ TriggerVolume = { switch = "PlayerLocalInside" } }),
  BP_AmbientMain_POLAR_C = triggerListKind("TriggerVolumeList"),
  BP_PlayerShip_C = shuttleKind,
  BP_FinalExplosion_C = finalExplosionKind,
  BP_SplineCollision_C = fogKind,
  BP_GeneticsLab_Manager_C = labVisualKind,
  BP_JarDeco_Vert_1_1_C = labDecorKind,
  BP_JarDeco_Vert_1_2_C = labDecorKind,
  ["BP_JarDeco_Vert_2-1_C"] = labDecorKind,
  ["BP_JarDeco_Vert_2-2_C"] = labDecorKind,
  BP_JarDeco_Vert_3_1_C = labDecorKind,
  BP_JarDeco_Vert_3_2_C = labDecorKind,
  BP_JarDeco_Vert_3_3_C = labDecorKind,
  BP_Creature01_Deco_Table_C = labDecorKind,
  BP_Creature02_Deco_Table_C = labDecorKind,
  BP_Creature03_Deco_Table_C = labDecorKind,
  BP_Moray_C = morayKind,
  -- Of the triggers the pawn stands in, the highest priority picks the layer (BP_MapManagerExtended.CheckBestTrigger),
  -- and standing in none goes back to the default one
  BP_MapManagerExtended_C = {
    leavesStaleVolumes = true,
    contains = function(_, volume, location)
      return isInsideVolume(volume, location, 0)
    end,
    volumesOf = mapTriggers,
    setInside = function(manager, volume, monster, isInside)
      if isInside then
        manager:BeginOverlap(volume, monster)
        return
      end
      manager:EndOverlap(volume, monster)
    end,
  },
}

-- The managers of every kind in the world, by class name, looked for again on a new world and every
-- config.areas.rescanSeconds: each lookup walks every object in the game, there are dozens of kinds, and some appear
-- later in a mission (the lab's jars and morays, the final explosion).
local managersByClass = {}
local scannedWorldKey = nil
local nextScanAt = 0

local function scanManagers(monster)
  local worldKey = monster:GetWorld():GetAddress()
  local now = game.timeSeconds(monster)
  if worldKey == scannedWorldKey and now < nextScanAt then
    return
  end
  scannedWorldKey = worldKey
  nextScanAt = now + config.areas.rescanSeconds
  for className in pairs(managerKinds) do
    managersByClass[className] = FindAllOf(className) or {}
  end
end

-- The volumes the entity is inside, by "<manager address>:<volume address>": { manager, kind, volume }.
local enteredVolumes = {}
-- The entity being followed, by address, so a new one starts by leaving the volumes it isn't in.
local followedMonsterAddress = nil
-- The level scripts that load parts of their map once the local pawn first crosses a trigger: Hawking's
-- (SpaceShip: its central static map and what follows it) and Polar's (PolarMap: its workshop). The crew body a player
-- drove before becoming the entity may never have crossed it, so the entity's machine loads them itself, once per
-- world. LoadLevel runs the same DoOnce the trigger does, so a level the body already loaded isn't loaded twice.
local LEVEL_SCRIPT_CLASSES = { "SpaceShip_C", "PolarMap_C" }
local levelsLoadedForWorld = nil

local function loadTriggeredLevels(monster)
  local worldKey = monster:GetWorld():GetAddress()
  if worldKey == levelsLoadedForWorld then
    return
  end
  levelsLoadedForWorld = worldKey
  for _, className in ipairs(LEVEL_SCRIPT_CLASSES) do
    local levelScript = FindFirstOf(className)
    if levelScript and levelScript:IsValid() then
      levelScript:LoadLevel()
      game.log("Loaded the levels %s loads when the player first crosses its trigger", className)
    end
  end
end

-- Runs a few times a second on the entity player's machine while they drive the entity.
function areas.follow(monster)
  loadTriggeredLevels(monster)
  scanManagers(monster)
  local location = monster:K2_GetActorLocation()
  local isNewMonster = monster:GetAddress() ~= followedMonsterAddress
  followedMonsterAddress = monster:GetAddress()
  local stillInside = {}

  for className, kind in pairs(managerKinds) do
    for _, manager in ipairs(managersByClass[className]) do
      if manager:IsValid() then
        for _, volume in ipairs(kind.volumesOf(manager)) do
          local key = manager:GetAddress() .. ":" .. volume:GetAddress()
          if kind.contains(manager, volume, location) then
            stillInside[key] = { manager = manager, kind = kind, volume = volume }
            if not enteredVolumes[key] then
              kind.setInside(manager, volume, monster, true)
            end
          elseif isNewMonster and kind.leavesStaleVolumes then
            kind.setInside(manager, volume, monster, false)
          end
        end
      end
    end
  end

  local changed = false
  for key in pairs(stillInside) do
    changed = changed or not enteredVolumes[key]
  end
  for key, entry in pairs(enteredVolumes) do
    if not stillInside[key] then
      changed = true
      if entry.manager:IsValid() and entry.volume:IsValid() then
        entry.kind.setInside(entry.manager, entry.volume, monster, false)
      end
    end
  end
  enteredVolumes = stillInside

  if changed then
    local count = 0
    for _ in pairs(enteredVolumes) do
      count = count + 1
    end
    game.log("The entity is in %d trigger volume(s); the game follows it through their areas", count)
  end
end

-- Once the player no longer drives the entity, the volumes are left as the game's own overlaps would leave them.
function areas.forget(monster)
  for _, entry in pairs(enteredVolumes) do
    if entry.manager:IsValid() and entry.volume:IsValid() and monster and monster:IsValid() then
      entry.kind.setInside(entry.manager, entry.volume, monster, false)
    end
  end
  enteredVolumes = {}
  followedMonsterAddress = nil
end

return areas
