-- Copyright © 2026 Jalapeno Labs

-- The entity player's controls, on their own machine.
--
-- The game binds all gameplay input on its player controller (BP_MyPlayerController.InpActEvt_IA_*), and every
-- handler forwards to the possessed pawn's BPI_PlayerInput interface. No monster implements it, so while the
-- player drives one those handlers do nothing; post-hooks on them drive it instead. The player's own
-- key bindings therefore carry over unchanged. Movement, look and the view apply here, where the player's movement
-- prediction and camera run; every other action is a command for the host.

local areas = require("entity.areas")
local camera = require("entity.camera")
local config = require("entity.config")
local hud = require("entity.hud")
local minimap = require("entity.minimap")
local movement = require("entity.movement")
local objectives = require("entity.objectives")
local picker = require("entity.picker")
local vision = require("entity.vision")
local game = require("entity.game")
local links = require("entity.links")

local control = {}

local function aimOf(controller)
  return game.rotationDirection(controller:GetControlRotation())
end

-- FInputActionValue has no reflected fields; the engine's own converters read it. UE4SS copies the struct into the
-- call whole (CopyCompleteValue), so the value reaches the converter exactly as the handler received it.
local function axisValue(actionValueParameter)
  local inputLibrary = StaticFindObject(game.paths.inputLibrary)
  return inputLibrary:Conv_InputActionValueToAxis2D(actionValueParameter:get())
end

local function buttonPressed(actionValueParameter)
  local inputLibrary = StaticFindObject(game.paths.inputLibrary)
  return inputLibrary:Conv_InputActionValueToBool(actionValueParameter:get())
end

-- Playtest diagnostics, once each: the first values the stick and mouse produce, and whether the controller is
-- ignoring movement or look input (an engine flag games set during cutscenes and menus).
local reportedValues = {}
local function reportValue(kind, controller, value)
  if reportedValues[kind] or (value.X == 0 and value.Y == 0) then
    return
  end
  reportedValues[kind] = true
  game.log("%s value X=%.2f Y=%.2f; move input ignored: %s, look input ignored: %s", kind, value.X, value.Y,
    tostring(controller:IsMoveInputIgnored()), tostring(controller:IsLookInputIgnored()))
end

-- Mirrors BP_Character.BPI_PlayerInput_Move: forward and right along the camera's yaw.
local function move(controller, actionValueParameter)
  local monster = game.monsterDrivenBy(controller)
  if not monster then
    return
  end
  local value = axisValue(actionValueParameter)
  reportValue("Move", controller, value)
  local yaw = math.rad(controller:GetControlRotation().Yaw)
  monster:AddMovementInput({ X = math.cos(yaw), Y = math.sin(yaw), Z = 0 }, value.Y, false)
  monster:AddMovementInput({ X = -math.sin(yaw), Y = math.cos(yaw), Z = 0 }, value.X, false)
end

-- Mirrors BP_Character.BPI_PlayerInput_Look.
local function look(controller, actionValueParameter)
  local monster = game.monsterDrivenBy(controller)
  if not monster then
    return
  end
  local value = axisValue(actionValueParameter)
  reportValue("Look", controller, value)
  monster:AddControllerYawInput(value.X * config.look.sensitivity)
  monster:AddControllerPitchInput(value.Y * config.look.sensitivity)
end

local function button(command)
  return function(controller, actionValueParameter)
    if not game.monsterDrivenBy(controller) or not buttonPressed(actionValueParameter) then
      return
    end
    links.sendCommand(command, aimOf(controller), nil)
  end
end

-- A button an entity's move may be held on (the Terminator fires its gatling while Shoot is held): the command when
-- pressed, and <command>Release when let go, which the host passes to the move that is held. The game binds more than
-- one event per action (its handlers come in pairs), so only a change between held and let go is sent.
local function heldButton(command)
  local releaseCommand = command .. "Release"
  local isHeld = false
  return function(controller, actionValueParameter)
    if not game.monsterDrivenBy(controller) then
      return
    end
    local isPressed = buttonPressed(actionValueParameter)
    if isPressed == isHeld then
      return
    end
    isHeld = isPressed
    links.sendCommand(isPressed and command or releaseCommand, aimOf(controller), nil)
  end
end

local function toggleView(controller, actionValueParameter)
  if not game.monsterDrivenBy(controller) or not buttonPressed(actionValueParameter) then
    return
  end
  camera.toggle()
end

-- The game's objectives key (Tab by default): shows the entity's objectives while held. The game's own handler asks
-- the pawn to show the crew's (and the crew's name tags), which the entity ignores.
local function viewObjectives(controller, actionValueParameter)
  if not game.monsterDrivenBy(controller) then
    return
  end
  if buttonPressed(actionValueParameter) then
    objectives.show(controller)
    return
  end
  objectives.hide()
end

-- The pause menu opens only while the controller's canPause is on (BP_MyPlayerController._CanOpenPauseMenu), and the
-- crew body turns it off on its way out (BP_Character calls BPI_PlayerController_SetCanPause(false) in several
-- states). The game's own handler has already run when this post-hook does, so when it refused, pausing goes back on
-- through the game's own setter and the menu opens.
local function openPauseMenu(controller, actionValueParameter)
  if not game.monsterDrivenBy(controller) or not buttonPressed(actionValueParameter) or controller.canPause then
    return
  end
  game.log("Pausing was off for the entity; turning it back on")
  controller:BPI_PlayerController_SetCanPause(true)
  controller:OpenPauseMenu()
end

