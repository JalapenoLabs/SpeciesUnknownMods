-- Copyright © 2026 Jalapeno Labs

-- The Terminator (BP_BigRobot): a slow, armoured robot that never enters the vents. It fires its gatling, lobs
-- grenades, charges, and kills by grabbing a crew member and crushing their head. It starts powered down, lying on the
-- floor where the game spawned it, and wakes when the crew turns the power on.

local MONTAGES = "/Game/Blueprints/Monsters/BigRobot/MannequinTest/"
local VOICES = "/Game/Sound/RobotCollection_SoundPack/SoldierBot/"

local terminator = {
  id = "Terminator",
  displayName = "Terminator",
  -- MonsterList value (BP_Lobby_FunctionLibrairy.GetMonsterSoftClass): what the game manager spawns for it.
  monsterType = 7,
  className = "BP_BigRobot_C",
  classPath = "/Game/Blueprints/Monsters/BP_BigRobot.BP_BigRobot_C",
  -- The codex's animated portrait of it (a UI material), for the host's picker.
  portrait = "/Game/Blueprints/Screens/Terminals/CodexExtended/SpriteSheet/"
    .. "BigRobot_Spritesheet_Mat_Inst.BigRobot_Spritesheet_Mat_Inst",
  -- Too big for the vents: no duct lair, no vent time, no crawl openings, no vent markers.
  usesVents = false,
  -- The game's own roll never gives it a contract the crew arrives at without their main weapon, nor its easiest
  -- difficulty (BP_GameManager.Get Random): its armour is beaten by those guns. A Random entity follows the same rule
  -- (takeover.lua).
  needsCrewMainWeapons = true,
  -- Its replicated "awake" flag: it spawns with it off, lying on the floor, and the lair (lair.lua) keeps it that way
  -- until the power is on. While it is off, the player's own machine moves nothing (control.lua).
  poweredFlag = "IsPowered",

  -- Its body's pool (BP_BaseMonster's own fields, which don't replicate) and its stun: at two thirds and a third of
  -- its health it goes down and can't be hurt for a while (SetStunt, which sets IsStunt on every machine). While it
  -- holds its gatling the gun takes every hit instead (moves/terminator.lua shows that pool).
  healthFields = {
    health = "Health",
    maxHealth = "MaxHealth",
    downed = "IsStunt",
  },

  -- What the HUD's action stack shows for each of its moves (moves/terminator.lua), the cooldown each starts, and
  -- whether the lair holds it back while it lies powered down (every move: it can't move at all).
  moves = {
    -- The gatling fires while Shoot is held. Once the crew has broken it, Shoot punches the crew member nearest the
    -- aim within this reach and cone instead.
    Primary = { icon = "Gatling", cooldown = 0.3, heldByLair = true, reach = 250, coneDegrees = 60 },
    -- A grenade lobbed at the crew member nearest the aim within this range and cone, or this far ahead along it. Its
    -- blast reaches 400 units and would hurt its own gatling, so it never lands nearer than safeDistance.
    Secondary = {
      icon = "Grenade",
      cooldown = 8,
      heldByLair = true,
      range = 1500,
      coneDegrees = 40,
      aheadDistance = 1000,
      safeDistance = 450,
    },
    -- The arm grab takes the crew member nearest the aim within this reach and cone, after its half-second windup.
    Ultimate = { icon = "ArmGrab", cooldown = 6, heldByLair = true, reach = 300, coneDegrees = 60 },
    -- The charge, along where it faces.
    Mobility = { icon = "Dash", cooldown = 6, heldByLair = true, reach = 500, coneDegrees = 35 },
  },

  -- Its cries (cries.lua), from the voice its Blueprint brings with it (the SoldierBot sound pack).
  cries = {
    Roar = VOICES .. "ChatterShort/WAV/RobotChase_Cue.RobotChase_Cue",
    Curious = VOICES .. "ChatterShort/WAV/RobotSearch_Cue.RobotSearch_Cue",
    Call = VOICES .. "Aggro/WAV/WAV_SoldierBot_Aggro_v1a.WAV_SoldierBot_Aggro_v1a",
    Seen = VOICES .. "ChatterMicro/WAV/WAV_SoldierBot_ChatterMicro_v1f.WAV_SoldierBot_ChatterMicro_v1f",
    Escape = VOICES .. "EmoteNegative/WAV/WAV_SoldierBot_EmoteNegative_v1g.WAV_SoldierBot_EmoteNegative_v1g",
  },

  -- Its punch once the gatling is gone. Never its other close attack (atk_front03), which crushes the head of whoever
  -- it lands on: a kill the meter can't rule.
  swingMontage = MONTAGES .. "atk_front02_Montage.atk_front02_Montage",
  -- Its charge.
  dashMontage = MONTAGES .. "atk_dash1_Montage.atk_dash1_Montage",

  -- The grab that kills, which the kill meter rules (abilities.lua): the arm grab's sphere check calls GrabPlayer, and
  -- the grab montage later crushes the head (Decapitation) only while IsGrabPlayer is still set. Its light hit
  -- interrupts the montage, which lets go and clears it.
  killGrab = {
    functionName = "GrabPlayer (Multi)",
    breakMontage = MONTAGES .. "hit_light_front_Montage.hit_light_front_Montage",
  },
}

return terminator
