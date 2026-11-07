# Controllable Entity

One player becomes the mission's monster and hunts the crew. Balanced around a kill meter instead of free instant
kills, and around sound instead of wallhacks.

- **Status:** design. Nothing is built yet.
- **Who installs it:** every player (the mod adds networked gameplay and a HUD).
- **Independent of** [Unlimited Lobby Size](../unlimited-lobby-size/README.md); either works without the other.

## Scope

- **One entity to start: the squid** (the game's `BP_Monster_Poulpi`). More monsters come later, each as its own
  kit on the same framework.
- Modes stay the game's own. The entity is a fourth party inside a normal contract, not a new game mode.

## Rules

### Choosing the entity

- In the lobby, a player opts in to be the entity before the shuttle leaves. The choice is private: only that
  player sees it in the UI; the host's game is told over the network.
- The entity is chosen before the mission loads, so the mission spawns the squid as its specimen, with the right
  bodies and corpses loaded.

### Kill meter

- Basic attacks hurt and slow, but never kill outright. A shared cooldown stops spamming.
- The meter fills slowly over time, faster near sounds, and from landing hits. When full, the ultimate (the squid's
  head grab) is a guaranteed kill. It still has to land: the wind-up is visible and weakness weapons can interrupt it.

### Frenzy

When the crew reaches the mission's turning point, kills stop costing meter. Each kill re-arms after a short delay
(start at 6 to 8 seconds and tune in playtests).

| Contract type | Full frenzy starts when | Partial frenzy |
|---------------|------------------------|----------------|
| Extraction | A player picks up the black box into their hands | |
| Kill or capture | | A player gets the special weapon |
| Self destruct | The engines are activated | |

Partial frenzy is still to be defined (for example, a faster meter instead of free kills).

### Losing

If the crew kills or captures the entity, the entity player loses. No respawn.

### No wallhacks, only sound

- The entity never sees players through walls.
- Every noise the game's AI would hear shows through walls as a faint ping at its rough position: gunfire, doors,
  alarms, objectives. It flashes in fast and fades within about 1.5 seconds. Louder noises get bigger, longer pings,
  and the further away a noise is, the fuzzier its position, so distant noises give a direction, not a spot.
- This is fair by construction: the pings come from the same hearing sense the AI monsters use (`AISense_Hearing`
  through `AIPerception`), so the entity knows exactly what the AI would know.

### Vents

- Vent entrances near the entity are highlighted. Entering, leaving and peeking down through a grate use the
  squid's own vent moves (`JumpToVent`, `JumpFromVent`, `LookFromVent`).
- Inside vents, a simple overlay of the vent network keeps the entity from getting lost.

### Controls and HUD

- The entity uses the player's own input actions, so their key bindings carry over:

  | Game action | Squid |
  |-------------|-------|
  | `IA_Move`, `IA_Look`, `IA_Sprint` | Move, look, run |
  | `IA_Shoot` | Basic attack |
  | `IA_ADS` | Leap (aim, then release) |
  | `IA_Interact` | Enter or leave a vent |
  | `IA_Crouch` | Peek down from a vent |
  | `IA_FlashLight` | Second ability (to be designed) |
  | Space (new, the game has no jump) | Ultimate |

- HUD in the style of Overwatch: the ultimate and its meter in the middle, abilities with cooldowns in the bottom
  left.

## Architecture

One design, identical on every machine. Two layers, split by what each tool can do:

- **Blueprint logic mod** (a pak loaded by UE4SS's BPModLoader; authored in the UE 5.7 editor). Owns everything
  that must exist on every machine or cross the network: a replicated component on each player controller, input
  bindings to the game's input actions, server calls that turn input into squid moves on the host, the replicated
  meter and frenzy state, the HUD widgets, and the sound pings.
- **Lua adapter** (UE4SS). A thin layer for the game's own Blueprints, which a Blueprint mod can call but not hook:
  keeping the entity out of the shuttle's "everyone seated" launch count, catching the frenzy triggers, and forcing
  the mission's specimen to the squid.

Taking control of the monster is plain possession. Monsters are `ACharacter`s (`BP_BaseMonster` with a
`CharacterMovementComponent`), so movement replicates without extra work once the entity player's controller
possesses the squid and its AI controller is set aside.

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

## Still to trace

- The three frenzy triggers: picking up the black box, getting the special weapon, activating the engines.
- Which game sounds are reported as AI noise events.
- How the entity player is kept out of the shuttle seat count and the crew list.
