-- Copyright © 2026 Jalapeno Labs

-- Mike (BP_Monster_Michel): a fast vent ambusher with no leap. He swipes, dodges aside, and kills by grabbing a crew
-- member and eating their face.

local MONTAGES = "/Game/BossMichel/"
local VOICES = "/Game/MonsterSoundFXPack2/wav/Monsters/Monster_07/"

local mike = {
  id = "Mike",
  displayName = "Mike",
  -- MonsterList value (BP_Lobby_FunctionLibrairy.GetMonsterSoftClass): what the game manager spawns for him.
  monsterType = 3,
  className = "BP_Monster_Michel_C",
  classPath = "/Game/Blueprints/Monsters/BP_Monster_Michel.BP_Monster_Michel_C",
  -- The codex's animated portrait of him (a UI material), for the host's picker.
  portrait = "/Game/Blueprints/Screens/Terminals/CodexExtended/SpriteSheet/"
    .. "Mike_Spritesheet_Mat_Inst2.Mike_Spritesheet_Mat_Inst2",
  -- He lives in the vents: the lair, the hunt's vent time, crawl openings and the vent markers all apply.
  usesVents = true,

  -- One pool: his Health (350), which only hits to his head drain, and only while it is open. Electrocution
  -- (DamageType_Electrocut, his weakness) stuns him and opens it, so "downed" is Electrocuted. Each time Health runs
  -- out a face breaks and it refills (to 1.5 times after the second), and the third time he dies; the HUD clamps the
  -- overfull pool.
  healthFields = {
    health = "Health",
    maxHealth = "MaxHealth",
    downed = "Electrocuted",
  },

  -- What the HUD's action stack shows for each of his moves (moves/mike.lua), the cooldown each starts, and whether
  -- the lair holds it back until the power is on.
  moves = {
    -- The swipe lands on the crew member nearest the aim within this reach and cone.
    Primary = { icon = "Swipe", cooldown = 1.2, reach = 350, coneDegrees = 60 },
    -- The dodge carries him this far aside, inside the 250 to 350 units his own dodges cover.
    Secondary = { icon = "Dodge", cooldown = 4, heldByLair = true, distance = 300 },
    -- The grab takes the crew member nearest the aim within this reach and cone: close, since it pulls them to him.
    Ultimate = { icon = "Devour", cooldown = 6, heldByLair = true, reach = 220, coneDegrees = 70 },
    Mobility = { icon = "Vent", cooldown = 1 },
  },

  -- His cries (cries.lua), from his own voice slots (BP_Monster_Michel's PlayVoiceType cues). Several are plain
  -- SoundWaves, which the voice plays the same way.
  cries = {
    -- His chase roar (voice type 3)
    Roar = VOICES .. "MonsterPack2_Monster07_Roar07_Cue.MonsterPack2_Monster07_Roar07_Cue",
    -- His search (type 0)
    Curious = VOICES .. "MonsterPack2_Monster07_Serching_Cue.MonsterPack2_Monster07_Serching_Cue",
    -- His searching call (type 8)
    Call = VOICES .. "MonsterPack2_Monster07_Roar05.MonsterPack2_Monster07_Roar05",
    -- His "seen you" (type 2)
    Seen = VOICES .. "MonsterPack2_Monster07_Grunt13.MonsterPack2_Monster07_Grunt13",
    -- His escape roar (type 6), as the stun wears off
    Escape = VOICES .. "MonsterPack2_Monster07_Roar14.MonsterPack2_Monster07_Roar14",
  },

  -- His swipes at a standing target (GetAttackSimpleAnim picks one at random; a crouched target gets the grab).
  swingMontage = MONTAGES .. "Anim/BossMichel_Anim_Attack_1_Montage.BossMichel_Anim_Attack_1_Montage",

  -- The grab that kills, which the kill meter rules (abilities.lua). Every grab goes through GrabPlayerVent: the
  -- swipe at a crouched crew member and the ultimate. The face-eating kill fires 2.18 seconds into the eating
  -- montage (AnimNotify_EatFace), and checks only that he still holds someone, so the break is his front hit: it
  -- interrupts the montage on every machine, which lets go and clears what he holds.
  killGrab = {
    functionName = "GrabPlayerVent ( Multi)",
    breakMontage = MONTAGES .. "Hit/BossMichel_Anim_Hit_Front_1_Montage.BossMichel_Anim_Hit_Front_1_Montage",
  },
}

return mike
