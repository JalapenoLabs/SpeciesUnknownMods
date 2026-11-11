-- Copyright © 2026 Jalapeno Labs

-- The extra entities' arrival, as the host: the clock from the power, the game's own spawn and setup, the mission's
-- monster left in place, capture contracts left alone, the Zombie Master's stand-in, and a hot reload mid-mission.
-- Run from the repository root:
--   lua mods/multi-entity/tests/spawner_test.lua

package.path = "mods/multi-entity/MultiEntity/Scripts/?.lua;mods/multi-entity/tests/?.lua;" .. package.path

local fake = require("fake_ue4ss")
fake.install()

local game = require("multi.game")

local fields = game.contractFields
local monsterNames = { game.classNames.monster }

-- A world for one mission: the game state with its contract, the game manager with its spawn point, and the
-- GameplayStatics spawn calls that make monsters of the class they're given.
local function mission(options)
  fake.instances, fake.calls = {}, {}
  local gameState = fake.object(game.classNames.gameState, {
    ContractInit = true,
    LightStatut = options.power or game.lightStatus.Off,
    Contract = {
      [fields.type] = options.contractType or game.contractTypes.Elimination,
      [fields.extraEntities] = options.extraEntities,
      [game.powerAtStartField] = options.powerAtStart or false,
    },
  }, nil, { "GameStateBase" })

  local point = fake.object("TargetPoint", nil, {
    GetTransform = function() return { Translation = { X = 5, Y = 6, Z = 7 } } end,
    K2_GetActorLocation = function() return { X = 5, Y = 6, Z = 7 } end,
  })
  local manager = fake.object(game.classNames.gameManager, {
    Monster = fake.invalid(),
    MonsterToSpawn = options.monsterType or 2,
    ["Game Time Progression"] = 0.25,
    setUpFor = {},
  }, {
    GetSpawnPoint = function(_, out) out.Selected = point end,
  })
  manager.SetUpBaseMonsterState = function(self)
    table.insert(self.setUpFor, self.Monster)
  end

  local spawnedClasses = {}
  fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
    GetTimeSeconds = function() return fake.now end,
    BeginDeferredActorSpawnFromClass = function(_, _, class, _, collision, owner, scale)
      assert(collision == 2 and owner == nil and scale == 1, "the game's own spawn arguments")
      table.insert(spawnedClasses, class)
      return fake.object("Monster", {
        class = class,
        IsDead = false,
        Tags = {},
        ShouldCheckIfStuck = true,
        GameTimeProgression = 0,
        ["Respawn Data"] = { [game.respawnFlagField] = true },
      }, { GetClass = function() return class end }, monsterNames)
    end,
  })
  fake.objects[game.paths.netPushModelHelpers] = fake.object("NetPushModelHelpers")
  return gameState, manager, spawnedClasses
end

local function monsterOfClass(className)
  local class = fake.object("Class", nil, { GetFName = function() return fake.name(className) end })
  return fake.object(className, { class = class, IsDead = false, Tags = {} }, {
    GetClass = function() return class end,
  }, monsterNames)
end

local function loadMod()
  for name in pairs(package.loaded) do
    if name:match("^multi%.") then
      package.loaded[name] = nil
    end
  end
  fake.hooks, fake.watchers, fake.loops = {}, {}, {}
  dofile("mods/multi-entity/MultiEntity/Scripts/main.lua")
  fake.spawnInstanceOf(game.paths.gameState)
end

local function tickAt(seconds)
  fake.now = seconds
  fake.runLoops()
end

local function powerOn(gameState, seconds, status)
  fake.now = seconds
  gameState.LightStatut = status or game.lightStatus.On
  fake.runHook(game.paths.gameState .. ":OnRep_LightStatut", fake.param(gameState))
end

local function extras()
  local found = {}
  for _, monster in ipairs(FindAllOf(game.classNames.monster) or {}) do
    if monster:ActorHasTag(FName(game.extraEntityTag)) then
      table.insert(found, monster)
    end
  end
  return found
end

local tests = {}

