# Game internals

What Species Unknown is built from, as far as it matters for modding. Everything here was read from the
installed build of 2026-11-06 (Steam app `2747330`). Re-check after a game update.

## Engine and build

- **Unreal Engine 5.7**, changelist `++UE5+Release-5.7-CL-51494982` (from the shipping executable).
- **Shipping build.** The in-game console is compiled out and the game writes no log to `Saved/Logs`.
  UE4SS restores both (see [ue4ss.md](ue4ss.md)).
- **Blueprint-only gameplay.** The executable has no `/Script/SpeciesUnknown` module: every game system is a
  Blueprint under `/Game/...`. In practice:
  - Lua mods hook engine and plugin functions (`/Script/Engine...`, `/Script/OnlineSubsystemBlueprints...`) or
    the game's Blueprint functions (`/Game/...`).
  - There is no game C++ to read; game logic is Kismet bytecode inside the cooked assets.
- **Native plugins compiled in** (from reflection strings): Redpoint EOS Online Framework (`RedpointEOS*`,
  `OnlineSubsystemRedpointEOS`), OnlineSubsystemBlueprints, OnlineSubsystemSteam, VaRest, StateTree, Sentry crash
  reporting, MetaHuman SDK runtime.
- **No mod loader or mod SDK ships with the game.** Mods load through stock UE pak loading and the community
  UE4SS loader.
- **The game detects UE4SS.** The title screen's play page (`WBP_TitleScreen_PlayPage`) calls `IsUsingUE4SS()`. When
  it's true, the page shows the `ST_MainMenu.MODWrningMsg` banner ("Installed mods detected. Mods are not supported
  yet, please only play with mods in solo or private sessions...") and disables the Public button; Solo and Private
  stay available. This repository's mods respect that: play them solo or in private sessions. The executable
  references EOS Anti-Cheat functions (part of the Redpoint plugin), but no anti-cheat binaries are installed, so
  nothing blocks DLL injection or extra paks.

## Content containers

All in `SpeciesUnknown/Content/Paks/`:

| File | Format | Holds |
|------|--------|-------|
| `SpeciesUnknown-Windows.pak` | Pak v12, Oodle | Config `.ini` files and other loose (non-asset) files |
| `SpeciesUnknown-Windows.utoc` / `.ucas` | IoStore TOC v8, Oodle | Every cooked asset (~25,000 chunks) |
| `global.utoc` / `global.ucas` | IoStore | Script objects shared by all containers |

- **Not encrypted.** The pak's encryption key GUID is all zeros, its index is unencrypted, and the IoStore container
  flags are `Compressed | Indexed` with no `Encrypted` or `Signed` bit. No AES key is needed to read assets or to
  load new paks.
- **Oodle compressed.** Reading assets needs a tool that bundles or downloads the Oodle decompressor (see
  [reverse-engineering.md](reverse-engineering.md)).
- **File list without unpacking.** `Manifest_UFSFiles_Win64.txt` in the install root lists every packaged path.
  `grep` it to find assets by name.

## Assets worth knowing

