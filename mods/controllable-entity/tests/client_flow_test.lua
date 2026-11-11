-- Copyright © 2026 Jalapeno Labs

-- Runs the mod's real scripts as the entity player's machine (a client), against fake game objects: input hooks,
-- the mod's keys, the view, host events and the HUD.
-- Run from the repository root: lua mods/controllable-entity/tests/client_flow_test.lua

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
-- The fakes pass plain tables as input values: { X, Y } for axes, { pressed } for buttons.
fake.objects[game.paths.inputLibrary] = fake.object("EnhancedInputLibrary", nil, {
  Conv_InputActionValueToAxis2D = function(_, value) return value end,
  Conv_InputActionValueToBool = function(_, value) return value.pressed end,
})
fake.objects[game.paths.widgetLayoutLibrary] = fake.object("WidgetLayoutLibrary", nil, {
  GetViewportScale = function() return 2 end,
})
fake.installModPak(game.modClasses)
fake.object("GameStateBase")
fake.world = fake.object("World")

local function widgetElement(name)
  return fake.object(name, { Slot = fake.object(name .. "Slot") })
end
local widget = fake.object("WBP_EntityHUD_C", {
  UltimateBar = widgetElement("UltimateBar"),
  UltimateText = widgetElement("UltimateText"),
  FrenzyText = widgetElement("FrenzyText"),
  StatusText = widgetElement("StatusText"),
  AbilityText = widgetElement("AbilityText"),
})
for pingIndex = 0, 11 do
  widget["Ping" .. pingIndex] = widgetElement("Ping" .. pingIndex)
end
local createdWidgets = 0
fake.objects[game.paths.widgetLibrary] = fake.object("WidgetBlueprintLibrary", nil, {
  Create = function()
    createdWidgets = createdWidgets + 1
    return widget
  end,
})

local cameraManager = fake.object("PlayerCameraManager", { CameraStyle = fake.name("Default"), FreeCamDistance = 256 })
local controller = fake.object("BP_MyPlayerController_C", {
  Pawn = fake.invalid(),
  PlayerCameraManager = cameraManager,
}, {
  IsLocalController = function() return true end,
  GetControlRotation = function() return { Pitch = 0, Yaw = 90, Roll = 0 } end,
  ProjectWorldLocationToScreen = function(_, _, screen)
    screen.X, screen.Y = 800, 400
    return true
  end,
}, { "PlayerController" })
local link = fake.object("BP_EntityLink_C", { Owner = controller, Meter = 0.5, Frenzy = false })
local squid = fake.object("BP_Monster_Poulpi_C")
-- The crew HUD the player's crew body created before the takeover
local crewHud = fake.object("UI_HUD_Display_C", nil, { GetVisibility = function() return 4 end })

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

fake.loadClass(game.paths.controllerClass, {
  "InpActEvt_IA_Move_K2Node_EnhancedInputActionEvent_27",
  "InpActEvt_IA_Look_K2Node_EnhancedInputActionEvent_28",
  "InpActEvt_IA_Shoot_K2Node_EnhancedInputActionEvent_37",
  "InpActEvt_IA_FlashLight_K2Node_EnhancedInputActionEvent_44",
  "InpActEvt_IA_Reload_K2Node_EnhancedInputActionEvent_32",
})
local controllerPath = game.paths.controllerClass .. ":"
local moveHook = fake.hooks[controllerPath .. "InpActEvt_IA_Move_K2Node_EnhancedInputActionEvent_27"]
local shootHook = fake.hooks[controllerPath .. "InpActEvt_IA_Shoot_K2Node_EnhancedInputActionEvent_37"]
local flashlightHook = fake.hooks[controllerPath .. "InpActEvt_IA_FlashLight_K2Node_EnhancedInputActionEvent_44"]
assert(moveHook and shootHook and flashlightHook, "the controller's move, shoot and flashlight handlers are hooked")
assert(not fake.hooks[controllerPath .. "InpActEvt_IA_Reload_K2Node_EnhancedInputActionEvent_32"],
  "actions the squid doesn't use are left alone")

