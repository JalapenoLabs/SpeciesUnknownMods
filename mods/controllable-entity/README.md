# Controllable Entity

One player becomes the mission's monster and hunts the crew. Balanced around a kill meter instead of free instant
kills, and around sound instead of wallhacks.

- **Status:** playtested alone eight times (volunteering, the takeover, moving, the HUD, the lair, vents, the shuttle
  rules and the cries work); co-op is next (see [Test plan](#test-plan)).
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

- **Entity mode** is on by default. The host's F9 turns it on or off for the session, and only the host sees the
  "Entity mode: ON/OFF" message. Anyone else's F9 shows them that the host decides. Turning it off releases the
  volunteer; an entity already playing finishes their mission.
- **Volunteering:** in the lobby, a player presses F8 to be the entity next mission (F8 again backs out). The choice
  is private: only that player sees it; the host is told over the network. There is one entity per mission.
- **Random pick:** in co-op with no volunteer, a random player becomes the entity when the squid appears. The pick
  lasts one mission. Playing alone there is no random pick, only a volunteer.
- While entity mode is on, every co-op mission's specimen is the squid, and so is a solo mission with a volunteer.
  The squid is forced from the lobby, before the mission loads, so the mission spawns it with the right bodies and
  corpses loaded. The mission rolls its monster seconds after it loads, before every player has arrived, which is
  why the random pick can't wait until then to decide.

### The start: the lair and the power

- At the takeover the squid goes straight into the ducts: the vent nearest where the game spawned it that is at
  least 25 m from every crew member (the farthest from them when none is). The game manager picks each mission's
  monster spawn (`BP_GameManager.GetSpawnPoint`: the map's `MonsterSpawnPoint`, or one of its `PowerOnSpawnPoint`s
  when the power is on at the start; the Terminator, which can't vent, has its own `NoVentSpawnPoint`s), so the
  entity starts where the AI would.
- Missions start with the ship's power off, and the crew is safe until they turn it on: the game's own grace
  period. Until then the whole duct network is the squid's lair. Moving, looking, the lash, peeking, the cries and
  climbing inside the ducts stay free, but leaving the ducts (the vent drop, the leap, the ultimate) waits for the
  power. Leaving them another way (out of a crawl opening) puts the squid back where it last stood inside.
- Playing alone, nobody else can turn the power on, so F8 as the entity turns it on (as the power screen does), for
  testing what comes after the lair.
- Once the power is on, the squid is free for good, even if the crew turns the power off again. Contracts that
  start with the power on leave it free from the start.
- How the game represents the power and the vents:
  [docs/game-internals.md](../../docs/game-internals.md#gameplay-state-worth-knowing).

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

### The hunt: the vents stop hiding the squid

The AI never hides in the vents for good, but a player could. So in kill and capture contracts, once a crew member
holds the special weapon (the same trigger as partial frenzy), the vents are only a short refuge:

- The squid has 20 seconds in the vents at a time. The time drains while it's inside them and refills a second for
  every six outside. The entity sees it at the top centre of the screen, only while it isn't full.
- When the time runs out, the squid is forced out through the nearest shaft: straight down when one is in reach,
  otherwise taken beside the nearest one on its floor first. The vents then stay shut to it until half the time is
  back ("The vents won't take you yet").
- The lair lets the squid go when the hunt starts, even with the power still off.
- A squid still in the vents 10 seconds after being forced out (a spot the drop can't reach) is moved to the floor in
  front of the screen that restores the power (`BP_Screen_RestorePower`, one per map, found on the navigation).
- The hunted squid is loud: every 12 seconds it cries out, so the crew can follow it. The AI's cries come from its
  behaviour tree, which a player's squid doesn't run, so the host plays them: the squid's own chase cry
  (`BPI_Monster_PlayVoiceType`, replicated, heard near it) and its far call (`PlayVoiceFar(Multi)`, heard only well
  away from it).

### The shuttle and the forbidden areas

The AI keeps out of the game's forbidden areas and never guards the crew's shuttle; a player would do both. So:

- **The shuttle is the crew's.** The entity can't board it, except in capture contracts (below). Aboard is the
  shuttle's own bay box, the one its launch check uses (`BP_PlayerShip.TriggerBoxOverlap`, or on Polar the volume
  outside it, `ExtTriggerBase`). The host puts a squid that strays aboard back where it last stood outside ("Hunt
  them away from their shuttle").
- **Its approach is calm.** Within 15 m of the bay, which takes in Hawking's corridor from the airlock, the entity
  can't sprint, can't use its ultimate, and its grabs never kill (frenzy included); the lash still works. Its HUD
  says so while it's there.
- **Forbidden areas are the game's own:** where its AI may not path (`NavArea_Forbidden`): the genetics lab's wing on
  Hawking, the underground electrical area on Polar. The host asks the navigation whether the squid stands on
  forbidden floor (a point projects through the game's `QuerryFilter_CheckForbidden` only outside them), so every
  map's areas count without a list of them, and puts the squid back where it last stood outside.
- **The entity sees the edges:** glowing posts, only on its machine, red where it may not go and amber around the
  shuttle's approach. The forbidden areas' posts come from the trigger boxes carrying the forbidden area, which load
  with their section of the ship, so they appear as the squid gets near.

### Capture contracts: kill it off the shuttle

A capture contract wants the specimen alive in the shuttle's capture cell, and killing it fails the contract. A human
entity could keep away from the shuttle for good, so with an entity:

- Killed anywhere off the shuttle, the entity counts as captured, and the crew completes the contract.
- Killed aboard the shuttle (the shuttle's own aboard check, `BP_PlayerShip.MonsterInside`), the contract fails as the
  game has it. So the entity wants to come aboard, where the crew may only capture it.
- The mod finishes the mission the way a real capture does (the monster's `BPI_BasicMonster_SetIsCaptured`, then
  `BPI_GameState_FinishGame(1)`) as the squid dies, before the game's own kill result about 15 seconds later, which
  the game then ignores. Still to check in play: the lobby's specimen display after such a capture.

### Voice: the entity has no comms

- Nobody hears the entity player at all, nearby or over the radio, and their radio key does nothing (not even its
  click). Their own machine never turns their mic on, and the host mutes them on both of the game's voice channels.
- Once the entity has lost, its player can talk to everyone again, over the radio too: the crew finally hear the
  thing they hunted speak.
- The entity hears the crew only as someone standing near them would. The host takes the entity off the radio
  channel, and every crew machine sends radio speech on the proximity channel too: the crew still hear each other
  over the radio, and the entity hears a crew member on the radio only up close, without the radio's static.
- The game's voice is the Onset VoIP plugin, compiled into the game: channel 0 is proximity (3D, from the speaker's
  pawn), channel 1 is radio (2D, with the static), and a listener hears a speaker only through a channel both are
  in, the radio winning when both are (see
  [docs/game-internals.md](../../docs/game-internals.md#gameplay-state-worth-knowing)).

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
- Louder kinds draw bigger (gunshots more than twice the size of a footstep). A noise behind the camera or off the
  screen sits on a ring around the screen's centre instead, in its direction, like a hit indicator: straight ahead is
  the top of the ring, behind is the bottom.
- On the roadmap: longer pings for louder noises.

### Vents

- Space climbs into the vent shaft within 4 m across the floor, or drops out of the one within 4 m onto any crew
  member below. Inside the ducts, at the foot of a step up (where a duct rises 2.5 m, like an elbow joint), Space
  climbs it instead when the step is nearer than an opening. Crouch peeks down through the grate; Crouch again,
  crawling away from the grate, the leap or a climb ends the peek. All four use the
  squid's own vent moves (`JumpToVent`, `AttackFromVent`, `ClimbVent250`, `LookFromVent`). Climbing stays inside the
  ducts, so the lair allows it before the power is on.
- **Crawl openings:** the floor-level openings the crew crouch through into the ducts (six on Hawking, two in crew
  quarters and four in the lab) take the squid too: as it moves into one, the host puts it in its crouched vent
  state, and coming back out the game's own trigger stands it up. Only the squid crawls; an entity that doesn't use
  the vents wouldn't.
- **Seeing in the vents:** the ducts are unlit, and much of the network is invisible collision rather than modelled
  walls. So the entity carries a soft light (full in the ducts, faint in the rooms, which the game keeps dark on
  purpose), and glowing light-blue discs
  mark the vent openings within 35 m: over the holes in the duct floor while inside, on the floor under each vent
  while in a room. Only the entity player's
  machine creates them, so nobody else sees either. They use the engine's own cylinder and the game's own unlit
  material (the in-game map's), because a mod can't ship new material shaders for the game's renderer.
- **Map sections:** the game shows each part of the ship only while the local player stands in its streaming
  volumes, and the squid's collision never triggers them. The entity's machine tells each volume when the squid is
  inside it, through the game's own `BPI_Streaming_AddActorToTrigger`, so walls and floors appear around the squid
  as they do around crew ([docs/game-internals.md](../../docs/game-internals.md#gameplay-state-worth-knowing)).
- **The minimap's deck:** where decks overlap, the map draws the one the local player stands on, picked from map
  triggers the same way, and the entity's machine walks the squid through those too (`BeginOverlap` and
  `EndOverlap` on `BP_MapManagerExtended`). When the player takes the squid, it first leaves the triggers their crew
  body stood in, which the game would otherwise go on counting.
- On the roadmap: seeing down into the room below while in the vents (the crew and the openings under the squid), from
  playtest 5. Then a glowing path along the ducts to the nearest opening (needs the host's navigation data sent to
  the entity), and an overlay of the duct network while inside.

### Controls and HUD

The entity uses the player's own input actions, so their key bindings carry over. What the game has no action for
gets a mod key of its own.

| Input | As the entity |
|-------|---------------|
| Move, Look (`IA_Move`, `IA_Look`) | Move and look |
| Shoot (`IA_Shoot`) | Lash: a basic attack on the nearest crew member ahead, never lethal; with nobody in reach the squid swings at the air |
| Aim (`IA_ADS`) | Leap where you look; a grab on landing is broken off unless the kill is ready |
| Interact (`IA_Interact`, E) | Ultimate: with a full meter, leap (or drop) and the grab kills |
| Crouch (`IA_Crouch`) | Peek down through the grate while in a vent |
| Objectives (`IA_ViewPseudo`, Tab, held) | Show the entity's objectives, in the crew's own overlay |
| Flashlight (`IA_FlashLight`) | Switch between third person (the start) and first person; in first person the squid's own mesh is hidden from its player |
| Hold Tool (`IA_HoldTool`, Space) | Climb into the nearest vent, drop out of it onto whoever is below, or climb a step up inside the ducts |
| Weapon slots 1, 2, 3 (`IA_Slot1`–`IA_Slot3`) | Cry out, for everyone near to hear: a roar, a curious call, a long call |
| F8 (mod key, in the lobby) | Volunteer to be the entity next mission, or back out. As the entity, playing alone: turn the power on |
| F9 (mod key, host only) | Turn entity mode on or off |
| Left Shift (mod key, held) | Sprint, on stamina |
| `.` and `,` (mod keys) | Zoom the minimap in and out |
| H (mod key) | Hide the key hints under the minimap, or show them again |

The view starts in third person, behind the squid along the player's look, passing through walls (many duct walls
are invisible collision, which would otherwise pull the camera into the squid's head).
First person is the squid's eye view. The game's own camera stays in its cached crew body's head, and the entity's
body is parked, not destroyed (see [docs/game-internals.md](../../docs/game-internals.md#gameplay-state-worth-knowing)),
so on the entity's machine the mod hands the game's camera the squid through its own `BPI_CameraPlayer_ResetPlayer`,
and gives the squid a spring arm with a camera on it. Third person is the arm at 3.2 m, first person at zero. In
third person the player can look at most 50° down: the arm swings the camera up as they look down, and nearly
straight down took it through the ship's outer hull, blacking out the screen. First person keeps the game's own
limit.

The HUD is laid out like the crew's own, so the top of the screen holds only the minimap:

- **Actions, bottom left, stacked:** the lash (left mouse button), the leap (right), the ultimate (a skull and E)
  and venting (Space). Each row is the key, the icon, and a bar on the right while it charges, in the crew HUD's
  flashlight-bar colour, and nothing once it's ready; the bar's space stays reserved, so the stack never shifts. The
  ultimate's bar is the kill meter (amber), or in full frenzy the re-arm between kills (red). A move the lair holds
  back (leaving the ducts before the power is on) dims.
- **Keys are the game's own glyphs** (its `/Game/KeyIcons` textures, as in its "press E" prompts), each as large as
  fits its slot without stretching: the space bar's glyph is wide, the mouse's tall.
- **Health and stamina, under the actions:** the health bar shows the pool the squid is on. Standing, that is its
  stagger pool, in the crew HUD's green: hits drain it, and at zero the squid is knocked down. Down, it is the squid's
  real health, in red, which only the crew's fire drains while the squid is down and burning. The stamina bar shows
  only once sprinting has used some, as the crew's does.
- **Bottom centre:** the `FRENZY` banner, then the host's messages. A message stays a second plus 300 ms a word, at
  least three seconds; the volunteer's status and the lair's "wait for the power" hint stay until they change.
- **Bottom right:** `Human respawns remaining: N`, the crew's shared respawns (`BP_MyGameState.Respawn`), live. The
  entity wins when the crew is all dead with none left.
- **Noise pings** as coloured markers over the world: red gunshots, blue footsteps, amber alarms, doors and
  explosions.
- **The minimap, top right:** the game's own minimap (the screen of the crew's minimap tool, `UMG_MiniMap`), always
  centred on the squid with north up, the player icon turning with the squid, and a view cone turning with the look.
  The widget is laid out as a 1024-unit square (its Tick has the number written in), so it stays that size, clipped
  to it, scaled down to a 300-unit square pinned at its top-right corner. The map draws world +Y up and +X to the
  left. The widget turns its map with whatever it follows, so it follows an invisible actor that rides with the squid
  but never turns. Its item icons (the special weapons, the black box) are hidden: they stay on the map while a crew
  member carries them, which would show the entity where that player is.
- **Objectives, while Tab is held:** the crew's own objectives overlay (`UMG_ObjectiveList`), headed "THE ENTITY"
  instead of the contract, with the entity's objectives: kill all humans, leave them no respawns (with how many the
  crew have left, `BP_MyGameState.Respawn`), and stay alive. The entity wins exactly when the crew is all dead with no
  respawns left, which is when the game itself ends the mission. Nothing on it hints at the crew's contract, and the
  crew's name tags, which their Tab also shows, stay hidden.
- **Key hints, under the minimap, small:** `C Peek`, only while peeking would work (in a vent, over a grate, with
  peek recharged), and `F camera`. H hides them, and brings them back.
- The crew HUD (status bars, objectives, crosshair) is hidden while the player is the squid, and so are the wall maps
  on the bridge and in the planet's power room (`UMG_Map`, `UMG_Map_POLAR`, blank on the entity's screen only): they
  show where the mission's items are, which the entity must find out by hunting, so the crew can mislead them. The
  respawn capsules' screens show `?????` instead of the name of the crew member who took one (`UMG_ScreenCapsule`).

The bars are the mod's own, rounded like the crew's and in its colours (read from the game's cooked HUD): the crew
HUD's bars can't be handed to the mod's widget, because a progress bar's style can only be set from C++ or the editor
(`UProgressBar::SetWidgetStyle` isn't Blueprint-callable), and the crew HUD itself is driven by the crew character.

The keys shown are the game's default bindings; a player who rebinds an action sees the default. The icons are
SVGs in [`art/icons/`](art/icons/).

The squid moves at the game's combat speed, 30% faster in the vents than the game's own crouched speed. Holding
Left Shift sprints at the squid's top speed (the game's own, as when the AI monster gets angry) for up to 6 seconds;
the stamina refills over 10 seconds, and an out-of-breath squid sprints again once it is back to 30%. The crew's
sprint is bound on the crew character, not the controller, so the mod watches Shift itself. The host owns the
stamina; both machines apply the same speed (see `movement.lua`).

## Install

Every player installs both halves, the Lua and the pak.

- **Players:** download `ControllableEntity-<version>.zip` from the
  [Releases page](https://github.com/JalapenoLabs/SpeciesUnknownMods/releases) and follow
  [Installing](../../README.md#installing): UE4SS once, then extract the zip into the game's folder.
- **Developers:** `scripts/package-mods.sh --install ControllableEntity` builds the pak and copies
  `ControllableEntity_P.{pak,utoc,ucas}` into `SpeciesUnknown/Content/Paks/~mods/`, and
  `scripts/link-mod.sh controllable-entity` links the Lua into `Win64/ue4ss/Mods/`, so the game runs it from the
  repository (UE4SS's Ctrl+R reloads it).

## Architecture

One design, identical on every machine. Lua owns the gameplay; a small Blueprint pak supplies only what Lua cannot
create: network events and a widget layout.

- **Lua (UE4SS)**, in `ControllableEntity/Scripts/entity/`, one module per job:

  | Module | Runs on | Does |
  |--------|---------|------|
  | `links.lua` | both | Spawns a `BP_EntityLink` per player (host) and routes its events to the modules below |
  | `takeover.lua` | host | Entity mode, volunteering and the random pick, forcing the squid, possessing it, crew exclusion, loss |
  | `lair.lua` | host | The start in the ducts near the game's spawn, the ducts as the lair until the power is on, and F8's power alone |
  | `cries.lua` | host | The squid's cries: on the 1, 2 and 3 keys, on spotting a crew member, and on getting back up |
  | `vents.lua` | both | Finding vent shafts, the in-duct spots beside them, and the steps up inside the ducts |
  | `abilities.lua` | host | Commands to squid moves, cooldowns, the grab rule, the meter's tick |
  | `movement.lua` | both | The squid's speed, the vent bonus, and the sprint and its stamina |
  | `meter.lua` | host | The kill meter and frenzy rules, as plain logic (unit tested) |
  | `frenzy.lua` | host | The three frenzy triggers |
  | `hunt.lua` | host | The vents' time limit once the crew holds the special weapon |
  | `crawl.lua` | host | Crouching the squid into the floor-level crawl openings |
  | `zones.lua` | both | The shuttle, its approach and the forbidden areas: where the entity may not go |
  | `capture.lua` | host | In capture contracts, the entity killed off the shuttle counts as captured |
  | `senses.lua` | host | Noise sources to blurred pings |
  | `control.lua` | entity player | Input to movement and commands; the mod's keys |
  | `camera.lua` | entity player | Third and first person |
  | `vision.lua` | entity player | The entity's own light and the vent-opening markers |
  | `areas.lua` | entity player | The map sections and the minimap's deck around the squid, which the game only follows for crew |
  | `minimap.lua` | entity player | The game's minimap in the corner, north up, centred on the squid |
  | `hud.lua` | entity player | The HUD, and hiding the crew HUD |
  | `objectives.lua` | entity player | The entity's objectives, in the crew's objectives overlay |
  | `voice.lua` | both | The entity's silence, and the crew's radio heard by the entity only nearby |
  | `game.lua`, `config.lua` | both | Game paths and helpers; every tunable |

- **Blueprint pak** (`ControllableEntity_P`, in `Content/Paks/~mods/`), generated from code by the asset builder
  in `unreal/SpeciesUnknown/Source/SpeciesUnknownModKit` (see [docs/pak-mods.md](../../docs/pak-mods.md)):
  - `BP_EntityLink`: a replicated actor the host spawns for every player, owned by their controller and relevant to
    them alone. Its events, `EntityServerCommand` (player to host), `EntityClientPing` and `EntityClientEvent`
    (host to player), have no logic of their own: UE4SS's `RegisterCustomEvent` runs Lua when each one executes,
    on the machine it executes on. Its replicated `Meter`, `Frenzy`, `Health`, `Downed` and `Stamina` feed the HUD:
    the squid's own health doesn't replicate, so the host sends the pool it is on.
  - `WBP_EntityHUD`: the HUD's layout, and its five icons as UI textures (the four actions and the view cone). Lua
    fills in every value and places what sits on the minimap.
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
- `tests/entity_mode_test.lua`: F9, forcing the squid from the lobby, and the random pick.
- `tests/lair_test.lua`: the start in the ducts near the game's spawn, the ducts as the lair, the power, and F8 alone.
- `tests/cries_test.lua`: the cries the squid makes on its own.
- `tests/hunt_test.lua`: the vents' time limit once the crew holds the special weapon.
- `tests/crawl_test.lua`: the squid crouching into a crawl opening only while heading in.
- `tests/zones_test.lua`: kept off the shuttle and out of forbidden areas, the shuttle's approach, and the marked
  boxes.
- `tests/capture_test.lua`: the entity killed off or aboard the shuttle in capture contracts.
- `tests/voice_test.lua`: the entity's mic and radio click, and crew radio speech sent nearby too.
- `tests/vision_test.lua`: the entity's light and the vent markers.
- `tests/areas_test.lua`: the map sections and the minimap's deck around the squid.
- `tests/minimap_test.lua`: the minimap, its follower, the hidden item icons and the zoom.
- `tests/solo_flow_test.lua` and `tests/lobby_display_squid_test.lua`: playing alone, and regressions from playtests.

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
| Start in a vent | The AI walks the ducts to the spots beside each shaft (`BTTask_FindClosestVentpoint`, from `BPI_Vent_GetAllpointLocation`) | Read the same spots (`Point1Component` to `Point4Component`), `BPI_Monster_SetInVent(true)` (which crouches it), then `K2_TeleportTo` the spot two frames later, once the crouched capsule fits the duct |
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
- The AI's own timers (`CheckTarget`, `Check If Stuck`) start when the controller is a `BP_Basic_AI_Controller`,
  so a squid taken over after it spawned has them running. `Check If Stuck` respawns a monster that hasn't moved for
  20 seconds through `BP_GameManager.InitMonster`, which destroys it, and a player lying in wait stands still that
  long. The takeover sets the squid's `ShouldCheckIfStuck` to false, the flag that check reads first.
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

`BP_GameManager` (placed in each mission map, runs on the host) picks the specimen, then something else decides when
it appears:

1. **The pick**, 1.5 seconds after the game manager begins play: `BP_MyGameInstance.spawnForceSessionMonster` when
   set (not 0 or 1), otherwise `Get Random`. That roll is filtered by difficulty (the easiest one allows only Mike,
   the Ghost and, in co-op, the Eye), by the contract's weapon categories (no first category: no Zombie Master or
   Terminator), and drops the last monster finished; it is weighted by how often the host has met each monster. Until
   then `MonsterToSpawn` holds the placed game manager's default (3, Mike), which is what a construction hook sees.
2. **The spawn:** 2 seconds after begin play, but only if the level's game manager has `AutoSpawnMonster` on.
   Hawking has it off: its level script spawns the monster the first time a crew member walks into `TriggerVolume_6`
   on the way out of the shuttle (`InitMonster(true, ...)`, which calls `SpawnMonster` when no monster exists yet).
   A respawn after a capture goes through `InitMonster` too, from `BP_MyGameState`.

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
- Balance against a human entity (playtest 6), each awaiting a decision: camping in the vents once the crew holds the
  weapon that can kill it; guarding the shuttle or its approach in destroy and extract contracts; the crew waiting on
  the shuttle in capture contracts; hiding the contract type from a player who knows in advance they're the entity;
  keeping the entity off the crew's radio while still hearing nearby voices; and, for the ghost later, haunting one
  player all game.

## Test plan

UE4SS writes the mod's log lines, all starting `[ControllableEntity]`, to `Win64/ue4ss/UE4SS.log` on each machine.

**Testing alone** works for steps 1 to 7 (volunteering, the takeover, moving, the view, the lair and the moves) and
16 to 19 (the objectives, the crawl openings, the shuttle and the forbidden areas).
There's nobody to lash, grab or hear, and the shuttle can't launch: as the only player you stay on the crew list
(emptying it ends the mission), and the squid can't sit. Leave through the pause menu. Steps 8 to 15 need at least
one friend.

1. **Loads.** Every player launches with UE4SS, the pak and the Lua installed. The log shows `Loaded. F8 in the lobby
   volunteers to be the entity; the host's F9 turns entity mode on or off.` and, once in the lobby,
   `Hooked ... BP_MyPlayerController`.
2. **Volunteering is private.** In the lobby, one player presses F8. Only they see "You'll be the entity next
   mission". Pressing F8 again backs out; a second player pressing F8 while someone is signed up sees "Someone else
   already claimed the entity".
3. **The squid is forced and taken.** Start a contract. The mission's specimen is the squid, the volunteer sees
   "You are the entity" and controls it, and the host's log shows `took control of the squid` then
   `The squid starts in a vent at ...`. The volunteer's crew body is gone. On Hawking the squid only spawns once a
   crew member steps out of the shuttle, so until then the volunteer plays as crew; alone, walk out yourself (see
   [How the mission's monster is chosen](#how-the-missions-monster-is-chosen)).
4. **Moving and looking.** The view jumps into the vents, behind the squid. Walk and look around. The log shows
   `Move value X=...` and `Look value X=...` lines once each. If walking or looking still does nothing, send the log:
   those lines say whether the input reaches the squid. Check the crew see the squid move smoothly, and note any
   rubber-banding.
5. **The view and the HUD.** The Flashlight key switches to first person and back; in first person the squid's own
   body is gone from view. The crew HUD (health, stamina, objectives, crosshair) is gone. The entity HUD has the
   actions stacked bottom left with the health bar (full, green) under them, and only the minimap at the top, with
   a view cone that turns as you look and `F camera` under it. The rows read top to bottom: left mouse, right mouse,
   E, then the game's space bar glyph, each key, then its icon, then its bar on the right while it charges. Sprint
   until the stamina bar appears under the health bar; it goes once full again. H hides the hints, H again brings
   them back.
6. **The lair.** You start in the ducts near where the game spawns its monster. With the power still off, the hint
   "Lurk in the vents until the power is on" stays on screen (alone, it adds that F8 turns it on). Crawl anywhere in
   the ducts: nothing pulls you back. Space over an opening, Aim and E answer "The vents hold you until the power is
   on"; Aim's and E's rows in the stack are dimmed. When the power comes on (alone: press F8), the entity sees "The
   power is on. Hunt." and roams freely. A contract that starts with the power on shows the squid free from the start.
7. **Vents and peeking.** Once free: Space over a vent opening drops out; Space standing under a vent climbs in.
   At the foot of a step up inside the ducts (an elbow joint the crew can only drop down), Space climbs it, even
   before the power is on. In third person, looking down stops at about 50° and the screen never goes black.
   Over a grate in a vent, `C Peek` shows under the minimap; Crouch peeks through the grate, and the hint goes while
   peek recharges. Away from a grate there's no hint. Shoot with nobody near: the squid swings at the air.
   Press 1, 2 and 3: a roar, a curious call and a long call, each with a short cooldown.
8. **Entity mode.** In a co-op lobby the host presses F9: only the host sees "Entity mode: OFF"; the next mission
   rolls its own monster and nobody becomes it. F9 again turns it back on. A client's F9 shows "The host turns entity
   mode on or off".
9. **The random pick.** In co-op, with nobody volunteering, start a contract: the squid is the specimen, and when it
   appears one random player becomes it (only they are told). The next mission picks again.
10. **The lash and the leap.** Shoot next to a crew member: a lash, and its bar fills in the stack. Aim: a leap where
   you look; a grab on landing breaks off with "Your hunger isn't ready". Have the crew shoot the squid: the health
   bar drains, and when the squid is knocked down it turns red and shows the real health.
11. **The kill.** Wait for the ultimate's bar to fill and disappear (90 s, faster near noise), press E facing a crew
   member: the leap's grab kills. The bar comes back empty.
12. **Senses.** Have the crew shoot, walk and trigger doors and alarms out of sight. The entity sees fading markers
   through walls, never the players themselves.
13. **Frenzy.** On an extraction contract, pick up the black box: `FRENZY` appears and grabs kill without meter, each
   re-arming after 7 s.
14. **Launching.** The crew board the shuttle and launch without the entity; with the squid aboard, it doesn't launch.
15. **Losing.** Kill the squid: the entity player sees "The crew got you" and watches a crew member.
16. **Objectives (alone).** As the squid, hold Tab: the crew's objectives overlay shows "THE ENTITY" with Kill all
    humans, Leave them no respawns (with the count), and Stay alive, and no contract icon. Letting go hides it. If it
    shows the header but no rows, or nothing at all, send the log.
17. **Crawl openings (alone).** In crew quarters, walk the squid into the low opening the crew crouch through: it
    crouches and goes in. Walk back out into the room: it stands up and stays standing. The log shows `The squid
    crouches into a crawl opening`.
18. **The shuttle (alone).** Walk toward the shuttle: within about 15 m of its bay the HUD says "Near the shuttle: no
    sprinting, and no kills", Shift doesn't sprint, and E answers "Save your hunger". Try to board: the squid is put
    back with "Hunt them away from their shuttle". Amber posts glow around the approach and red ones around the bay.
19. **Forbidden areas (alone).** Head for the genetics lab's wing: red posts stand at its edge, and stepping in puts
    the squid back with "Hunt elsewhere". A `Put the squid back: Denied.Forbidden` line in the host's log anywhere
    else (for example at a closed vent door) is a false positive worth reporting.
20. **The hunt (with a friend, kill or capture contract).** Once a friend picks up the special weapon, the entity
    sees "the vents won't hide you for long" and a vent-time bar at the top whenever it's in the vents. Stay in for
    20 s: the squid is forced out of the nearest shaft, and Space under a vent answers "The vents take you again once
    your vent time is half back" until about a minute outside. The squid roars every 12 s; the friend should hear
    it near the squid and, far away, its distant call. Report if a forced exit lands the squid in a wall.
    Also with the friend: their first time in your view, the squid calls out on its own; when they knock it down and
    it gets back up, it roars. Your 1, 2 and 3 cries reach them from where the squid is.
21. **Voice (with a friend).** The entity's voice reaches nobody, and their radio key makes no sound. The friend holds
    the radio key and talks: the entity hears them only when close, with no radio static. A hook error in the log on
    the first radio press names the voice call that needs fixing.
22. **Capture (with a friend, capture contract).** Kill the squid away from the shuttle: the contract completes as
    captured. Kill it aboard: the contract fails, as normal. Check the lobby's specimen display after the first.
