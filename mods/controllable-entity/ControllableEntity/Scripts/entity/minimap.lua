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
local WIDGET_CLASS_NAME = "UMG_MiniMap_C"
local FOLLOWER_CLASS = "/Script/Engine.StaticMeshActor"
local FOLLOWER_CLASS_NAME = "StaticMeshActor"
-- EAttachmentRule, EComponentMobility, ESlateVisibility, EWidgetClipping
local SNAP_TO_TARGET = 2
local KEEP_WORLD = 1
local MOVABLE = 2
local COLLAPSED = 1
local CLIP_TO_BOUNDS = 1
-- The widget is laid out as a 1024-unit square: its map canvas is that wide, and its Tick centres the map with that
-- number written in (UMG_MiniMap.Tick divides by 1024). It stays at that size, clipped to it, and is scaled down to
-- the corner square, pinned at its top-right corner so the scaling keeps it in place (playtest 6: sized to the square
-- instead, the map was off centre and spilled over the whole screen).
local DESIGN_SIZE = 1024

-- What this machine has built: { worldKey, squidAddress, widget, follower }, or nil.
local built = nil
-- The widget's Scale, which "." and "," change; every new minimap starts fully zoomed out.
local zoom = config.minimap.minimumZoom

-- An invisible actor that rides along with the squid but keeps a world rotation of zero, so the map stays north up.
local function spawnFollower(world, monster)
  local follower = world:SpawnActor(StaticFindObject(FOLLOWER_CLASS), monster:K2_GetActorLocation(), {})
  if not follower or not follower:IsValid() then
    game.log("Could not spawn the minimap's follower")
    return nil
  end
  local root = follower.StaticMeshComponent
  root:SetMobility(MOVABLE)
  follower:K2_AttachToActor(monster, FName("None"), SNAP_TO_TARGET, KEEP_WORLD, KEEP_WORLD, false)
  root:SetAbsolute(false, true, true)
  root:K2_SetWorldRotation({ Pitch = 0, Yaw = 0, Roll = 0 }, false, {}, true)
  return follower
end

-- A hot reload of the mod forgets what it built but leaves it in the world (playtest 6: the old, unscaled minimap
-- covered the screen). The mod's minimaps are the ones following a follower of its own, a plain StaticMeshActor; the
-- crew's minimap tools follow the tool, and are left alone.
local function removeLeftovers()
  for _, leftover in ipairs(FindAllOf(WIDGET_CLASS_NAME) or {}) do
    local followed = leftover:IsValid() and leftover.ParentActor
    if followed and followed:IsValid() and followed:GetClass():GetFName():ToString() == FOLLOWER_CLASS_NAME then
      leftover:RemoveFromParent()
      followed:K2_DestroyActor()
      game.log("Removed a minimap left by an earlier run of the mod")
    end
  end
end

local function build(controller, monster)
  removeLeftovers()
  local widgetClass = game.loadGameAsset(WIDGET_CLASS)
  if not widgetClass then
    return nil
  end
  local follower = spawnFollower(controller:GetWorld(), monster)
  if not follower then
    return nil
  end

  local widget = StaticFindObject(game.paths.widgetLibrary):Create(controller, widgetClass, controller)
  widget:AddToViewport(45)
  widget:SetAlignmentInViewport({ X = 1, Y = 0 })
  widget:SetDesiredSizeInViewport({ X = DESIGN_SIZE, Y = DESIGN_SIZE })
  widget["Screen Width"] = DESIGN_SIZE
  widget:SetClipping(CLIP_TO_BOUNDS)
  local shrink = config.minimap.size / DESIGN_SIZE
  widget:SetRenderTransformPivot({ X = 1, Y = 0 })
  widget:SetRenderScale({ X = shrink, Y = shrink })
  widget.ParentActor = follower

  zoom = config.minimap.minimumZoom
  game.log("The minimap is up")
  return {
    worldKey = controller:GetWorld():GetAddress(),
    monsterAddress = monster:GetAddress(),
    widget = widget,
    follower = follower,
    placedForWidth = nil,
  }
end

-- Pins the minimap's top-right corner near the screen's. Setting a viewport widget's position or size resets its
-- anchors to the top-left corner (UGameViewportSubsystem::SetWidgetSlotPosition), so the corner is placed from the
-- viewport's width, in HUD units, and placed again whenever the window changes size.
local function placeInCorner(controller)
  local layoutLibrary = StaticFindObject(game.paths.widgetLayoutLibrary)
  local width = layoutLibrary:GetViewportSize(controller).X / layoutLibrary:GetViewportScale(controller)
  if built.placedForWidth == width then
    return
  end
  built.placedForWidth = width
  built.widget:SetPositionInViewport({ X = width - config.minimap.margin, Y = config.minimap.margin }, false)
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
function minimap.follow(controller, monster)
  local worldKey = controller:GetWorld():GetAddress()
  if built and (built.worldKey ~= worldKey or built.monsterAddress ~= monster:GetAddress()) then
    minimap.forget()
  end
  if not built then
    built = build(controller, monster)
    if not built then
      return
    end
  end

  placeInCorner(controller)
  local widget = built.widget
  widget.Scale = zoom
  widget.CanvasPanel_DynamicIcone:SetVisibility(COLLAPSED)
  -- The icon turns with the squid. The map draws world +Y up and +X to the left (MapUtils.WorldToWidgetLocation
  -- negates both), so a heading of yaw points the icon yaw - 90 degrees clockwise from up
  local heading = monster:K2_GetActorRotation().Yaw
  widget.UMG_Icone_player_C_0:SetRenderTransformAngle(heading + config.minimap.iconAngleOffset)
end

-- One step in (+1) or out (-1).
function minimap.zoom(direction)
  local stepped = zoom * config.minimap.zoomStep ^ direction
  zoom = math.max(config.minimap.minimumZoom, math.min(config.minimap.maximumZoom, stepped))
end

return minimap
