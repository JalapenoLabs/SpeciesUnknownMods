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

local widget = fake.entityHud()

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
local link = fake.object("BP_EntityLink_C", {
  Owner = controller, Meter = 0.5, Frenzy = false, Health = 0.8, Downed = false, Stamina = 1,
})
local squid = fake.object("BP_Monster_Poulpi_C", { InVent = false, Mesh = fake.object("SkeletalMeshComponent") }, {
  K2_GetActorLocation = function() return { X = 0, Y = 300, Z = 0 } end,
})
fake.giveSquidState(squid)
local squidComponents = fake.acceptComponents(squid)
-- The crew HUD the player's crew body created before the takeover
local crewHud = fake.object("UI_HUD_Display_C")
-- The bridge's wall map, which shows where the mission's items are
local wallMap = fake.object("UMG_Map_C", nil, { GetVisibility = function() return 4 end })
-- A respawn capsule's screen, naming the crew member who took it
local capsuleScreen = fake.object("UMG_ScreenCapsule_C", {
  Pseudo = { text = "Aidan" },
  TextBlock_Pseudo = fake.object("TextBlock"),
})

-- Regression (playtest 3): a module whose handler fails must not stop the others hearing the same event. Here a
-- handler registered before everyone else's fails on the takeover; the HUD still learns the player is the entity
links.onClientEvent("BecameEntity", function() error("a module's handler failed") end)

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

