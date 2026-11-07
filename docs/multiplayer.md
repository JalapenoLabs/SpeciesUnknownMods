# Multiplayer

How Species Unknown connects players, and how to decide whether a mod can be host-only.

## Stack

- **Online subsystem:** Redpoint EOS Online Framework (`DefaultPlatformService=RedpointEOS`), on top of Epic
  Online Services. OnlineSubsystemSteam is compiled in too, presumably for Steam sign-in and friends; the exact
  split between the two is unconfirmed.
- **Blueprint access:** the game drives everything online through **OnlineSubsystemBlueprints** (OSB) async nodes.
  `BP_MyGameInstance` creates a session (`CreateSession`) and three EOS lobbies through `CreateLobby` with OSB
  lobby transactions: a player lobby, a chat lobby and a spectator lobby. Every OSB node copies its inputs into
  `__Store__*` properties that a UE4SS pre-hook on `Activate()` can rewrite (see
  [ue4ss.md](ue4ss.md#changing-what-an-async-blueprint-node-does)).
- **Topology:** listen server (inferred: the game ships no dedicated server). The host's game is the server;
  everyone else is a client. The host creates the session (an EOS lobby), and clients find and join it.
- **Stock cap:** four players (host plus three).

## Limits outside the game

- An EOS lobby holds at most **64** members (`EOS_LOBBY_MAX_LOBBY_MEMBERS`). No mod can go past that.
- `AGameSession::AtCapacity` on the server refuses logins past `GameSession.MaxPlayers`, unless
  `net.MaxPlayersOverride` is above zero, in which case the override applies.

## Limits inside the game

The game's Blueprints enforce four players on their own, on the host: `BP_LobbyGameMode` checks for more than four
players in the lobby and acts on it, and `BP_MyGameState` auto-kicks past `playerLobbyCapacity`. Any player-count
mod has to handle these as well as the session and lobby caps. Details in
[Unlimited Lobby Size](../mods/unlimited-lobby-size/README.md#remaining-work).

## Host-only or everyone?

The host's machine is authoritative for the session, the game mode, spawning and every replicated variable, so
a mod can be host-only when everything it changes is one of:

- Session or lobby settings the host creates.
- Server-side rules: game mode, login checks, AI, spawning, damage, mission logic.
- Replicated values whose types stay the same (clients just receive different numbers).

It needs every player when it changes:

- Anything only clients run: HUD, widgets, local input, camera, client-side prediction.
- The *shape* of replicated data: new replicated properties or RPCs, new actor classes, changed asset layouts.
  Mismatched layouts break the connection.
- Assets a client must load to see the change (new meshes or textures from a pak mod).

UE4SS Lua mods change values at runtime without changing any class layout, so a server-side Lua mod is safe to
run on the host alone.
