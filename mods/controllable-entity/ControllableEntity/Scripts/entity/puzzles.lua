-- Copyright © 2026 Jalapeno Labs

-- The crew's puzzles, sized for the crew alone, on the host (playtest 9: in a two-player game the lone crew member
-- needed six keycards, where a crew of one needs four, and more engineering valves).
--
-- The game sizes each puzzle by the session's players (BP_MyGameInstance."OWNER Get Nb Expected Players": the lobby's
-- members, the entity player among them) as its level loads: Hawking's keycards (BP_ConsoleKeypass.Max), its
-- engineering pipes (BP_ERAccess_RiddleSystem.Start: how many of each pipe's eight valves start on) and Polar's raw
-- materials (BP_3DPrinterTerminal: the stock each printer starts with). Each goal is checked live, so once there is an
-- entity the host sizes each again for one player fewer, with the game's own numbers, whoever the entity is: the
-- host's pick, a volunteer, or a random pick made only once the monster appears. A puzzle is only ever made easier,
-- never harder: the game's numbers stop at four players.

local config = require("entity.config")
local game = require("entity.game")

local puzzles = {}

-- The game's own sizes, by players (0 counts as 1), from each puzzle's switch.
local KEYCARDS_BY_PLAYERS = { [0] = 4, [1] = 4, [2] = 6, [3] = 7, [4] = 8 }
local VALVES_ON_BY_PLAYERS = { [0] = 6, [1] = 6, [2] = 5, [3] = 4, [4] = 3 }
local STOCK_BY_PLAYERS = { [0] = 3.5, [1] = 3.5, [2] = 2.75, [3] = 0.9, [4] = 0.2 }
local MOST_SIZED_PLAYERS = 4

-- Each pipe's valves all start off until the riddle's Start sizes it.
local VALVES_PER_PIPE = 8
local PIPES = { "pipe1", "pipe2" }
local VALVES_ON_FIELD_BY_PIPE = { pipe1 = "nbActiveOnPipe1", pipe2 = "nbActiveOnPipe2" }

-- The replication indices the game marks dirty when it changes these (push-model replication: a change no one marks
-- never reaches the other machines).
local KEYPASS_MAX_INDEX = 12
local PRINTER_STOCK_INDEX = 15
local PUSH_MODEL_HELPERS = "/Script/Engine.Default__NetPushModelHelpers"

-- The puzzles in the current world, looked for again every config.areas.rescanSeconds (their sections stream in), and
-- the ones already sized for the crew, by address.
local world = { key = nil, nextScanAt = 0, keypasses = {}, riddles = {}, printers = {}, sized = {} }

local function markDirty(object, index, propertyName)
  StaticFindObject(PUSH_MODEL_HELPERS):MarkPropertyDirtyFromRepIndex(object, index, FName(propertyName))
end

-- The crew: the session's players as the game counts them for its puzzles, less the entity.
local function crewSize()
  local gameInstance = FindFirstOf(game.classNames.gameInstance)
  local out = {}
  gameInstance["OWNER Get Nb Expected Players"](gameInstance, out)
  return math.min(MOST_SIZED_PLAYERS, math.max(0, (out.nbExpected or 1) - 1))
end

-- The keycards: fewer to insert. If the crew already has enough in, the door opens as it would on the last card.
local function sizeKeypass(keypass, crew)
  local target = KEYCARDS_BY_PLAYERS[crew]
  if keypass.Max <= target then
    return true
  end
  keypass.Max = target
  markDirty(keypass, KEYPASS_MAX_INDEX, "Max")
  keypass:OnRep_Max()
  if keypass.Step == 0 and keypass.Current >= target then
    keypass:ForceOpen()
  end
  game.log("The crew needs %d keycards (sized for %d)", target, crew)
  return true
end

-- The pipes: more of each pipe's valves on, switched through the riddle's own gates (BP_ERAccess_RiddleSystem
-- .SetValveOn), which turn the valve and tell the reactor's terminal, whose check reads the gates. Waits for the
-- riddle's Start, which sizes it as the engineering section loads.
local function sizeRiddle(riddle, crew)
  if riddle.nbActiveOnPipe1 >= VALVES_PER_PIPE then
    return false
  end
  local target = VALVES_ON_BY_PLAYERS[crew]
  local switched = 0
  for _, pipe in ipairs(PIPES) do
    local missing = target - riddle[VALVES_ON_FIELD_BY_PIPE[pipe]]
    riddle[pipe]:ForEach(function(_, element)
      local valve = element:get()
      if missing <= 0 or not valve:IsValid() then
        return
      end
      local state = {}
      riddle:IsValveOn(valve, state)
      if not state.isOn then
        riddle:SetValveOn(valve, true)
        missing = missing - 1
        switched = switched + 1
      end
    end)
  end
  if switched > 0 then
    game.log("Turned %d more engineering valves on (sized for %d)", switched, crew)
  end
  return true
end

-- The raw materials: more stock to start with, never less.
local function sizePrinter(printer, crew)
  local target = STOCK_BY_PLAYERS[crew]
  if printer.nb_units_already_there >= target then
    return true
  end
  printer.nb_units_already_there = target
  markDirty(printer, PRINTER_STOCK_INDEX, "nb_units_already_there")
  printer:OnRep_nb_units_already_there()
  game.log("A printer starts with %.2f units of material (sized for %d)", target, crew)
  return true
end

local sizerByList = { keypasses = sizeKeypass, riddles = sizeRiddle, printers = sizePrinter }
local classNameByList = {
  keypasses = "BP_ConsoleKeypass_C",
  riddles = "BP_ERAccess_RiddleSystem_C",
  printers = "BP_3DPrinterTerminal_C",
}

-- Runs every second on the host. Once there is an entity, sizes every puzzle in the world for the crew alone, each
-- once, as it appears.
function puzzles.tickHost(entity)
  if not entity then
    return
  end
  local monster = entity.monster
  local worldKey = monster:GetWorld():GetAddress()
  local now = game.timeSeconds(monster)
  if worldKey ~= world.key then
    world = { key = worldKey, nextScanAt = 0, keypasses = {}, riddles = {}, printers = {}, sized = {} }
  end
  if now >= world.nextScanAt then
    world.nextScanAt = now + config.areas.rescanSeconds
    for list, className in pairs(classNameByList) do
      world[list] = FindAllOf(className) or {}
    end
  end

  local crew = nil
  for list, sizeFor in pairs(sizerByList) do
    for _, puzzle in ipairs(world[list]) do
      local address = puzzle:IsValid() and puzzle:GetAddress()
      if address and not world.sized[address] then
        crew = crew or crewSize()
        world.sized[address] = sizeFor(puzzle, crew)
      end
    end
  end
end

return puzzles
