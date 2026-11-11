-- Copyright © 2026 Jalapeno Labs

-- The entity's minimap, on their own machine: the game's own minimap (UMG_MiniMap, the screen of the crew's minimap
-- tool) in the top-right corner, centred on the squid, north up, with the player icon turning as the squid turns.
-- "." and "," zoom.
--
-- The widget centres its map on its ParentActor every frame and turns the map with that actor (UMG_MiniMap.Tick). Given
-- the squid itself, the map would spin with the squid, so it follows an invisible actor attached to the squid that
-- takes its position but never turns. The widget's moving item icons (the special weapons, the black box) are hidden:
-- their icons stay on the map while a crew member carries them, which would show the entity where that player is.

local config = require("entity.config")
local game = require("entity.game")

local minimap = {}

local WIDGET_CLASS = "/Game/Blueprints/Inventory/Map/UMG_MiniMap.UMG_MiniMap_C"
local FOLLOWER_CLASS = "/Script/Engine.StaticMeshActor"
-- EAttachmentRule, EComponentMobility, ESlateVisibility
local SNAP_TO_TARGET = 2
local KEEP_WORLD = 1
local MOVABLE = 2
local COLLAPSED = 1

-- What this machine has built: { worldKey, squidAddress, widget, follower }, or nil.
local built = nil
-- The zoom survives between missions: the widget's Scale, which the crew's tool sets from 0.7 to 1.0 by upgrade.
local zoom = nil

local function loadWidgetClass()
  local class = StaticFindObject(WIDGET_CLASS)
  if not class or not class:IsValid() then
    LoadAsset(WIDGET_CLASS)
    class = StaticFindObject(WIDGET_CLASS)
  end
  if not class or not class:IsValid() then
    game.log("Could not load the game's minimap (%s)", WIDGET_CLASS)
    return nil
  end
  return class
end

-- An invisible actor that rides along with the squid but keeps a world rotation of zero, so the map stays north up.
local function spawnFollower(world, squid)
  local follower = world:SpawnActor(StaticFindObject(FOLLOWER_CLASS), squid:K2_GetActorLocation(), {})
  if not follower or not follower:IsValid() then
    game.log("Could not spawn the minimap's follower")
    return nil
  end
  local root = follower.StaticMeshComponent
  root:SetMobility(MOVABLE)
  follower:K2_AttachToActor(squid, FName("None"), SNAP_TO_TARGET, KEEP_WORLD, KEEP_WORLD, false)
  root:SetAbsolute(false, true, true)
  root:K2_SetWorldRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, true)
  return follower
end

local function build(controller, squid)
  local widgetClass = loadWidgetClass()
  if not widgetClass then
    return nil
  end
  local follower = spawnFollower(controller:GetWorld(), squid)
  if not follower then
    return nil
  end

  local widget = StaticFindObject(game.paths.widgetLibrary):Create(controller, widgetClass, controller)
  widget:AddToViewport(45)
  widget:SetAnchorsInViewport({ Minimum = { X = 1, Y = 0 }, Maximum = { X = 1, Y = 0 } })
  widget:SetAlignmentInViewport({ X = 1, Y = 0 })
  widget:SetPositionInViewport({ X = -config.minimap.margin, Y = config.minimap.margin }, false)
  widget:SetDesiredSizeInViewport({ X = config.minimap.size, Y = config.minimap.size })
  widget["Screen Width"] = config.minimap.size
  widget.ParentActor = follower

  zoom = zoom or config.minimap.startZoom
  game.log("The minimap is up")
  return {
    worldKey = controller:GetWorld():GetAddress(),
    squidAddress = squid:GetAddress(),
    widget = widget,
    follower = follower,
  }
end

function minimap.forget()
  if not built then
    return
  end
  if built.widget:IsValid() then
    built.widget:RemoveFromParent()
  end
  if built.follower:IsValid() then
    built.follower:K2_DestroyActor()
  end
  built = nil
end

-- Runs about thirty times a second on the entity player's machine while they drive the squid.
function minimap.follow(controller, squid)
  local worldKey = controller:GetWorld():GetAddress()
  if built and (built.worldKey ~= worldKey or built.squidAddress ~= squid:GetAddress()) then
    minimap.forget()
  end
  if not built then
    built = build(controller, squid)
    if not built then
      return
    end
  end

  local widget = built.widget
  widget.Scale = zoom
  widget.CanvasPanel_DynamicIcone:SetVisibility(COLLAPSED)
  -- North up: the icon turns by the squid's heading (yaw 0 faces up the map)
  widget.UMG_Icone_player_C_0:SetRenderTransformAngle(squid:K2_GetActorRotation().Yaw + config.minimap.iconAngleOffset)
end

-- One step in (+1) or out (-1).
function minimap.zoom(direction)
  local current = zoom or config.minimap.startZoom
  local stepped = current * config.minimap.zoomStep ^ direction
  zoom = math.max(config.minimap.minimumZoom, math.min(config.minimap.maximumZoom, stepped))
end

return minimap
