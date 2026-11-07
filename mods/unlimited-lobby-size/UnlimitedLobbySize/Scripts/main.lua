-- Copyright © 2026 Jalapeno Labs

-- Unlimited Lobby Size: lets a host's lobby hold more than the stock four players.
--
-- Only the host needs it: the lobby, the session and the auto-kick all live on the host's machine. On a client it
-- raises the client's local copy of the same setting, which is harmless. See ../README.md for what the game's
-- Blueprints do with the cap and docs/multiplayer.md for the networking stack behind it.

local UEHelpers = require("UEHelpers")

-- An EOS lobby holds at most 64 members (EOS_LOBBY_MAX_LOBBY_MEMBERS). The game's voice chat lobby holds every
-- player plus every spectator, so players get whatever is left after the spectator slots. Lower this number for
-- a softer cap; nothing else in this file needs to change.
local MAX_LOBBY_MEMBERS = 64

-- Every player cap in the game derives from one variable on its game instance: the player lobby's capacity, the
-- chat lobby's capacity (players + spectators), the main session's slot count, the player-id slot loops, and the
-- auto-kick in BP_MyGameState.CheckAutoKickMaxPlayersNumber. It is a class default (4) that the Blueprints never
-- assign, so raising it once, before the host creates a lobby, changes all of them consistently.
local GAME_INSTANCE_CLASS = "BP_MyGameInstance_C"

-- Session builders that ignore playerLobbyCapacity and hard-code their slots (private join-by-code sessions use
-- 10, public ones 4 + 4). OSB copies each node's inputs into these reflected properties, and the node's native
-- Activate() reads them back, so they can be raised just before Activate() runs.
local sessionSettingsPropertyByNodeClass = {
  OnlineSessionSubsystemCreateSession = "__Store__NewSessionSettings",
  OnlineSessionSubsystemUpdateSession = "__Store__UpdatedSessionSettings",
}

-- The player capacity this mod settled on, once the game instance has been raised.
local playerCapacity = nil

-- Whether the missing game instance has been reported, so a renamed class is logged once instead of on every call.
local reportedMissingGameInstance = false

-- Raises the game instance's player capacity and the engine's login cap. Returns false while the game instance
-- doesn't exist yet, so the caller can try again on the next async node.
local function raiseGameCapacity()
  local gameInstance = FindFirstOf(GAME_INSTANCE_CLASS)
  if not gameInstance:IsValid() then
    if not reportedMissingGameInstance then
      reportedMissingGameInstance = true
      print(string.format(
        "[UnlimitedLobbySize] No %s yet, retrying on the next online call (if this repeats, a patch renamed it)\n",
        GAME_INSTANCE_CLASS
      ))
    end
    return false
  end

  local spectatorCapacity = gameInstance.spectatorLobbyCapacity
  local originalCapacity = gameInstance.playerLobbyCapacity
  playerCapacity = MAX_LOBBY_MEMBERS - spectatorCapacity

  if originalCapacity < playerCapacity then
    gameInstance.playerLobbyCapacity = playerCapacity
  end

  -- AGameSession::AtCapacity refuses logins past GameSession.MaxPlayers. A new GameSession is spawned on every
  -- map travel, but net.MaxPlayersOverride is read on every login and survives travel, so set it once here.
  UEHelpers.GetKismetSystemLibrary():ExecuteConsoleCommand(
    gameInstance,
    "net.MaxPlayersOverride " .. playerCapacity,
    nil
  )

  print(string.format(
    "[UnlimitedLobbySize] playerLobbyCapacity %d -> %d (%d EOS slots minus %d spectator slots)\n",
    originalCapacity,
    gameInstance.playerLobbyCapacity,
    MAX_LOBBY_MEMBERS,
    spectatorCapacity
  ))
  return true
end

-- Grows the connection pool a session uses until it can hold every player. Private slots are invite-only, so a
-- session the game made private stays private, and a public one keeps its private slots.
local function raiseSessionCapacity(node, settingsPropertyName, nodeClassName)
  local settings = node[settingsPropertyName]
  local publicSlots = settings.NumPublicConnections
  local privateSlots = settings.NumPrivateConnections

  if publicSlots + privateSlots >= playerCapacity then
    return
  end

  if publicSlots > 0 then
    settings.NumPublicConnections = playerCapacity - privateSlots
  else
    settings.NumPrivateConnections = playerCapacity
  end

  -- Read the property back from the node rather than trusting our own handle, so the log proves the new values
  -- are in the memory Activate() is about to read.
  local storedSettings = node[settingsPropertyName]
  print(string.format(
    "[UnlimitedLobbySize] %s: public %d -> %d, private %d -> %d\n",
    nodeClassName,
    publicSlots,
    storedSettings.NumPublicConnections,
    privateSlots,
    storedSettings.NumPrivateConnections
  ))
