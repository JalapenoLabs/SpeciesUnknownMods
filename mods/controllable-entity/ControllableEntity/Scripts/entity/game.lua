-- Copyright © 2026 Jalapeno Labs

-- Shared knowledge of the game: object paths, class names, and the few lookups every module needs.
-- Paths are confirmed against the shipped game's manifest and Blueprint bytecode (see the mod README).

local game = {}

-- The mod's own classes, from ControllableEntity_P.pak: { package, class }.
game.modClasses = {
  link = { package = "/Game/Mods/ControllableEntity/BP_EntityLink", class = "BP_EntityLink_C" },
  hud = { package = "/Game/Mods/ControllableEntity/WBP_EntityHUD", class = "WBP_EntityHUD_C" },
}

game.paths = {
  assetRegistryHelpers = "/Script/AssetRegistry.Default__AssetRegistryHelpers",
  squidClass = "/Game/Blueprints/Monsters/BP_Monster_Poulpi.BP_Monster_Poulpi_C",
  controllerClass = "/Game/Blueprints/Player/BP_MyPlayerController.BP_MyPlayerController_C",
  gameStateClass = "/Game/Blueprints/Core/BP_MyGameState.BP_MyGameState_C",
  weaponClass = "/Game/Weapon/Weapon_Base.Weapon_Base_C",
  characterClass = "/Game/Blueprints/Player/BP_ParentCharacter.BP_ParentCharacter_C",
  engineClass = "/Game/Blueprints/Engine/BP_Engine.BP_Engine_C",
  grabInterruptedMontage =
    "/Game/Blueprints/Monsters/Poulpi/Anim/Hit/Poulpi_Hit_DuringGrab_Front_Montage.Poulpi_Hit_DuringGrab_Front_Montage",
  inputLibrary = "/Script/EnhancedInput.Default__EnhancedInputLibrary",
  widgetLibrary = "/Script/UMG.Default__WidgetBlueprintLibrary",
  widgetLayoutLibrary = "/Script/UMG.Default__WidgetLayoutLibrary",
  gameplayStatics = "/Script/Engine.Default__GameplayStatics",
}

game.classNames = {
  squid = "BP_Monster_Poulpi_C",
  crewCharacter = "BP_Character_C",
  link = "BP_EntityLink_C",
  gameInstance = "BP_MyGameInstance_C",
  gameState = "BP_MyGameState_C",
  gameManager = "BP_GameManager_C",
  -- Players' controllers. Spectators get BP_MyPlayerControllerSpectator, which isn't one of these.
  playerController = "BP_MyPlayerController_C",
  lobbyGameMode = "BP_LobbyGameMode_C",
  missionGameMode = "BP_PlayableGameMode_C",
  mainMenuGameMode = "BP_MainMenuGameMode_C",
  -- The game's vent shafts; the Polar map uses a subclass.
  vents = { "BP_Vent_Up_C", "BP_Vent_Up_POLAR_C" },
  -- The crew HUD, which the crew character creates (BP_Character): status bars, objectives, the crosshair and the
  -- respawn-capsule status.
  crewHudWidgets = { "UI_HUD_Display_C", "UMG_ObjectiveList_C", "UI_Crosshair_Simple_C", "HUD_Respawn_C" },
}

-- MonsterList value for the squid (BP_Lobby_FunctionLibrairy.GetMonsterSoftClass).
game.squidMonsterType = 2

-- BP_MyGameState.LightStatut (LightStatutEnum), the ship's power. Missions start with it off unless the contract
-- has power at start; the crew is safe from the monster until they turn it on.
game.lightStatus = {
  On = 0,
  Off = 1,
  -- Self destruct armed: the crew must evacuate.
  Evacuation = 2,
  -- Emergency power: on, but dimmed.
  Limited = 3,
}

-- Contract types (BP_MyGameState.Contract.ContractType_2_...).
game.contractTypes = {
  Elimination = 0,
  Destruction = 1,
  Capture = 2,
  Extraction = 3,
}

function game.log(message, ...)
  print(string.format("[ControllableEntity] " .. message .. "\n", ...))
end

-- Mod classes that failed to load, so a missing pak is reported once instead of on every retry.
local reportedMissingClasses = {}

-- Loads one of the mod's own classes (game.modClasses), or returns nil after reporting why. UE4SS's LoadAsset can't
-- do this: it only loads assets listed in the game's asset registry, and a mod pak's assets never are. Asset data
-- built by hand loads by path instead, which is how UE4SS's own BPModLoader loads mods from paks.
function game.loadModClass(modClass)
  local classPath = modClass.package .. "." .. modClass.class
  local class = StaticFindObject(classPath)
  if class and class:IsValid() then
    return class
  end

  local assetRegistryHelpers = StaticFindObject(game.paths.assetRegistryHelpers)
  class = assetRegistryHelpers:GetAsset({ PackageName = FName(modClass.package), AssetName = FName(modClass.class) })
  if class and class:IsValid() then
    game.log("Loaded %s", classPath)
    return class
  end

  if not reportedMissingClasses[classPath] then
    reportedMissingClasses[classPath] = true
    game.log("Could not load %s; is ControllableEntity_P.pak in Content/Paks/~mods?", classPath)
  end
  return nil
