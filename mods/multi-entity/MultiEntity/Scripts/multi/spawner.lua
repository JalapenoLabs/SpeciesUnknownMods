-- Copyright © 2026 Jalapeno Labs

-- Host side of the extra entities: when the mission's contract carries them, each arrives its delay after the ship's
-- power first comes on, through the game's own spawn point and monster setup, and keeps pace with the mission's
-- monster as the game ramps it up.
--
-- What the game assumes about its one monster, and how the extras live with it (read from BP_GameManager,
-- BP_BaseMonster and BP_MyGameState; see the mod README):
-- - BP_GameManager tracks one monster (Monster). The extras are never it, so the game's music, forced noises (doors,
--   alarms) and respawns stay with the mission's own monster.
-- - A monster that stands still for 20 seconds asks the game manager to respawn the *tracked* monster, which would
--   replace the mission's monster for an extra's sake, so the extras skip that check (ShouldCheckIfStuck).
-- - The stock AI only ever targets the crew (BPI_Human), and monsters make no noise the AI hears, so the entities
--   never hunt each other without any help from the mod.

local config = require("multi.config")
local contracts = require("multi.contracts")
local game = require("multi.game")
local rules = require("multi.rules")

local spawner = {}

-- The current mission: { managerAddress, poweredAt, monsterSeenAt, spawned, reportedCapture }, or nil outside one.
local mission = nil

local function isPowerOn(gameState)
  local status = gameState.LightStatut
  return status == game.lightStatus.On or status == game.lightStatus.Limited
end

local function isAlive(actor)
  return actor and actor:IsValid() and not actor.IsDead
end

-- Every monster in the map but the game manager's own: the extras, alive or dead, since a dead one still arrived.
local function extrasInWorld(manager)
  local tracked = manager.Monster
  local trackedAddress = tracked and tracked:IsValid() and tracked:GetAddress() or nil
  local extras = {}
  for _, monster in ipairs(FindAllOf(game.classNames.monster) or {}) do
    if monster:IsValid() and monster:GetAddress() ~= trackedAddress then
      table.insert(extras, monster)
    end
  end
  return extras
end

-- The mission record for the map's game manager, made fresh when the map (so the manager) changes. A record made
-- while the mission's monster is already out is a hot reload of the mod mid-mission: the power counts as on from
-- now if it reads on, and the extras already in the map count as arrived.
local function currentMission(manager, gameState, now)
  local managerAddress = manager:GetAddress()
  if mission and mission.managerAddress == managerAddress then
    return mission
  end

  mission = { managerAddress = managerAddress, poweredAt = nil, monsterSeenAt = nil, spawned = 0 }
  if isAlive(manager.Monster) then
    mission.monsterSeenAt = now
    mission.spawned = #extrasInWorld(manager)
    if isPowerOn(gameState) then
      mission.poweredAt = now
    end
    game.log("Picked up a mission in progress; extra entities already here: %d", mission.spawned)
  end
  return mission
end

-- The class the extras are: the mission's own species, unless config.extraSpeciesInstead names another.
local function extraClass(manager)
  local missionType = manager.MonsterToSpawn
  local extraType = config.extraSpeciesInstead[missionType]
  if not extraType then
    return manager.Monster:GetClass()
  end

  local classPath = game.monsterClassPaths[extraType]
  local class = StaticFindObject(classPath)
  if not class or not class:IsValid() then
    LoadAsset(classPath)
    class = StaticFindObject(classPath)
  end
  if not class or not class:IsValid() then
    game.log("Could not load %s for the extra entities", classPath)
    return nil
  end
  return class
end

