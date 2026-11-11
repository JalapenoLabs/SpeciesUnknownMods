-- Copyright © 2026 Jalapeno Labs

-- The extra entities on every screen that lists a contract's modifiers, on any machine with the mod. Each screen
-- builds its list from the game's own modifiers, then a post-hook here adds the mod's through that screen's own
-- helper (CreateBoolModifier or CreateLineModifier), which reads the rows contracts.ensureRows adds, so they look
-- like the game's: the same icon frame, the same line with its bounty, the same description when selected.
--
-- The game builds these lists only from modifiers in its GlobalModifiersStatus_DT, and reads each one's value
-- through a switch over its own names, so a new name added there would never show. The mod's rows stay out of that
-- table, which also keeps them out of contract generation.

local contracts = require("multi.contracts")
local game = require("multi.game")
local rules = require("multi.rules")

local screens = {}

-- The modifiers to draw for a contract, or none when the tables can't take them yet.
local function modifiersToDraw(contract)
  local count = contracts.extraEntitiesOf(contract)
  if count == 0 or not contracts.ensureRows() then
    return {}
  end
  return rules.activeModifiers(count)
end

-- Appends to a Blueprint array (TArray, 1-based in Lua; writing one past the end grows it).
local function append(array, value)
  array[#array + 1] = value
end

-- The contract board's card: a row of icons (WBP_ContractCard.Setup). CreateBoolModifier returns the icon in its
-- size box, and Setup adds the list to modifiers_wbox.
local function onContractCard(contextParam)
  local card = contextParam:get()
  for _, modifier in ipairs(modifiersToDraw(card.contractData)) do
    local out = {}
    card:CreateBoolModifier(FName(modifier.rowName), out)
    card.modifiers_wbox:AddChild(out.modifier)
  end
end

-- The contract's detail page: a selectable line per modifier, with its bounty (WBP_Contract_DetailPage."Setup
-- Contract Detail Page"). The page keeps each line and its row name side by side (listOfModifLines,
-- listOfModifKeys); selecting a line shows its row's description. Setup ends by making every line selectable, whose
-- buttons register with the page's navigation a frame later, so a line made selectable here registers with them.
local function onContractDetailPage(contextParam)
  local page = contextParam:get()
  for _, modifier in ipairs(modifiersToDraw(page.proxyContract)) do
    local lineOut, rowNameOut = {}, {}
    page:CreateLineModifier(FName(modifier.rowName), lineOut, rowNameOut)
    local line = lineOut.line

    append(page.listOfModifKeys, FName(modifier.rowName))
    append(page.listOfModifLines, line)
    -- The page's own spacing for its lines (Setup's scroll box slot padding)
    local slot = page.modifiers_scroll_box:AddChild(line)
    slot:SetPadding({ Left = 0, Top = 5, Right = 5, Bottom = 5 })
    -- Blueprint indices are 0-based
    page:MakeModifLineSelectable(line, #page.listOfModifLines - 1)
  end
end

-- The shuttle screen's mission start page: a line per modifier, with its bounty (WBP_MissionStart_Page."Set Up
-- Additional", which takes the contract).
local function onMissionStartPage(contextParam, contractParam)
  local page = contextParam:get()
  for _, modifier in ipairs(modifiersToDraw(contractParam:get())) do
    local lineOut, rowNameOut = {}, {}
    page:CreateLineModifier(FName(modifier.rowName), lineOut, rowNameOut)

    append(page.listOfModifKeys, FName(modifier.rowName))
    append(page.listOfModifLines, lineOut.line)
    page.VerticalBox_MofifierList:AddChild(lineOut.line)
  end
end

-- The mission brief the crew holds Tab for: modifier lines in two columns (UMG_ObjectiveList."Create Modifier
-- List", which takes the contract). Its own padding: 10 below every line, and 10 to the right of the left column's.
local function onObjectiveList(contextParam, contractParam)
  local list = contextParam:get()
  for _, modifier in ipairs(modifiersToDraw(contractParam:get())) do
    local lineOut, rowNameOut = {}, {}
    list:CreateLineModifier(FName(modifier.rowName), lineOut, rowNameOut)
    local line = lineOut.line

    -- The line's 0-based index decides its column, as in the game's loop
    local isLeftColumn = #list.listOfModifLines % 2 == 0
    append(list.listOfModifKeys, FName(modifier.rowName))
    append(list.listOfModifLines, line)
    list.WrapBox_Modifier:AddChild(line)
    line:SetPadding({ Left = 0, Top = 0, Right = isLeftColumn and 10 or 0, Bottom = 10 })
  end
end

-- The score page after a mission: a row of icons, drawn one at a time (WBP_ScorePage's ubergraph, which ends the
-- row with FinishSetupModifiers). CreateBoolModifier adds the icon to the row itself. The bounty they pay is already
-- in the page's "additional conditions" total (contracts.lua).
local function onScorePageModifiers(contextParam)
  local page = contextParam:get()
  for _, modifier in ipairs(modifiersToDraw(page.Contract)) do
    page:CreateBoolModifier(FName(modifier.rowName))
  end
end

function screens.register()
  game.hookWhenLoaded(game.paths.contractCard, "Setup", game.guarded("The contract card", onContractCard))
  game.hookWhenLoaded(game.paths.contractDetailPage, "Setup Contract Detail Page",
    game.guarded("The contract detail page", onContractDetailPage))
  game.hookWhenLoaded(game.paths.missionStartPage, "Set Up Additional",
    game.guarded("The mission start page", onMissionStartPage))
  game.hookWhenLoaded(game.paths.objectiveList, "Create Modifier List",
    game.guarded("The mission brief", onObjectiveList))
  game.hookWhenLoaded(game.paths.scorePage, "FinishSetupModifiers",
    game.guarded("The score page", onScorePageModifiers))
end

return screens
