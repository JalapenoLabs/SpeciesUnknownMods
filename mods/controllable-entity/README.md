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

## Names

| Game name | Our name |
|-----------|----------|
| `BP_Monster_Poulpi` | the squid |
| `BP_BigRobot` | the Terminator |
| `BP_Monster_Michel` | Mike |

## Still to trace

- How a contract chooses its specimen, so the squid can be forced in.
- The three frenzy triggers: picking up the black box, getting the special weapon, activating the engines.
- Which game sounds are reported as AI noise events.
- How the squid's moves are triggered by its AI (`SpecialAttack`, `GrabHeadPlayer`, `PredictJumpAttack`, the vent
  functions), so the Blueprint layer can drive the same functions from input.
- How the entity player is kept out of the shuttle seat count and the crew list.
