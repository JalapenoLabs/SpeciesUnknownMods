-- Copyright © 2026 Jalapeno Labs

-- Host side of where the entity starts. The entity goes straight into the ducts (its lair) and stays in them until the
-- crew turns the power on: the game's own grace period, in which the crew is safe. Some contracts start with the power
-- on, and then the entity is free at once. An entity too big for the vents (the Terminator) lies powered down where the
-- game spawned it instead, as its AI does at the start, and wakes when the power comes on.
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

-- The current lair: { monster, controller, lastInside, leashed, lastWarnedAt, wake }, or nil. `wake` is the powered-
-- down entity's (its moves' wake), nil for the ducts.
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

-- Alone, nobody else can turn the power on, so the entity is told how to (onSoloPowerOn).
local function holdEvent(baseEvent)
  local gameState = FindFirstOf(game.classNames.gameState)
  local isAlone = gameState:IsValid() and gameState.PlayerArray:GetArrayNum() == 1
  return isAlone and baseEvent .. "Alone" or baseEvent
end

-- An entity too big for the vents lies powered down where the game spawned it until the power is on. One already
-- awake (a reload of the mod mid-mission takes it back) stays awake: waking it again would push the mission on.
local function beginPoweredDown(entity, kitMoves)
  local monster = entity.monster
  if monster[entity.kit.poweredFlag] then
    current = nil
    return
  end
  current = {
    monster = monster,
    controller = entity.controller,
    lastInside = nil,
    leashed = isPowerOff(),
    lastWarnedAt = -math.huge,
    wake = kitMoves.wake,
  }
  if not current.leashed then
    wake(monster, current.wake)
    game.log("The entity starts where the game spawned it, awake: the power is on")
    return
  end
  links.sendEvent(entity.controller, holdEvent("Dormant"))
  game.log("The entity lies powered down where the game spawned it until the power is on")
end

-- Starts the entity in its lair, right after the takeover (and, for one that lies powered down, after a reload of the
-- mod takes it back). `kitMoves` are its moves (moves.lua), for waking one that lies powered down.
function lair.begin(entity, kitMoves)
  if not entity.kit.usesVents then
    beginPoweredDown(entity, kitMoves)
    return
  end

  local monster, controller = entity.monster, entity.controller
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
    wake = nil,
  }
  if leashed then
    links.sendEvent(controller, holdEvent("Leashed"))
  end
  game.log("The entity starts in a vent at %.0f, %.0f, %.0f%s", spot.X, spot.Y, spot.Z,
    leashed and ", held in the ducts until the power is on" or "")
end

-- Wakes an entity lying powered down, through its moves' wake. It calls into the game by a name only research has
-- seen; a failure is logged rather than leaving the lair half let go.
local function wake(monster, wakeStep)
  local ok, failure = pcall(wakeStep, monster)
  if not ok then
    game.log("Waking the entity failed: %s", tostring(failure))
  end
end

-- Lets the entity go: the power came on, or the hunt started (hunt.lua) and the vents stopped being safe for it. One
-- lying powered down wakes.
local function letGo(event)
  current.leashed = false
  if current.wake then
    wake(current.monster, current.wake)
  end
  links.sendEvent(current.controller, event)
end

-- Lets the entity out of its lair early, when the vents stop being safe for it (hunt.lua).
function lair.release()
  if current and current.leashed then
    letGo("Released")
    game.log("The lair lets the entity go: the vents are no longer safe")
  end
end

-- What a move the lair holds back is answered with: the ducts hold the entity, or it lies powered down.
function lair.heldDenial()
  if current and current.wake then
    return "Denied.Dormant"
  end
  return "Denied.PowerOff"
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
    letGo(current.wake and "Awake" or "PowerRestored")
    game.log("The power is on: the entity is free")
    return
  end
  -- Powered down, it can't move: the player's own machine moves nothing (control.lua)
  if current.wake then
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
