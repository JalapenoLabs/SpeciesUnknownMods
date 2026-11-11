-- Copyright © 2026 Jalapeno Labs

-- The mod's rules outside the game: eligibility, the roll, the bounty and the arrival schedule. Run from the
-- repository root:
--   lua mods/multi-entity/tests/rules_test.lua

package.path = "mods/multi-entity/MultiEntity/Scripts/?.lua;" .. package.path

local config = require("multi.config")
local game = require("multi.game")
local rules = require("multi.rules")

-- A random source that returns the given values in turn
local function sequence(...)
  local values = { ... }
  local index = 0
  return function()
    index = index + 1
    return values[index]
  end
end

local second, third = config.modifiers[1], config.modifiers[2]

local tests = {}

tests["capture contracts never get extra entities"] = function()
  assert(not rules.isEligible(game.contractTypes.Capture))
  assert(rules.rollExtraEntities(game.contractTypes.Capture, sequence(0, 0)) == 0)
  for _, contractType in ipairs({ "Elimination", "Destruction", "Extraction" }) do
    assert(rules.isEligible(game.contractTypes[contractType]), contractType .. " must be eligible")
  end
end

tests["the roll grants a modifier below its chance"] = function()
  local elimination = game.contractTypes.Elimination
  assert(rules.rollExtraEntities(elimination, sequence(second.chance)) == 0, "the chance is exclusive")
  assert(rules.rollExtraEntities(elimination, sequence(second.chance - 0.01, third.chance)) == 1)
  assert(rules.rollExtraEntities(elimination, sequence(0, third.chance - 0.01)) == 2)
end

tests["a third entity needs the second: a failed second roll stops there"] = function()
  local rolls = 0
  local count = rules.rollExtraEntities(game.contractTypes.Extraction, function()
    rolls = rolls + 1
    -- Fails the second's roll, and would grant the third's
    return rolls == 1 and 0.99 or 0
  end)
  assert(count == 0, count)
  assert(rolls == 1, "the third must not be rolled without the second")
end

tests["each extra entity pays its bounty"] = function()
  assert(rules.bonusFor(0) == 0)
  assert(rules.bonusFor(1) == 2500, rules.bonusFor(1))
  assert(rules.bonusFor(2) == 5000, rules.bonusFor(2))
end

tests["a replicated count outside the range is clamped"] = function()
  assert(rules.normalizeCount(nil) == 0)
  assert(rules.normalizeCount(-3) == 0)
  assert(rules.normalizeCount(7) == rules.maximumExtraEntities)
  assert(#rules.activeModifiers(7) == 2)
  assert(rules.activeModifiers(1)[1] == second)
end

tests["the second arrives 2.5 minutes after the power, the third at 4"] = function()
  assert(second.spawnDelaySeconds == 150 and third.spawnDelaySeconds == 240)
  assert(rules.extrasDue(2, nil) == 0, "nothing arrives before the power comes on")
  assert(rules.extrasDue(2, 149) == 0)
  assert(rules.extrasDue(2, 150) == 1)
  assert(rules.extrasDue(2, 239) == 1)
  assert(rules.extrasDue(2, 240) == 2)
  assert(rules.extrasDue(1, 1000) == 1, "a contract with one extra entity never gets a second")
  assert(rules.extrasDue(0, 1000) == 0)
end

tests["the descriptions spell out the delay"] = function()
  assert(rules.describeDelay(150) == "2.5 minutes", rules.describeDelay(150))
  assert(rules.describeDelay(240) == "4 minutes", rules.describeDelay(240))
  assert(rules.describeDelay(60) == "1 minute", rules.describeDelay(60))
  assert(rules.describeDelay(45) == "45 seconds", rules.describeDelay(45))
  assert(rules.descriptionOf(second) == "Another specimen joins the hunt 2.5 minutes after the power comes on.",
    rules.descriptionOf(second))
end

local failures = 0
local total = 0
for name, test in pairs(tests) do
  total = total + 1
  local succeeded, message = pcall(test)
  if not succeeded then
    failures = failures + 1
    print("FAIL  " .. name .. ": " .. tostring(message))
  end
end
print(string.format("%d/%d rules tests passed", total - failures, total))
os.exit(failures == 0 and 0 or 1)
