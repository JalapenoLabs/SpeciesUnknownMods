-- Copyright © 2026 Jalapeno Labs

-- The crew's puzzles, sized for the crew alone once there is an entity (playtest 9: a lone crew member needed six
-- keycards, as for two players). The game sizes them by the session's players, the entity's included; the host sizes
-- each again for one fewer with the game's own numbers, only ever easier, each once, as it appears.
-- Run from the repository root: lua mods/controllable-entity/tests/puzzles_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local config = require("entity.config")
local game = require("entity.game")
local puzzles = require("entity.puzzles")

fake.world = fake.object("World")
fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
local dirty = {}
fake.objects["/Script/Engine.Default__NetPushModelHelpers"] = fake.object("NetPushModelHelpers", nil, {
  MarkPropertyDirtyFromRepIndex = function(_, object, index, name)
    table.insert(dirty, { object = object, index = index, name = name:ToString() })
  end,
})

-- Two players in the session: one crew member and the entity
local players = 2
fake.object("BP_MyGameInstance_C", nil, {
  ["OWNER Get Nb Expected Players"] = function(_, out) out.nbExpected = players end,
})
local entity = { monster = fake.object("BP_Monster_Poulpi_C") }

-- Hawking's keypass, sized by the game for two players
local keypass = fake.object("BP_ConsoleKeypass_C", { Max = 6, Current = 0, Step = 0 })
keypass.OnRep_Max = function(self) table.insert(fake.calls, { object = self, method = "OnRep_Max", args = {} }) end
keypass.ForceOpen = function(self) table.insert(fake.calls, { object = self, method = "ForceOpen", args = {} }) end

puzzles.tickHost(nil)
assert(keypass.Max == 6, "nothing changes before there is an entity")
fake.now = 10
puzzles.tickHost(entity)
assert(keypass.Max == 4, "a lone crew member needs four keycards, as the game asks of one player")
assert(#fake.callsTo(keypass, "OnRep_Max") == 1 and dirty[1].object == keypass and dirty[1].index == 12,
  "and every machine is told")
assert(#fake.callsTo(keypass, "ForceOpen") == 0, "the door stays shut with no cards in")
puzzles.tickHost(entity)
assert(#fake.callsTo(keypass, "OnRep_Max") == 1, "sized once")

-- Hawking's engineering pipes, once their section has loaded and the riddle has sized them for two players: five of
-- each pipe's eight valves on. Sized for one, six are: one more on each pipe, through the riddle's own gates
local gateOn = {}
local function valve(isOn)
  local object = fake.object("BP_ValvePipe_C")
  gateOn[object] = isOn
  return object
end
local function pipe(onCount)
  local valves = {}
  for index = 1, 8 do
    table.insert(valves, valve(index <= onCount))
  end
  return valves
end
local pipe1, pipe2 = pipe(5), pipe(5)
local riddle = fake.object("BP_ERAccess_RiddleSystem_C", {
  nbActiveOnPipe1 = 8,
  nbActiveOnPipe2 = 8,
  pipe1 = fake.array(pipe1),
  pipe2 = fake.array(pipe2),
}, {
  IsValveOn = function(_, valveObject, out) out.isOn = gateOn[valveObject] end,
  SetValveOn = function(_, valveObject, on) gateOn[valveObject] = on end,
})
local function onCount(valves)
  local count = 0
  for _, valveObject in ipairs(valves) do
    count = count + (gateOn[valveObject] and 1 or 0)
  end
  return count
end
fake.now = fake.now + config.areas.rescanSeconds
puzzles.tickHost(entity)
assert(onCount(pipe1) == 5, "the riddle is left alone until its Start has sized it")
riddle.nbActiveOnPipe1, riddle.nbActiveOnPipe2 = 5, 5
puzzles.tickHost(entity)
assert(onCount(pipe1) == 6 and onCount(pipe2) == 6, "one more valve on each pipe")
puzzles.tickHost(entity)
assert(onCount(pipe1) == 6, "once")

-- Polar's printers start with the stock the game gives one player
local printer = fake.object("BP_3DPrinterTerminal_C", { nb_units_already_there = 2.75 })
printer.OnRep_nb_units_already_there = function(self)
  table.insert(fake.calls, { object = self, method = "OnRep_nb_units_already_there", args = {} })
end
fake.now = fake.now + config.areas.rescanSeconds
puzzles.tickHost(entity)
assert(printer.nb_units_already_there == 3.5, "a printer starts with a lone player's stock")
assert(#fake.callsTo(printer, "OnRep_nb_units_already_there") == 1 and dirty[#dirty].index == 15, "told everywhere")

-- A crew that already has enough keycards in gets its door as on the last card
fake.world = fake.object("World")
local fullKeypass = fake.object("BP_ConsoleKeypass_C", { Max = 6, Current = 5, Step = 0 })
fullKeypass.OnRep_Max = function() end
fullKeypass.ForceOpen = function(self) table.insert(fake.calls, { object = self, method = "ForceOpen", args = {} }) end
keypass.destroyed = true
puzzles.tickHost(entity)
assert(fullKeypass.Max == 4 and #fake.callsTo(fullKeypass, "ForceOpen") == 1, "enough cards in: the door opens")

-- A puzzle is never made harder: past four players the game's numbers aren't known
players = 6
fake.world = fake.object("World")
local bigKeypass = fake.object("BP_ConsoleKeypass_C", { Max = 0, Current = 0, Step = 0 })
local OnRepCalls = 0
bigKeypass.OnRep_Max = function() OnRepCalls = OnRepCalls + 1 end
fullKeypass.destroyed = true
puzzles.tickHost(entity)
assert(bigKeypass.Max == 0 and OnRepCalls == 0, "a keypass the game made easier stays so")

print("puzzles test passed")
