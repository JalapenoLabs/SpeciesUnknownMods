-- Copyright © 2026 Jalapeno Labs

-- Shared knowledge of the game: object paths, field names, enums, and the few helpers every module needs. Every path
-- and field was read from the shipped game's Blueprint bytecode (see the mod README and docs/game-internals.md).

local game = {}

game.paths = {
  missionLibrary = "/Game/Blueprints/Mission/BP_Mission_FunctionLibrairy.BP_Mission_FunctionLibrairy_C",
  -- The lobby's contract terminal, which generates the contract list on the host
  contractTerminal =
    "/Game/Blueprints/Screens/Terminals/Contract/BP_ContractManagerTerminal.BP_ContractManagerTerminal_C",
  -- The modifier tables every contract screen reads by row name: name, icon and description; and the bounty.
  modifierTable = "/Game/Blueprints/Screens/Terminals/Contract/ContractModifier_Data.ContractModifier_Data",
  bountyTable = "/Game/Blueprints/Mission/Addiitonal_Bounty_DataTable.Addiitonal_Bounty_DataTable",
  contractCard = "/Game/Blueprints/Screens/Terminals/Contract/WBP_ContractCard.WBP_ContractCard_C",
  contractDetailPage = "/Game/Blueprints/Screens/Terminals/Contract/WBP_Contract_DetailPage.WBP_Contract_DetailPage_C",
  missionStartPage = "/Game/Blueprints/Screens/Ship/WBP_MissionStart_Page.WBP_MissionStart_Page_C",
  objectiveList = "/Game/Blueprints/UI/UMG_ObjectiveList.UMG_ObjectiveList_C",
  scorePage = "/Game/Blueprints/Screens/Ship/WBP_ScorePage.WBP_ScorePage_C",
  gameState = "/Game/Blueprints/Core/BP_MyGameState.BP_MyGameState_C",
  gameplayStatics = "/Script/Engine.Default__GameplayStatics",
  netPushModelHelpers = "/Script/Engine.Default__NetPushModelHelpers",
}

game.classNames = {
  gameState = "BP_MyGameState_C",
  -- Placed in each mission map; it picks, spawns and tracks the mission's monster (its Monster property)
  gameManager = "BP_GameManager_C",
  -- The base of every hunting monster; the Zombie Master's zombies aren't ones
  monster = "BP_BaseMonster_C",
}

-- The monsters by their MonsterList value (BP_GameManager.MonsterToSpawn; BP_Lobby_FunctionLibrairy's
-- GetMonsterSoftClass maps the same values).
game.monsterClassPaths = {
  [2] = "/Game/Blueprints/Monsters/BP_Monster_Poulpi.BP_Monster_Poulpi_C",
  [3] = "/Game/Blueprints/Monsters/BP_Monster_Michel.BP_Monster_Michel_C",
  [4] = "/Game/Blueprints/Monsters/BP_Monster_Eye.BP_Monster_Eye_C",
  [5] = "/Game/Blueprints/Monsters/BP_Monster_Ghost.BP_Monster_Ghost_C",
  [6] = "/Game/Blueprints/Monsters/BP_Monster_ZombieMaster.BP_Monster_ZombieMaster_C",
  [7] = "/Game/Blueprints/Monsters/BP_BigRobot.BP_BigRobot_C",
}

-- The actor tag the mod gives each extra entity it spawns (AActor.Tags), so the extras are told apart from every
-- other monster in the map, through a hot reload of the mod too. Tags don't replicate; only the host reads it.
game.extraEntityTag = "MultiEntityExtra"

-- BP_BaseMonster's "Respawn Data" (RespawnMonsterStruct): when its Respawn flag is set, the monster's begin play
-- restores a stuck predecessor's state half a second after it spawns.
game.respawnFlagField = "Respawn_14_0B4F186440AE4A32147201A4B7EEEE8E"

-- ContractStruct's power modifier: the power is on when the crew arrives.
game.powerAtStartField = "PowerAtStart_11_C457EA0B40DD327B66E17FBA29A033CD"

-- UGameplayStatics' spawn arguments, as BP_GameManager.SpawnMonsterEvent passes them.
game.spawnCollision = { AdjustIfPossibleButAlwaysSpawn = 2 }
game.spawnScale = { MultiplyWithRoot = 1 }

-- ContractStruct's fields, by their full generated names.
game.contractFields = {
  type = "ContractType_2_AD7B8E08435CF5A38556E7BA67C34760",
  maxBounty = "MaxBounty_40_41D52ADA489C1A0CC271FC8E07865CA3",
  -- How many extra entities the contract has. ContractStruct has no room for a new modifier, and changing its layout
  -- would break every machine without the mod, so the count rides in `Bonus`: an int the game sets to 0 on every
  -- contract and never reads (checked against every gameplay Blueprint and map). It replicates with the contract to
  -- every player and travels with it into the mission.
  extraEntities = "Bonus_37_1897E8074DDDA168BDAA24BC50497746",
}

