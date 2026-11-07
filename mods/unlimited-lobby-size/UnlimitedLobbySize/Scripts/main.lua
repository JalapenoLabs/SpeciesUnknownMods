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

print("[UnlimitedLobbySize] Loaded; the player cap is raised when the game's first online call starts\n")
