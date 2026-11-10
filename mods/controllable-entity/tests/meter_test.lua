-- Copyright © 2026 Jalapeno Labs

-- Tests the kill meter rules outside the game. Run from the repository root:
--   lua mods/controllable-entity/tests/meter_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;" .. package.path

local Meter = require("entity.meter")
local config = require("entity.config")

local tests = {}

tests["fills in fillSeconds with nothing nearby"] = function()
  local meter = Meter.new(config.meter)
  meter:advance(0, config.meter.fillSeconds / 2)
  assert(math.abs(meter.value - 0.5) < 1e-9, meter.value)
  meter:advance(0, config.meter.fillSeconds)
  assert(meter.value == 1, "meter must cap at 1")
end

tests["fills faster while a noise was heard recently, then back to normal"] = function()
  local meter = Meter.new(config.meter)
  meter:noteNoiseNearby(10)
  meter:advance(11, 9)
  local expected = 9 / config.meter.fillSeconds * config.meter.noiseNearbyMultiplier
  assert(math.abs(meter.value - expected) < 1e-9, meter.value)

  local before = meter.value
  meter:advance(10 + config.meter.noiseNearbyMemory + 1, 9)
  assert(math.abs(meter.value - before - 9 / config.meter.fillSeconds) < 1e-9, "noise bonus must expire")
end

tests["arming needs a full meter"] = function()
  local meter = Meter.new(config.meter)
  meter.value = 0.99
  assert(not meter:arm(0), "a partial meter must not arm")
  assert(not meter:grabKills(0))
  meter.value = 1
  assert(meter:arm(0))
  assert(meter:grabKills(1))
end

tests["an armed kill stands down after the window but keeps the meter"] = function()
  local meter = Meter.new(config.meter)
  meter.value = 1
  meter:arm(0)
  meter:advance(config.meter.armedWindow + 0.1, 0.1)
  assert(not meter:grabKills(config.meter.armedWindow + 0.1))
  assert(meter.value == 1)
end

tests["spending an armed kill empties the meter"] = function()
  local meter = Meter.new(config.meter)
  meter.value = 1
  meter:arm(0)
  meter:spendKill(1)
  assert(meter.value == 0)
  assert(not meter:grabKills(1))
end

tests["full frenzy kills without meter, then re-arms after the delay"] = function()
  local meter = Meter.new(config.meter)
  assert(meter:raiseFrenzy(Meter.frenzyLevels.Full))
  assert(meter:grabKills(0), "first frenzy grab kills on an empty meter")
  meter:spendKill(0)
  assert(meter.value == 0)
  assert(not meter:grabKills(config.meter.frenzyRearm - 0.1), "must wait for the re-arm")
  assert(meter:frenzyRearmRemaining(1) > 0)
  assert(meter:grabKills(config.meter.frenzyRearm))
end

tests["partial frenzy speeds the meter up but grants no free kills"] = function()
  local meter = Meter.new(config.meter)
  meter:raiseFrenzy(Meter.frenzyLevels.Partial)
  meter:advance(0, 10)
  local expected = 10 / config.meter.fillSeconds * config.meter.partialFrenzyMultiplier
  assert(math.abs(meter.value - expected) < 1e-9, meter.value)
  assert(not meter:grabKills(0))
end

tests["frenzy only escalates"] = function()
  local meter = Meter.new(config.meter)
  meter:raiseFrenzy(Meter.frenzyLevels.Full)
  assert(not meter:raiseFrenzy(Meter.frenzyLevels.Partial))
  assert(meter.frenzy == Meter.frenzyLevels.Full)
end

local failures = 0
for name, test in pairs(tests) do
  local ok, message = pcall(test)
  if not ok then
    failures = failures + 1
    print("FAIL  " .. name .. ": " .. tostring(message))
  end
end

local total = 0
for _ in pairs(tests) do
  total = total + 1
end
print(string.format("%d/%d meter tests passed", total - failures, total))
os.exit(failures == 0 and 0 or 1)
