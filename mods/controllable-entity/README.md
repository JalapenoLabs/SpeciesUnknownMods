# Controllable Entity

One player becomes the mission's monster and hunts the crew. Balanced around a kill meter instead of free instant
kills, and around sound instead of wallhacks.

- **Status:** first version built and tested offline, awaiting its first playtest (see [Test plan](#test-plan)).
- **Payload:** the Lua mod [`ControllableEntity/`](ControllableEntity/) plus the pak `ControllableEntity_P`, built by
  `scripts/package-mods.sh`.
- **Who installs it:** every player (the mod adds networked gameplay and a HUD).
- **Independent of** [Unlimited Lobby Size](../unlimited-lobby-size/README.md); either works without the other.

## Scope

- **One entity to start: the squid** (the game's `BP_Monster_Poulpi`). More monsters come later, each as its own
  kit on the same framework.
- Modes stay the game's own. The entity is a fourth party inside a normal contract, not a new game mode.

## Rules

### Choosing the entity

- In the lobby, a player presses F8 to be the entity next mission (F8 again backs out). The choice is private:
  only that player sees it; the host is told over the network. There is one entity per mission.
- The entity is chosen before the mission loads, so the mission spawns the squid as its specimen, with the right
  bodies and corpses loaded.

### Kill meter

- The lash (basic attack) hurts but never kills. Every move has its own cooldown (`config.lua`).
- The meter fills over 90 seconds, twice as fast while a noise was heard within 15 m in the last 3 seconds. When
  full, the ultimate arms the kill for 3 seconds and leaps (or drops from a vent): the grab that follows kills and
  empties the meter. It still has to land, and shooting the squid breaks the grab as in the base game.
- Any other grab is broken off (see [The grab rule](#the-grab-rule)).
- On the roadmap: filling the meter from landed lashes.

### Frenzy

When the crew reaches the mission's turning point, kills stop costing meter: in full frenzy every grab kills, and
each kill re-arms after 7 seconds.

| Contract type | Full frenzy starts when | Partial frenzy |
|---------------|------------------------|----------------|
| Extraction | A player picks up the black box into their hands | |
| Kill or capture | | A player gets the special weapon |
| Self destruct | The engines are activated | |

Partial frenzy fills the meter 2.5 times faster but grants no free kills.

How the mod detects each trigger, on the host. None of the game's functions fire exactly once (re-grabs and every
engine state change call them again); frenzy only ever escalates, so repeats change nothing.

| Trigger | Post-hook | Condition |
|---------|-----------|-----------|
| Black box picked up | `/Game/Blueprints/Core/BP_MyGameState.BP_MyGameState_C:BPI_GameState_SetGrabBlackBox` | Host only (it also runs on clients through `OnRep_IsGrabbed`) |
| Special weapon obtained | `/Game/Weapon/Weapon_Base.Weapon_Base_C:BPI_Weapon_SetGrabbed` | The weapon's `IsObjectiveWeapon` and `IsGrabbed` are true, and the contract is kill or capture |
| Engines activated | `/Game/Blueprints/Engine/BP_Engine.BP_Engine_C:OnRep_EngineState` | Any engine's `EngineState >= 1` (0 ready, 1 starting, 2 turning, 3 critical) on a destruction contract |

- The contract type is `BP_MyGameState.Contract.ContractType_2_...` (replicated, valid once `ContractInit` is
  true): 0 elimination (kill), 1 destruction (self destruct), 2 capture, 3 extraction. The map is
  `Contract.Map_33_...`: 0 Hawking, 1 Polar.
- A weapon is the special weapon when its damage type matches the weakness of `GameManager.MonsterToSpawn`
  (`Weapon_Base.DetermineWeaponObjective`, about 5 seconds after it spawns at level load).
- When both engines go critical, `BPI_GameState_LaunchEmergency` arms the self destruct and sets
  `LightStatut = 2`. `OnRep_LightStatut` with `LightStatut == 2` is a map-independent fallback trigger.

### Losing

If the crew kills the entity, the entity player loses: no respawn, and their camera follows a crew member for the
rest of the mission. Losing to capture is still to be confirmed (see [Open questions](#open-questions)).

### No wallhacks, only sound

- The entity never sees players through walls.
- Every noise the game's AI would hear shows through walls as a ping at its rough position: gunfire, footsteps,
  doors, the airlock alarm, explosions. It fades over 1.5 seconds. The further away a noise is, the further its
  ping lands from the true spot (12% of the distance, up to 6 m), so distant noises give a direction, not a spot.
- This is fair by construction: the pings come from the same noises, under the same range rules, that the AI
  monsters' hearing uses (see [How the game makes noise](#how-the-game-makes-noise)).
- On the roadmap: bigger, longer pings for louder noises.

### Vents

- Interact climbs into the nearest vent entrance within 3 m, or drops out of the nearest exit within 4 m onto any
  crew member below. Crouch peeks down through the grate. All three use the squid's own vent moves (`JumpToVent`,
  `AttackFromVent`, `LookFromVent`).
- On the roadmap: highlighting nearby vent entrances, and an overlay of the duct network while inside.

### Controls and HUD

The entity uses the player's own input actions, so their key bindings carry over. The game has no jump and no free
key the mod could reuse, so the mod's two keys are its own.

| Input | As the entity |
|-------|---------------|
| Move, Look (`IA_Move`, `IA_Look`) | Move and look |
| Shoot (`IA_Shoot`) | Lash: a basic attack on the nearest crew member ahead, never lethal |
| Aim (`IA_ADS`) | Leap where you look; a grab on landing is broken off unless the kill is ready |
| Interact (`IA_Interact`) | Climb into the nearest vent, or drop out of it onto whoever is below |
| Crouch (`IA_Crouch`) | Peek down through the grate while in a vent |
| Space (mod key) | Ultimate: with a full meter, leap (or drop) and the grab kills |
| F8 (mod key, in the lobby) | Volunteer to be the entity next mission, or back out |

The HUD puts the kill meter bottom centre (`HEAD GRAB  73%`, then `HEAD GRAB READY [SPACE]`), abilities with their
cooldowns bottom left, a `FRENZY` banner top centre, short messages mid-screen, and noise pings as coloured
markers over the world: red gunshots, blue footsteps, amber alarms, doors and explosions.

There's no sprint yet: the crew's sprint is bound on the crew character, not the controller, so it never reaches
the squid. The squid moves at the game's combat speed.

## Install

Every player installs both halves:

1. UE4SS, as for any mod ([docs/ue4ss.md](../../docs/ue4ss.md#installing-ue4ss)).
2. The pak: `scripts/package-mods.sh --install` builds it and copies `ControllableEntity_P.{pak,utoc,ucas}` into
   `SpeciesUnknown/Content/Paks/~mods/`. Players without the repository copy those three files there.
3. The Lua: copy `ControllableEntity/` into `Win64/ue4ss/Mods/` (or `scripts/link-mod.sh controllable-entity`).

## Architecture

One design, identical on every machine. Lua owns the gameplay; a small Blueprint pak supplies only what Lua cannot
create: network events and a widget layout.

- **Lua (UE4SS)**, in `ControllableEntity/Scripts/entity/`, one module per job:

  | Module | Runs on | Does |
  |--------|---------|------|
  | `links.lua` | both | Spawns a `BP_EntityLink` per player (host) and routes its events to the modules below |
  | `takeover.lua` | host | Volunteering, forcing the squid, possessing it, crew exclusion, loss |
  | `abilities.lua` | host | Commands to squid moves, cooldowns, the grab rule, the meter's tick |
  | `meter.lua` | host | The kill meter and frenzy rules, as plain logic (unit tested) |
  | `frenzy.lua` | host | The three frenzy triggers |
  | `senses.lua` | host | Noise sources to blurred pings |
  | `control.lua` | entity player | Input to movement and commands; the mod's keys |
  | `hud.lua` | entity player | The HUD |
  | `game.lua`, `config.lua` | both | Game paths and helpers; every tunable |

- **Blueprint pak** (`ControllableEntity_P`, in `Content/Paks/~mods/`), generated from code by the asset builder
  in `unreal/SpeciesUnknown/Source/SpeciesUnknownModKit` (see [docs/pak-mods.md](../../docs/pak-mods.md)):
  - `BP_EntityLink`: a replicated actor the host spawns for every player, owned by their controller and relevant to
    them alone. Its events, `EntityServerCommand` (player to host), `EntityClientPing` and `EntityClientEvent`
    (host to player), have no logic of their own: UE4SS's `RegisterCustomEvent` runs Lua when each one executes,
    on the machine it executes on. Its replicated `Meter` and `Frenzy` feed the HUD.
  - `WBP_EntityHUD`: the HUD's layout. Lua fills in every value.
- **Runtime Blueprint only, by necessity.** Unreal projects normally put systems in C++, but a pak mod cannot ship
  C++: the game's executable does not contain our modules. Any C++ stays in editor-only tooling.
- **Built with UE 5.7.4** (changelist 51494982, the game's exact engine build), so cooked assets match the game.

### Input

The game binds all gameplay input on its player controller (`BP_MyPlayerController.InpActEvt_IA_*`), and each
handler forwards to the possessed pawn's `BPI_PlayerInput_*` interface. The squid doesn't implement it, so while
the player drives the squid the handlers do nothing, and Lua post-hooks on them take over:

- **Move and look** apply on the player's own machine, mirroring the crew character's own handlers: movement along
  the camera's yaw (`AddMovementInput`), look through `AddControllerYawInput` / `AddControllerPitchInput`. The
  squid is a possessed `ACharacter`, so movement replicates like any player's.
- **Buttons** become `EntityServerCommand` calls carrying the camera's aim.
- **Reading the values:** `FInputActionValue` has no reflected fields, so Lua passes it straight to the engine's
  own converters (`Conv_InputActionValueToAxis2D`, `...ToBool`). UE4SS copies a struct of the right type into a
  call whole (`CopyCompleteValue`), which is what makes that work.
- **Generated names:** handler names carry node numbers (`..._K2Node_EnhancedInputActionEvent_27`) that a game
  patch can change, so the hooks find them by pattern when the controller class loads.

### Flow of one action

1. The entity player presses Shoot. `InpActEvt_IA_Shoot_*` runs on their machine; the Lua post-hook sees it.
2. Lua calls `BP_EntityLink.EntityServerCommand("Attack", aim, nil)`, a server event, so it runs on the host.
3. On the host, `RegisterCustomEvent("EntityServerCommand")` runs Lua, which checks the sender is the entity and
   the move is off cooldown, then calls the squid's own function (`BPI_BasicMonster_SetSimpleAttack`).
4. The host answers with `EntityClientEvent("Cooldown.Attack", 1.2)`, which the HUD shows.

### The grab rule

Every grab starts in the squid's `GrabHeadPlayer`, whether from a leap or a vent drop, and the game's decapitation
later kills only while the squid's `IsGrabPlayer` is still set. When a grab starts and the meter says it may not
kill, the host plays the squid's own "hit while grabbing" knockback (`KnockBack (Clients)` with
`Poulpi_Hit_DuringGrab_Front_Montage`) a frame later. That releases the player on every machine and clears
`IsGrabPlayer`, the same way the game breaks a grab when the crew shoots the squid.

### Tests

`scripts/test-mods.sh` runs, offline:

- `tests/meter_test.lua`: the meter and frenzy rules.
- `tests/host_flow_test.lua` and `tests/client_flow_test.lua`: the real scripts through a whole round, as the host
  and as the entity player's machine, against `tests/fake_ue4ss.lua`, a stand-in for UE4SS and the game objects.

They prove the wiring, call shapes and rules. Only a playtest proves the game agrees with the stand-in.

## How the squid's moves work

Read from `BP_Monster_Poulpi`, `BP_BaseMonster`, `BP_ParentMonster`, the AI's behavior-tree tasks and the montages'
anim notifies. Every move can be started on the host without the behavior tree, and nothing in the squid stops a
player controller from possessing it. Every trigger must run on the host: the moves end in multicast events, and
damage, sphere checks and the kill only run where `IsServer` is true.

| Move | How the AI starts it | How the mod starts it (on the host) |
|------|----------------------|-------------------------------------|
| Basic attack | `BTService_CheckBasicAttack` -> `BPI_BasicMonster_SetSimpleAttack(target, location, distance)` | Same call, with the aimed actor |
| Leap | `BPI_Monster_CanSpecialAttack` (checks angle, 300 to 500 units, a clear `PredictJumpAttack` arc, then writes `LastSpecialAttackPlayerLocation`) -> `BPI_Monster_SetSpecialAttack(target)` | Write `LastSpecialAttackPlayerLocation` from the aim point (validated with `PredictJumpAttack`), then `SetSpecialAttack` |
| Head grab | The leap's forward sphere check hits a grabbable player -> `GrabHeadAnim (Multi)` + `Timeline_GrabHead_Start` | Comes from the leap, or from a vent drop |
| Enter vent | A navmesh smart link calls `MonsterUseVent` -> `BPI_Monster_JumpToVent(vent, true)` | Find the nearest `BP_Vent_Up` and call `JumpToVent` (smart links only fire for AI path following) |
| Leave vent / drop attack | `BTService_CheckPlayerDownVent` -> `BPI_Monster_AttackFromVent(vent, player)` | Same call; `player` may be none |
| Peek down | `BTTask_LookFromVent` -> `BPI_Monster_LookFromVent(vent, on, noise)` | Same call |
| Speed | `BTTask_SetSpeedType` -> `GetSpeedByType(type)` -> `BPI_Monster_SetSpeed` (0 walk, 1 combat, 2 combat loose, 3 escape, 4 max, 5 escape from capture; `IsAngry` forces max) | Same calls |

- **The head grab kills outright.** `AnimNotify_Decapitation` in the grab montages calls `Decapitation`, which
  calls the player's `BPI_Human_CustomDeath`. A shield turns it into 150 damage and a failed attack instead.
- **The grab can be interrupted.** Enough damage to the squid triggers `KnockBack`, which calls `StopGrabPlayer`.
- **The leap itself does no damage.** It only grabs on contact; a shield takes 25 damage and fails the leap.
- **Vents are navmesh.** Entering switches the squid to flying for the jump and makes it invulnerable while it plays.
  Inside, `SetInVent` crouches it automatically, and it walks crouched along the ducts. There are no splines.
- **For the kill meter:** the meter has to gate the head grab, because the head grab is the only instant kill. So
  without meter, the leap and the vent drop must not grab: the mod can end the attack (clear `IsAttacking`) before
  the sphere check grabs, or let the grab start and release it with `StopGrabPlayer` before the decapitation notify.
  To be decided when building.

Possession notes:

- `CanMove` gates movement on `IsAttacking`, `IsLookingDownVent` and similar flags; the input handler should
  respect it.
- The AI's own timers (`CheckTarget`, `Check If Stuck`) only start when the controller is a
  `BP_Basic_AI_Controller`, so possessing at spawn skips them. Taking over a live squid needs them cleared.
- `BP_ParentMonster` can teleport a monster back onto the navmesh when it walks off it
  (`OutOfNavCheckEvent` -> `TeleportToNavigationPoint`). What triggers it is untraced.
- Motion warping targets are set only on the host, so the leap and vent jumps may rubber-band on the squid
  player's screen. Playtest.

## How the game makes noise

Monsters have no sight sense; they hunt by hearing, through two channels:

| Channel | Sources | How it reaches the monster |
|---------|---------|----------------------------|
| Native `ReportNoiseEvent`, heard by the `AIPerception` component on the AI controller | Every gun (`Weapon_Base.MakeNoiseAI`, tag `Shoot`, per-weapon `HearingLoudness` and `HearingRange`); crew footsteps (`BP_ParentCharacter.BPI_Footsteps_PlaySound`, range `Volume^1.3 x 1100`, doubled in water, roughly 566 units at a full sprint, only when the character's `FootstepsNoise` is on); zombie footsteps | `BP_Basic_AI_Controller` forwards hearing stimuli to `BPI_Monster_HearSoundFromPerception(actor, location)` |
| `BP_MyGameState.BPI_GameState_ForceSound(actor, location, maxDistance, minDistance, fromActors)` | Big door cycles (difficulty 2 to 4), the decontamination airlock alarm (`BP_Sas_Controller`, up to 8000 units), explosive canisters | Calls `BPI_Monster_HearSoundFromPerception` on the monster directly, after its own distance rules |

- The perception listener lives on the AI controller, so once a player possesses the squid, channel 1 delivers
  nothing. The mod therefore watches the sources itself, on the host: post-hooks on `Weapon_Base_C:MakeNoiseAI`
  (no parameters; read `PawnOwner`, `HearingLoudness`, `HearingRange` from the weapon),
  `BP_ParentCharacter_C:BPI_Footsteps_PlaySound` and `BP_MyGameState_C:BPI_GameState_ForceSound`. It applies the
  same range rules the AI would (the AI controller's hearing range reads as 4000 units, to be confirmed live) and
  sends each surviving noise to the squid player as a ping.
- None of these hooks read a native function's parameters, so they don't depend on how UE4SS exposes them.
- Possible gap: on a listen server, the host's own gunshots may never call `MakeNoiseAI` (the call path runs only for
  shooters who aren't locally controlled). Test in play.

## Keeping the entity player out of the crew

`BP_MyGameState."In Game Player State "` is the crew list (note the trailing space in the name). The shuttle's launch
and seat checks, the score screen and the crew-count scaling (monster difficulty, spawners, labs) all read it.

- Its only writer is `BP_MyGameState.UpdateInGamePlayers(playerState, add)`. It updates `InGamePlayersNumber`,
  replicates through push-model replication and an OnRep, and **calls `GameOver` when the last entry is removed**.
- A player is added when their crew character is possessed (`BP_Character.ReceivePossessed` ->
  `SetInGamePlayerState(true)`), and removed on game-over death, player-state destruction or logout. Dead players
  who can still respawn stay in the list.

The mod's approach, on the host:

1. Post-hook `UpdateInGamePlayers`. When the entity player is added, call `UpdateInGamePlayers(entity, false)`
   through the game's own function (a raw array write may not replicate), but only once someone else is in the list,
   so it never triggers `GameOver`.
2. Also call `SetPlayers(theirCharacter, false)`, which drops them from the spectate list.
3. The score screen's end data marks anyone missing from the list as dead, so the entity shows as a dead crew member
   unless the mod also adjusts `SetUpEndData`. To be decided.

Faking a death instead is worse: it runs the whole death flow (notifications, item drop, a possible zombie, a
respawn that re-adds them).

The entity player's crew body is parked at the takeover (hidden, no collision, movement disabled) and destroyed
only once another crew body exists. Destroying a body takes it off `BP_MyGameState.ActualPlayersPawn`, and when
that list empties the game travels everyone back to the lobby. Alone in a mission the body simply stays parked.

## How the mission's monster is chosen

`BP_GameManager` (placed in each mission map, runs on the host) decides the specimen when the mission starts:

1. If `BP_MyGameInstance.spawnForceSessionMonster` is set (not 0 or 1), it spawns that monster.
2. Otherwise it picks one at random (`Get Random`).

The game instance survives map travel, so setting `spawnForceSessionMonster` on the host while still in the lobby
makes the next mission spawn the squid, through the game's own spawn path (`GetMonsterSoftClass` ->
`SpawnMonsterEvent`). Nothing in the game sets the variable itself; it reads like a leftover debug override.

`MonsterList` values (from `BP_Lobby_FunctionLibrairy.GetMonsterSoftClass`):

| Value | Monster |
|-------|---------|
| 0, 1 | None (0 also means "pick at random") |
| 2 | `BP_Monster_Poulpi` (the squid) |
| 3 | `BP_Monster_Michel` (Mike) |
| 4 | `BP_Monster_Eye` |
| 5 | `BP_Monster_Ghost` |
| 6 | `BP_Monster_ZombieMaster` |
| 7 | `BP_BigRobot` (the Terminator) |

## Names

| Game name | Our name |
|-----------|----------|
| `BP_Monster_Poulpi` | the squid |
| `BP_BigRobot` | the Terminator |
| `BP_Monster_Michel` | Mike |

## Open questions

- Partial frenzy (kill and capture contracts): it currently fills the meter faster; is that enough?
- Whether the score screen should show the entity player as something other than a dead crew member.
- Destruction contracts on the Polar map: no engine path was found there; `LightStatut == 2` is the fallback trigger.
- Capture: losing on death is handled; whether a captured squid also counts as a loss is untested.
- To confirm live with UE4SS: the AI hearing range (4000), weapon `HearingLoudness`/`HearingRange`, the special
  guns' `IsUnique` flag, and whether the host's own gunshots make noise.

## Test plan

UE4SS writes the mod's log lines, all starting `[ControllableEntity]`, to `Win64/ue4ss/UE4SS.log` on each machine.

**Testing alone** works for steps 1 to 5 (volunteering, the takeover, moving, the moves and the HUD). There's nobody
to lash, grab or hear, and the shuttle can't launch: as the only player you stay on the crew list (emptying it ends
the mission), and the squid can't sit. Leave through the pause menu. Steps 6 to 10 need at least one friend.

1. **Loads.** Every player launches with UE4SS, the pak and the Lua installed. The log shows
   `Loaded. F8 in the lobby volunteers to be the entity.` and, once in the lobby, `Hooked ... BP_MyPlayerController`.
2. **Volunteering is private.** In the lobby, one player presses F8. Only they see "You'll be the entity next
   mission". Pressing F8 again backs out; a second player pressing F8 while someone is signed up sees "Someone else
   already claimed the entity".
3. **The squid is forced and taken.** Start a contract. The mission's specimen is the squid, the volunteer sees
   "You are the entity" and controls it, and the host's log shows `took control of the squid` then
   `Kept the entity out of the crew`. The volunteer's crew body is gone.
4. **Moving.** Walk, look, and check the crew see the squid move smoothly. Note any rubber-banding.
5. **Lash, leap, vents.** Shoot next to a crew member: a lash with a cooldown on the HUD. Aim: a leap where you
   look; a grab on landing breaks off with "Your hunger isn't ready". Interact by a vent: climb in; Crouch peeks;
   Interact again drops out.
6. **The kill.** Wait for the meter to fill (90 s, faster near noise), press Space facing a crew member: the leap's
   grab kills. The meter empties.
7. **Senses.** Have the crew shoot, walk and trigger doors and alarms out of sight. The entity sees fading markers
   through walls, never the players themselves.
8. **Frenzy.** On an extraction contract, pick up the black box: `FRENZY` appears and grabs kill without meter, each
   re-arming after 7 s.
9. **Launching.** The crew board the shuttle and launch without the entity; with the squid aboard, it doesn't launch.
10. **Losing.** Kill the squid: the entity player sees "The crew got you" and watches a crew member.
