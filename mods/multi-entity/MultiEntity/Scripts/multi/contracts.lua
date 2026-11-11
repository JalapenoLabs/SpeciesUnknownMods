-- Copyright © 2026 Jalapeno Labs

-- The extra entities as contract modifiers: the host rolls them onto new contracts, and every machine pays their
-- bounty and gives them rows in the game's modifier tables, which the contract screens read (see screens.lua).

local config = require("multi.config")
local game = require("multi.game")
local rules = require("multi.rules")

local contracts = {}

local fields = game.contractFields

-- How many extra entities a contract carries, from its replicated field.
function contracts.extraEntitiesOf(contract)
  return rules.normalizeCount(contract[fields.extraEntities])
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The roll, on the host
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- BP_Mission_FunctionLibrairy.GenerateContracts builds the contract list for the lobby's terminal. This post-hook
-- edits the list in its out parameter, which is the caller's own variable, before the terminal stores it in its
-- replicated generatedContracts and hands it to the other terminal and the screens. The game raises nothing here:
-- the roll only adds a count and its bounty to contracts the game already balanced.
local function onContractsGenerated(_, _, _, contractsParam)
  if not game.isHost() then
    -- A client's screen generates a stand-in list only while the host's hasn't arrived; the host's list replaces it
    return
  end

  local contractList = contractsParam:get()
  local rolled = 0
  for index = 1, #contractList do
    local contract = contractList[index]
    local count = rules.rollExtraEntities(contract[fields.type], math.random)
    contract[fields.extraEntities] = count
    contract[fields.maxBounty] = contract[fields.maxBounty] + rules.bonusFor(count)

    -- Read back: the array element is the game's memory, so the write must show through it
    if count > 0 then
      rolled = rolled + 1
      game.log("Contract %d: extra entities %d, bounty %d", index, contracts.extraEntitiesOf(contract),
        contract[fields.maxBounty])
    end
  end
  game.log("Rolled extra entities onto %d of %d contracts", rolled, #contractList)
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The bounty, on every machine
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- BP_Mission_FunctionLibrairy.GetConditionalCombinedBounty adds up what a contract's modifiers pay. The score
-- screen pays each player from it on their own machine (WBP_ScorePage.SetUpBaseMission, then the seat's AddMoney),
-- so the extra entities pay out wherever the mod is installed, under the screen's "additional conditions" line, like
-- the game's own modifiers. The host's roll above runs after generation's own calls to it, so nothing counts twice.
local function onCombinedBounty(_, contractParam, _, bountyParam)
  local count = contracts.extraEntitiesOf(contractParam:get())
  if count == 0 then
    return
  end
  bountyParam:set(bountyParam:get() + rules.bonusFor(count))
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The modifier tables, on every machine
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local reportedProblems = {}

local function reportOnce(key, message, ...)
  if reportedProblems[key] then
    return
  end
  reportedProblems[key] = true
  game.log(message, ...)
end

local function loadIcon()
  local icon = StaticFindObject(config.iconPath)
  if icon and icon:IsValid() then
    return icon
  end
  LoadAsset(config.iconPath)
  icon = StaticFindObject(config.iconPath)
  if icon and icon:IsValid() then
    return icon
  end
  reportOnce("icon", "Could not load %s; the modifiers keep the template's icon", config.iconPath)
  return nil
end

-- The row named `rowName` in `dataTable`, by reference: the existing one, or a new one cloned from the game's
-- template modifier. Nil when the table has no template to clone.
local function rowFor(dataTable, rowName)
  local existing = dataTable:FindRow(rowName)
  if existing then
    return existing
  end

  local tableName = dataTable:GetFName():ToString()
  local template = dataTable:FindRow(game.templateModifierRow)
  if not template then
    reportOnce("template:" .. tableName, "%s has no %s row to clone; the modifiers can't show", tableName,
      game.templateModifierRow)
    return nil
  end
  dataTable:AddRow(rowName, template)
  game.log("Added the %s row to %s", rowName, tableName)
  return dataTable:FindRow(rowName)
end

-- Gives each modifier its rows in ContractModifier_Data (name, icon, description) and Addiitonal_Bounty_DataTable
-- (its bounty, paid at value 1), which every contract screen reads by row name. Runs before each screen draws the
-- modifiers: data tables are assets, so the game can unload one and load it fresh, and writing the fields each time
-- also applies a changed config.lua after a hot reload. False when the tables aren't loaded.
function contracts.ensureRows()
  local modifierTable = StaticFindObject(game.paths.modifierTable)
  local bountyTable = StaticFindObject(game.paths.bountyTable)
  if not modifierTable or not modifierTable:IsValid() or not bountyTable or not bountyTable:IsValid() then
    reportOnce("tables", "The modifier tables aren't loaded; skipping the extra entities' rows")
    return false
  end

  local icon = loadIcon()
  for _, modifier in ipairs(config.modifiers) do
    local displayRow = rowFor(modifierTable, modifier.rowName)
    if displayRow then
      displayRow[game.modifierRowFields.name] = FText(modifier.label)
      displayRow[game.modifierRowFields.description] = FText(rules.descriptionOf(modifier))
      if icon then
        displayRow[game.modifierRowFields.icon] = icon
      end
    end

    local bountyRow = rowFor(bountyTable, modifier.rowName)
    if bountyRow then
      bountyRow[game.bountyRowFields.minValue] = 0
      bountyRow[game.bountyRowFields.maxValue] = 1
      bountyRow[game.bountyRowFields.minBounty] = 0
      bountyRow[game.bountyRowFields.maxBounty] = modifier.bounty
      bountyRow[game.bountyRowFields.defaultValue] = 0
    end
  end
  return true
end

function contracts.register()
  -- The terminal calls GenerateContracts and the score page GetConditionalCombinedBounty, so the library is loaded
  -- once either exists
  local loadedWith = { game.paths.contractTerminal, game.paths.scorePage }
  game.hookWhenLoaded(game.paths.missionLibrary, "GenerateContracts",
    game.guarded("Rolling extra entities", onContractsGenerated), loadedWith)
  game.hookWhenLoaded(game.paths.missionLibrary, "GetConditionalCombinedBounty",
    game.guarded("Adding the extra entities' bounty", onCombinedBounty), loadedWith)
end

return contracts