tests["the second arrives 2.5 minutes after the power, the third at 4, and no more"] = function()
  loadMod()
  local gameState, manager, spawnedClasses = mission({ extraEntities = 2 })
  tickAt(0)
  manager.Monster = monsterOfClass("BP_Monster_Poulpi_C")
  tickAt(10)
  powerOn(gameState, 20)

  tickAt(169)
  assert(#spawnedClasses == 0, "nothing before 2.5 minutes of power")
  tickAt(170)
  assert(#spawnedClasses == 1 and spawnedClasses[1] == manager.Monster.class, "the mission's own species")

  -- The power going off and on again doesn't restart the clock
  gameState.LightStatut = game.lightStatus.Off
  powerOn(gameState, 200)
  tickAt(259)
  assert(#spawnedClasses == 1)
  tickAt(260)
  assert(#spawnedClasses == 2, "the third at 4 minutes of power")
  tickAt(1000)
  assert(#spawnedClasses == 2, "a contract's extras arrive once")
end

tests["an extra gets the game's setup and leaves the mission's monster tracked"] = function()
  loadMod()
  local gameState, manager = mission({ extraEntities = 1 })
  local missionMonster = monsterOfClass("BP_Monster_Michel_C")
  manager.Monster = missionMonster
  powerOn(gameState, 0)
  tickAt(150)

  local extra = extras()[1]
  assert(extra, "an extra arrived")
  assert(manager.setUpFor[1] == extra, "SetUpBaseMonsterState ran for the extra")
  assert(manager.Monster == missionMonster, "the manager tracks the mission's monster again")
  assert(extra["Respawn Data"][game.respawnFlagField] == false, "an extra never restores a stuck monster")
  assert(extra.ShouldCheckIfStuck == false, "an extra can't make the game respawn the mission's monster")
  local finished = fake.callsTo(fake.objects[game.paths.gameplayStatics], "FinishSpawningActor")
  assert(#finished == 1 and finished[1].args[1] == extra, "the deferred spawn is finished")

  -- It keeps pace with the mission's monster
  manager["Game Time Progression"] = 0.5
  tickAt(151)
  assert(extra.GameTimeProgression == 0.5)
  assert(#fake.callsTo(extra, "OnRep_GameTimeProgression") >= 1)
end

tests["only the mod's tagged monsters count as extras"] = function()
  loadMod()
  local gameState, manager, spawnedClasses = mission({ extraEntities = 1 })
  manager.Monster = monsterOfClass("BP_Monster_Poulpi_C")
  -- Another monster of the base class the game placed itself, untagged
  monsterOfClass("BP_Monster_Poulpi_C")
  powerOn(gameState, 0)
  tickAt(150)
  assert(#spawnedClasses == 1, "a monster the mod didn't spawn isn't an arrived extra")
  assert(extras()[1].class == manager.Monster.class)
end

tests["the mission's monster goes back to the manager even when the setup fails"] = function()
  loadMod()
  local gameState, manager = mission({ extraEntities = 1 })
  local missionMonster = monsterOfClass("BP_Monster_Poulpi_C")
  manager.Monster = missionMonster
  manager.SetUpBaseMonsterState = function() error("setup broke") end
  powerOn(gameState, 0)
  tickAt(150)
  assert(manager.Monster == missionMonster)
  assert(extras()[1].ShouldCheckIfStuck == false, "the extra still skips the stuck check")
end

tests["with power at start, the clock waits for the mission's monster"] = function()
  loadMod()
  local _, manager, spawnedClasses = mission({ extraEntities = 1, powerAtStart = true, power = game.lightStatus.On })
  tickAt(0)
  tickAt(200)
  assert(#spawnedClasses == 0, "no extra before the mission's monster")
  manager.Monster = monsterOfClass("BP_Monster_Ghost_C")
  tickAt(201)
  tickAt(350)
  assert(#spawnedClasses == 0)
  tickAt(351)
  assert(#spawnedClasses == 1, "2.5 minutes after the monster came out")
end

tests["emergency power counts as on"] = function()
  loadMod()
  local gameState, manager, spawnedClasses = mission({ extraEntities = 1 })
  manager.Monster = monsterOfClass("BP_Monster_Eye_C")
  tickAt(0)
  powerOn(gameState, 5, game.lightStatus.Limited)
  tickAt(155)
  assert(#spawnedClasses == 1)
end

tests["the lights reading on before the game switches them off don't start the clock"] = function()
  loadMod()
  -- The game state's default is on; the game manager switches it off a moment into the mission
  local gameState, manager, spawnedClasses = mission({ extraEntities = 1, power = game.lightStatus.On })
  tickAt(0)
  manager.Monster = monsterOfClass("BP_Monster_Poulpi_C")
  tickAt(400)
  assert(#spawnedClasses == 0, "only a change to on, or power at start, starts the clock")
  powerOn(gameState, 410)
  tickAt(560)
  assert(#spawnedClasses == 1)
end

tests["capture contracts never get extras, whatever they carry"] = function()
  loadMod()
  local gameState, manager, spawnedClasses = mission({ extraEntities = 2, contractType = game.contractTypes.Capture })
  manager.Monster = monsterOfClass("BP_Monster_Poulpi_C")
  powerOn(gameState, 0)
  tickAt(1000)
  assert(#spawnedClasses == 0)
end

tests["the Zombie Master's extras are Mike"] = function()
  loadMod()
  local gameState, manager, spawnedClasses = mission({ extraEntities = 1, monsterType = 6 })
  manager.Monster = monsterOfClass("BP_Monster_ZombieMaster_C")
  local mike = fake.object("Class")
  fake.objects[game.monsterClassPaths[3]] = mike
  powerOn(gameState, 0)
  tickAt(150)
  assert(spawnedClasses[1] == mike, "the stand-in species, not a second Zombie Master")
end

tests["only the host spawns"] = function()
  loadMod()
  local gameState, manager, spawnedClasses = mission({ extraEntities = 2 })
  manager.Monster = monsterOfClass("BP_Monster_Poulpi_C")
  fake.isHost = false
  powerOn(gameState, 0)
  tickAt(1000)
  fake.isHost = true
  assert(#spawnedClasses == 0)
end

tests["a hot reload mid-mission counts the extras already here"] = function()
  loadMod()
  local gameState, manager, spawnedClasses = mission({ extraEntities = 2 })
  manager.Monster = monsterOfClass("BP_Monster_Poulpi_C")
  powerOn(gameState, 0)
  tickAt(150)
  assert(#spawnedClasses == 1)

  -- UE4SS drops the old scripts' hooks and loops and runs fresh copies
  loadMod()
  tickAt(160)
  assert(#spawnedClasses == 1, "the extra already here counts as arrived")
  tickAt(400)
  assert(#spawnedClasses == 2, "the third still comes, counted from the reload")
end

local failures = 0
local total = 0
for name, test in pairs(tests) do
  total = total + 1
  local succeeded, message = pcall(test)
  if not succeeded then
    failures = failures + 1
    print("FAIL  " .. name .. ": " .. tostring(message))
  end
end
print(string.format("%d/%d spawner tests passed", total - failures, total))
os.exit(failures == 0 and 0 or 1)
