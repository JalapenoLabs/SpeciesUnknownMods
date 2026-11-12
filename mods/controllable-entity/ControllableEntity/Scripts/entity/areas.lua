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
--     (playtest 9).
-- Each manager also has a way in by hand that runs the same check the overlaps do (BP_FunctionLibrairy.
-- GetOnlyVisualOverlap: the local player's pawn counts), so the mod tells them when the entity is inside a volume's
-- bounding box (AActor.GetActorBounds; AVolume's exact EncompassesPoint isn't exposed to Blueprints or Lua). A rotated
-- volume's box is a little larger than the volume, which only switches an area slightly early.
--
-- The map sections' volumes only reach as high as the crew can climb, and the ducts climb higher: in the vents high
-- over the labs, the entity stood in no volume, and the whole ship below it went invisible (playtest 9). So a map
-- section's box counts as reaching config.areas.sectionHeadroom higher. Standing in one more volume only keeps one more
-- section showing; the map's deck is picked from exact boxes, or the minimap could draw the deck below.

local config = require("entity.config")
local game = require("entity.game")

local areas = {}

local MAP_TRIGGER_COMPONENT_CLASS = "TriggerMap_ActorComponent_C"

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
  headroom = config.areas.sectionHeadroom,
  volumesOf = listedVolumes,
  setInside = function(manager, volume, monster, isInside)
    manager:BPI_Streaming_AddActorToTrigger(volume, monster, isInside)
  end,
}

-- An actor that switches something on while the local player stands in one of its own trigger volumes: by the field
-- holding each volume, what its overlap events call. Either the overlap handlers themselves, { enter, leave }, which
-- run the game's own check (GetOnlyVisualOverlap) and pass the entity as this machine's pawn; or, where the handlers
-- are generated stubs, the switch they end in, { switch }, called with whether the entity is inside.
local function ownVolumesKind(handlersByVolumeField, leavesStaleVolumes)
  return {
    leavesStaleVolumes = leavesStaleVolumes == true,
    headroom = 0,
    volumesOf = function(actor)
      local volumes = {}
      for field in pairs(handlersByVolumeField) do
        local volume = actor[field]
        if volume and volume:IsValid() then
          table.insert(volumes, volume)
        end
      end
      return volumes
    end,
    setInside = function(actor, volume, monster, isInside)
      for field, handlers in pairs(handlersByVolumeField) do
        local ownVolume = actor[field]
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
    headroom = 0,
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
  -- Of the triggers the pawn stands in, the highest priority picks the layer (BP_MapManagerExtended.CheckBestTrigger),
  -- and standing in none goes back to the default one
  BP_MapManagerExtended_C = {
    leavesStaleVolumes = true,
    headroom = 0,
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

-- The volumes the entity is inside, by "<manager address>:<volume address>": { manager, kind, volume }.
local enteredVolumes = {}
-- The entity being followed, by address, so a new one starts by leaving the volumes it isn't in.
local followedMonsterAddress = nil
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
local function isInside(volume, location, headroom)
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

-- Runs a few times a second on the entity player's machine while they drive the entity.
function areas.follow(monster)
  local location = monster:K2_GetActorLocation()
  local isNewMonster = monster:GetAddress() ~= followedMonsterAddress
  followedMonsterAddress = monster:GetAddress()
  local stillInside = {}

  for className, kind in pairs(managerKinds) do
    for _, manager in ipairs(FindAllOf(className) or {}) do
      if manager:IsValid() then
        for _, volume in ipairs(kind.volumesOf(manager)) do
          local key = manager:GetAddress() .. ":" .. volume:GetAddress()
          if isInside(volume, location, kind.headroom) then
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
