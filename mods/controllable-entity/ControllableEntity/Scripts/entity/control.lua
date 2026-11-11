-- Copyright © 2026 Jalapeno Labs

-- The entity player's controls, on their own machine.
--
-- The game binds all gameplay input on its player controller (BP_MyPlayerController.InpActEvt_IA_*), and every
-- handler forwards to the possessed pawn's BPI_PlayerInput interface. The squid doesn't implement it, so while the
-- player drives the squid those handlers do nothing; post-hooks on them drive the squid instead. The player's own
-- key bindings therefore carry over unchanged. Movement, look and the view apply here, where the player's movement
-- prediction and camera run; every other action is a command for the host.

local camera = require("entity.camera")
local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")

local control = {}

-- The squid this machine's player drives, or nil while they drive anything else.
local function drivenSquid(controller)
  if not controller:IsLocalController() then
    return nil
  end
  local pawn = controller.Pawn
  if not pawn:IsValid() or pawn:GetClass():GetFName():ToString() ~= game.classNames.squid then
    return nil
  end
  return pawn
end

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
  local squid = drivenSquid(controller)
  if not squid then
    return
  end
  local value = axisValue(actionValueParameter)
  reportValue("Move", controller, value)
  local yaw = math.rad(controller:GetControlRotation().Yaw)
  squid:AddMovementInput({ X = math.cos(yaw), Y = math.sin(yaw), Z = 0 }, value.Y, false)
  squid:AddMovementInput({ X = -math.sin(yaw), Y = math.cos(yaw), Z = 0 }, value.X, false)
end

-- Mirrors BP_Character.BPI_PlayerInput_Look.
local function look(controller, actionValueParameter)
  local squid = drivenSquid(controller)
  if not squid then
    return
  end
  local value = axisValue(actionValueParameter)
  reportValue("Look", controller, value)
  squid:AddControllerYawInput(value.X * config.look.sensitivity)
  squid:AddControllerPitchInput(value.Y * config.look.sensitivity)
end

local function button(command)
  return function(controller, actionValueParameter)
    if not drivenSquid(controller) or not buttonPressed(actionValueParameter) then
      return
    end
    links.sendCommand(command, aimOf(controller), nil)
  end
end

local function toggleView(controller, actionValueParameter)
  if not drivenSquid(controller) or not buttonPressed(actionValueParameter) then
    return
  end
  camera.toggle(controller)
end

-- The pause menu opens only while the controller's canPause is on (BP_MyPlayerController._CanOpenPauseMenu), and the
-- crew body turns it off on its way out (BP_Character calls BPI_PlayerController_SetCanPause(false) in several
-- states). The game's own handler has already run when this post-hook does, so when it refused, pausing goes back on
-- through the game's own setter and the menu opens.
local function openPauseMenu(controller, actionValueParameter)
  if not drivenSquid(controller) or not buttonPressed(actionValueParameter) or controller.canPause then
    return
  end
  game.log("Pausing was off for the entity; turning it back on")
  controller:BPI_PlayerController_SetCanPause(true)
  controller:OpenPauseMenu()
end

-- The handler for each game input action the entity uses, by the action's name (IA_<Name>). Buttons become a host
-- command when pressed, except the flashlight, which the squid has no use for and which switches the view instead.
-- The rest of the game's actions (reload, weapon slots, ...) mean nothing to the squid.
local handlerByAction = {
  Move = move,
  Look = look,
  Shoot = button("Attack"),
  ADS = button("Leap"),
  Interact = button("Vent"),
  Crouch = button("Peek"),
  FlashLight = toggleView,
  OpenPauseMenu = openPauseMenu,
}

-- The game has no jump, so the mod's own keys fill in: the ultimate, volunteering in the lobby, and entity mode (the
-- host decides whether a press counts). UE4SS key binds run outside the game thread, so each hops onto it before
-- touching game objects.
local function registerKeys()
  RegisterKeyBind(Key[config.keys.ultimate], function()
    ExecuteInGameThread(function()
      local controller = game.localController()
      if controller and drivenSquid(controller) then
        links.sendCommand("Ultimate", aimOf(controller), nil)
      end
    end)
  end)

  RegisterKeyBind(Key[config.keys.volunteer], function()
    ExecuteInGameThread(function()
      links.sendCommand("Volunteer", nil, nil)
    end)
  end)

  RegisterKeyBind(Key[config.keys.entityMode], function()
    ExecuteInGameThread(function()
      links.sendCommand("ToggleEntityMode", nil, nil)
    end)
  end)
end

-- Playtest diagnostics: the first time each action arrives at all, and the first time it arrives while the player
-- drives the squid, so a playtest log shows exactly where input stops.
local reportedArrivals = {}
local function reportArrival(actionName, controller)
  local drivingSquid = drivenSquid(controller) ~= nil
  local key = actionName .. (drivingSquid and ":squid" or ":crew")
  if reportedArrivals[key] then
    return
  end
  reportedArrivals[key] = true
  local pawn = controller.Pawn
  local pawnClass = pawn:IsValid() and pawn:GetClass():GetFName():ToString() or "no pawn"
  game.log("Input %s arrived (pawn: %s%s)", actionName, pawnClass, drivingSquid and ", driving the squid" or "")
end

-- On the player's own machine, as they become the entity: the camera goes to the squid (the host sets it too, but
-- that only arrives by replication), and any input the game had told the controller to ignore is let through again.
local function onBecameEntity()
  local controller = game.localController()
  if not controller then
    return
  end
  local squid = drivenSquid(controller)
  if squid then
    controller:SetViewTargetWithBlend(squid, 0, 0, 0, false)
  end
  camera.begin(controller)
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
    local squid = controller and drivenSquid(controller)
    if squid then
      camera.keepOnSquid(controller, squid)
    end
  end)
  links.onClientEvent("BecameEntity", onBecameEntity)
  links.onClientEvent("Lost", function()
    local controller = game.localController()
    if controller then
      camera.reset(controller)
    end
  end)
end

return control
