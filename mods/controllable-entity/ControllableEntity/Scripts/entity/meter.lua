-- Copyright © 2026 Jalapeno Labs

-- The kill meter and frenzy rules, as plain logic with no game calls, so they can be tested outside the game
-- (tests/meter_test.lua). The host owns one Meter for the entity player and feeds it time and events.
--
-- The rules (mods/controllable-entity/README.md):
-- - The meter fills over time, faster with noise nearby and in partial frenzy.
-- - A full meter can be armed (the ultimate). While armed, the next grab kills and empties the meter.
-- - In full frenzy every grab kills, but each kill re-arms only after a delay.

local Meter = {}
Meter.__index = Meter

Meter.frenzyLevels = {
  None = "None",
  -- Kill and capture contracts once a crew member has the special weapon: the meter fills faster.
  Partial = "Partial",
  -- Extraction (black box picked up) and self destruct (engines started): kills cost no meter.
  Full = "Full",
}

function Meter.new(settings)
  return setmetatable({
    settings = settings,
    value = 0,
    frenzy = Meter.frenzyLevels.None,
    armedUntil = nil,
    lastNoiseNearbyAt = nil,
    frenzyRearmedAt = 0,
  }, Meter)
end

function Meter:fillRate(now)
  local rate = 1 / self.settings.fillSeconds
  local heardRecently = self.lastNoiseNearbyAt and now - self.lastNoiseNearbyAt <= self.settings.noiseNearbyMemory
  if heardRecently then
    rate = rate * self.settings.noiseNearbyMultiplier
  end
  if self.frenzy == Meter.frenzyLevels.Partial then
    rate = rate * self.settings.partialFrenzyMultiplier
  end
  return rate
end

function Meter:advance(now, deltaSeconds)
  self.value = math.min(1, self.value + self:fillRate(now) * deltaSeconds)

  -- An armed kill that found no grab in time stands down; the meter stays full for the next try
  if self.armedUntil and now > self.armedUntil then
    self.armedUntil = nil
  end
end

function Meter:noteNoiseNearby(now)
  self.lastNoiseNearbyAt = now
end

-- Returns true when the ultimate armed; false (meter not full) leaves everything as it was.
function Meter:arm(now)
  if self.value < 1 then
    return false
  end
  self.armedUntil = now + self.settings.armedWindow
  return true
end

function Meter:isArmed(now)
  return self.armedUntil ~= nil and now <= self.armedUntil
end

-- Whether a grab that starts now ends in a kill.
function Meter:grabKills(now)
  if self.frenzy == Meter.frenzyLevels.Full then
    return now >= self.frenzyRearmedAt
  end
  return self:isArmed(now)
end

-- Called when a grab that `grabKills` allowed has started: spends the kill.
function Meter:spendKill(now)
  if self.frenzy == Meter.frenzyLevels.Full then
    self.frenzyRearmedAt = now + self.settings.frenzyRearm
    return
  end
  self.value = 0
  self.armedUntil = nil
end

-- Frenzy only escalates: once full, a later partial trigger (a special weapon picked up again) can't lower it.
function Meter:raiseFrenzy(level)
  local rank = { None = 0, Partial = 1, Full = 2 }
  if rank[level] <= rank[self.frenzy] then
    return false
  end
  self.frenzy = level
  return true
end

-- Seconds until the next frenzy kill is ready, for the HUD; 0 when ready or outside full frenzy.
function Meter:frenzyRearmRemaining(now)
  if self.frenzy ~= Meter.frenzyLevels.Full then
    return 0
  end
  return math.max(0, self.frenzyRearmedAt - now)
end

return Meter
