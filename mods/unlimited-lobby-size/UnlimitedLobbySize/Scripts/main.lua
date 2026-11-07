-- Copyright © 2026 Jalapeno Labs

-- Unlimited Lobby Size: lets a host's lobby hold more than the stock four players.
--
-- Everything here acts only on the machine that creates the session, which is always the host. Clients need
-- nothing installed: the EOS lobby they join and the server that admits them both live on the host.
-- See ../README.md for which caps exist and docs/multiplayer.md for the networking stack behind them.

local UEHelpers = require("UEHelpers")

-- EOS lobbies hold at most 64 members (EOS_LOBBY_MAX_LOBBY_MEMBERS), so 64 is "no cap" in practice.
-- Lower it if you want a softer limit; nothing else in this file needs to change.
local MAX_PLAYERS = 64

-- The game creates its lobby through OnlineSubsystemBlueprints (OSB) async nodes. When a Blueprint calls one,
-- the node copies its inputs into reflected `__Store__*` properties, and its native Activate() later reads them
-- back to call the online subsystem. Rewriting the stored settings just before Activate() runs changes what
-- the lobby is created with, without depending on any of the game's own Blueprint names, which change between
-- patches. Both names below are confirmed in the shipped binary's reflection strings.
local sessionSettingsPropertyByNodeClass = {
  OnlineSessionSubsystemCreateSession = "__Store__NewSessionSettings",
  OnlineSessionSubsystemUpdateSession = "__Store__UpdatedSessionSettings",
}

-- OSB node classes already reported to the log, so each unhandled one is reported once rather than on every call.
local reportedNodeClasses = {}

-- Grows the connection pool the game is using until the session totals MAX_PLAYERS slots. Private slots are
-- invite-only, so a lobby the game made private stays private, and a public one keeps its private slots.
local function raiseSessionCapacity(node, settingsPropertyName, nodeClassName)
  local settings = node[settingsPropertyName]
  local publicSlots = settings.NumPublicConnections
  local privateSlots = settings.NumPrivateConnections

  if publicSlots + privateSlots >= MAX_PLAYERS then
    print(string.format(
      "[UnlimitedLobbySize] %s already allows %d players, leaving it alone\n",
      nodeClassName,
      publicSlots + privateSlots
    ))
    return
  end

  if publicSlots > 0 then
    settings.NumPublicConnections = MAX_PLAYERS - privateSlots
  else
    settings.NumPrivateConnections = MAX_PLAYERS
  end

  -- Read the property back from the node rather than trusting our own handle, so the log proves the new
  -- values are in the memory Activate() is about to read.
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

-- The engine's own login check (AGameSession::AtCapacity) refuses joins past GameSession.MaxPlayers. A new
-- GameSession is spawned on every map travel and reads MaxPlayers from the travel URL, so overriding the
-- property would have to chase every travel. net.MaxPlayersOverride is read by AtCapacity on every login and
-- survives travel, so one console command covers the whole play session.
local function raiseServerCapacity()
  local kismetSystemLibrary = UEHelpers.GetKismetSystemLibrary()
  local world = UEHelpers.GetWorld()
  if not world:IsValid() then
    print("[UnlimitedLobbySize] No world yet, so net.MaxPlayersOverride is unset; joins may stop at the stock cap\n")
    return
  end

  kismetSystemLibrary:ExecuteConsoleCommand(world, "net.MaxPlayersOverride " .. MAX_PLAYERS, nil)
end

-- `/Script/` hooks run before the native function, which is what lets us edit the stored settings in time.
RegisterHook("/Script/Engine.BlueprintAsyncActionBase:Activate", function(context)
  local node = context:get()
  local nodeClass = node:GetClass()
  local nodeClassName = nodeClass:GetFName():ToString()
  local settingsPropertyName = sessionSettingsPropertyByNodeClass[nodeClassName]

  if not settingsPropertyName then
    -- Every async Blueprint node in the game passes through here. Report each distinct OSB node once, so the log
    -- shows which online calls the game makes if a patch moves lobby creation to a call this mod doesn't handle.
    local isOnlineNode = nodeClass:GetFullName():find("/Script/OnlineSubsystemBlueprints.", 1, true)
    if isOnlineNode and not reportedNodeClasses[nodeClassName] then
      reportedNodeClasses[nodeClassName] = true
      print(string.format("[UnlimitedLobbySize] Saw online node %s (not a session capacity change)\n", nodeClassName))
    end
    return
  end

  raiseSessionCapacity(node, settingsPropertyName, nodeClassName)
  raiseServerCapacity()
end)

print(string.format("[UnlimitedLobbySize] Loaded, hosted lobbies will allow up to %d players\n", MAX_PLAYERS))
