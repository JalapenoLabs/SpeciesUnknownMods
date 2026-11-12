-- Copyright © 2026 Jalapeno Labs

-- The host's entity picker, on the host's machine: F9 in the lobby opens a panel of tiles (Random, each playable
-- entity with its codex portrait, AI only; Random and each player), in the game's own UI mode; a click on a tile picks
-- it and marks it; players joining show up; F9 closes it and gives the game its input back. Outside the lobby, F9
-- tells the host to pick in the lobby.
-- Run from the repository root: lua mods/controllable-entity/tests/picker_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local game = require("entity.game")
local kits = require("entity.kits")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
local modAssets = fake.installModPak(game.modAssets)
fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0, Contract = {} })

-- The game's UI-mode switch, as its pause menu uses
local uiLibrary = fake.object("UI_FunctionLibrary")
fake.objects["/Game/Blueprints/UI_FunctionLibrary.UI_FunctionLibrary_C"] = fake.object("UI_FunctionLibrary_C", nil, {
  GetCDO = function() return uiLibrary end,
})
local portrait = fake.object("MaterialInstanceConstant")
fake.objects[kits.byId.Squid.portrait] = portrait

-- A tile's button: pressed while the mouse holds it, hovered while the mouse is over it
local function button(name)
  return fake.object("Button", { name = name, pressed = false, hovered = false }, {
    IsPressed = function(self) return self.pressed end,
    IsHovered = function(self) return self.hovered end,
  })
end
local function wrap(name)
  return fake.object("WrapBox", { name = name, children = {} }, {
    AddChildToWrapBox = function(self, child) table.insert(self.children, child) end,
    ClearChildren = function(self) self.children = {} end,
  })
end
local panel = fake.object("WBP_EntityPicker_C", {
  RandomEntity = button("RandomEntity"),
  AiOnly = button("AiOnly"),
  RandomPlayer = button("RandomPlayer"),
  EntityTiles = wrap("EntityTiles"),
  PlayerTiles = wrap("PlayerTiles"),
})
fake.objects[game.paths.widgetLibrary] = fake.object("WidgetBlueprintLibrary", nil, {
  Create = function(_, _, class)
    if class == modAssets.picker then
      return panel
    end
    if class == modAssets.pickerTile then
      return fake.object("WBP_PickerTile_C", {
        Tile = button("Tile"),
        TileImage = fake.object("Image"),
        TileLabel = fake.object("TextBlock"),
      })
    end
    return fake.entityHud()
  end,
})

local function playerState(lobbyId, name)
  return fake.object("BP_MyPlayerState_C", nil, {
    BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = lobbyId end,
    GetPlayerName = function() return fake.name(name) end,
  })
end
local function controller(isLocal, state)
  local object = fake.object("BP_MyPlayerController_C", { PlayerState = state, Pawn = fake.invalid() }, {
    IsLocalController = function() return isLocal end,
    IsPlayerController = function() return true end,
  }, { "PlayerController" })
  fake.giveView(object)
  return object
end
local hostController = controller(true, playerState(0, "Alex"))
local link = nil
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local spawned = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    spawned.SetOwner = function(self, owner)
      self.Owner = owner
      if owner == hostController then
        link = spawned
      end
    end
    return spawned
  end,
})
fake.object("BP_MyGameState_C", { ["In Game Player State "] = fake.array({}) }, nil, { "GameStateBase" })
local lobbyGameMode = fake.object("BP_LobbyGameMode_C")

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")
local takeover = require("entity.takeover")
fake.runLoops(1000)

local function lastArgument(target, method)
  local calls = fake.callsTo(target, method)
  return calls[#calls] and calls[#calls].args
end
local function click(target)
  target.hovered, target.pressed = true, true
  fake.runLoops(16)
  target.pressed = false
  fake.runLoops(16)
  target.hovered = false
end
local function isTinted(target)
  return lastArgument(target, "SetBackgroundColor")[1].G < 1
end

-- F9 opens the picker, in the game's own UI mode
fake.keybinds.F9()
assert(#fake.callsTo(panel, "AddToViewport") == 1, "the host's F9 opens the picker")
local switches = fake.callsTo(uiLibrary, "SwitchUIModeCross")
assert(#switches == 1 and switches[1].args[2] == panel and switches[1].args[3] == true,
  "in the game's UI mode, focused on the picker")

-- The entity row: Random, a tile per playable entity with its codex portrait, AI only
local entityTiles = panel.EntityTiles.children
assert(#entityTiles == #kits.playable, "a tile for each playable entity")
assert(lastArgument(entityTiles[1].TileLabel, "SetText")[1].text == "Squid", "named")
assert(lastArgument(entityTiles[1].TileImage, "SetBrushFromMaterial")[1] == portrait, "with its codex portrait")
-- The player row: Random and each player
local playerTiles = panel.PlayerTiles.children
assert(#playerTiles == 1 and lastArgument(playerTiles[1].TileLabel, "SetText")[1].text == "Alex", "a tile per player")
-- Random is chosen, for both
assert(isTinted(panel.RandomEntity) and isTinted(panel.RandomPlayer), "both choices start on Random")
assert(not isTinted(entityTiles[1].Tile), "and nothing else is marked")

-- A click is a press released over a tile
click(entityTiles[1].Tile)
assert(takeover.choice.entity == "Squid", "clicking the squid picks it")
assert(isTinted(entityTiles[1].Tile) and not isTinted(panel.RandomEntity), "and marks it")
panel.AiOnly.pressed = true
fake.runLoops(16)
panel.AiOnly.pressed = false
fake.runLoops(16)
assert(takeover.choice.entity == "Squid", "a press released off the tile isn't a click")

-- A player joining shows up; the host picks them
local crewController = controller(false, playerState(1, "Jacob"))
fake.now = 2
fake.runLoops(16)
playerTiles = panel.PlayerTiles.children
assert(#playerTiles == 2 and lastArgument(playerTiles[2].TileLabel, "SetText")[1].text == "Jacob",
  "a player joining gets a tile")
click(playerTiles[2].Tile)
assert(takeover.choice.player == "lobby:1", "clicking a player picks them")
click(panel.AiOnly)
assert(takeover.choice.entity == "AiOnly", "AI only is a choice too")

-- F9 again closes it, and the game has its input back
fake.keybinds.F9()
assert(#fake.callsTo(panel, "RemoveFromParent") == 1, "F9 closes the picker")
switches = fake.callsTo(uiLibrary, "SwitchUIModeCross")
assert(#switches == 2 and switches[2].args[3] == false, "and leaves the UI mode")

-- Outside the lobby, the host is told to pick there
lobbyGameMode.destroyed = true
fake.keybinds.F9()
assert(#fake.callsTo(panel, "AddToViewport") == 1, "no picker outside the lobby")
local events = fake.callsTo(link, "EntityClientEvent")
assert(events[#events].args[1]:ToString() == "Denied.PickInLobby", "the host is told to pick in the lobby")
assert(crewController ~= nil)

print("picker test passed")
