-- Copyright © 2026 Jalapeno Labs

-- The extra entities as contract modifiers: the host's roll onto a generated contract list, the bounty every machine
-- pays, the rows the screens read, and every contract screen drawing them. Run from the repository root:
--   lua mods/multi-entity/tests/contracts_test.lua

package.path = "mods/multi-entity/MultiEntity/Scripts/?.lua;mods/multi-entity/tests/?.lua;" .. package.path

local fake = require("fake_ue4ss")
fake.install()

local config = require("multi.config")
local contracts = require("multi.contracts")
local game = require("multi.game")
local screens = require("multi.screens")

local fields = game.contractFields
local libraryPath = game.paths.missionLibrary

local function contract(contractType, maxBounty, extraEntities)
  return { [fields.type] = contractType, [fields.maxBounty] = maxBounty, [fields.extraEntities] = extraEntities or 0 }
end

local function installTables()
  local modifierTable = fake.dataTable("ContractModifier_Data", {
    Turret = { name = "TurretsName", icon = "turret icon", bg = "threat colour", description = "TurretsDesc" },
  })
  local bountyTable = fake.dataTable("Addiitonal_Bounty_DataTable", {
    Turret = { [game.bountyRowFields.maxBounty] = 800, [game.bountyRowFields.defaultValue] = 0 },
  })
  fake.objects[game.paths.modifierTable] = modifierTable
  fake.objects[game.paths.bountyTable] = bountyTable
  return modifierTable, bountyTable
end

contracts.register()
screens.register()

-- The library has no instances: its hooks wait for the terminal, which calls it
fake.loadClassQuietly(libraryPath)
assert(fake.hooks[libraryPath .. ":GenerateContracts"] == nil, "the library's hooks wait for a class that calls it")
fake.spawnInstanceOf(game.paths.contractTerminal)
assert(fake.hooks[libraryPath .. ":GenerateContracts"], "the terminal appearing hooks the library")
assert(fake.hooks[libraryPath .. ":GetConditionalCombinedBounty"])

local tests = {}

tests["the host rolls extra entities onto the generated list, never onto capture"] = function()
  local chances = { config.modifiers[1].chance, config.modifiers[2].chance }
  config.modifiers[1].chance, config.modifiers[2].chance = 1, 1
  fake.isHost = true

  local generated = {
    contract(game.contractTypes.Elimination, 9000),
    contract(game.contractTypes.Capture, 12000),
    contract(game.contractTypes.Extraction, 7000),
  }
  fake.runHook(libraryPath .. ":GenerateContracts", fake.param(nil), fake.param(false), fake.param(nil),
    fake.param(generated))

  config.modifiers[1].chance, config.modifiers[2].chance = chances[1], chances[2]
  assert(generated[1][fields.extraEntities] == 2, generated[1][fields.extraEntities])
  assert(generated[1][fields.maxBounty] == 14000, "the bounty shown includes both modifiers")
  assert(generated[2][fields.extraEntities] == 0, "capture contracts keep one entity")
  assert(generated[2][fields.maxBounty] == 12000)
  assert(generated[3][fields.extraEntities] == 2)
end

tests["a client never rolls: the host's list replaces its stand-in"] = function()
  fake.isHost = false
  local generated = { contract(game.contractTypes.Elimination, 9000) }
  local chance = config.modifiers[1].chance
  config.modifiers[1].chance = 1
  fake.runHook(libraryPath .. ":GenerateContracts", fake.param(nil), fake.param(false), fake.param(nil),
    fake.param(generated))
  config.modifiers[1].chance = chance
  fake.isHost = true
  assert(generated[1][fields.extraEntities] == 0)
  assert(generated[1][fields.maxBounty] == 9000)
end

tests["every machine pays the extra entities with the contract's other conditions"] = function()
  local bounty = fake.param(1200)
  fake.runHook(libraryPath .. ":GetConditionalCombinedBounty", fake.param(nil),
    fake.param(contract(game.contractTypes.Destruction, 0, 1)), fake.param(nil), bounty)
  assert(bounty:get() == 3700, bounty:get())

  local stock = fake.param(1200)
  fake.runHook(libraryPath .. ":GetConditionalCombinedBounty", fake.param(nil),
    fake.param(contract(game.contractTypes.Destruction, 0, 0)), fake.param(nil), stock)
  assert(stock:get() == 1200, "a stock contract pays as before")
