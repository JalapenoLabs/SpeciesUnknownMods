-- Copyright © 2026 Jalapeno Labs

-- The entity player's controls, on their own machine.
--
-- The game binds all gameplay input on its player controller (BP_MyPlayerController.InpActEvt_IA_*), and every
-- handler forwards to the possessed pawn's BPI_PlayerInput interface. The squid doesn't implement it, so while the
-- player drives the squid those handlers do nothing; post-hooks on them drive the squid instead. The player's own
-- key bindings therefore carry over unchanged. Movement and look apply here, where the player's movement
-- prediction runs; every other action is a command for the host.

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

-- Mirrors BP_Character.BPI_PlayerInput_Move: forward and right along the camera's yaw.
local function move(controller, actionValueParameter)
  local squid = drivenSquid(controller)
  if not squid then
    return
  end
  local value = axisValue(actionValueParameter)
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

-- The handler for each game input action the entity uses, by the action's name (IA_<Name>). Buttons become a host
-- command when pressed; the rest of the game's actions (reload, weapon slots, ...) mean nothing to the squid.
local handlerByAction = {
  Move = move,
  Look = look,
  Shoot = button("Attack"),
  ADS = button("Leap"),
  Interact = button("Vent"),
  Crouch = button("Peek"),
}

-- The game has no jump, so the mod's own keys fill in: the ultimate, and volunteering in the lobby. UE4SS key binds
-- run outside the game thread, so each hops onto it before touching game objects.
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
end

function control.register()
  game.hookMatchingWhenLoaded(game.paths.controllerClass, "^InpActEvt_IA_(%w+)_K2Node_EnhancedInputActionEvent_%d+$",
    function(actionName)
      local handler = handlerByAction[actionName]
      if not handler then
        return nil
      end
      return function(context, actionValueParameter)
        handler(context:get(), actionValueParameter)
      end
    end)
  registerKeys()
end

return control