-- The handler for each game input action the entity uses, by the action's name (IA_<Name>). Buttons become a host
-- command when pressed, except the flashlight, which the entity has no use for and which switches the view instead.
-- The entity's four moves (kits.slots) are Shoot (LMB), ADS (RMB), Interact (E, playtest 6) and HoldTool (Space,
-- playtest 6); the weapon slots cry out (playtest 7). The rest of the game's actions (reload, ...) mean nothing to it.
local handlerByAction = {
  Move = move,
  Look = look,
  Shoot = heldButton("Primary"),
  ADS = button("Secondary"),
  Interact = button("Ultimate"),
  HoldTool = button("Mobility"),
  -- The crew's weapon-slot keys (1, 2 and 3) are the entity's cries (cries.lua)
  Slot1 = button("Roar"),
  Slot2 = button("Curious"),
  Slot3 = button("Call"),
  Crouch = button("Peek"),
  FlashLight = toggleView,
  ViewPseudo = viewObjectives,
  OpenPauseMenu = openPauseMenu,
}

-- The mod's own keys, for what the game has no action for: volunteering in the lobby, entity mode (the host decides
-- whether a press counts), the minimap's zoom and the hints. UE4SS key binds run outside the game thread, so each hops
-- onto it before touching game objects.
local function registerKeys()
  RegisterKeyBind(Key[config.keys.hints], function()
    ExecuteInGameThread(function()
      local controller = game.localController()
      if controller and game.monsterDrivenBy(controller) then
        hud.toggleHints()
      end
    end)
  end)

  -- F8 volunteers, in the lobby; as the entity it turns the power on when playing alone, for testing (lair.lua)
  RegisterKeyBind(Key[config.keys.volunteer], function()
    ExecuteInGameThread(function()
      local controller = game.localController()
      local isEntity = controller and game.monsterDrivenBy(controller)
      links.sendCommand(isEntity and "SoloPowerOn" or "Volunteer", nil, nil)
    end)
  end)

  -- F9: the host's entity picker opens on the host's own machine; anyone else's press goes to the host, who answers
  -- that it's the host's
  RegisterKeyBind(Key[config.keys.picker], function()
    ExecuteInGameThread(function()
      local controller = game.localController()
      if controller and game.isHost() then
        picker.toggle(controller)
        return
      end
      links.sendCommand("OpenPicker", nil, nil)
    end)
  end)

  for key, direction in pairs({ [config.keys.zoomIn] = 1, [config.keys.zoomOut] = -1 }) do
    RegisterKeyBind(Key[key], function()
      ExecuteInGameThread(function()
        minimap.zoom(direction)
      end)
    end)
  end
end

-- Playtest diagnostics: the first time each action arrives at all, and the first time it arrives while the player
-- drives the monster, so a playtest log shows exactly where input stops.
local reportedArrivals = {}
local function reportArrival(actionName, controller)
  local drivingMonster = game.monsterDrivenBy(controller) ~= nil
  local key = actionName .. (drivingMonster and ":monster" or ":crew")
  if reportedArrivals[key] then
    return
  end
  reportedArrivals[key] = true
  local pawn = controller.Pawn
  local pawnClass = pawn:IsValid() and pawn:GetClass():GetFName():ToString() or "no pawn"
  game.log("Input %s arrived (pawn: %s%s)", actionName, pawnClass, drivingMonster and ", driving the entity" or "")
end

-- On the player's own machine, as they become the entity: the camera goes to the entity (see camera.lua), and any input
-- the game had told the controller to ignore is let through again.
local function onBecameEntity()
  local controller = game.localController()
  if not controller then
    return
  end
  local monster = game.monsterDrivenBy(controller)
  if monster then
    camera.follow(controller, monster)
  end
  game.log("Became the entity; move input ignored: %s, look input ignored: %s",
    tostring(controller:IsMoveInputIgnored()), tostring(controller:IsLookInputIgnored()))
  controller:ResetIgnoreMoveInput()
  controller:ResetIgnoreLookInput()
end

function control.register()
  game.hookMatchingWhenLoaded(game.paths.controllerClass, "^InpActEvt_IA_(%w+)_K2Node_EnhancedInputActionEvent_%d+$",
    function(actionName)
      local handler = handlerByAction[actionName]
      if not handler then
        return nil
      end
      return function(context, actionValueParameter)
        local controller = context:get()
        reportArrival(actionName, controller)
        handler(controller, actionValueParameter)
      end
    end)
  registerKeys()
  LoopInGameThreadWithDelay(1000, function()
    local controller = game.localController()
    local monster = controller and game.monsterDrivenBy(controller)
    if monster then
      camera.follow(controller, monster)
    end
  end)
  LoopInGameThreadWithDelay(33, function()
    local controller = game.localController()
    local monster = controller and game.monsterDrivenBy(controller)
    if monster then
      minimap.follow(controller, monster)
      return
    end
    minimap.forget()
  end)
  -- The entity this machine last drove, so the areas it stood in can be handed back once it stops
  local lastMonster = nil
  LoopInGameThreadWithDelay(250, function()
    local controller = game.localController()
    local monster = controller and game.monsterDrivenBy(controller)
    if monster then
      lastMonster = monster
      areas.follow(monster)
      return
    end
    if lastMonster then
      areas.forget(lastMonster)
      lastMonster = nil
    end
  end)
  LoopInGameThreadWithDelay(100, function()
    local controller = game.localController()
    local monster = controller and game.monsterDrivenBy(controller)
    if monster then
      vision.follow(controller, monster)
      movement.followPlayer(controller, monster)
      return
    end
    vision.forget()
    objectives.hide()
  end)
  links.onClientEvent("BecameEntity", onBecameEntity)
  links.onClientEvent("Lost", camera.reset)
end

return control
