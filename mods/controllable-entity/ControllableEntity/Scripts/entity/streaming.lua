-- Copyright © 2026 Jalapeno Labs

-- Which parts of the ship the entity player's machine shows.
--
-- The game streams the ship in sections: each BP_StreamingVolume_Manager shows its sections while the local player's
-- pawn stands in one of its trigger volumes (TriggerVolumeList), and hides them when it leaves. It decides from the
-- volumes' overlap events, and the squid's collision never overlaps them, so walls and floors stayed hidden around
-- the entity (playtest 5). The managers' own BPI_Streaming_AddActorToTrigger enters or leaves a volume by hand, and
-- runs the same check the overlaps do (BP_FunctionLibrairy.GetOnlyVisualOverlap: the local player's pawn counts),
-- so the mod tells them when the squid is inside a volume's bounding box (AActor.GetActorBounds; AVolume's exact
-- EncompassesPoint isn't exposed to Blueprints or Lua). A rotated volume's box is a little larger than the volume,
-- which only shows a section slightly early.

local game = require("entity.game")

local streaming = {}

local MANAGER_CLASS = "BP_StreamingVolume_Manager_C"

-- The volumes the squid is inside, by "<manager address>:<volume address>": { manager, volume }.
local enteredVolumes = {}
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
    game.log("A streaming volume gave no bounds; its section is left to the game")
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

local function volumesOf(manager)
  local volumes = {}
  manager.TriggerVolumeList:ForEach(function(_, element)
    local volume = element:get()
    if volume:IsValid() then
      table.insert(volumes, volume)
    end
  end)
  return volumes
end

local function setInside(manager, volume, squid, isInside)
  manager:BPI_Streaming_AddActorToTrigger(volume, squid, isInside)
end

-- Runs a few times a second on the entity player's machine while they drive the squid.
function streaming.follow(squid)
  local location = squid:K2_GetActorLocation()
  local stillInside = {}

  for _, manager in ipairs(FindAllOf(MANAGER_CLASS) or {}) do
    if manager:IsValid() then
      for _, volume in ipairs(volumesOf(manager)) do
        if isInside(volume, location) then
          local key = manager:GetAddress() .. ":" .. volume:GetAddress()
          stillInside[key] = { manager = manager, volume = volume }
          if not enteredVolumes[key] then
            setInside(manager, volume, squid, true)
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
        setInside(entry.manager, entry.volume, squid, false)
      end
    end
  end
  enteredVolumes = stillInside

  if changed then
    local count = 0
    for _ in pairs(enteredVolumes) do
      count = count + 1
    end
    game.log("The squid is in %d streaming volume(s); the game shows their sections", count)
  end
end

-- Once the player no longer drives the squid, the volumes are left as the game's own overlaps would leave them.
function streaming.forget(squid)
  for _, entry in pairs(enteredVolumes) do
    if entry.manager:IsValid() and entry.volume:IsValid() and squid and squid:IsValid() then
      setInside(entry.manager, entry.volume, squid, false)
    end
  end
  enteredVolumes = {}
end

return streaming