fake.loadClass(game.paths.controllerClass, {
  "InpActEvt_IA_Move_K2Node_EnhancedInputActionEvent_27",
  "InpActEvt_IA_Look_K2Node_EnhancedInputActionEvent_28",
  "InpActEvt_IA_Shoot_K2Node_EnhancedInputActionEvent_37",
  "InpActEvt_IA_FlashLight_K2Node_EnhancedInputActionEvent_44",
  "InpActEvt_IA_Interact_K2Node_EnhancedInputActionEvent_30",
  "InpActEvt_IA_HoldTool_K2Node_EnhancedInputActionEvent_19",
  "InpActEvt_IA_OpenPauseMenu_K2Node_EnhancedInputActionEvent_10",
  "InpActEvt_IA_Reload_K2Node_EnhancedInputActionEvent_32",
})
local controllerPath = game.paths.controllerClass .. ":"
local moveHook = fake.hooks[controllerPath .. "InpActEvt_IA_Move_K2Node_EnhancedInputActionEvent_27"]
local shootHook = fake.hooks[controllerPath .. "InpActEvt_IA_Shoot_K2Node_EnhancedInputActionEvent_37"]
local flashlightHook = fake.hooks[controllerPath .. "InpActEvt_IA_FlashLight_K2Node_EnhancedInputActionEvent_44"]
local interactHook = fake.hooks[controllerPath .. "InpActEvt_IA_Interact_K2Node_EnhancedInputActionEvent_30"]
local holdToolHook = fake.hooks[controllerPath .. "InpActEvt_IA_HoldTool_K2Node_EnhancedInputActionEvent_19"]
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
holdToolHook(fake.param(controller), fake.param({ pressed = true }))
assert(#fake.callsTo(link, "EntityServerCommand") == 1, "the vent key is the crew's own as crew")
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
-- Regression (playtest 6): in first person the view was from inside the squid's own head
assert(lastArgument(squid.Mesh, "SetOwnerNoSee") == true, "first person hides the squid from its own player")
flashlightHook(fake.param(controller), fake.param({ pressed = false }))
assert(arm.TargetArmLength == 0, "releasing the key changes nothing")
flashlightHook(fake.param(controller), fake.param({ pressed = true }))
assert(arm.TargetArmLength == config.camera.thirdPersonDistance, "and back to third person")
assert(lastArgument(squid.Mesh, "SetOwnerNoSee") == false, "with the squid visible again")

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

-- HoldTool (Space) vents and Interact (E) fires the ultimate (playtest 6), through the game's own bindings
holdToolHook(fake.param(controller), fake.param({ pressed = true }))
commands = fake.callsTo(link, "EntityServerCommand")
assert(commands[#commands].args[1]:ToString() == "Vent", "Space vents")
interactHook(fake.param(controller), fake.param({ pressed = true }))
commands = fake.callsTo(link, "EntityServerCommand")
assert(commands[#commands].args[1]:ToString() == "Ultimate", "Interact fires the ultimate")
assert(not fake.keybinds.SPACE, "venting is no mod key, so it stays out of the game's menus")

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
-- Regression (playtest 6): the wall maps told the entity where the crew's special weapon was
local wallMapVisibility = fake.callsTo(wallMap, "SetVisibility")
assert(#wallMapVisibility >= 1 and wallMapVisibility[1].args[1] == 1, "the wall maps are blanked for the entity")
-- Regression (playtest 6): the capsule screens named who could still respawn
assert(capsuleScreen.Pseudo.text == "?????", "a capsule's occupant is a mystery to the entity")
assert(lastArgument(capsuleScreen.TextBlock_Pseudo, "SetText").text == "?????", "on its screen too")
fake.loadClass(game.paths.capsuleScreenClass)
capsuleScreen.Pseudo = { text = "Aidan" }
local capsuleSetText = fake.hooks[game.paths.capsuleScreenClass .. ":BPI_UI_SetText"]
capsuleSetText(fake.param(capsuleScreen), fake.param({ text = "Aidan" }))
assert(capsuleScreen.Pseudo.text == "?????", "a name written later is masked at once")
assert(lastArgument(widget.Actions, "SetVisibility") == 3, "the actions show once the player is the entity")
assert(lastArgument(widget.UltimateBar, "SetPercent") == 0.5, "the ultimate's bar shows the replicated meter")
assert(lastArgument(widget.UltimateBar, "SetVisibility") == 3, "while it charges")

-- Regression (playtest 6): a full meter kept "HEAD GRAB READY" on screen; the ultimate now shows like every action,
-- its bar gone once it's ready
link.Meter = 1
fake.runLoops(33)
assert(lastArgument(widget.UltimateBar, "SetVisibility") == 2, "a ready ultimate shows no bar")

-- A cooldown fills its bar; a ready action hides it
assert(lastArgument(widget.LashBar, "SetVisibility") == 2, "a ready action shows no bar")
fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name("Cooldown.Attack")), fake.param(0))
fake.runLoops(33)
assert(lastArgument(widget.LashBar, "SetVisibility") == 3, "a recharging action shows its bar")
assert(lastArgument(widget.LashBar, "SetPercent") == 0, "the bar starts empty and fills")

-- The health bar shows the pool the squid is on (playtest 6), green while it stands and red once it's down
assert(lastArgument(widget.HealthBar, "SetPercent") == 0.8, "the health bar shows the replicated pool")
assert(lastArgument(widget.HealthBar, "SetFillColorAndOpacity").R < 0.5, "in the crew HUD's green while standing")
link.Downed, link.Health = true, 0.3
fake.runLoops(33)
assert(lastArgument(widget.HealthBar, "SetFillColorAndOpacity").R > 0.5, "and red once the squid is down")
link.Downed, link.Health = false, 0.8
-- The stamina bar shows only once sprinting has used some
assert(lastArgument(widget.StaminaBar, "SetVisibility") == 2, "full stamina shows no bar")
link.Stamina = 0.4
fake.runLoops(33)
assert(lastArgument(widget.StaminaBar, "SetVisibility") == 3 and lastArgument(widget.StaminaBar, "SetPercent") == 0.4,
  "a used stamina bar shows how much is left")

-- The view cone sits on the minimap's centre and turns with the look (yaw 90 is up on the north-up map); the key hints
-- sit under the minimap
local minimapCentre = config.minimap.margin + config.minimap.size / 2
local conePosition = lastArgument(widget.ViewCone.Slot, "SetPosition")
assert(conePosition.X == -minimapCentre and conePosition.Y == minimapCentre, "the cone is on the minimap's centre")
assert(lastArgument(widget.ViewCone, "SetRenderTransformAngle") == 0, "pointing where the player looks")
assert(lastArgument(widget.Hints.Slot, "SetPosition").Y > config.minimap.margin + config.minimap.size,
  "the hints sit under the minimap")
assert(lastArgument(widget.Hints, "SetVisibility") == 3, "and show to begin with")

-- Regression (playtest 6): peek's slot sat on screen all the time. Its prompt shows only while C would work: in a
-- vent, over a grate, with peek recharged
fake.object("BP_Vent_Up_C", nil, { K2_GetActorLocation = function() return { X = 0, Y = 400, Z = 150 } end })
assert(lastArgument(widget.PeekPrompt, "SetVisibility") == 2, "no peek prompt outside a vent")
squid.InVent = true
fake.now = 1
fake.runLoops(33)
assert(lastArgument(widget.PeekPrompt, "SetVisibility") == 3, "the prompt shows in a vent over a grate")
fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name("Cooldown.Peek")), fake.param(0))
fake.runLoops(33)
assert(lastArgument(widget.PeekPrompt, "SetVisibility") == 2, "and hides while peek recharges")
fake.now = 2
-- H hides the prompts and hints, and brings them back
fake.keybinds.H()
fake.runLoops(33)
assert(lastArgument(widget.PeekPrompt, "SetVisibility") == 2 and lastArgument(widget.Hints, "SetVisibility") == 2,
  "H hides the peek prompt and the hints")
fake.keybinds.H()
fake.runLoops(33)
assert(lastArgument(widget.PeekPrompt, "SetVisibility") == 3 and lastArgument(widget.Hints, "SetVisibility") == 3,
  "and H again shows them")
fake.now = 0
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
local removalsBeforeTravel = #fake.callsTo(widget, "RemoveFromParent")
fake.world = fake.object("World")
controller.Pawn = fake.invalid()
fake.runLoops(33)
assert(#fake.callsTo(widget, "RemoveFromParent") == removalsBeforeTravel + 1, "the old world's HUD is removed")
fake.runLoops(33)
assert(createdWidgets == createdForMessage, "no HUD is rebuilt in a world where the host hasn't named this player")

-- Regression (playtest 6): after a hot reload the HUD never learned the player was the entity again, so it stayed
-- hidden. Driving the squid is proof enough on the player's own machine
for name in pairs(package.loaded) do
  if name:match("^entity%.") then
    package.loaded[name] = nil
  end
end
fake.loops, fake.customEvents, fake.hooks = {}, {}, {}
dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")
controller.Pawn = squid
local createdBeforeReload = createdWidgets
fake.runLoops(33)
assert(createdWidgets == createdBeforeReload + 1, "the reloaded HUD comes back while the player drives the squid")
assert(lastArgument(widget.Actions, "SetVisibility") == 3, "with the actions showing")

print("client flow test passed")
