-- Copyright © 2026 Jalapeno Labs

-- The squid (BP_Monster_Poulpi): a vent hunter that lashes, leaps where it looks, and kills with a head grab.

local squid = {
  id = "Squid",
  displayName = "Squid",
  -- MonsterList value (BP_Lobby_FunctionLibrairy.GetMonsterSoftClass): what the game manager spawns for it.
  monsterType = 2,
  className = "BP_Monster_Poulpi_C",
  classPath = "/Game/Blueprints/Monsters/BP_Monster_Poulpi.BP_Monster_Poulpi_C",
  -- The codex's animated portrait of it (a UI material), for the host's picker.
  portrait = "/Game/Blueprints/Screens/Terminals/CodexExtended/SpriteSheet/"
    .. "Poulpi_Spritesheet_Mat_Inst1.Poulpi_Spritesheet_Mat_Inst1",
  -- It lives in the vents: the lair, the hunt's vent time, crawl openings and the vent markers all apply.
  usesVents = true,

  -- Its two health pools (BP_Monster_Poulpi's own fields, not BP_BaseMonster's). Hits drain the stagger pool, and at
  -- zero the squid falls to the ground (IsOnGround); only while it is down and burning (HeatValue) do hits drain its
  -- real health, and at zero health it dies. Neither replicates.
  healthFields = {
    health = "Health",
    maxHealth = "MaxHealth",
    stagger = "HealthTemporal",
    maxStagger = "MaxHealthTemporal",
    downed = "IsOnGround",
  },

  -- The stagger pool refills a little every host frame on its own (BP_Monster_Poulpi.TickChildServerFonction adds 0.1 a
  -- frame), the game's tuning for its AI: a player's squid healed too fast to fight (playtest 9). This share of that
  -- refill is kept. A rise of more than maxNaturalRise between two of the host's checks (a thirtieth of a second) is
  -- one of the game's full refills (getting up, and after an eye breaks), which stay as they are.
  staggerRefill = { keptShare = 0.5, maxNaturalRise = 2 },

  -- What the HUD's action stack shows for each of its moves (moves/squid.lua), the cooldown each starts, and whether
  -- the lair holds it back until the power is on: the leap, and the ultimate that leaps, would leave the ducts.
  moves = {
    -- The lash lands on the crew member nearest the aim within this reach and cone (playtest 9: at 1.2 s apart, the
    -- squid stayed on top of a crew member spamming it).
    Primary = { icon = "Lash", cooldown = 2, reach = 350, coneDegrees = 60 },
    -- The game's own leap lands 300 to 500 units ahead; the entity always leaps this far along their aim. It costs this
    -- share of the stamina and can't be made out of breath (playtest 9: it kept the entity up with a fleeing crew
    -- member while nearly out of stamina).
    Secondary = { icon = "Leap", cooldown = 6, heldByLair = true, distance = 450, staminaCost = 0.4 },
    Ultimate = { icon = "HeadGrab", cooldown = 6, heldByLair = true },
    Mobility = { icon = "Vent", cooldown = 1 },
  },

  -- Its cries (cries.lua), among the cues its Blueprint brings with it, by the name the mod gives each.
  cries = {
    Roar = "/Game/Monster_SoundFX_Pack1/Wav/Monsters/Monster06/Roar/Monster6_Chase_Wav_Cue.Monster6_Chase_Wav_Cue",
    Curious =
      "/Game/Monster_SoundFX_Pack1/Wav/Monsters/Monster06/Calls/Monster6_Sound_Wav_Cue1.Monster6_Sound_Wav_Cue1",
    Call = "/Game/Monster_SoundFX_Pack1/Wav/Monsters/Monster05/Calls/Monster5_Call8_Wav_Cue.Monster5_Call8_Wav_Cue",
    Seen = "/Game/Monster_SoundFX_Pack1/Wav/Monsters/Monster06/Calls/Monster6_See_Wav_Cue.Monster6_See_Wav_Cue",
    Escape = "/Game/Monster_SoundFX_Pack1/Wav/Monsters/Monster06/Roar/Monster6_Escape_Wav_Cue.Monster6_Escape_Wav_Cue",
  },

  -- Its basic attack's swing, played on its own when the lash finds nobody (GetAttackSimpleAnim always picks it).
  swingMontage = "/Game/Blueprints/Monsters/Poulpi/Anim/Poulpi_Attack_Small1_Montage.Poulpi_Attack_Small1_Montage",

  -- The grab that kills, which the kill meter rules (abilities.lua): the function that starts it, hooked on the host,
  -- and the knockback that breaks it off when the meter says it may not kill.
  killGrab = {
    functionName = "GrabHeadPlayer",
    breakMontage = "/Game/Blueprints/Monsters/Poulpi/Anim/Hit/"
      .. "Poulpi_Hit_DuringGrab_Front_Montage.Poulpi_Hit_DuringGrab_Front_Montage",
    -- A grab broken off lands as a lash would (playtest 9: the leap bounced off a crew member for nothing): the lash's
    -- own sphere attack (Poulpi_Attack_Small1_Montage's AnimNotify_BasicSphereAttack), at the squid's face, where it
    -- holds the crew member's head.
    brokenGrabHit = {
      radius = 60,
      forwardOffset = 50,
      damage = 18,
      damageType = "/Game/Blueprints/DamageType/DamageType_Punch.DamageType_Punch_C",
    },
  },
}

return squid
