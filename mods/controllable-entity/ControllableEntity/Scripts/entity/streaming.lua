-- Copyright © 2026 Jalapeno Labs

-- Which parts of the ship the entity player's machine shows.
--
-- The game streams the ship in sections: each BP_StreamingVolume_Manager shows its sections while the local player's
-- pawn stands in one of its trigger volumes (TriggerVolumeList), and hides them when it leaves. It decides from the
-- volumes' overlap events, and the squid's collision never overlaps them, so walls and floors stayed hidden around
-- the entity (playtest 5). The managers' own BPI_Streaming_AddActorToTrigger enters or leaves a volume by hand, and
-- runs the same check the overlaps do (BP_FunctionLibrairy.GetOnlyVisualOverlap: the local player's pawn counts),
-- so the mod tells them when the squid is inside a volume, from the volume's own shape (AVolume.EncompassesPoint).

local game = require("entity.game")

local streaming = {}

local MANAGER_CLASS = "BP_StreamingVolume_Manager_C"
local VOLUME_CLASS = "/Script/Engine.Volume"

-- The volumes the squid is inside, by "<manager address>:<volume address>": { manager, volume }.
local enteredVolumes = {}

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
  local volumeClass = StaticFindObject(VOLUME_CLASS)
  local location = squid:K2_GetActorLocation()
  local stillInside = {}

  for _, manager in ipairs(FindAllOf(MANAGER_CLASS) or {}) do
    if manager:IsValid() then
      for _, volume in ipairs(volumesOf(manager)) do
        if volume:IsA(volumeClass) and volume:EncompassesPoint(location, 0, {}) then
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