end

-- Every async Blueprint node runs through this native function, and the game starts one (AutoLogin) at launch,
-- long before anyone can host. `/Script/` hooks run before the function, so session inputs can still be edited.
-- The hook reads object properties, never the hooked call's parameters.
RegisterHook("/Script/Engine.BlueprintAsyncActionBase:Activate", function(context)
  if not playerCapacity and not raiseGameCapacity() then
    return
  end

  local node = context:get()
  local nodeClassName = node:GetClass():GetFName():ToString()
  local settingsPropertyName = sessionSettingsPropertyByNodeClass[nodeClassName]
  if settingsPropertyName then
    raiseSessionCapacity(node, settingsPropertyName, nodeClassName)
  end
end)

-- ---------------------------------------------------------------------------------------------------------------
-- Standing room in the shuttle
-- ---------------------------------------------------------------------------------------------------------------

-- The shuttle (BP_PlayerShip) spawns exactly four seats, and its launch checks compare the number of seated
-- players (NbPlayerSited) with the number of players: everyone in the game to start a mission, everyone inside the
-- ship to escape at the end, everyone in the game for the end-of-mission score. Past four players those checks
-- can never pass. Standing room: once every seat is taken, players standing inside the ship count as seated.
--
-- The ship re-runs both checks on server timers (CheckForLaunch every 0.5 s via CheckEmergency, Check Player Sit
-- End every second once a mission is finished), so a post-hook on each gets a chance on every tick. When the seats
-- are full and more players are inside, the hook raises NbPlayerSited to the number inside, re-runs the game's own
-- check (which still enforces closed doors, no monster aboard, everyone aboard, and so on), and restores the real
-- count. NbPlayerSited is read only by these checks and isn't replicated, so the temporary value is never seen
-- anywhere else.
local SHIP_CLASS = "/Game/Blueprints/Ship/BP_PlayerShip.BP_PlayerShip_C"
local SHIP_SEATED_CHECKS = { "CheckForLaunch", "Check Player Sit End" }

-- Set while the mod re-runs a check, so the post-hook ignores its own nested call.
local isRerunningSeatedCheck = false

-- The shuttle class the hooks are registered on. A map change can unload and reload the class, which creates new
-- functions that need hooking again; the same class must not be hooked twice.
local hookedShipClassAddress = nil

local function rerunWithStandingRoom(ship, checkName)
  if isRerunningSeatedCheck or not ship:HasAuthority() then
    return
  end

  local seatedCount = ship.NbPlayerSited
  local insideCount = ship.NbPlayerInShip
  local seatsFull = seatedCount >= #ship.ChairArray
  if not seatsFull or insideCount <= seatedCount then
    return
  end

  isRerunningSeatedCheck = true
  ship.NbPlayerSited = insideCount
  local isOk, errorMessage = pcall(function()
    ship[checkName](ship)
  end)
  ship.NbPlayerSited = seatedCount
  isRerunningSeatedCheck = false

  if not isOk then
    print(string.format("[UnlimitedLobbySize] Standing room re-run of %s failed: %s\n", checkName, errorMessage))
  end
end

-- Blueprint functions only exist once their class loads, so hook them when a shuttle is constructed. Blueprint
-- hooks run after the function, which is exactly when the game's own check has just failed.
NotifyOnNewObject(SHIP_CLASS, function(ship)
  local shipClassAddress = ship:GetClass():GetAddress()
  if shipClassAddress == hookedShipClassAddress then
    return
  end
  hookedShipClassAddress = shipClassAddress

  for _, checkName in ipairs(SHIP_SEATED_CHECKS) do
    RegisterHook(SHIP_CLASS .. ":" .. checkName, function(context)
      rerunWithStandingRoom(context:get(), checkName)
    end)
  end

  print("[UnlimitedLobbySize] Shuttle class loaded; standing room applies once all seats are taken\n")
end)

print("[UnlimitedLobbySize] Loaded; the player cap is raised when the game's first online call starts\n")
