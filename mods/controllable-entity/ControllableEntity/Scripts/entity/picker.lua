-- Copyright © 2026 Jalapeno Labs

-- The host's entity picker (playtest 8), on the host's machine. F9 in the lobby opens a panel of clickable tiles:
-- which entity the missions have (Random, each playable kit, or AI only, where the monster stays the game's AI) and
-- who plays it (Random, or any player in the session). Random is the default for both, and the choices hold for the
-- session (takeover.lua keeps them).
--
-- The panel (WBP_EntityPicker) and its tiles (WBP_PickerTile) are the mod's own widgets; a kit's tile shows the game's
-- codex portrait of its monster. Each tile is a button, which the panel polls while it's open: a press released over a
-- tile is a click. The game's own UI-mode switch (UI_FunctionLibrary.SwitchUIModeCross, as its pause menu uses) shows
-- the cursor and stops the character while the panel is open.

local game = require("entity.game")
local kits = require("entity.kits")
local links = require("entity.links")
local takeover = require("entity.takeover")

local picker = {}

local UI_LIBRARY_CLASS = "/Game/Blueprints/UI_FunctionLibrary.UI_FunctionLibrary_C"
local Z_ORDER = 60
local UI_FADE_SECONDS = 0.25
-- The chosen tiles take the HUD's amber; the rest keep their own colour.
local CHOSEN_TINT = { R = 1.0, G = 0.70, B = 0.23, A = 1 }
local PLAIN_TINT = { R = 1, G = 1, B = 1, A = 1 }
-- A click lasts about a tenth of a second, so the open panel checks its tiles about 60 times a second; players joining
-- or leaving are picked up once a second.
local CLICK_POLL_MS = 16
local PLAYERS_REFRESH_SECONDS = 1

-- The open panel: { widget, controller, worldKey, tiles = { { button, kind, choice } }, wasPressed, playersShown,
-- nextPlayersRefreshAt }, or nil while it's closed. A tile's kind is "entity" or "player".
local open = nil

local function uiLibrary()
  local class = game.loadGameAsset(UI_LIBRARY_CLASS)
  return class and class:GetCDO()
end

-- One of the mod's tiles, added to a row of the panel: its label, and in place of its icon a material when given.
local function createTile(row, label, portrait)
  local tileClass = game.loadModAsset(game.modAssets.pickerTile)
  if not tileClass then
    return nil
  end
  local tile = StaticFindObject(game.paths.widgetLibrary):Create(open.controller, tileClass, open.controller)
  tile.TileLabel:SetText(FText(label))
  if portrait then
    tile.TileImage:SetBrushFromMaterial(portrait)
  end
  row:AddChildToWrapBox(tile)
  return tile
end

-- Marks the host's current choices.
local function markChoices()
  for _, tile in ipairs(open.tiles) do
    local isChosen = takeover.choice[tile.kind] == tile.choice
    tile.button:SetBackgroundColor(isChosen and CHOSEN_TINT or PLAIN_TINT)
  end
end

-- The entity row: Random first and AI only last are part of the panel; one tile per playable kit between them.
local function fillEntities(widget)
  table.insert(open.tiles, { button = widget.RandomEntity, kind = "entity", choice = "Random" })
  for _, kit in ipairs(kits.playable) do
    local tile = createTile(widget.EntityTiles, kit.displayName, game.loadGameAsset(kit.portrait))
    if tile then
      table.insert(open.tiles, { button = tile.Tile, kind = "entity", choice = kit.id })
    end
  end
  table.insert(open.tiles, { button = widget.AiOnly, kind = "entity", choice = "AiOnly" })
end

-- The player row: Random is part of the panel; one tile per player in the session, rebuilt when that changes.
local function fillPlayers()
  local players = takeover.players()
  local shown = {}
  for _, player in ipairs(players) do
    table.insert(shown, player.key)
  end
  local shownKey = table.concat(shown, ",")
  if shownKey == open.playersShown then
    return
  end
  open.playersShown = shownKey

  local remaining = {}
  for _, tile in ipairs(open.tiles) do
    if tile.kind ~= "player" or tile.choice == "Random" then
      table.insert(remaining, tile)
    end
  end
  open.tiles = remaining
  open.wasPressed = {}
  open.widget.PlayerTiles:ClearChildren()
  for _, player in ipairs(players) do
    local tile = createTile(open.widget.PlayerTiles, player.name, nil)
    if tile then
      table.insert(open.tiles, { button = tile.Tile, kind = "player", choice = player.key })
    end
  end
  markChoices()
end

local function close()
  local library = uiLibrary()
  if open.widget:IsValid() then
    open.widget:RemoveFromParent()
  end
  if library and open.controller:IsValid() then
    library:SwitchUIModeCross(open.controller, nil, false, false, true, UI_FADE_SECONDS, open.controller)
  end
  open = nil
end

local function choose(tile)
  if tile.kind == "entity" then
    takeover.chooseEntity(tile.choice)
  else
    takeover.choosePlayer(tile.choice)
  end
  markChoices()
end

-- Runs while the panel is open: a press released over a tile picks it; players joining or leaving update the row.
local function poll()
  if not open then
    return
  end
  -- A map change took the panel with it
  if not open.widget:IsValid() or game.currentWorldKey() ~= open.worldKey then
    open = nil
    return
  end

  for index, tile in ipairs(open.tiles) do
    local isPressed = tile.button:IsPressed()
    if open.wasPressed[index] and not isPressed and tile.button:IsHovered() then
      choose(tile)
    end
    open.wasPressed[index] = isPressed
  end

  local now = game.timeSeconds(open.controller)
  if now >= open.nextPlayersRefreshAt then
    open.nextPlayersRefreshAt = now + PLAYERS_REFRESH_SECONDS
    fillPlayers()
  end
end

-- F9 on the host: opens the picker in the lobby, or closes it. Elsewhere the host is told to pick in the lobby.
function picker.toggle(controller)
  if open then
    close()
    return
  end
  if not game.isLobby() then
    links.sendEvent(controller, "Denied.PickInLobby")
    return
  end
  local pickerClass = game.loadModAsset(game.modAssets.picker)
  local library = uiLibrary()
  if not pickerClass or not library then
    return
  end

  local widget = StaticFindObject(game.paths.widgetLibrary):Create(controller, pickerClass, controller)
  open = {
    widget = widget,
    controller = controller,
    worldKey = game.currentWorldKey(),
    tiles = {},
    wasPressed = {},
    playersShown = nil,
    nextPlayersRefreshAt = 0,
  }
  table.insert(open.tiles, { button = widget.RandomPlayer, kind = "player", choice = "Random" })
  fillEntities(widget)
  fillPlayers()
  markChoices()
  widget:AddToViewport(Z_ORDER)
  library:SwitchUIModeCross(controller, widget, true, false, true, UI_FADE_SECONDS, controller)
  game.log("The host's entity picker is open")
end

function picker.register()
  LoopInGameThreadWithDelay(CLICK_POLL_MS, poll)
end

return picker
