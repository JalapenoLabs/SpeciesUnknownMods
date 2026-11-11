-- Copyright © 2026 Jalapeno Labs

-- The entity's minimap, on their own machine: the game's own minimap widget in the corner, following an actor that
-- rides with the squid but never turns (north up), the player icon turning with the squid, the carried-item icons
-- hidden, and "." and "," zooming.
-- Run from the repository root: lua mods/controllable-entity/tests/minimap_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.isHost = false

local config = require("entity.config")
local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.objects["/Script/Engine.StaticMeshActor"] = fake.object("StaticMeshActorClass")
local widgetClass = fake.object("UMG_MiniMap_C_Class")
fake.objects["/Game/Blueprints/Inventory/Map/UMG_MiniMap.UMG_MiniMap_C"] = widgetClass
fake.objects[game.paths.widgetLayoutLibrary] = fake.object("WidgetLayoutLibrary", nil, {
  GetViewportScale = function() return 2 end,
  GetViewportSize = function() return { X = 3840, Y = 2160 } end,
})
fake.installModPak(game.modClasses)
fake.object("GameStateBase")

local follower = nil
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    follower = fake.object("StaticMeshActor", { StaticMeshComponent = fake.object("StaticMeshComponent") })
    return follower
  end,
})

local minimapWidget = fake.object("UMG_MiniMap_C", {
  ParentActor = fake.invalid(),
  Scale = 0.7,
  CanvasPanel_DynamicIcone = fake.object("CanvasPanel"),
  UMG_Icone_player_C_0 = fake.object("UMG_Icone_player_C"),
})
local createdWith = nil
fake.objects[game.paths.widgetLibrary] = fake.object("WidgetBlueprintLibrary", nil, {
  Create = function(_, _, class)
    createdWith = class
    return minimapWidget
  end,
})

local controller = fake.object("BP_MyPlayerController_C", { Pawn = fake.invalid() }, {
  IsLocalController = function() return true end,
}, { "PlayerController" })
fake.giveView(controller)

local squid = fake.object("BP_Monster_Poulpi_C", { yaw = 30 }, {
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
  K2_GetActorRotation = function(self) return { Pitch = 0, Yaw = self.yaw, Roll = 0 } end,
})
fake.giveMovement(squid)

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

local function lastArgument(target, method)
  local calls = fake.callsTo(target, method)
  return calls[#calls] and calls[#calls].args
end

-- As crew there is no minimap
fake.runLoops(33)
assert(createdWith == nil, "the crew gets no minimap")

-- Driving the squid: the game's minimap, top right, following an actor that rides with the squid and never turns
controller.Pawn = squid
fake.runLoops(33)
assert(createdWith == widgetClass, "the game's own minimap widget is used")
assert(#fake.callsTo(minimapWidget, "AddToViewport") == 1, "it goes on the screen")
-- Regression (playtest 6): sized to the corner square, the map spilled over the whole screen. It keeps its 1024-unit
-- layout, clipped to it, and is scaled down to the square
assert(lastArgument(minimapWidget, "SetDesiredSizeInViewport")[1].X == 1024, "at the size it is laid out for")
assert(lastArgument(minimapWidget, "SetClipping")[1] == 1, "clipped to its square")
assert(math.abs(lastArgument(minimapWidget, "SetRenderScale")[1].X - config.minimap.size / 1024) < 1e-9,
  "scaled down to the corner")
-- Regression (playtest 6): setting a viewport widget's position resets its anchors to the top-left corner, so the
-- minimap anchored top right with a negative offset landed off screen. Its top-right corner is placed from the width
local placed = lastArgument(minimapWidget, "SetPositionInViewport")[1]
assert(placed.X == 3840 / 2 - config.minimap.margin and placed.Y == config.minimap.margin,
  "the minimap's top-right corner sits near the screen's, in HUD units")
assert(lastArgument(minimapWidget, "SetAlignmentInViewport")[1].X == 1, "measured from its right edge")
assert(minimapWidget.ParentActor == follower, "centred on the follower, not the squid")
assert(lastArgument(follower, "K2_AttachToActor")[1] == squid, "which rides with the squid")
local absolute = lastArgument(follower.StaticMeshComponent, "SetAbsolute")
assert(absolute[1] == false and absolute[2] == true, "taking its position but keeping its own rotation")
assert(lastArgument(follower.StaticMeshComponent, "K2_SetWorldRotation")[1].Yaw == 0, "facing north for good")

-- No carried-item icons: they would show where the crew member carrying them is
assert(lastArgument(minimapWidget.CanvasPanel_DynamicIcone, "SetVisibility")[1] == 1, "the item icons are hidden")

-- The player icon turns with the squid
squid.yaw = 120
fake.runLoops(33)
assert(lastArgument(minimapWidget.UMG_Icone_player_C_0, "SetRenderTransformAngle")[1] == 120 - 90,
  "the icon shows which way the squid faces (the map draws +Y up)")

-- "." zooms in and "," out, within the limits
local startZoom = minimapWidget.Scale
fake.keybinds[config.keys.zoomIn]()
fake.runLoops(33)
assert(minimapWidget.Scale > startZoom, "the period key zooms in")
for _ = 1, 50 do
  fake.keybinds[config.keys.zoomOut]()
end
fake.runLoops(33)
assert(minimapWidget.Scale == config.minimap.minimumZoom, "zooming out stops at the limit")
assert(#fake.callsTo(minimapWidget, "AddToViewport") == 1, "the minimap is built once")

-- Once the player stops driving the squid, the minimap and its follower go
controller.Pawn = fake.invalid()
fake.runLoops(33)
assert(#fake.callsTo(minimapWidget, "RemoveFromParent") == 1, "the minimap leaves the screen")
assert(follower.destroyed, "and its follower is removed")

-- Regression (playtest 6): a hot reload left the old minimap on screen. A new run removes the mod's own leftovers,
-- the minimaps following one of its followers, and leaves the crew's minimap tools alone
local crewTool = fake.object("BP_Tool_MiniMap_C")
local crewToolScreen = fake.object("UMG_MiniMap_C", { ParentActor = crewTool })
local staleFollower = fake.object("StaticMeshActor")
local staleMinimap = fake.object("UMG_MiniMap_C", { ParentActor = staleFollower })
controller.Pawn = squid
fake.runLoops(33)
assert(#fake.callsTo(staleMinimap, "RemoveFromParent") == 1 and staleFollower.destroyed, "a leftover minimap is removed")
assert(#fake.callsTo(crewToolScreen, "RemoveFromParent") == 0 and not crewTool.destroyed, "the crew's tool is left alone")

print("minimap test passed")