end

-- UEHelpers.GetPlayerController returns the first player controller, which on a listen server can be a remote
-- player's. Only the controller this machine's player drives is local.
function game.localController()
  local controllers = FindAllOf("PlayerController") or {}
  for _, controller in ipairs(controllers) do
    if controller:IsValid() and controller:IsLocalController() then
      return controller
    end
  end
  return nil
end

-- True when this process is the host. Every gameplay rule runs there; clients only send input and draw the HUD.
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

function game.distance(from, to)
  local deltaX, deltaY, deltaZ = to.X - from.X, to.Y - from.Y, to.Z - from.Z
  return math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)
end

-- Unit vector a rotator points along. Pitch is included for aiming; movement uses yaw alone.
function game.rotationDirection(rotation)
  local pitch, yaw = math.rad(rotation.Pitch), math.rad(rotation.Yaw)
  return { X = math.cos(pitch) * math.cos(yaw), Y = math.cos(pitch) * math.sin(yaw), Z = math.sin(pitch) }
end

-- The player controller driving a pawn, or nil while the AI or no one drives it.
function game.playerControllerOf(pawn)
  local controller = pawn.Controller
  if not controller or not controller:IsValid() or not controller:IsPlayerController() then
    return nil
  end
  return controller
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Hooks on Blueprint functions
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Blueprint functions only exist while their class is loaded, and a map change can load a class again as a new
-- object, so each loaded class object gets its hooks exactly once. There is one NotifyOnNewObject per class however
-- many modules hook it: UE4SS warns that duplicate watchers on a class cost performance.
local hooksByClassPath = {}

local function registerPendingHooks(classPath)
  local entry = hooksByClassPath[classPath]
  local class = StaticFindObject(classPath)
  if not class or not class:IsValid() then
    return
  end

  -- Keyed on the hooked class itself, not the new instance's: a subclass instance (every special gun, every Polar
  -- vent) reports its own class, and must not register the base class's hooks a second time
  local classAddress = class:GetAddress()
  if entry.hookedClassAddress == classAddress then
    return
  end
  entry.hookedClassAddress = classAddress

  local hookedCount = 0
  for _, hook in ipairs(entry.hooks) do
    RegisterHook(classPath .. ":" .. hook.functionName, hook.callback)
    hookedCount = hookedCount + 1
  end

  -- Functions named by a pattern, for generated names that carry node numbers a game patch can change
  for _, patternHook in ipairs(entry.patternHooks) do
    class:ForEachFunction(function(unrealFunction)
      local functionName = unrealFunction:GetFName():ToString()
      local captures = { functionName:match(patternHook.pattern) }
      local callback = #captures > 0 and patternHook.makeCallback(table.unpack(captures)) or nil
      if callback then
        RegisterHook(classPath .. ":" .. functionName, callback)
        hookedCount = hookedCount + 1
      end
    end)
  end
  game.log("Hooked %d function(s) on %s", hookedCount, classPath)
end

local function entryFor(classPath)
  local entry = hooksByClassPath[classPath]
  if entry then
    return entry
  end
  entry = { hooks = {}, patternHooks = {}, hookedClassAddress = nil }
  hooksByClassPath[classPath] = entry
  NotifyOnNewObject(classPath, function()
    registerPendingHooks(classPath)
  end)
  return entry
end

-- Declares a post-hook (UE4SS runs Blueprint hooks after the function) on a Blueprint function.
function game.hookWhenLoaded(classPath, functionName, callback)
  table.insert(entryFor(classPath).hooks, { functionName = functionName, callback = callback })
end

-- Declares post-hooks on every function of the class whose name matches a Lua pattern. `makeCallback` receives the
-- pattern's captures and returns that function's hook, or nil to leave the function alone.
function game.hookMatchingWhenLoaded(classPath, pattern, makeCallback)
  table.insert(entryFor(classPath).patternHooks, { pattern = pattern, makeCallback = makeCallback })
end

-- Classes already loaded when the mod starts (a hot reload mid-game) get their hooks now instead of at the next
-- load. Called once, after every module has declared its hooks.
function game.hookLoadedClasses()
  for classPath in pairs(hooksByClassPath) do
    registerPendingHooks(classPath)
  end
end

return game