-- Spawns one extra entity the way BP_GameManager.SpawnMonsterEvent spawns the mission's monster: at the manager's
-- own spawn point (GetSpawnPoint, which after the first spawn is the map's monster spawn point, or a Terminator's
-- own points), then the manager's own setup. SetUpBaseMonsterState sets up whatever its Monster property names
-- (difficulty, damage, the far-away sound, combat music, the escape route's nav modifiers), so the extra stands in
-- for the call and the mission's monster is put straight back: the swap is synchronous, so nothing else sees it.
local function spawnExtra(manager)
  local class = extraClass(manager)
  if not class then
    return
  end

  local pointOut = {}
  manager:GetSpawnPoint(pointOut)
  local point = pointOut.Selected
  if not point or not point:IsValid() then
    game.log("The game manager has no spawn point; no extra entity this time")
    return
  end

  local transform = point:GetTransform()
  local statics = StaticFindObject(game.paths.gameplayStatics)
  local extra = statics:BeginDeferredActorSpawnFromClass(manager, class, transform,
    game.spawnCollision.AdjustIfPossibleButAlwaysSpawn, nil, game.spawnScale.MultiplyWithRoot)
  if not extra or not extra:IsValid() then
    game.log("Spawning an extra entity failed")
    return
  end
  statics:FinishSpawningActor(extra, transform, game.spawnScale.MultiplyWithRoot)

  local missionMonster = manager.Monster
  manager.Monster = extra
  manager:SetUpBaseMonsterState()
  manager.Monster = missionMonster

  -- The setup copies the manager's respawn data, a stuck monster's state when there was one; an extra starts fresh
  extra["Respawn Data"][game.respawnFlagField] = false
  extra.ShouldCheckIfStuck = false

  local location = point:K2_GetActorLocation()
  game.log("An extra %s arrived at %.0f, %.0f, %.0f", class:GetFName():ToString(), location.X, location.Y,
    location.Z)
end

-- BP_GameManager.GameTimeProgression ramps its tracked monster's aggression up over the mission, each second; the
-- extras get the same value, the same way.
local function keepPace(manager, extras)
  local progression = manager["Game Time Progression"]
  local pushModel = StaticFindObject(game.paths.netPushModelHelpers)
  for _, extra in ipairs(extras) do
    if isAlive(extra) and extra.GameTimeProgression ~= progression then
      extra:FlushNetDormancy()
      extra.GameTimeProgression = progression
      pushModel:MarkPropertyDirty(extra, FName("GameTimeProgression"))
      extra:OnRep_GameTimeProgression()
    end
  end
end

-- Once a second on the host.
function spawner.tick()
  local manager = FindFirstOf(game.classNames.gameManager)
  local gameState = FindFirstOf(game.classNames.gameState)
  if not manager:IsValid() or not gameState:IsValid() then
    -- Outside a mission (the lobby has no game manager)
    mission = nil
    return
  end
  if not gameState.ContractInit then
    return
  end

  local now = game.timeSeconds(manager)
  local current = currentMission(manager, gameState, now)
  local contract = gameState.Contract
  local count = contracts.extraEntitiesOf(contract)
  if count == 0 then
    return
  end
  if not rules.isEligible(contract[game.contractFields.type]) then
    if not current.reportedCapture then
      current.reportedCapture = true
      game.log("This contract carries %d extra entities but captures keep one; none will come", count)
    end
    return
  end

  -- A contract with power at start never switches it on, so the power counts as on from the mission's start
  if not current.poweredAt and contract[game.powerAtStartField] then
    current.poweredAt = now
  end
  if not isAlive(manager.Monster) then
    return
  end
  current.monsterSeenAt = current.monsterSeenAt or now

  -- The clock starts once the power is on and the mission's monster is out: power at start counts from the monster's
  -- arrival, so the extras never come before it
  local secondsSincePower = nil
  if current.poweredAt then
    secondsSincePower = now - math.max(current.poweredAt, current.monsterSeenAt)
  end

  local extras = extrasInWorld(manager)
  current.spawned = math.max(current.spawned, #extras)
  local due = rules.extrasDue(count, secondsSincePower)
  while current.spawned < due do
    -- Counted before spawning, so a spawn that fails is reported once instead of retried every second
    current.spawned = current.spawned + 1
    spawnExtra(manager)
  end

  keepPace(manager, extrasInWorld(manager))
end

-- BP_MyGameState.OnRep_LightStatut runs on the host too: ChangeLightStatut calls it after every change. The first
-- change to on (full or emergency power) starts the clock; the power going off again later doesn't stop it.
local function onPowerChanged(contextParam)
  local gameState = contextParam:get()
  if not game.isHost() or not isPowerOn(gameState) then
    return
  end
  local manager = FindFirstOf(game.classNames.gameManager)
  if not manager:IsValid() then
    return
  end

  local now = game.timeSeconds(manager)
  local current = currentMission(manager, gameState, now)
  if not current.poweredAt then
    current.poweredAt = now
    game.log("The power is on; extra entities count from now")
  end
end

function spawner.register()
  game.hookWhenLoaded(game.paths.gameState, "OnRep_LightStatut", game.guarded("Watching the power", onPowerChanged))
end

return spawner
