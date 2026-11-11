# Multi Entity

Contracts can carry a second and a third entity, each a modifier worth extra bounty. The extra entities arrive a set
time after the ship's power comes on, and hunt the crew alongside the mission's own.

- **Status:** awaiting first playtest (see [Test plan](#test-plan)).
- **Payload:** the Lua mod [`MultiEntity/`](MultiEntity/). No pak.
- **Who installs it:** the host, who rolls the modifiers and spawns the entities. Every other player installs it too to
  see the modifiers on their screens and to be paid their bounty: the game pays each player from their own machine
  (see [The bounty](#the-bounty)).
- **Independent of** the other mods here; it works alongside [Controllable Entity](../controllable-entity/README.md)
  (see [With Controllable Entity](#with-controllable-entity)).

## Rules

### The modifiers

| Modifier | Bounty | Arrives | Chance on a new contract |
|----------|--------|---------|--------------------------|
| Second Entity | +2,500 $ | 2.5 minutes after the power comes on | 30% |
| Third Entity | +2,500 $ | 4 minutes after the power comes on | 40% of the contracts with a second entity |

- A third entity always comes with a second: the third is only rolled on a contract that got the second.
- Capture contracts never carry them, and a capture mission never gets an extra entity, whatever its contract says.
- Every tunable (bounties, chances, delays, labels) is in [`config.lua`](MultiEntity/Scripts/multi/config.lua).

### When they arrive

- The clock starts the first time the ship's power comes on, full or emergency, and keeps running if the crew turns
  the power off again.
- On a contract that starts with the power on, the clock starts when the mission's own monster appears (on Hawking,
  when the crew steps out of the shuttle), so the extras never come before it.
- An extra entity spawns where the game spawns its own monster (the map's monster spawn point, or the Terminator's
  own points), and is set up by the game's own code, with the mission's difficulty.

### The species

The extra entities are the mission's own species, so the special weapon the map places for its weakness works on
them too. The exception is the Zombie Master: its zombies each follow the one Zombie Master in the map, and the
zombie bodies are placed only for the mission's own, so its extra entities are Mike, the game's baseline monster.

### The hunt

- **The entities never hunt each other.** As the game's bytecode reads, its monsters only pick crew as targets
  (every target check requires the crew's `BPI_Human` interface, which no monster class lists), no monster makes a
  noise the AI hears, and the game's forced noises (doors, the airlock alarm, canisters) come from what the crew does.
  So the mod adds no rule of its own; the test plan checks it in play.
- **Stray fire still hurts.** The Terminator's gatling and grenades damage whatever they hit, so another monster in
  the line of fire takes damage, as a crew member would. Melee attacks and grabs only ever catch crew.
- **The mission ends with the first kill.** Killing any entity ends the mission as a kill, exactly as killing the one
  specimen does in the stock game, on every contract that ends that way (kill, capture, extraction). Destruction
  contracts go on, with the other entities still hunting.
- **The game's doors, alarms and explosive canisters** call only the mission's own monster (`BPI_GameState_ForceSound`
  reaches the game manager's tracked monster). The extra entities hear gunshots and footsteps like any monster.

### The bounty

The modifiers pay like the game's own: their bounty is in the contract's bounty on the contract board, and the score
screen adds it to the "additional conditions" line of the payout. The game works the payout out on each player's own
machine and adds it to their own wallet there, so a player without the mod sees the higher bounty on the board but
is paid without the extra entities' share.

## Install

1. UE4SS, as for any mod ([docs/ue4ss.md](../../docs/ue4ss.md#installing-ue4ss)).
2. Copy `MultiEntity/` into `Win64/ue4ss/Mods/` (or `scripts/link-mod.sh multi-entity`). The host must have it; every
   other player should.

Every player should run the same version: the host's copy decides the roll and the spawns, and each machine's copy
decides the labels and the bounty it pays its own player.

## Architecture

Lua only, in `MultiEntity/Scripts/multi/`, one module per job:

| Module | Runs on | Does |
|--------|---------|------|
| `rules.lua` | both | Eligibility, the roll, the bounty and the arrival schedule, as plain logic (unit tested) |
| `contracts.lua` | both | The host's roll onto new contracts; the bounty every machine pays; the modifiers' rows in the game's tables |
| `screens.lua` | both | The modifiers on every screen that lists a contract's modifiers |
| `spawner.lua` | host | The clock, the spawns, and keeping the extras in step with the mission's monster |
| `game.lua`, `config.lua` | both | Game paths, field names and helpers; every tunable |

### Where a contract keeps its extra entities

`ContractStruct` has a fixed field per modifier, and adding one would change its layout, which breaks every machine
without the mod. The mod keeps the count of extra entities (0, 1 or 2) in its `Bonus` field instead: an int the game
sets to 0 on every contract and never reads (checked against every gameplay Blueprint and map). The count replicates
with the contract to every player and travels with it into the mission, so every screen and the spawner read it from
the contract itself. The third-needs-the-second rule holds by construction.

### The roll

`BP_ContractManagerTerminal` fills its replicated `generatedContracts` from
`BP_Mission_FunctionLibrairy.GenerateContracts` on the host. A post-hook on `GenerateContracts` writes each contract's
count, and adds its bounty to `MaxBounty`, through the function's out parameter: that is the terminal's own variable,
so the terminal stores, replicates and shows the rolled list as if the game had generated it. The game's own
generation, which balances modifiers against bounty targets per tier, runs untouched before it.

### The bounty

`BP_Mission_FunctionLibrairy.GetConditionalCombinedBounty` sums what a contract's modifiers pay. The score screen
(`WBP_ScorePage.SetUpBaseMission`) adds it, with the objective's bounty, into the mission bounty, which each player's
seat then pays into their own wallet (`BPI_Player_AddMoney`, then the local game instance's save). A post-hook adds
the extra entities' bounty to the sum on every machine with the mod. Contract generation calls it too, but before the
roll, when every count is still 0, so nothing counts twice.

### The screens

Every screen that lists a contract's modifiers builds its list from the game's own: it walks
`GlobalModifiersStatus_DT`, reads each modifier through a switch over the game's names (`Contract Get Bool Modifier
From Player View`), and draws it with its own helper, which looks the modifier's name, icon and description up in
`ContractModifier_Data` and its bounty in `Addiitonal_Bounty_DataTable`, by row name.

The mod adds a row for each of its modifiers to those two tables (cloned from the game's sentry-turret modifier, so
the icon frame's colour matches the game's other threats), and a post-hook on each screen draws them with the screen's
own helper after the game's:

| Screen | Post-hook | Draws |
|--------|-----------|-------|
| Contract board card | `WBP_ContractCard.Setup` | An icon each (`CreateBoolModifier`) |
| Contract details | `WBP_Contract_DetailPage."Setup Contract Detail Page"` | A selectable line each, with its bounty; selecting it shows its description |
| Shuttle mission start | `WBP_MissionStart_Page."Set Up Additional"` | A line each, with its bounty |
| Mission brief (Tab) | `UMG_ObjectiveList."Create Modifier List"` | A line each, in the brief's two columns |
| Score screen | `WBP_ScorePage.FinishSetupModifiers` | An icon each, after the game's |

The rows stay out of `GlobalModifiersStatus_DT`: the game reads modifier values through a switch over its own names,
so a new name there would never show, and leaving it out also keeps the mod's modifiers out of contract generation.
The icon is the game's codex chimera (`T_UI_chimeria_icon`), so the mod needs no pak.

### The spawns

`BP_GameManager` (placed in each mission map, on the host) spawns and tracks the mission's one monster (`Monster`).
Once a second the host's spawner works out how many extra entities are due (from the contract's count and the time
since the power came on), counts the ones already in the map (the monsters carrying the mod's actor tag,
`MultiEntityExtra`, so a hot reload of the mod never spawns twice), and spawns the rest the way
`BP_GameManager.SpawnMonsterEvent` does:

1. `GetSpawnPoint`, the manager's own choice of spawn point.
2. `BeginDeferredActorSpawnFromClass` and `FinishSpawningActor`, with the game's arguments (adjust the spawn if it
   collides, but always spawn). The tag goes on between the two, before the extra begins play.
3. `SetUpBaseMonsterState`, the manager's setup of whatever its `Monster` names: difficulty, damage, the far-away
   sound, combat music and the escape route's nav modifiers. The extra stands in as `Monster` for that one
   synchronous call, then the mission's monster is put straight back, even if the call fails.
4. The extra's `Respawn Data` is cleared (the setup copies a stuck predecessor's state when there was one) and its
   stuck check is turned off (`ShouldCheckIfStuck`).

The manager also ramps its monster's aggression up over the mission (`GameTimeProgression`, once a second); the
spawner gives the extras the same value the same way.

### What the game assumes about its one monster

- **The stuck check respawns the tracked monster.** `BP_BaseMonster."Check If Stuck"` calls
  `BP_GameManager.InitMonster(false, ...)` after 20 seconds without moving, which destroys and replaces the *tracked*
  monster, not the stuck one. An extra entity stuck in a duct would keep replacing the mission's monster, which is why
  the extras skip the check.
- **Any monster's death ends the mission.** `BP_BaseMonster.FinishDeath` (a few seconds after death: the Ghost 4 s,
  the squid 15 s) calls `BPI_GameState_FinishGame` as a kill on kill, capture and extraction contracts. It also calls
  `BPI_GameState_SetMonsterOff`, which stops the monster music on any death.
- **One monster species per map.** Map load places per-species content for `MonsterToSpawn` only (the Zombie Master's
  zombie bodies, the special weapon for its weakness), which is why the extras share the mission's species.

### With Controllable Entity

Controllable Entity hands a player the game manager's tracked monster, so with both mods the entity player plays the
mission's own squid and the extra squids hunt as AI. Its rules act on the entity's own squid only (its grab rule,
for one, checks which squid grabbed), so the extra squids play as the stock game's.

### Tests

`scripts/test-mods.sh` runs, offline, against `tests/fake_ue4ss.lua`:

- `tests/rules_test.lua`: eligibility, the roll, the bounty and the schedule.
- `tests/contracts_test.lua`: the host's roll, the bounty every machine pays, the table rows, and every screen.
- `tests/spawner_test.lua`: the clock, the game's spawn and setup, captures, the Zombie Master, and a hot reload.

They prove the wiring, call shapes and rules. Only a playtest proves the game agrees with the stand-in.

## Open questions

- **Killing an entity ends the mission**, as in the stock game. The alternative is a kill contract that needs every
  entity dead, which means stopping a dead entity's `FinishDeath` (its pending latent call) while others still hunt;
  only destroying the body does that, and the body would vanish within two seconds of death.
- **The Terminator's stray fire** hurts other entities. Stopping it means zeroing monster-on-monster damage in a
  pre-hook on the native `ApplyPointDamage`, whose parameters UE4SS may not expose when Blueprint calls it (see
  [docs/reverse-engineering.md](../../docs/reverse-engineering.md)).
- **Doors, alarms and canisters** only call the mission's own monster; forwarding them to the extras means
  re-implementing `BPI_GameState_ForceSound`'s distance rules.
- **Balance:** whether 30% and 40% are the right chances, and 2.5 and 4 minutes the right delays.
- To confirm live: that `UDataTable:AddRow` takes a cloned row and the text and icon writes show on screen, and that
  growing a screen's Blueprint arrays from Lua works in this UE4SS build.

## Test plan

UE4SS writes the mod's log lines, all starting `[MultiEntity]`, to `Win64/ue4ss/UE4SS.log` on each machine. For a
quick run, set both modifiers' `chance` to `1` in `config.lua` first, so every contract that can carry them does.

1. **Loads.** The log shows `Loaded. Contracts can carry a second and a third entity; the host decides and spawns
   them.`, and in the lobby `Hooked 2 function(s) on /Game/Blueprints/Mission/BP_Mission_FunctionLibrairy...`.
2. **The roll.** The host's log shows `Rolled extra entities onto N of M contracts` and a `Contract N: extra entities
   2, bounty ...` line for each. No capture contract is among them.
3. **The board.** Each such card shows two new icons (the codex chimera) after its other modifiers, and its bounty
   includes 5,000 $ for them. Capture cards show none.
4. **The details.** Open a contract with both: `Second Entity` and `Third Entity` lines, `2 500 $` each, after the
   game's own lines. Selecting each (mouse and controller) shows `Another specimen joins the hunt 2.5 minutes after
   the power comes on.` (4 minutes for the third). The game's own lines still select and describe as before.
5. **The brief and the shuttle.** After accepting the contract, the shuttle's mission start screen and the Tab brief
   list both modifiers with the game's, the brief in its two columns.
6. **The arrival.** In the mission, the host's log has no `The power is on` line until the crew turns the power on;
   then it shows `The power is on; extra entities count from now`. 2.5 minutes later it shows `An extra
   BP_Monster_..._C arrived at ...`, and 4 minutes after the power, a second. Turning the power off and on again
   doesn't delay them.
7. **No hunting each other.** Watch two entities near each other (from a vent, or spectating after a death): neither
   turns to, follows or attacks the other, and each goes on hunting the crew. A Terminator's stray fire can still
   hit one.
8. **Power at start.** On a contract that starts with the power on, the first extra arrives 2.5 minutes after the
   mission's monster appears.
9. **The Zombie Master.** On a Zombie Master mission with the modifier, the extra is `BP_Monster_Michel_C` (Mike).
10. **Stuck.** While an extra stands still for more than 20 seconds (in a duct, waiting), the mission's monster stays
   where it is: it never vanishes and reappears at the monster spawn point.
11. **The payout.** Finish the mission: the score screen shows the two icons after the game's, and the additional
   conditions include the 5,000 $. A player with the mod is paid it into their wallet; a player without it isn't.
12. **Capture.** A capture contract never shows the modifiers, and its mission never gets an extra entity.
13. **Hot reload.** With extras in the mission, press `Ctrl+R` (UE4SS hot reload): the log shows `Picked up a
   mission in progress; extra entities already here: N`, and no extra entity spawns twice.
14. **With Controllable Entity** (both mods installed): the entity player plays the mission's squid; the extra squids
   arrive as AI and hunt the crew.
