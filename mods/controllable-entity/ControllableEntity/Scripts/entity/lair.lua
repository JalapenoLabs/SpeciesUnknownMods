-- Copyright © 2026 Jalapeno Labs

-- Host side of where the entity starts. The entity goes straight into the ducts (its lair) and stays in them until the
-- crew turns the power on: the game's own grace period, in which the crew is safe. Some contracts start with the power
-- on, and then the entity is free at once.
--
-- It starts in the vent nearest where the game spawned it: the game manager's spawn point for the mission's monster
-- (BP_GameManager.GetSpawnPoint), the one the AI would start from, skipping vents too near the crew. Inside, the
-- whole duct network is the entity's (playtest 7: a radius around the start pulled the squid back from ducts it could
-- see and crawl into, with no sign why). Only leaving the ducts puts it back.

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")
local vents = require("entity.vents")

local lair = {}

local POWER_SCREEN_CLASS_NAME = "BP_Screen_RestorePower_C"

-- The current lair: { monster, controller, lastInside, leashed, lastWarnedAt }, or nil.
local current = nil

local function isPowerOff()
  local gameState = FindFirstOf(game.classNames.gameState)
  return gameState:IsValid() and gameState.LightStatut == game.lightStatus.Off
end

-- Where the crew stands. The entity player's own parked body is hidden, and doesn't count.
local function crewLocations()
  local locations = {}
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    if crewMember:IsValid() and not crewMember.bHidden then
      table.insert(locations, crewMember:K2_GetActorLocation())
    end
  end
  return locations
end

-- A random vent spot at least minimumCrewDistance from every crew member, or the spot farthest from the crew when
-- none is that far. Nil when the map has no vents.
-- The duct spot nearest where the game spawned the entity that is far enough from every crew member, or the one
-- farthest from the crew when none is.
local function chooseStartSpot(spawnLocation)
  local crew = crewLocations()
  local nearestFarEnough, nearestFarEnoughDistance = nil, math.huge
  local farthestSpot, farthestDistance = nil, -1

  for _, vent in ipairs(vents.all()) do
    local spot = vents.spotsOf(vent)[1]
    if spot then
      local nearestCrewDistance = math.huge
      for _, location in ipairs(crew) do
        nearestCrewDistance = math.min(nearestCrewDistance, game.distance(spot, location))
      end
      local spawnDistance = game.distance(spot, spawnLocation)
      if nearestCrewDistance >= config.lair.minimumCrewDistance and spawnDistance < nearestFarEnoughDistance then
        nearestFarEnough, nearestFarEnoughDistance = spot, spawnDistance
      end
      if nearestCrewDistance > farthestDistance then
        farthestSpot, farthestDistance = spot, nearestCrewDistance
      end
    end
  end
  return nearestFarEnough or farthestSpot
end

-- Starts the entity in its lair, right after the takeover.
function lair.begin(monster, controller)
  local spot = chooseStartSpot(monster:K2_GetActorLocation())
  if not spot then
    game.log("No vent on this map; the entity starts where the game spawned it")
    current = nil
    return
  end

  vents.moveInto(monster, spot)
  local leashed = isPowerOff()
  current = {
    monster = monster,
    controller = controller,
    lastInside = spot,
    leashed = leashed,
    lastWarnedAt = -math.huge,
  }
  if leashed then
    -- Alone, nobody else can turn the power on, so the entity is told how to (onSoloPowerOn)
    local gameState = FindFirstOf(game.classNames.gameState)
    local isAlone = gameState:IsValid() and gameState.PlayerArray:GetArrayNum() == 1
    links.sendEvent(controller, isAlone and "LeashedAlone" or "Leashed")
  end
  game.log("The entity starts in a vent at %.0f, %.0f, %.0f%s", spot.X, spot.Y, spot.Z,
    leashed and ", held in the ducts until the power is on" or "")
end

-- Lets the entity out of its lair early, when the vents stop being safe for it (hunt.lua).
function lair.release()
  if current and current.leashed then
    current.leashed = false
    game.log("The lair lets the entity go: the vents are no longer safe")
  end
end

function lair.forget()
  current = nil
end

-- Whether the entity is still held in its lair: the power hasn't come on yet.
function lair.isLeashed(monster)
  return current ~= nil and current.leashed and current.monster:IsValid()
    and current.monster:GetAddress() == monster:GetAddress()
end

-- Runs about five times a second on the host. While the power is off, an entity that leaves the ducts or strays past
-- the leash goes back to the last spot it stood at inside the leash; once the power is on, it is free for good, even
-- if the crew turns the power off again.
function lair.tick()
  if not current or not current.leashed then
    return
  end
  local monster = current.monster
  if not monster:IsValid() then
    current = nil
    return
  end

  if not isPowerOff() then
    current.leashed = false
    links.sendEvent(current.controller, "PowerRestored")
    game.log("The power is on: the entity may leave the vents")
    return
  end

  local location = monster:K2_GetActorLocation()
  if monster.InVent then
    current.lastInside = { X = location.X, Y = location.Y, Z = location.Z }
    return
  end

  vents.moveInto(monster, current.lastInside)
  local now = game.timeSeconds(monster)
  if now - current.lastWarnedAt >= config.lair.warningInterval then
    current.lastWarnedAt = now
    links.sendEvent(current.controller, "Denied.PowerOff")
    game.log("Pulled the entity back into the ducts from %.0f, %.0f, %.0f", location.X, location.Y, location.Z)
  end
end

-- F8 as the entity, playing alone: turns the power on, as the crew would at the power screen, so a solo player can
-- test what comes after the lair. With anyone else in the session it's the crew's job, and F8 does nothing.
local function onSoloPowerOn(takeover, controller)
  local gameState = FindFirstOf(game.classNames.gameState)
  if not takeover.isEntityController(controller) or not gameState:IsValid() then
    game.log("Solo power from a player who isn't the entity; ignored")
    return
  end
  if gameState.PlayerArray:GetArrayNum() > 1 then
    links.sendEvent(controller, "Denied.NotAlone")
    return
  end
  if not isPowerOff() then
    return
  end
  -- What the power screen sets: emergency power on contracts that have it (BP_Screen_RestorePower.LimitedLight)
  local screen = FindFirstOf(POWER_SCREEN_CLASS_NAME)
  local isLimited = screen and screen:IsValid() and screen.LimitedLight == true
  gameState:ChangeLightStatut(isLimited and game.lightStatus.Limited or game.lightStatus.On, false)
  game.log("The entity turned the power on, playing alone")
end

function lair.register(takeover)
  links.onCommand("SoloPowerOn", function(_, controller)
    onSoloPowerOn(takeover, controller)
  end)
end

return lair