| Asset | Role |
|-------|------|
| `/Game/Blueprints/Core/BP_MyGameInstance` | Game instance; persists across travel |
| `/Game/Blueprints/Core/BP_MainMenuGameMode` | Main menu |
| `/Game/Blueprints/Core/BP_LobbyGameMode` | The ship hub players gather in before a contract; a subclass of `BP_PlayableGameMode`, so "a playable game mode exists" is true in the lobby too |
| `/Game/Blueprints/Core/BP_PlayableGameMode` | Missions |
| `/Game/Blueprints/Core/BP_FirstPersonGameMode` | Base first-person mode |
| `/Game/Blueprints/Lobby/BP_Lobby_FunctionLibrairy` | Lobby helper functions (the misspelling is the game's) |
| `/Game/Blueprints/BPI/BPI_GameInstance` | Interface the game instance implements |
| `/Game/Blueprints/Online/BP_Online_FunctionLibrary` | Builds session settings (main, private by code, public) |

## Gameplay state worth knowing

Read from the Blueprint bytecode; the mods that rely on each fact link back here.

- **The ship's power** is `BP_MyGameState.LightStatut` (`LightStatutEnum`, replicated): 0 on, 1 off, 2 evacuation
  (self destruct armed; `CanLightOff` is false), 3 limited (emergency power, dimmed). `BP_GameManager` sets it at
  mission start: off, unless the contract has `PowerAtStart` (then it stays on, or limited with `EmergencyPower`).
  `OnRep_LightStatut` runs on every machine when it changes; on the host, `ChangeLightStatut` calls it after every
  change. The switch-off comes `DesactivatePowerStartDelay` into the mission, so until then the power reads on even on
  a contract without power at start, and a contract with power at start (without emergency power) never changes it.
- **Vents** are `BP_Vent_Up` actors (`BP_Vent_Up_POLAR` on Polar): vertical shafts from a room's ceiling into the
  ducts, standing on the room's floor. Up to four billboard components (`Point1Component` to `Point4Component`) mark
  spots beside each shaft's top, inside the duct; `BPI_Vent_GetAllpointLocation` returns them. Crossing a shaft's
  `BoxOverlap` sets the monster's `InVent` (`BPI_Monster_SetInVent`, which also crouches it to fit the ducts).
  Hawking's persistent level `Maps/SpaceShip` places 265 shafts and about 970 vent navigation links
  (`Nav_Link_VentPoint_*`); its sublevels add decoration only (`BP_VentWall`, `BP_VentDoor`). The links taller than
  250 (`Up500`, `Up550_Child`, `Up600_Child`) join a shaft to its room; `Nav_Link_VentPoint_Up250` is a 2.5 m step
  inside the ducts, which the AI climbs through `BPI_Monster_ClimbVent250(link, fromUp)`: the monster warps to the
  step's foot, 75 units to the link's left (or its top, 75 to the right and 250 up) and plays its `Vent250_Up` (or
  `_Down`) montage, whose root motion does the climb. The duct pieces themselves (`Vent_1m`, `Vent_Door`,
  `Vent_Hole_LowPart`, ...) are plain static meshes, and nothing but a shaft's box puts a monster in its vent state,
  except at the floor-level openings the crew crawl through: each has a `BP_Trigger_Crouch` (`VentEnter`, its forward
  into the duct; six on Hawking, two in crew quarters and four in the lab). On the host only, it crouches a monster
  heading in, but only one its AI drives (`BPI_Crouch_SetCrouch(true, VentEnter)`), and stands any monster up as it
  leaves toward the room (`SetCrouch(false)`, then `SetInVent(false)`). A shaft's box, by contrast, sets the vent
  state on every machine as a monster leaves it: true out of the top, false out of the bottom. The ducts' navigation
  is marked by `NavArea_Vent` modifier volumes, which miss parts of the lab's crawl network.
- **The camera ignores the view target.** The player camera manager (`Character_CameraBP`) overrides
  `BlueprintUpdateCamera`: while its cached crew body (`Player`) is valid, the camera sits at that body's `Camera`
  component, whatever `SetViewTarget` says. Its own `BPI_CameraPlayer_ResetPlayer(pawn)` sets the view target and
  caches the pawn only if it is a `BP_Character`, so passing any other pawn clears the cache and the engine's normal
  view of that pawn takes over. Changing `CameraStyle` from UE4SS does nothing (neither the property nor
  `ClientSetCameraMode` moved the camera in playtest 4). It keeps the engine's look limits (`ViewPitchMin`,
  `ViewPitchMax`), which limit the control rotation and can be set at runtime.
- **The ship streams in sections.** Each `BP_StreamingVolume_Manager` shows its sublevels while the local player's
  pawn overlaps one of its `TriggerVolumeList` volumes (`BP_FunctionLibrairy.GetOnlyVisualOverlap`: the pawn must be
  the local player controller's, a spectator or a death pawn). `BPI_Streaming_AddActorToTrigger(trigger, pawn, on)`
  enters or leaves a volume by hand, through the same check. Vent shafts (`BP_Vent_Up`) hide with their section.
- **The map has deck layers.** One map image (`BP_MapManager`) plus extra layers for decks that overlap others, such
  as crew quarters. `BP_MapManagerExtended` keeps the map triggers the local player's pawn overlaps (actors carrying a
  `TriggerMap_ActorComponent` with a `Layer` and a `Priority`, registered at begin play), picks the highest priority
  a tenth of a second after a change, and calls `BP_MapManager.SwitchMapExtraLayer`; no trigger means the default
  layer. Its `BeginOverlap(trigger, actor)` and `EndOverlap(trigger, actor)` run the same `GetOnlyVisualOverlap`
  check. It counts triggers, not actors, so a pawn that stops being the local player's pawn inside a trigger leaves
  it counted. `UMG_MiniMap` dims the base map to 15% while an extra layer shows.
