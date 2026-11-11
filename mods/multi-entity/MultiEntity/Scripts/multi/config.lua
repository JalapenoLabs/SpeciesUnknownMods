-- Copyright © 2026 Jalapeno Labs

-- Every tunable of the mod in one place. The host's copy decides the roll and the spawns; each machine's copy decides
-- the labels and the bonus it pays its own player, so every player should run the same version.

local config = {}

-- The contract modifiers, in the order they stack: a contract has the second entity before it can have the third.
-- The contract carries how many of them it has (see contracts.lua), so "the third needs the second" holds by
-- construction.
--
--   rowName            the modifier's row in the game's modifier tables; unique, so no game row is ever replaced
--   label              its name on every screen that lists modifiers
--   bounty             what it adds to the contract's bounty, like the game's own modifiers
--   chance             how likely an eligible contract is to get it, given it has every modifier before it
--   spawnDelaySeconds  when its entity arrives, counted from the moment the ship's power first comes on
config.modifiers = {
  {
    rowName = "MultiEntitySecond",
    label = "Second Entity",
    bounty = 2500,
    chance = 0.3,
    spawnDelaySeconds = 150,
  },
  {
    rowName = "MultiEntityThird",
    label = "Third Entity",
    bounty = 2500,
    chance = 0.4,
    spawnDelaySeconds = 240,
  },
}

-- The description each modifier shows when selected on the contract terminal. `%s` is the spawn delay, written out
-- (`2.5 minutes`), so the text always matches the timing above.
config.descriptionFormat = "Another specimen joins the hunt %s after the power comes on."

-- The extra entities are the mission's own species, so the special weapon the map places for its weakness works on
-- them too. The exceptions, by MonsterList value (game.monsterClassPaths): the Zombie Master's zombies each find
-- their master as the one Zombie Master in the map, and its zombie bodies are placed only for the mission's own, so
-- its extras are Mike (3), the game's baseline monster.
config.extraSpeciesInstead = {
  [6] = 3,
}

-- The icon the modifiers show: a game texture, so the mod needs no pak. The game's codex chimera reads as "a
-- creature" without naming one.
config.iconPath = "/Game/Materials/UI/HUD/ProgressCircle/Final/T_UI_chimeria_icon.T_UI_chimeria_icon"

return config
