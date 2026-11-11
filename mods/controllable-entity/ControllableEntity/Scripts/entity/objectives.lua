-- Copyright © 2026 Jalapeno Labs

-- The entity's objectives, on their own machine. Holding the game's "objectives" key (IA_ViewPseudo, Tab by default)
-- shows the crew the contract's objectives as a checklist; the entity gets the same overlay (UMG_ObjectiveList) with
-- its own objectives instead (playtest 6). The entity wins when the crew is all dead with no respawns left, so it
-- shows how many respawns are left. Nothing on it hints at the crew's contract.
--
-- The rows are built the way the list builds its own (UMG_ObjectiveList.SetObjectiveList): one UMG_Objective per
-- objective, its exposed properties set before it's added, with the list's own spacing.

local game = require("entity.game")

local objectives = {}

local LIST_CLASS = "/Game/Blueprints/UI/UMG_ObjectiveList.UMG_ObjectiveList_C"
local ENTRY_CLASS = "/Game/Blueprints/UI/UMG_Objective.UMG_Objective_C"
-- The crew's overlay sits on this layer (BP_Character.ShowOtherPseudoPostProcess).
local OVERLAY_Z_ORDER = 2
-- The list's own spacing between objectives.
local ENTRY_PADDING = { Left = 0, Top = 5, Right = 0, Bottom = 5 }
local HEADER = "THE ENTITY"
-- ESlateVisibility
local COLLAPSED = 1

-- The overlay on this machine: { worldKey, list, respawnsShown }, or nil.
local built = nil

-- The entity's objectives as rows: their text, and whether they're done.
local function entityObjectives()
  local gameState = FindFirstOf(game.classNames.gameState)
  local respawnsLeft = (gameState and gameState:IsValid()) and gameState.Respawn or 0
  return {
    { text = "Kill all humans", isDone = false },
    { text = string.format("Leave them no respawns (%d left)", respawnsLeft), isDone = respawnsLeft <= 0 },
    { text = "Stay alive", isDone = false },
  }, respawnsLeft
end

local function fill(controller)
  local rows, respawnsLeft = entityObjectives()
  if built.respawnsShown == respawnsLeft then
    return
  end
  built.respawnsShown = respawnsLeft

  local entryClass = game.loadGameAsset(ENTRY_CLASS)
  if not entryClass then
    return
  end
  local widgetLibrary = StaticFindObject(game.paths.widgetLibrary)
  local layoutLibrary = StaticFindObject(game.paths.widgetLayoutLibrary)
  local box = built.list.VerticalBoxObjective
  box:ClearChildren()
  for index, row in ipairs(rows) do
    local entry = widgetLibrary:Create(controller, entryClass, controller)
    entry.Text = FText(row.text)
    entry.index = index - 1
    entry.IsCurrent = not row.isDone
    entry.IsFinished = row.isDone
    entry.IsCancel = false
    -- Shown at once rather than animated in, as in the crew's overlay (the list's Instant is "not in the HUD")
    entry.Instant = true
    box:AddChild(entry)
    layoutLibrary:SlotAsVerticalBoxSlot(entry):SetPadding(ENTRY_PADDING)
  end
end

local function build(controller)
  local listClass = game.loadGameAsset(LIST_CLASS)
  if not listClass then
    return nil
  end
  local list = StaticFindObject(game.paths.widgetLibrary):Create(controller, listClass, controller)
  -- The header names the contract for the crew; the entity's names the entity, and the contract's icon and
  -- modifiers go
  list.TxtContractType:SetText(FText(HEADER))
  list.ImgContractType:SetVisibility(COLLAPSED)
  list.WrapBox_Modifier:SetVisibility(COLLAPSED)
  return { worldKey = controller:GetWorld():GetAddress(), list = list, respawnsShown = nil }
end

-- Whether a widget is the entity's own overlay, which the crew-HUD sweep must leave on screen (hud.lua).
function objectives.owns(widget)
  return built ~= nil and built.list:IsValid() and built.list:GetAddress() == widget:GetAddress()
end

-- While the key is held: the overlay, up to date.
function objectives.show(controller)
  local isStale = built and (built.worldKey ~= controller:GetWorld():GetAddress() or not built.list:IsValid())
  if not built or isStale then
    built = build(controller)
    if not built then
      return
    end
  end
  fill(controller)
  if not built.list:IsInViewport() then
    built.list:AddToViewport(OVERLAY_Z_ORDER)
  end
end

function objectives.hide()
  if built and built.list:IsValid() and built.list:IsInViewport() then
    built.list:RemoveFromParent()
  end
end

return objectives
