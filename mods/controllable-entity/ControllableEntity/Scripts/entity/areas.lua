-- Copyright © 2026 Jalapeno Labs

-- The areas of the ship the entity player's machine treats the squid as standing in.
--
-- Some of the game's managers follow the local player's pawn through trigger volumes, and decide from the volumes'
-- overlap events, which the squid's collision never fires:
--   - map sections: each BP_StreamingVolume_Manager shows its sections while the pawn stands in one of its volumes, so
--     walls and floors stayed hidden around the entity (playtest 5);
--   - the map's deck: BP_MapManagerExtended picks which layer the minimaps draw from the map triggers the pawn stands
--     in, so the entity's minimap showed the deck below crew quarters (playtest 6).
-- Each manager also has a way in by hand that runs the same check the overlaps do (BP_FunctionLibrairy.
-- GetOnlyVisualOverlap: the local player's pawn counts), so the mod tells them when the squid is inside a volume's
-- bounding box (AActor.GetActorBounds; AVolume's exact EncompassesPoint isn't exposed to Blueprints or Lua). A rotated
-- volume's box is a little larger than the volume, which only switches an area slightly early.

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

-- Each kind of manager, by class: where its volumes are, how it is told the squid entered or left one, and whether a
-- new squid first leaves every volume it isn't in. The map manager counts triggers, not who stands in them, so the
-- crew body the player drove before the squid stays counted in the triggers it last stood in: once the player drives
-- the squid, the body's own end-overlaps fail GetOnlyVisualOverlap (playtest 6: the minimap stuck on the safe zone
-- the crew start in). Leaving a trigger the manager doesn't count does nothing.
local managerKinds = {
  BP_StreamingVolume_Manager_C = {
    leavesStaleVolumes = false,
    volumesOf = listedVolumes,
    setInside = function(manager, volume, monster, isInside)
      manager:BPI_Streaming_AddActorToTrigger(volume, monster, isInside)
    end,
  },
  -- Of the triggers the pawn stands in, the highest priority picks the layer (BP_MapManagerExtended.CheckBestTrigger),
  -- and standing in none goes back to the default one
  BP_MapManagerExtended_C = {
    leavesStaleVolumes = true,
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

-- The volumes the squid is inside, by "<manager address>:<volume address>": { manager, kind, volume }.
local enteredVolumes = {}
-- The squid being followed, by address, so a new one starts by leaving the volumes it isn't in.
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

local function isInside(volume, location)
  local bounds = boundsOf(volume)
  return bounds and math.abs(location.X - bounds.origin.X) <= bounds.extent.X
    and math.abs(location.Y - bounds.origin.Y) <= bounds.extent.Y
    and math.abs(location.Z - bounds.origin.Z) <= bounds.extent.Z
end

-- Runs a few times a second on the entity player's machine while they drive the squid.
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
          if isInside(volume, location) then
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
    game.log("The squid is in %d trigger volume(s); the game follows it through their areas", count)
  end
end

-- Once the player no longer drives the squid, the volumes are left as the game's own overlaps would leave them.
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
