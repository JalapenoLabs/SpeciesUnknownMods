-- Copyright © 2026 Jalapeno Labs

-- Voice on a player's own machine: as the entity their mic never turns on and the radio key's click is silent; as
-- crew, radio speech also goes out on the proximity channel, so the entity hears it nearby.
-- Run from the repository root: lua mods/controllable-entity/tests/voice_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.isHost = false

local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modClasses)
fake.object("GameStateBase")
fake.world = fake.object("World")

local playerState = fake.object("BP_MyPlayerState_C", { want_use_radio = false })
local controller = fake.object("BP_MyPlayerController_C", { Pawn = fake.invalid(), PlayerState = playerState }, {
  IsLocalController = function() return true end,
}, { "PlayerController" })
fake.giveView(controller)
local squid = fake.object("BP_Monster_Poulpi_C")
fake.giveSquidState(squid)
local localVoice = fake.object("OnsetVoipLocalPlayerSubsystem")

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")
fake.loadClass("/Game/Blueprints/Player/BP_MyPlayerState.BP_MyPlayerState_C")

local voicePath = "/Script/OnsetVoip.OnsetVoipLocalPlayerSubsystem:"
local function captureAsked(functionName)
  local capture = fake.param(true)
  fake.hooks[voicePath .. functionName](fake.param(localVoice), capture, fake.param(0))
  return capture:get()
end
local function clickVolume(soundName)
  local volume = fake.param(1)
  local sound = fake.object(soundName)
  sound.GetFName = function() return fake.name(soundName) end
  fake.hooks["/Script/Engine.GameplayStatics:PlaySound2D"](fake.param(nil), fake.param(controller), fake.param(sound),
    volume)
  return volume:get()
end

-- As crew, the game's own voice settings stand
assert(captureAsked("ToggleVoiceCaptureWithChannel") == true, "the crew's mic works as the game sets it")
assert(clickVolume("radio_static_placeholder") == 1, "the crew hear their radio click")

-- As crew holding the radio key, speech also goes out on the proximity channel
playerState.want_use_radio = true
fake.hooks["/Game/Blueprints/Player/BP_MyPlayerState.BP_MyPlayerState_C:UpdateComChannels"](fake.param(playerState))
local both = fake.callsTo(localVoice, "ToggleVoiceCaptureWithChannels")
assert(#both == 1 and both[1].args[1] == true and both[1].args[2][1] == 0 and both[1].args[2][2] == 1,
  "radio speech is sent nearby too, so the entity hears a crew member on the radio only up close")
playerState.want_use_radio = false

-- Regression (playtest 6): the entity's radio key played the crew's radio sound, and their voice reached the crew.
-- As the entity, the mic never turns on and the click is silent
controller.Pawn = squid
fake.runLoops(1000)
assert(#fake.callsTo(playerState, "UpdateComChannels") == 1, "becoming the entity has the game pick the mic again")
assert(captureAsked("ToggleVoiceCapture") == false, "and the entity's mic stays off")
assert(captureAsked("ToggleVoiceCaptureWithChannel") == false, "on any channel")
assert(captureAsked("ToggleVoiceCaptureWithChannels") == false, "or channels")
assert(clickVolume("radio_static_placeholder") == 0, "the radio key's click is silent")
assert(clickVolume("UI_Click") == 1, "other sounds play as normal")
fake.runLoops(1000)
assert(#fake.callsTo(playerState, "UpdateComChannels") == 1, "once per change")

-- Once the player stops driving the squid, the game's settings are back
controller.Pawn = fake.invalid()
fake.runLoops(1000)
assert(#fake.callsTo(playerState, "UpdateComChannels") == 2 and captureAsked("ToggleVoiceCapture") == true,
  "the mic is back to the game's own settings")

-- Regression (playtest 7): leaving a mission for the main menu asked the main menu's player state, which has no
-- voice, to pick the mic's channels, and failed
controller.Pawn = squid
fake.runLoops(1000)
local menuPlayerState = fake.object("BP_MainMenuPlayerState_C", nil, {
  UpdateComChannels = function() error("the main menu's player state has no voice") end,
})
controller.PlayerState = menuPlayerState
controller.Pawn = fake.invalid()
fake.runLoops(1000)
assert(captureAsked("ToggleVoiceCapture") == true, "back at the main menu, the mic is the game's again")

print("voice test passed")
