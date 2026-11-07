# Unlimited Lobby Size

![Cover](cover.png)

Lets a host run a Species Unknown lobby with more than the stock four players, up to 64 (the most an EOS lobby can
hold). Only the host installs it.

- **Type:** UE4SS Lua mod (see [docs/ue4ss.md](../../docs/ue4ss.md))
- **Payload:** [`UnlimitedLobbySize/`](UnlimitedLobbySize/), copied or linked into `Win64/ue4ss/Mods/`
- **Status:** incomplete. It raises the session, lobby and engine caps, but the game's own Blueprints also kick
  players past four, and that check isn't handled yet (see [Remaining work](#remaining-work)). Not yet playtested.

## Install

1. Install UE4SS for the game ([docs/ue4ss.md](../../docs/ue4ss.md#installing-ue4ss)).
2. Copy `UnlimitedLobbySize/` into
   `Species Unknown/SpeciesUnknown/Binaries/Win64/ue4ss/Mods/`. Developers can run
   `scripts/link-mod.sh unlimited-lobby-size` to symlink it instead.
3. Host a game. The `enabled.txt` inside the folder turns the mod on without editing `mods.txt`.

To change the cap, edit `MAX_PLAYERS` at the top of `Scripts/main.lua`.

## How it works

Three caps that the mod raises, all on the host:

| Cap | Where it is enforced | What the mod does |
|-----|----------------------|-------------------|
| Session slots | The session the host creates (`CreateSession`) | Raises `NumPublicConnections` / `NumPrivateConnections` |
| EOS lobby capacity | Epic's lobby service; the game's player, chat and spectator lobbies | Calls `SetCapacity(64)` on each lobby transaction |
| Engine login check (`AGameSession::AtCapacity`) | The host's server, on every join | Sets `net.MaxPlayersOverride` |

**Session and lobbies.** The game creates both through OnlineSubsystemBlueprints (OSB) async nodes. When a
Blueprint calls one, OSB copies the inputs into the node's `__Store__*` properties (`__Store__NewSessionSettings`,
`__Store__Transaction`), and the node's native `Activate()` then hands them to the Redpoint EOS subsystem. The
mod pre-hooks `/Script/Engine.BlueprintAsyncActionBase:Activate` and, for create and update nodes:

- **Sessions:** grows the connection pool the game uses until the total is `MAX_PLAYERS`.
- **Lobbies:** calls the transaction's `SetCapacity`. The transaction keeps its capacity in a field Lua can't
  see, so the mod calls the setter instead of editing a property. A Lua call goes through `ProcessEvent` with a
  proper parameter frame.

The hook reads the node's own properties, never the hooked call's parameters, and keys on OSB's native class
names rather than the game's Blueprint names, so routine game patches don't break it.

**Server capacity.** `net.MaxPlayersOverride` is an engine console variable that `AGameSession::AtCapacity` reads on
every login. A console variable survives map travel, while the `GameSession` actor and its `MaxPlayers` are rebuilt
on every travel, so the console variable is the one setting that holds for a whole play session.

All of this happens only on the machine that creates the session and lobbies. On a client the mod loads and does
nothing.

## Remaining work

The game also enforces four players in its own Blueprints. Function and variable names from the cooked assets
(unpacked with retoc; see [docs/reverse-engineering.md](../../docs/reverse-engineering.md)):

- **`BP_LobbyGameMode`** has `Check More Than 4Players` and `TryFixModeThan4Players`, with the messages
  `ASSERT_FAILED_MORE_THAN_4_PLAYER_IN_LOBBY` and `TRY_FIX_MORE_THAN_4_PLAYER_IN_LOBBY`. It counts players in the EOS
  lobby (`OWNER Get Online Nb Players in Lobby`) and acts on more than four. That four may be a hard-coded literal.
- **`BP_MyGameState`** has `CheckAutoKickMaxPlayersNumber`, which compares players against an int64
  `playerLobbyCapacity` and calls `OWNER_KickPlayerFromLobby`. If `playerLobbyCapacity` comes from the lobby's
  capacity, the lobby change above already fixes it.
- **`BP_MyGameInstance`** builds the lobbies (`Make Player / Chat / Spectator Lobby Transaction`) and runs
  `CheckAllowConnectionLobby` before letting a player connect.

All three run on the host, so the mod stays host-only. Choosing the right hook needs the Blueprint bytecode,
which the asset names alone don't show. Still to check on clients: lobby slot widgets and per-player arrays sized
for four (for example `DEBUGColorsEnum`). Out-of-range reads in Blueprint log a warning and return a default, so
the worst likely symptom is a missing name tag or colour.

## Test plan

UE4SS writes everything the mod prints to `Win64/ue4ss/UE4SS.log`.

1. Launch with UE4SS and the mod installed. The log shows
   `[UnlimitedLobbySize] Loaded, hosted lobbies will allow up to 64 players`.
   On this first launch, also dump the game's `.usmap` mappings from the UE4SS GUI's Dumpers tab. Asset tools
   need it to read the Blueprint bytecode behind [Remaining work](#remaining-work).
2. Host a lobby. The log shows capacity lines for the session and each lobby, for example
   `[UnlimitedLobbySize] OnlineSessionSubsystemCreateSession: public 4 -> 64, private 0 -> 0` and
   `[UnlimitedLobbySize] OnlineLobbySubsystemCreateLobby: capacity set to 64`. If it doesn't:
   - `Saw online node` lines but no capacity line: the game creates its lobby through a node this mod doesn't
     handle yet. Report the node names.
   - No `Saw online node` lines at all: the hook never fired, so OSB's nodes don't run through
     `BlueprintAsyncActionBase:Activate` in this build. Report that; the mod needs a different hook point.
3. Open the UE4SS console (`F10` or `@`) and run `net.MaxPlayersOverride`. It reports `64`.
4. Have five or more players join, with the host as the only one running the mod. Until the Blueprint check is
   handled, expect the fifth player to be kicked; note when it happens and what the kicked player sees. Note
   anything else that breaks: failed joins, missing names or colours, spawn problems, a scoreboard that cuts off.
5. Start a contract with five or more players and travel back to the lobby. Check that everyone stays connected
   and a new player can still join after the travel.
6. As a client (mod installed, not hosting), join a stock four-player lobby. The log has no capacity lines and
   nothing changes.