- **Monsters respawn when stuck.** `BP_BaseMonster."Check If Stuck"` runs every second once an AI controller
  possesses the monster. After 20 seconds without moving it calls `BP_GameManager.InitMonster(false, ...)`, which
  destroys the game manager's *tracked* monster (`Monster`), not necessarily the stuck one, and spawns a new one.
  `ShouldCheckIfStuck` turns the check off; nothing in the game writes it.
- **The game manager spawns and tracks one monster.** `BP_GameManager.SpawnMonsterEvent` spawns the class at
  `GetSpawnPoint` (after the first spawn, the map's `MonsterSpawnPoint`; the Terminator picks from its own
  `PowerOnSpawnPoint` and `NoVentSpawnPoint` lists) with `BeginDeferredActorSpawnFromClass` (collision 2, adjust but
  always spawn) and `FinishSpawningActor`, stores it in `Monster`, then `SetUpBaseMonsterState` sets up whatever
  `Monster` names: damage multiplier, difficulty, `Respawn Data`, the far-away sound, combat music and, after the first
  spawn, the escape route's nav modifiers. `GameTimeProgression` pushes the mission's rising aggression to `Monster`
  once a second, and `BPI_GameState_ForceSound` (doors, alarms, canisters) reaches only `Monster`. Map load places
  per-species content for `MonsterToSpawn` alone: the Zombie Master's zombie bodies, and the special weapon for its
  weakness.
- **Monsters only target the crew.** Every target check (sight in `BP_BaseMonster.CheckTarget`, hearing, damage and
  touch) requires the `BPI_Human` interface, which no monster class lists, and no monster makes an AI-audible noise
  (`BP_ParentMonster.FootstepsNoiseReport` reads false on every monster class; both read from the cooked class
  data, to confirm in play). `BPI_GameState_ForceSound`'s callers are crew-driven: the big doors' cycle
  (`BP_BigDoor1`), the airlock alarm (`BP_Sas_Controller`) and explosive canisters. Melee attacks and grabs catch only
  `BPI_Human` actors; the Terminator's gatling and grenades damage anything they hit.
- **Any monster's death ends the mission.** `BP_BaseMonster.FinishDeath`, a few seconds after death (the Ghost 4 s,
  the squid 15 s), calls `BPI_GameState_FinishGame` as a kill on kill, capture and extraction contracts, unless the
  self destruct is armed. Every death also calls `BPI_GameState_SetMonsterOff`, which stops the monster music.
- **The shuttle** is `BP_PlayerShip` (one per map). Its `TriggerBoxOverlap` (half extents 2500×900×400 on Hawking,
  spanning the bay between the airlocks) is "aboard": on the host its overlaps fill `PlayersInside` and
  `MonstersInside` and set the replicated `MonsterInside`, and `CheckForLaunch` needs the power on, no monster
  inside, the doors closed and every player aboard seated. With `UseExteriorTrigger` (Polar) it uses the volumes
  `ExtTriggerBase` / `ExtTriggerVisual` instead. The capture cell (`BP_Capture`) is inside it.
- **Forbidden areas** are only the navigation area `NavArea_Forbidden`, which steers the AI's paths
  (`QuerryFilter_CheckForbidden` excludes it and `NavArea_Obstacle`; `GameManager.CheckForbiddenPath` drops targets
  behind it). Hawking marks the genetics lab's wing with three trigger boxes in the `Hawking_StaticMap_Laboratory`
  section whose `CollisionComponent.AreaClass` is the forbidden area; Polar spawns a `BP_DynamicNav_Forbidden` over its
  underground electrical area on the host. A possessed monster ignores them.
