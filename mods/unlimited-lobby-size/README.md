# Unlimited Lobby Size

![Cover](cover.png)

Lets a host run a Species Unknown lobby with more than the stock four players: as many as an EOS lobby allows
(64 members, minus the game's spectator slots). Only the host installs it.

- **Type:** UE4SS Lua mod (see [docs/ue4ss.md](../../docs/ue4ss.md))
- **Payload:** [`UnlimitedLobbySize/`](UnlimitedLobbySize/), copied or linked into `Win64/ue4ss/Mods/`
- **Status:** complete against the 2026-11-06 build, awaiting its first playtest (see [Test plan](#test-plan))

## Install

1. Install UE4SS for the game ([docs/ue4ss.md](../../docs/ue4ss.md#installing-ue4ss)).
2. Copy `UnlimitedLobbySize/` into
   `Species Unknown/SpeciesUnknown/Binaries/Win64/ue4ss/Mods/`. Developers can run
   `scripts/link-mod.sh unlimited-lobby-size` to symlink it instead.
3. Host a game. The `enabled.txt` inside the folder turns the mod on without editing `mods.txt`.

To set a lower cap, lower `MAX_LOBBY_MEMBERS` at the top of `Scripts/main.lua`.

## How the game caps players

Read from the game's Blueprint bytecode (see [docs/reverse-engineering.md](../../docs/reverse-engineering.md)).
Everything below runs on the host.

**One variable drives the cap.** `BP_MyGameInstance.playerLobbyCapacity` (int64, class default, never assigned
by the Blueprints) feeds:

- the player EOS lobby: `Make Player Lobby Transaction` calls `SetCapacity(playerLobbyCapacity)`;
- the voice chat EOS lobby: `SetCapacity(playerLobbyCapacity + spectatorLobbyCapacity)`;
- the main session: `MakeMainSessionSettings(playerLobbyCapacity)` sets `NumPublicConnections`;
- player-id slots: `CheckAllowConnectionLobby`, `PlayerIdFromUNetId` and `RegisterPlayerFunc` loop over slots
  `0 .. playerLobbyCapacity - 1`;
- the auto-kick: `BP_MyGameState.CheckAutoKickMaxPlayersNumber` kicks a joining player when `PlayerArray` is longer
  than `playerLobbyCapacity`.

**Two session builders hard-code their slots** instead: `MakePrivateSessionSettings` (join-by-code sessions) uses
10 public connections, and `MakePublicSessionSettings` uses 4 public + 4 private.

**The "more than 4 players" check doesn't kick.** `BP_LobbyGameMode.Check More Than 4Players` counts players in
the scene, and when there are more than four it sets `had_more_than_4_players`, prints a debug message (only with
the game's online debug tag on) and calls `TryFixModeThan4Players`, which is empty. It also reports an
`ASSERT_FAILED_MORE_THAN_4_PLAYER_IN_LOBBY` event through the game's analytics subsystem, so **the developers'
telemetry will see lobbies with more than four players.**

## How the mod works

The mod pre-hooks `/Script/Engine.BlueprintAsyncActionBase:Activate`, which every async Blueprint node runs
through. The game starts one (`AutoLogin`) at launch, long before anyone can host.

1. **On the first async node**, it raises `playerLobbyCapacity` to `MAX_LOBBY_MEMBERS - spectatorLobbyCapacity`,
   so the chat lobby (players + spectators) stays within the 64-member EOS limit. From then on, the game builds
   every lobby, session, slot loop and kick check from the new number by itself. It also sets the engine's
   `net.MaxPlayersOverride` to the same number, because `AGameSession::AtCapacity` checks logins against the
   engine's own cap and a console variable survives map travel.
2. **On every create or update session node**, it raises the session's slots to the player capacity. That covers
   the two builders that hard-code 10 and 4 + 4. OSB copies a node's inputs into `__Store__NewSessionSettings` /
   `__Store__UpdatedSessionSettings`, and the hook edits them before the native `Activate()` reads them.

The hook reads object properties, never the hooked call's parameters, so it doesn't depend on how UE4SS passes
the arguments of a native function called from Blueprint.

## Who installs it

The host. Everything that enforces the cap runs on the host.

A client that also installs it raises its own copy of `playerLobbyCapacity`. That does nothing to the cap, but the
player-id slot loops also run on clients (for example while registering players), so unmodded clients may not
resolve the ids of players five and up. If a playtest shows missing names, voice or colours for those players on
unmodded clients, have everyone install the mod.

## Test plan

UE4SS writes everything the mod prints to `Win64/ue4ss/UE4SS.log`.

1. Launch with UE4SS and the mod installed. The log shows
   `[UnlimitedLobbySize] playerLobbyCapacity 4 -> N (64 EOS slots minus S spectator slots)` shortly after the
   main menu loads. Note `N`: it is the real cap.
   - `No BP_MyGameInstance_C yet` repeating without the capacity line means a game patch renamed the class.
   - No line at all means the hook never fired; report it.
2. Host a lobby by code. The log shows
   `[UnlimitedLobbySize] OnlineSessionSubsystemCreateSession: public 10 -> N, private 0 -> 0`.
3. Open the UE4SS console (`F10` or `@`) and run `net.MaxPlayersOverride`. It reports `N`.
4. Have five or more players join, with the host as the only one running the mod. Note anything that breaks:
   failed joins, kicks, missing names, colours or voice for players five and up, spawn problems, a scoreboard
   that cuts off.
5. Start a contract with five or more players and travel back to the lobby. Check that everyone stays connected
   and a new player can still join after the travel.
6. Repeat step 4 with every player running the mod, if step 4 showed client-side glitches.