-- As crew, the hooks stay out of the way
moveHook(fake.param(controller), fake.param({ X = 0, Y = 1 }))
assert(#fake.callsTo(squid, "AddMovementInput") == 0)

-- Volunteering is a key press away, in the lobby
fake.keybinds.F8()
local commands = fake.callsTo(link, "EntityServerCommand")
assert(#commands == 1 and commands[1].args[1]:ToString() == "Volunteer")
fake.keybinds.SPACE()
assert(#fake.callsTo(link, "EntityServerCommand") == 1, "the ultimate key does nothing as crew")
flashlightHook(fake.param(controller), fake.param({ pressed = true }))
assert(cameraManager.CameraStyle:ToString() == "Default", "the flashlight is the crew's own as crew")

-- Entity mode: every player's F9 goes to the host, which decides whether it counts
fake.keybinds.F9()
commands = fake.callsTo(link, "EntityServerCommand")
assert(commands[#commands].args[1]:ToString() == "ToggleEntityMode")
fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name("EntityModeOff")), fake.param(0))
fake.runLoops(33)
local statusTexts = fake.callsTo(widget.StatusText, "SetText")
assert(statusTexts[#statusTexts].args[1].text == "Entity mode: OFF", "the presser sees the new mode")
local createdForMessage = createdWidgets

-- The host makes this player the entity
controller.Pawn = squid
fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name("BecameEntity")), fake.param(0))
assert(cameraManager.CameraStyle:ToString() == "FreeCam", "the entity starts in third person")
assert(cameraManager.FreeCamDistance == config.camera.thirdPersonDistance)
flashlightHook(fake.param(controller), fake.param({ pressed = true }))
assert(cameraManager.CameraStyle:ToString() == "Default", "the flashlight switches to first person")
flashlightHook(fake.param(controller), fake.param({ pressed = false }))
assert(cameraManager.CameraStyle:ToString() == "Default", "releasing the key changes nothing")
flashlightHook(fake.param(controller), fake.param({ pressed = true }))
assert(cameraManager.CameraStyle:ToString() == "FreeCam", "and back to third person")

moveHook(fake.param(controller), fake.param({ X = 0, Y = 1 }))
local moves = fake.callsTo(squid, "AddMovementInput")
assert(#moves == 2, "forward and right movement")
assert(math.abs(moves[1].args[1].Y - 1) < 1e-9 and moves[1].args[2] == 1, "forward follows the camera's yaw")

local commandsBeforeShooting = #fake.callsTo(link, "EntityServerCommand")
shootHook(fake.param(controller), fake.param({ pressed = true }))
shootHook(fake.param(controller), fake.param({ pressed = false }))
commands = fake.callsTo(link, "EntityServerCommand")
assert(#commands == commandsBeforeShooting + 1 and commands[#commands].args[1]:ToString() == "Attack",
  "a press sends one command, a release none")
assert(math.abs(commands[#commands].args[2].Y - 1) < 1e-9, "the command carries the aim")

fake.keybinds.SPACE()
commands = fake.callsTo(link, "EntityServerCommand")
assert(commands[#commands].args[1]:ToString() == "Ultimate")

-- The HUD shows the meter and a ping
fake.customEvents.EntityClientPing(fake.param(link), fake.param({ X = 100, Y = 0, Z = 0 }), fake.param(1.0),
  fake.param(fake.name("Gunshot")))
fake.runLoops(33)
assert(createdWidgets == createdForMessage, "the HUD is created once")
local crewHudVisibility = fake.callsTo(crewHud, "SetVisibility")
assert(#crewHudVisibility == 1 and crewHudVisibility[1].args[1] == 1, "the crew HUD is collapsed")
local percents = fake.callsTo(widget.UltimateBar, "SetPercent")
assert(percents[#percents].args[1] == 0.5, "the bar shows the replicated meter")
local labels = fake.callsTo(widget.UltimateText, "SetText")
assert(labels[#labels].args[1].text == "HEAD GRAB  50%")
local positions = fake.callsTo(widget.Ping0.Slot, "SetPosition")
assert(#positions == 1 and positions[1].args[1].X == 400, "markers sit at the projected spot, in widget units")

fake.now = 5
fake.runLoops(33)
local visibilities = fake.callsTo(widget.Ping0, "SetVisibility")
assert(visibilities[#visibilities].args[1] == 2, "a ping disappears after it fades")
assert(createdWidgets == createdForMessage, "the HUD is reused")

-- Until the power is on, the lair's hint stays on screen after its message fades
fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name("Leashed")), fake.param(0))
fake.now = 60
fake.runLoops(33)
statusTexts = fake.callsTo(widget.StatusText, "SetText")
assert(statusTexts[#statusTexts].args[1].text:find("power"), "the lair hint stays")
fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name("PowerRestored")), fake.param(0))
fake.now = 120
fake.runLoops(33)
statusTexts = fake.callsTo(widget.StatusText, "SetText")
assert(statusTexts[#statusTexts].args[1].text == "", "once the power is on, the hint goes")

-- Regression (playtest 2): after quitting to the main menu the entity HUD stayed on screen. A map change must remove
-- the old world's HUD and forget the old world's status until the host says otherwise.
fake.world = fake.object("World")
controller.Pawn = fake.invalid()
fake.runLoops(33)
assert(#fake.callsTo(widget, "RemoveFromParent") == 1, "the old world's HUD is removed")
fake.runLoops(33)
assert(createdWidgets == createdForMessage, "no HUD is rebuilt in a world where the host hasn't named this player")

print("client flow test passed")