- **The power** is restored at `BP_Screen_RestorePower` (one per map: Hawking's on the command deck): interacting with
  it runs `ChangeLightStatut` about 2 seconds later.
- **The AI's cries** come from its behaviour tree (`BTTask_PlayVoice` → `BPI_Monster_PlayVoiceType(type, override,
  volume, noIfPlaying, replicate)`), so a possessed monster is silent but for its footsteps and montages. With
  `replicate` the cry multicasts and plays on the monster's positional voice on every machine; `PlayVoiceFar(Multi)`
  plays its far call only for listeners over 2,000 units away.
- **Voice is the Onset VoIP plugin** (`/Script/OnsetVoip`, in the executable), voice data relayed through the host.
  The host puts each player's talker (`OnsetVoipWorldSubsystem.GetVoipTalker(playerState)`) in channel 0, proximity
  (3D on the speaker's pawn, `VOIPProxy` attenuation), and channel 1, radio (2D, `VOIPRadio` attenuation and the
  `SEPC_VoIP_Radio` effect chain), through `BP_MyPlayerState.SRV_SetVOIPChannel` → `SetVoiceChannel(channel, add)`,
  and re-adds both whenever voice is switched back on. Its proximity mute follows the player's mute setting or death
  (`SetMutedOnVoiceChannel(muted, 0)`). Each player's own machine picks what its mic sends in
  `BP_MyPlayerState.UpdateComChannels`: `want_use_radio` sends on channel 1
  (`OnsetVoipLocalPlayerSubsystem.ToggleVoiceCaptureWithChannel(true, 1)`), push-to-talk or open mic on channel 0,
  otherwise `ToggleVoiceCapture(false)`. The radio key's click
  (`radio_static_placeholder`) plays locally in `SetUseRadio`. A listener hears a speaker only through a channel
  both are in, and 2D radio wins when both are. Per-listener `SetMuted` and the voice volumes are reapplied every
  second by `BP_MyGameState.OnsetVOIPInit_Scotch`, so lasting changes belong on the host's talker.
- **The squid has two health pools** (`BP_Monster_Poulpi`; neither replicates). Hits drain `HealthTemporal`, its
  stagger pool; at zero the squid falls to the ground (`IsOnGround`) and `MaxHealthTemporal` grows by 10%. Only while
  it is down and burning (`HeatValue` above 0.15) do hits drain `Health`. The first time it reaches zero the squid's left
  eye breaks (`BreakEye (multi)`, unhurtable meanwhile, `Health` refilled); once the cut-eye montage completes, the host
  plays the ink get-up (`GetUpWithInk (multi)`), and as that blends out, `BPI_Monster_SetEscaping(true, true)`: the
  flight. The second time, the head breaks and it dies. Only ever one eye. `SetEscaping` calls `SetStayFar(true)`,
  which calls `LaunchFleeTuto` (once per monster, on kill and capture contracts, not during the self destruct):
  `LaunchFleeTuto(Multi)` makes every machine's `BP_Tuto_Notify_MonsterFlee` show the crew "The specimen has fled,
  track it" (`ST_Tooltip.TutoMonsterFleeText1`/`2`) through `BPI_Player_SendNotifyHUD`. Only Hawking's level places
  that actor. The escape's run itself needs the AI (`SwitchBehavior` stops before its behaviour tree without one).
  Mike flees the same way after each face break; the Terminator never does. The stagger pool refills by itself, a
  literal 0.1 every host frame (`TickChildServerFonction`).
  `Health` regenerates while it isn't heated, and `HealthTemporal` refills a little every tick.
- **The squid's basic attack** always plays `Poulpi_Attack_Small1_Montage` (`GetAttackSimpleAnim`), through the
  `AttackSimpleAnim (Clients)` multicast. Its damage is the montage's notify, a sphere check in front of the monster
  (`BP_ParentMonster.BasicSphereAttackDamage`) that runs only while the monster is attacking. `SetSimpleAttack` does
  nothing without a valid target.
- **Mike has one health pool** (`BP_Monster_Michel.Health`, 350, set at construction over the class default's 450; it
  doesn't replicate). Only hits to his head bones drain it, and only while his head is open (`HeadOpenValue` above
  0.2) or a face is already broken; hitting his head with `DamageType_Electrocut` (his weakness) electrocutes him
  (`Electrocuted`), stunning him and opening it. Each time it reaches zero a face breaks (`HeadBreak_Left`,
  `HeadBreak_Right`, replicated) and it refills, to full after the first and 1.5 times after the second; the third
  time he dies.
- **Mike's grab is his only kill.** Every grab goes through `GrabPlayerVent ( Multi)`: from his swipe at a crouched
  crew member (his `GetAttackSimpleAnim` plays `Attack_Player_Vent` at one) and the montage's sphere check
  (`ContinusSphereCheck`). The eating montage's `AnimNotify_EatFace` kills 2.18 seconds in, checking only that he
  still holds someone (`LastGrabPlayer`); interrupting the montage lets go. His drop from a vent doesn't grab, and he
  has no leap (`AllowSpecialAttack` is off).
- **The Terminator spawns powered down** (`BP_BigRobot.IsPowered` off, lying on the floor), and wakes when anything
  calls `BPI_Monster_SwitchBehavior` with a behaviour other than Wait (6): mission progress, a target, combat.
  Behaviour 3 (combat) also sets `IsInCombat`, which starts the action music for everyone. Nothing in its moves checks
  `IsPowered`, and nothing stops movement input reaching it, so a player's dormant robot must be held by the mod.
- **The Terminator's gatling takes every hit while it holds it** (`BP_Gatling.MainHealth`; the robot reaches it
  through its replicated `Gatling` and `HaveGatling`). At zero the gun breaks, and only then do belly hits drain the
  body's `Health`; at two thirds and a third it goes down, unhurtable, for 6 to 15 s (`SetStunt`, `IsStunt`). Only
  electrocution stops the gatling firing in the game's own code; a broken gun is never told to stop.
- **The Terminator has two instant kills:** the arm grab's montage (`Decapitation`, while `IsGrabPlayer` is set) and
  its close attack `atk_front03` (`CheckCrushHead`), which `SetSimpleAttack` picks once its gatling is gone.
- **Some things switch on only for the local player's own pawn**, deciding from trigger overlaps that pass
  `BP_FunctionLibrairy.GetOnlyVisualOverlap`: the map sections (`BP_StreamingVolume_Manager`), Polar's indoor fog
  (`BP_InsideVolume_Manager`), the minimap's deck (`BP_MapManagerExtended`), Hawking's reactor core (`BP_CoreReactor`,
  in `Hawking_StaticMap_Enginery`, hidden until `BeginOverlap` on its `TriggerVolume` runs `InitRender(true)`; its
  camera shake has its own `TriggerVolumeShake`) and the engineering water (`BP_Water`, in `SpaceShip.umap`, hidden
  until `BeginOverlap` on its `TriggerVolume` runs `InitWater(true)`). A possessed monster's collision never fires
  those overlaps. The reactor's pulse (`CheckPawnKill`, on the host) hurts every Character in its box regardless.
  The same gate decides: the shuttle's inside (`BP_PlayerShip.BeginOverlapVisual` → `PlayerLocalInside`, its
  interior sound, low-pass and lights, from its `TriggerBoxOverlapVisual` box or, with `UseExteriorTrigger`, the
  `ExtTriggerVisual` actor; it broadcasts `LocalInsideDispatch`, which `BP_AmbientMain_POLAR` follows to go quiet
  aboard), the genetics lab's decor (`BP_GeneticsLab_Manager.TriggerVisual`, handed to the jars and creature tables it
  spawns as their `TriggerVolume`, and to each moray as `Infos.TriggerVisual_11_...`), the final explosion's vortex
  sound (`BP_FinalExplosion.SphereOverlapVisual` → `PushSoundMixModifier(VortexSoundMix)`) and Polar's volumetric fog
  (`BP_SplineCollision`'s `Box` → `SetIC`, comparing with `GetPlayerPawn` rather than the gate). Two level scripts
  load parts of their maps once a local pawn first crosses a trigger, through the same DoOnce as their `LoadLevel`:
  `SpaceShip` (`Hawking_StaticMap_Central` and on) and `PolarMap` (`POLAR_StaticMap_Workshop`).
- **The reactor room** (Hawking) is `NavArea_DangerousArea` (`NavModifierVolume_89`, x -10537 to -7862, y ±1150,
  z -349 to -49; its brush doesn't collide), which nearly every AI query filter excludes, and its
  doors (`BP_Door_Reactor`) are placed locked. An unlocked door opens for a `BPI_PawnInfo` actor whose `CanOpenDoors`
  is true entering its `BoxEnter`; monsters inherit `CanOpenDoors = true` from `BP_ParentMonster`.
- **Polar's elevators** (`BP_Elevator_Cargo`, `BP_Elevator_Simple`, children of `BP_ElevatorParent`; Hawking has
  none) count riders in their car's `TriggerVolume`, which rides with the car. Any monster in it (`MonsterInside`)
  makes a start refuse with an alarm, and a refused start leaves the landing's call screens dead until someone rides
  the car. No monster AI rides them.
- **The minimap's reference box:** each map has one `BlockingVolume` tagged `RefBoxMap`; every map manager finds it
  as it begins play, and `UMG_MiniMap` copies it once, in `Construct`. A minimap built before that has none and draws
  the map frozen on its middle (`MapUtils_FunctionLibrary.WorldToWidgetLocation` returns zero).
- **Polar's visor frost** is Ultra Dynamic Weather's screen frost (`Ultra_Dynamic_Weather_C`, its
  `Screen Frost Post Process`), a post process on whatever camera is the local one, not tied to the crew character.
- **Contracts and their modifiers.** `ContractStruct` holds one fixed field per modifier (`PowerAtStart`,
  `EmergencyPower`, `Turret`, ...). `BP_Mission_FunctionLibrairy.GenerateContracts` builds the lobby's list on the host
  (balancing modifiers against bounty targets per tier, `ContractGenParams_DataTable`); `BP_ContractManagerTerminal`
  stores it in its replicated `generatedContracts`, and the chosen one travels through `BP_MyGameInstance.Contract`
  into the replicated `BP_MyGameState.Contract`. Every screen that lists modifiers (the contract card and details, the
  shuttle's mission start page, the Tab brief, the score screen) walks the released rows of
  `GlobalModifiersStatus_DT`, reads each through a switch over the game's names (`Contract Get Bool Modifier From
  Player View`) and draws it from its `ContractModifier_Data` row (name, icon, description) and its
  `Addiitonal_Bounty_DataTable` row (bounty), by row name. `Bonus`, `TimeLimit`, `TestModif` and `PirateInfasion` are
  set to defaults and never read by gameplay; `PirateInfasion` is still summed into the bounty.
- **Each player is paid on their own machine.** The score screen (`WBP_ScorePage.SetUpBaseMission`) adds the
  objective's bounty and `BP_Mission_FunctionLibrairy.GetConditionalCombinedBounty` (what the modifiers pay) into the
  mission bounty, adds the player's own score lines, and the seat pays the result into the local wallet
  (`BPI_Player_AddMoney`, then `BP_MyGameInstance.AddAndSave_MoneyMonunt`). `MaxBounty` is only displayed.
- **Default key bindings** (`IMC_Default`): Shift sprint, C crouch, LMB shoot, RMB aim, R reload, E interact,
  F flashlight, G drop weapon, Space hold tool, Tab show names, Left Ctrl radio. Each action's event handler on
  `BP_MyPlayerController` forwards to the possessed pawn. H, F8, F9 and the punctuation keys are free.
- **The crew HUD** (`/Game/Blueprints/UI/UI_HUD_Display`) is driven by events from the crew character
  (`SetHealthValue`, `SetStaminaValue`, `SetFlashLightValue`, ...). Its bars are progress bars on a shared dark track
  (linear `0.063, 0.102, 0.12, 0.75`), filled health green (`0.025, 0.25, 0.119, 0.75`), half-white for stamina, and
  pale blue-grey (`0.584, 0.708, 0.768`) for the flashlight and tool. Their rounded shape is the material
  `Mat_RoundedBox_UI`, whose instances set only size and corner radius; the colour is the bar's own.

## Paths on this machine

| What | Path |
|------|------|
| Install | `/mnt/FreightBay/SteamLibrary/steamapps/common/Species Unknown` |
| Executable | `<install>/SpeciesUnknown/Binaries/Win64/SpeciesUnknown-Win64-Shipping.exe` |
| Proton prefix | `/mnt/FreightBay/SteamLibrary/steamapps/compatdata/2747330/pfx` |
| Saved (config, saves) | `<prefix>/drive_c/users/steamuser/AppData/Local/SpeciesUnknown/Saved` |

The game runs under Proton Experimental with `-nohmd -dx11` (the launch arguments Steam passes).