end

tests["the modifier rows clone the template, with the mod's text, icon and bounty"] = function()
  fake.objects[game.paths.modifierTable], fake.objects[game.paths.bountyTable] = nil, nil
  assert(contracts.ensureRows() == false, "nothing to do before the tables load")

  local modifierTable, bountyTable = installTables()
  local icon = fake.object("Texture2D")
  fake.objects[config.iconPath] = icon
  assert(contracts.ensureRows())

  local display = modifierTable.rows.MultiEntitySecond
  assert(display[game.modifierRowFields.name].text == "Second Entity")
  assert(display[game.modifierRowFields.description].text:match("2.5 minutes"))
  assert(display[game.modifierRowFields.icon] == icon)
  assert(display.bg == "threat colour", "fields the mod doesn't set come from the template")
  assert(modifierTable.rows.MultiEntityThird[game.modifierRowFields.name].text == "Third Entity")
  assert(modifierTable.rows.Turret.name == "TurretsName", "the template row is untouched")

  local payout = bountyTable.rows.MultiEntityThird
  assert(payout[game.bountyRowFields.maxBounty] == 2500)
  assert(payout[game.bountyRowFields.minValue] == 0 and payout[game.bountyRowFields.maxValue] == 1)
  assert(payout[game.bountyRowFields.defaultValue] == 0)

  -- A later pass keeps the same rows and writes the config again (a hot reload with a changed label)
  config.modifiers[1].label = "Two Specimens"
  assert(contracts.ensureRows())
  config.modifiers[1].label = "Second Entity"
  assert(modifierTable.rows.MultiEntitySecond == display, "the row is reused, not cloned again")
  assert(display[game.modifierRowFields.name].text == "Two Specimens")
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Screens
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function hookOn(classPath, functionName)
  fake.spawnInstanceOf(classPath)
  return classPath .. ":" .. functionName
end

local function lineFactory()
  return function(self, rowName, lineOut, rowNameOut)
    lineOut.line = fake.object("Line", { row = rowName:ToString() })
    rowNameOut.rowNameOutput = rowName
    table.insert(fake.calls, { object = self, method = "CreateLineModifier", args = { rowName:ToString() } })
  end
end

