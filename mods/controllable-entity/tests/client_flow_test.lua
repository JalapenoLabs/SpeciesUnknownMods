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
local links = require("entity.links")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
-- The fakes pass plain tables as input values: { X, Y } for axes, { pressed } for buttons.
fake.objects[game.paths.inputLibrary] = fake.object("EnhancedInputLibrary", nil, {
  Conv_InputActionValueToAxis2D = function(_, value) return value end,
  Conv_InputActionValueToBool = function(_, value) return value.pressed end,
})
-- The engine's component classes the camera rig is built from
fake.objects["/Script/Engine.SpringArmComponent"] = fake.object("SpringArmComponentClass")
fake.objects["/Script/Engine.CameraComponent"] = fake.object("CameraComponentClass")
fake.objects[game.paths.widgetLayoutLibrary] = fake.object("WidgetLayoutLibrary", nil, {
  GetViewportScale = function() return 2 end,
  GetViewportSize = function() return { X = 1920, Y = 1080 } end,
})
fake.installModPak(game.modClasses)
fake.object("GameStateBase")
fake.world = fake.object("World")

local function widgetElement(name)
  return fake.object(name, { Slot = fake.object(name .. "Slot") })
end
local widget = fake.object("WBP_EntityHUD_C", {
  Abilities = widgetElement("Abilities"),
  UltimateText = widgetElement("UltimateText"),
  FrenzyText = widgetElement("FrenzyText"),
  StatusText = widgetElement("StatusText"),
})
for _, prefix in ipairs({ "Lash", "Leap", "Vent", "Peek", "View", "Ultimate" }) do
  for _, part in ipairs({ "Slot", "Icon", "Key", "KeyText", "Bar" }) do
    widget[prefix .. part] = widgetElement(prefix .. part)
  end
end
for pingIndex = 0, 11 do
  widget["Ping" .. pingIndex] = widgetElement("Ping" .. pingIndex)
end