-- SContractModifier_DataStruct (ContractModifier_Data's rows).
game.modifierRowFields = {
  name = "name_3_3A313BA54A97000D6CB4D2A9AEE6F71D",
  icon = "icon_5_9EA3603F46155E1B8CAA0F84E6A30736",
  description = "description_11_A2DEB7934F667D46383C3C917B3BC2A0",
}

-- AdditionalBountyStruct (Addiitonal_Bounty_DataTable's rows). A modifier pays its bounty through
-- GetAdditionalBounty(row, value): the value mapped from [minValue, maxValue] onto [minBounty, maxBounty]. A row
-- whose defaultValue is 0 means "on is the modifier", and screens show it with value 1.
game.bountyRowFields = {
  minValue = "Min_Int_3_6DBE8AC947579851C7355382905C4C74",
  maxValue = "Max_Int_5_C7D803E04B119E1B9CF2EB9E13F21BA9",
  minBounty = "Min-Bounty_7_3E34518A4A25F9DD115BE885F98DC204",
  maxBounty = "Max_Bounty_9_DEBC45E2499D9E25F04F8F8A1E28A468",
  defaultValue = "Default_Value_12_7C8C5BDF4DB03E3FAB5F6EA464516F27",
}

-- A game modifier whose rows the mod's rows are cloned from, so every field the mod doesn't set (the icon's
-- background colour) matches the game's other threats. Sentry turrets make a contract harder, as an entity does.
game.templateModifierRow = "Turret"

-- Contract types (ContractStruct.ContractType).
game.contractTypes = {
  Elimination = 0,
  Destruction = 1,
  Capture = 2,
  Extraction = 3,
}

-- BP_MyGameState.LightStatut (LightStatutEnum), the ship's power.
game.lightStatus = {
  On = 0,
  Off = 1,
  -- Self destruct armed: the crew must evacuate.
  Evacuation = 2,
  -- Emergency power: on, but dimmed.
  Limited = 3,
}

function game.log(message, ...)
  print(string.format("[MultiEntity] " .. message .. "\n", ...))
end

-- True when this process is the host, where every gameplay rule runs.
function game.isHost()
  local gameState = FindFirstOf("GameStateBase")
  if not gameState or not gameState:IsValid() then
    return false
  end
  return gameState:HasAuthority()
end

function game.timeSeconds(worldContext)
  return StaticFindObject(game.paths.gameplayStatics):GetTimeSeconds(worldContext)
end

-- Runs a hook's body, logging instead of raising: an error inside a hook would otherwise surface inside the game's
-- own call, and one failing screen must not stop the others.
function game.guarded(label, body)
  return function(...)
    local succeeded, problem = pcall(body, ...)
    if not succeeded then
      game.log("%s failed: %s", label, tostring(problem))
    end
  end
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Hooks on Blueprint functions
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Blueprint functions only exist while their class is loaded, and a map change can load a class again as a new
-- object, so each loaded class object gets its hooks exactly once.
local hooksByClassPath = {}
-- Classes with a NotifyOnNewObject watcher: one per class, however many hooks need it, because UE4SS warns that
-- duplicate watchers on a class cost performance.
local watchedClassPaths = {}

local function registerPendingHooks(classPath)
  local entry = hooksByClassPath[classPath]
  local class = StaticFindObject(classPath)
  if not class or not class:IsValid() then
    return
  end

  -- Keyed on the hooked class itself, not the new instance's, so a subclass instance can't hook its base twice
  local classAddress = class:GetAddress()
  if entry.hookedClassAddress == classAddress then
    return
  end
  entry.hookedClassAddress = classAddress

  for _, hook in ipairs(entry.hooks) do
    RegisterHook(classPath .. ":" .. hook.functionName, hook.callback)
  end
  game.log("Hooked %d function(s) on %s", #entry.hooks, classPath)
end

-- Every pending hook whose class is loaded gets registered; the rest wait for a later load.
local function registerAllPendingHooks()
  for classPath in pairs(hooksByClassPath) do
    registerPendingHooks(classPath)
  end
end

local function watch(classPath)
  if watchedClassPaths[classPath] then
    return
  end
  watchedClassPaths[classPath] = true
  NotifyOnNewObject(classPath, registerAllPendingHooks)
end

-- Declares a post-hook (UE4SS runs Blueprint hooks after the function) on a Blueprint function. The hook registers
-- once an instance of the class appears. A function library never gets instances, so it names in `loadedWith` the
-- classes that call it: their assets reference the library, so it is loaded by the time one of them exists.
function game.hookWhenLoaded(classPath, functionName, callback, loadedWith)
  local entry = hooksByClassPath[classPath]
  if not entry then
    entry = { hooks = {}, hookedClassAddress = nil }
    hooksByClassPath[classPath] = entry
  end
  table.insert(entry.hooks, { functionName = functionName, callback = callback })

  watch(classPath)
  for _, triggerClassPath in ipairs(loadedWith or {}) do
    watch(triggerClassPath)
  end
end

-- Classes already loaded when the mod starts (a hot reload mid-game) get their hooks now instead of at the next load.
-- Called once, after every module has declared its hooks.
game.hookLoadedClasses = registerAllPendingHooks

return game
