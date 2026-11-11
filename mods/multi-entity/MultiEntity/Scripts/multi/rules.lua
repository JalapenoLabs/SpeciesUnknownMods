-- Copyright © 2026 Jalapeno Labs

-- The mod's rules as plain logic, with no game objects, so they can be tested on their own: which contracts may carry
-- extra entities, how many one gets, what they pay, and when each one arrives.

local config = require("multi.config")
local game = require("multi.game")

local rules = {}

rules.maximumExtraEntities = #config.modifiers

-- Multiple entities never join capture contracts: the crew must bring one specimen back alive, and the game's
-- capture flow (the cell, the respawn after a capture) tracks only one.
function rules.isEligible(contractType)
  return contractType ~= game.contractTypes.Capture
end

-- How many extra entities a new contract gets. Each modifier is rolled only if every one before it was granted, so a
-- third entity always comes with a second. `random` returns a number in [0, 1), like math.random().
function rules.rollExtraEntities(contractType, random)
  if not rules.isEligible(contractType) then
    return 0
  end

  local count = 0
  for _, modifier in ipairs(config.modifiers) do
    if random() >= modifier.chance then
      break
    end
    count = count + 1
  end
  return count
end

-- The count a contract carries, read from a replicated field: anything outside [0, maximum] (a stock contract's 0, a
-- value from a newer version of the mod) is clamped rather than trusted.
function rules.normalizeCount(rawCount)
  local count = math.floor(tonumber(rawCount) or 0)
  return math.max(0, math.min(count, rules.maximumExtraEntities))
end

-- The modifiers a contract with `count` extra entities shows, in order.
function rules.activeModifiers(count)
  local active = {}
  for index = 1, rules.normalizeCount(count) do
    table.insert(active, config.modifiers[index])
  end
  return active
end

-- What a contract's extra entities add to its bounty.
function rules.bonusFor(count)
  local bonus = 0
  for _, modifier in ipairs(rules.activeModifiers(count)) do
    bonus = bonus + modifier.bounty
  end
  return bonus
end

-- How many of a contract's extra entities should be in the mission `secondsSincePower` after the power first came
-- on (nil while it hasn't).
function rules.extrasDue(count, secondsSincePower)
  if secondsSincePower == nil then
    return 0
  end

  local due = 0
  for _, modifier in ipairs(rules.activeModifiers(count)) do
    if secondsSincePower >= modifier.spawnDelaySeconds then
      due = due + 1
    end
  end
  return due
end

-- A delay written out for players: 150 -> "2.5 minutes", 240 -> "4 minutes", 45 -> "45 seconds".
function rules.describeDelay(seconds)
  if seconds < 60 then
    return string.format("%d seconds", seconds)
  end

  local minutes = seconds / 60
  local rounded = math.floor(minutes * 10 + 0.5) / 10
  local text = string.format("%.1f", rounded):gsub("%.0$", "")
  if text == "1" then
    return "1 minute"
  end
  return text .. " minutes"
end

function rules.descriptionOf(modifier)
  return string.format(config.descriptionFormat, rules.describeDelay(modifier.spawnDelaySeconds))
end

return rules