local function lastArgument(element, method)
  local calls = fake.callsTo(element, method)
  return calls[#calls] and calls[#calls].args[1]
end
local createdWidgets = 0
fake.objects[game.paths.widgetLibrary] = fake.object("WidgetBlueprintLibrary", nil, {
  Create = function()
    createdWidgets = createdWidgets + 1
    return widget
  end,
})

local controller = fake.object("BP_MyPlayerController_C", { Pawn = fake.invalid() }, {
  IsLocalController = function() return true end,
  GetControlRotation = function() return { Pitch = 0, Yaw = 90, Roll = 0 } end,
  ProjectWorldLocationToScreen = function(_, _, screen)
    screen.X, screen.Y = 800, 400
    return true
  end,
}, { "PlayerController" })
-- The player's crew body, which the game's camera manager has cached since it was possessed
local crewBody = fake.object("BP_Character_C")
fake.giveView(controller, crewBody)
local cameraManager = controller.PlayerCameraManager
local link = fake.object("BP_EntityLink_C", { Owner = controller, Meter = 0.5, Frenzy = false })
local squid = fake.object("BP_Monster_Poulpi_C", { InVent = false }, {
  K2_GetActorLocation = function() return { X = 0, Y = 300, Z = 0 } end,
})
local squidComponents = fake.acceptComponents(squid)
-- The crew HUD the player's crew body created before the takeover
local crewHud = fake.object("UI_HUD_Display_C")

-- Regression (playtest 3): a module whose handler fails must not stop the others hearing the same event. Here a
-- handler registered before everyone else's fails on the takeover; the HUD still learns the player is the entity
links.onClientEvent("BecameEntity", function() error("a module's handler failed") end)

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

fake.loadClass(game.paths.controllerClass, {
  "InpActEvt_IA_Move_K2Node_EnhancedInputActionEvent_27",
  "InpActEvt_IA_Look_K2Node_EnhancedInputActionEvent_28",
  "InpActEvt_IA_Shoot_K2Node_EnhancedInputActionEvent_37",
  "InpActEvt_IA_FlashLight_K2Node_EnhancedInputActionEvent_44",
  "InpActEvt_IA_OpenPauseMenu_K2Node_EnhancedInputActionEvent_10",
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
assert(#squidComponents == 0, "the flashlight is the crew's own as crew")

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

-- Regression (playtest 4): the game's camera stayed in the cached crew body, 17,000 units from the squid. The game's
-- own ResetPlayer hands its camera the squid, which clears the cache
assert(controller:GetViewTarget() == squid, "the camera follows the squid")
assert(not cameraManager.Player:IsValid(), "and no longer the crew body")
local arm = squidComponents[1]
assert(#squidComponents == 2 and arm.bUsePawnControlRotation, "the squid gets a camera on an arm that follows the look")
assert(arm.TargetArmLength == config.camera.thirdPersonDistance, "the entity starts in third person")
-- Regression (playtest 3): Escape did nothing as the squid, because the crew body had turned pausing off
local pauseHook = fake.hooks[controllerPath .. "InpActEvt_IA_OpenPauseMenu_K2Node_EnhancedInputActionEvent_10"]
controller.canPause = false
pauseHook(fake.param(controller), fake.param({ pressed = true }))
local pauseSetters = fake.callsTo(controller, "BPI_PlayerController_SetCanPause")
assert(#pauseSetters == 1 and pauseSetters[1].args[1] == true, "pausing goes back on")
assert(#fake.callsTo(controller, "OpenPauseMenu") == 1, "and the menu opens")
controller.canPause = true
pauseHook(fake.param(controller), fake.param({ pressed = true }))
assert(#fake.callsTo(controller, "OpenPauseMenu") == 1, "when the game could pause, its own handler opened the menu")

flashlightHook(fake.param(controller), fake.param({ pressed = true }))
assert(arm.TargetArmLength == 0, "the flashlight switches to first person")
flashlightHook(fake.param(controller), fake.param({ pressed = false }))
assert(arm.TargetArmLength == 0, "releasing the key changes nothing")
flashlightHook(fake.param(controller), fake.param({ pressed = true }))
assert(arm.TargetArmLength == config.camera.thirdPersonDistance, "and back to third person")

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

-- If the game's own code moves the camera elsewhere, it goes back to the squid within a second, keeping its rig
local shuttleCamera = fake.object("CameraActor")
controller:SetViewTargetWithBlend(shuttleCamera, 0, 0, 0, false)
fake.runLoops(1000)
assert(controller:GetViewTarget() == squid, "the view is put back on the squid")
assert(#squidComponents == 2, "the squid's camera is built once")

-- Regression (playtest 4): after a hot reload the mod forgot its rig and built a second one, which the engine never
-- viewed through, so the view toggle moved the wrong arm. A rig the squid already has is reused
package.loaded["entity.camera"] = nil
local reloadedCamera = require("entity.camera")
reloadedCamera.follow(controller, squid)
assert(#squidComponents == 2, "a reloaded mod reuses the squid's camera")
assert(arm.bDoCollisionTest == false, "with the current settings applied to it")
reloadedCamera.toggle()
assert(arm.TargetArmLength == 0, "and the view toggle moves the arm the player sees through")

-- The HUD shows the meter and a ping
fake.customEvents.EntityClientPing(fake.param(link), fake.param({ X = 100, Y = 0, Z = 0 }), fake.param(1.0),
  fake.param(fake.name("Gunshot")))
fake.runLoops(33)
assert(createdWidgets == createdForMessage, "the HUD is created once")
-- Regression (playtest 5): the respawn-capsule status set its own visibility again, so the crew HUD comes off the
-- screen instead of being hidden
assert(#fake.callsTo(crewHud, "RemoveFromParent") >= 1, "the crew HUD comes off the screen")
assert(lastArgument(widget.UltimateBar, "SetPercent") == 0.5, "the bar shows the replicated meter")
assert(lastArgument(widget.UltimateText, "SetText").text == "HEAD GRAB  50%")
assert(lastArgument(widget.LashKeyText, "SetText").text == "LMB", "each ability shows its key")
assert(lastArgument(widget.UltimateKeyText, "SetText").text == config.keys.ultimate)
assert(lastArgument(widget.Abilities, "SetVisibility") == 3, "the abilities show once the player is the entity")

-- A cooldown fills its bar; a ready ability hides it
assert(lastArgument(widget.LashBar, "SetVisibility") == 2, "a ready ability shows no bar")
fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name("Cooldown.Attack")), fake.param(0))
fake.runLoops(33)
assert(lastArgument(widget.LashBar, "SetVisibility") == 3, "a recharging ability shows its bar")
assert(lastArgument(widget.LashBar, "SetPercent") == 1, "the bar starts full and drains")

-- Peeking needs a vent, so outside one its slot dims; inside, it lights up
assert(lastArgument(widget.PeekSlot, "SetRenderOpacity") < 1, "peek is dimmed outside a vent")
squid.InVent = true
fake.runLoops(33)
assert(lastArgument(widget.PeekSlot, "SetRenderOpacity") == 1, "and usable inside one")
assert(lastArgument(widget.Ping0.Slot, "SetPosition").X == 400, "markers sit at the projected spot, in widget units")
assert(lastArgument(widget.Ping0, "SetRenderScale").X > 1, "gunshots draw bigger than the plain marker")

-- A noise behind the camera sits on the ring around the centre, below it (straight ahead is up). The camera looks
-- along +Y (yaw 90), and this noise is at -Y from the squid
local projectsToScreen = controller.ProjectWorldLocationToScreen
controller.ProjectWorldLocationToScreen = function() return false end
fake.customEvents.EntityClientPing(fake.param(link), fake.param({ X = 0, Y = -2000, Z = 0 }), fake.param(1.0),
  fake.param(fake.name("Footstep")))
fake.runLoops(33)
local ringPosition = lastArgument(widget.Ping1.Slot, "SetPosition")
assert(math.abs(ringPosition.X - 480) < 1e-6 and ringPosition.Y > 270, "a noise behind is on the ring, below centre")
controller.ProjectWorldLocationToScreen = projectsToScreen

fake.now = 5
fake.runLoops(33)
local visibilities = fake.callsTo(widget.Ping0, "SetVisibility")
assert(visibilities[#visibilities].args[1] == 2, "a ping disappears after it fades")
assert(createdWidgets == createdForMessage, "the HUD is reused")

-- Until the power is on, the lair's hint stays on screen after its message fades, and the moves that would leave the
-- ducts dim
fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name("Leashed")), fake.param(0))
fake.now = 60
fake.runLoops(33)
statusTexts = fake.callsTo(widget.StatusText, "SetText")
assert(statusTexts[#statusTexts].args[1].text:find("power"), "the lair hint stays")
assert(lastArgument(widget.VentSlot, "SetRenderOpacity") < 1, "leaving the vents is dimmed while the lair holds")
assert(lastArgument(widget.LashSlot, "SetRenderOpacity") == 1, "the lash stays usable")
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