tests["the contract card adds an icon per extra entity"] = function()
  installTables()
  local box = fake.object("WrapBox")
  local card = fake.object("WBP_ContractCard_C", {
    contractData = contract(game.contractTypes.Elimination, 0, 2),
    modifiers_wbox = box,
  }, {
    CreateBoolModifier = function(_, rowName, out) out.modifier = "icon:" .. rowName:ToString() end,
  })
  fake.runHook(hookOn(game.paths.contractCard, "Setup"), fake.param(card), fake.param(card.contractData))

  local added = fake.callsTo(box, "AddChild")
  assert(#added == 2, #added)
  assert(added[1].args[1] == "icon:MultiEntitySecond" and added[2].args[1] == "icon:MultiEntityThird")

  card.contractData = contract(game.contractTypes.Elimination, 0, 0)
  fake.runHook(hookOn(game.paths.contractCard, "Setup"), fake.param(card), fake.param(card.contractData))
  assert(#fake.callsTo(box, "AddChild") == 2, "a stock contract gets no extra icons")
end

tests["the detail page adds a selectable line after the game's own"] = function()
  installTables()
  local slot = fake.object("ScrollBoxSlot")
  local scrollBox = fake.object("ScrollBox", nil, { AddChild = function() return slot end })
  local stockLine = fake.object("Line")
  local page = fake.object("WBP_Contract_DetailPage_C", {
    proxyContract = contract(game.contractTypes.Extraction, 0, 1),
    listOfModifKeys = { fake.name("Difficulty") },
    listOfModifLines = { stockLine },
    modifiers_scroll_box = scrollBox,
  }, { CreateLineModifier = lineFactory() })
  fake.runHook(hookOn(game.paths.contractDetailPage, "Setup Contract Detail Page"), fake.param(page),
    fake.param(page.proxyContract))

  assert(#page.listOfModifLines == 2 and page.listOfModifLines[1] == stockLine)
  assert(page.listOfModifKeys[2]:ToString() == "MultiEntitySecond", "its key selects its description")
  local selectable = fake.callsTo(page, "MakeModifLineSelectable")
  assert(#selectable == 1)
  assert(selectable[1].args[1] == page.listOfModifLines[2] and selectable[1].args[2] == 1, "a 0-based index")
  assert(fake.callsTo(slot, "SetPadding")[1].args[1].Top == 5)
end

tests["the mission brief lays the lines out in the game's two columns"] = function()
  installTables()
  local wrapBox = fake.object("WrapBox")
  local list = fake.object("UMG_ObjectiveList_C", {
    listOfModifKeys = { fake.name("Difficulty"), fake.name("Respawn"), fake.name("Power") },
    listOfModifLines = { fake.object("Line"), fake.object("Line"), fake.object("Line") },
    WrapBox_Modifier = wrapBox,
  }, { CreateLineModifier = lineFactory() })
  local brief = contract(game.contractTypes.Elimination, 0, 2)
  fake.runHook(hookOn(game.paths.objectiveList, "Create Modifier List"), fake.param(list), fake.param(brief))

  assert(#list.listOfModifLines == 5)
  -- Lines 3 and 4 (0-based): the right column, then the left
  local right = fake.callsTo(list.listOfModifLines[4], "SetPadding")[1].args[1]
  local left = fake.callsTo(list.listOfModifLines[5], "SetPadding")[1].args[1]
  assert(right.Right == 0 and left.Right == 10, "padding follows the column")
  assert(right.Bottom == 10 and left.Bottom == 10)
end

tests["the mission start page and the score page list them too"] = function()
  installTables()
  local column = fake.object("VerticalBox")
  local startPage = fake.object("WBP_MissionStart_Page_C", {
    listOfModifKeys = {},
    listOfModifLines = {},
    VerticalBox_MofifierList = column,
  }, { CreateLineModifier = lineFactory() })
  fake.runHook(hookOn(game.paths.missionStartPage, "Set Up Additional"), fake.param(startPage),
    fake.param(contract(game.contractTypes.Destruction, 0, 2)))
  assert(#fake.callsTo(column, "AddChild") == 2)
  assert(#startPage.listOfModifKeys == 2)

  local scorePage = fake.object("WBP_ScorePage_C", { Contract = contract(game.contractTypes.Destruction, 0, 1) })
  fake.runHook(hookOn(game.paths.scorePage, "FinishSetupModifiers"), fake.param(scorePage))
  local icons = fake.callsTo(scorePage, "CreateBoolModifier")
  assert(#icons == 1 and icons[1].args[1]:ToString() == "MultiEntitySecond")
end

tests["a screen that fails is logged, not raised into the game"] = function()
  installTables()
  local card = fake.object("WBP_ContractCard_C", { contractData = contract(game.contractTypes.Elimination, 0, 1) },
    { CreateBoolModifier = function() error("widget gone") end })
  local printed = {}
  local originalPrint = print
  _G.print = function(text) table.insert(printed, text) end
  fake.runHook(hookOn(game.paths.contractCard, "Setup"), fake.param(card), fake.param(card.contractData))
  _G.print = originalPrint

  local reported = false
  for _, line in ipairs(printed) do
    reported = reported or line:match("The contract card failed: .*widget gone") ~= nil
  end
  assert(reported, "the failure must be logged: " .. table.concat(printed))
end

local failures = 0
local total = 0
for name, test in pairs(tests) do
  total = total + 1
  fake.calls = {}
  local succeeded, message = pcall(test)
  if not succeeded then
    failures = failures + 1
    print("FAIL  " .. name .. ": " .. tostring(message))
  end
end
print(string.format("%d/%d contracts tests passed", total - failures, total))
os.exit(failures == 0 and 0 or 1)
