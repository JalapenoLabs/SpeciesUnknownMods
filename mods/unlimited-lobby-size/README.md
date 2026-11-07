# Unlimited Lobby Size

![Cover](cover.png)

Lets a host run a Species Unknown lobby with more than the stock four players, up to 64 (the most an EOS lobby can
hold). Only the host installs it.

- **Type:** UE4SS Lua mod (see [docs/ue4ss.md](../../docs/ue4ss.md))
- **Payload:** [`UnlimitedLobbySize/`](UnlimitedLobbySize/), copied or linked into `Win64/ue4ss/Mods/`
- **Status:** written against the 2026-11-06 build, not yet playtested (see [Test plan](#test-plan))

## Install

1. Install UE4SS for the game ([docs/ue4ss.md](../../docs/ue4ss.md#installing-ue4ss)).
2. Copy `UnlimitedLobbySize/` into
   `Species Unknown/SpeciesUnknown/Binaries/Win64/ue4ss/Mods/`. Developers can run
   `scripts/link-mod.sh unlimited-lobby-size` to symlink it instead.
3. Host a game. The `enabled.txt` inside the folder turns the mod on without editing `mods.txt`.

To change the cap, edit `MAX_PLAYERS` at the top of `Scripts/main.lua`.

## How it works

A Species Unknown lobby has two independent caps, and both live on the host:

| Cap | Where it is enforced | What the mod does |
|-----|----------------------|-------------------|
| EOS lobby member limit | Epic's lobby service, using the slot count the host created the session with | Raises the slot count before the session is created |
| Engine login check (`AGameSession::AtCapacity`) | The host's server, on every join | Sets `net.MaxPlayersOverride` |

**Lobby slots.** The game creates its session through the OnlineSubsystemBlueprints (OSB) async nodes. When a
Blueprint calls `CreateSession`, OSB copies the session settings into the node's `__Store__NewSessionSettings`
property, and the node's native `Activate()` then hands them to the Redpoint EOS subsystem. The mod pre-hooks
`/Script/Engine.BlueprintAsyncActionBase:Activate`, and when the node is a create or update session node, it grows
`NumPublicConnections` (or `NumPrivateConnections` for invite-only lobbies) so the total is `MAX_PLAYERS`. The hook
keys on OSB's native class names, not on the game's Blueprint names, so routine game patches don't break it.

**Server capacity.** `net.MaxPlayersOverride` is an engine console variable that `AGameSession::AtCapacity` reads on
every login. A console variable survives map travel, while the `GameSession` actor and its `MaxPlayers` are rebuilt
on every travel, so the console variable is the one setting that holds for a whole play session.

Both changes happen only on the machine that creates a session. On a client the mod loads and does nothing.

## What could still need clients or more hooks

Host-only holds as long as nothing in the game's own Blueprints assumes four players. We have not read those
Blueprints yet (see [docs/reverse-engineering.md](../../docs/reverse-engineering.md)). The candidates:

- **Join gate in Blueprint.** `BP_LobbyGameMode` or `BP_PlayableGameMode` may count players on login and kick past
  four. That logic runs on the host, so a fix would still be host-only.
- **Four-slot UI and arrays.** Player-colour lists (`DEBUGColorsEnum`), lobby slot widgets or a scoreboard sized for
  four. These run on every client. Out-of-range reads in Blueprint log a warning and return a default rather than
  crash, so the likely symptom is a missing name tag or colour, not a broken game.
- **Lobby created through `OnlineLobbySubsystemCreateLobby`** instead of sessions. The mod logs every OSB node it
  sees but doesn't handle (`Saw online node ...`), so one hosted game shows which path is used.

## Test plan

UE4SS writes everything the mod prints to `Win64/ue4ss/UE4SS.log`.

1. Launch with UE4SS and the mod installed. The log shows
   `[UnlimitedLobbySize] Loaded, hosted lobbies will allow up to 64 players`.
2. Host a lobby. The log shows
   `[UnlimitedLobbySize] OnlineSessionSubsystemCreateSession: public 4 -> 64, private 0 -> 0`
   (numbers may differ). If it doesn't:
   - `Saw online node` lines but no capacity line: the game creates its lobby through a node this mod doesn't
     handle yet. Report the node names.
   - No `Saw online node` lines at all: the hook never fired, so OSB's nodes don't run through
     `BlueprintAsyncActionBase:Activate` in this build. Report that; the mod needs a different hook point.
3. Open the UE4SS console (`F10` or `@`) and run `net.MaxPlayersOverride`. It reports `64`.
4. Have five or more players join, with the host as the only one running the mod. Note anything that breaks:
   failed joins, missing names or colours, spawn problems, a scoreboard that cuts off.
5. Start a contract with five or more players and travel back to the lobby. Check that everyone stays connected
   and a new player can still join after the travel.
6. As a client (mod installed, not hosting), join a stock four-player lobby. The log has no capacity lines and
   nothing changes.
