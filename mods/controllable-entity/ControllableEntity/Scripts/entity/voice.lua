-- Copyright © 2026 Jalapeno Labs

-- Voice (playtest 6): nobody hears the entity at all, and the entity hears the crew only the way someone standing near
-- them would, never over their radio.
--
-- The game's voice is the Onset VoIP plugin. The host puts every player in two voice channels: 0 is proximity (3D,
-- from the speaker's pawn) and 1 is radio (2D, with the radio's static). Each player's own machine picks what its mic
-- sends (BP_MyPlayerState.UpdateComChannels: channel 1 while the radio key is held, else channel 0 on push-to-talk or
-- open mic). A listener hears a speaker only through a channel both are in, and the radio wins when both are.
--
--   - The entity's own machine never turns its mic on, whatever the game asks, and the radio key's click is silent.
--   - The host mutes the entity on both channels and takes it off the radio channel, for the rest of the mission.
--   - Every crew machine sends radio speech on the proximity channel too. The crew, in both channels, still hear the
--     radio; the entity, in proximity alone, hears the speaker only nearby, without the radio's effect.

local game = require("entity.game")

local voice = {}

local LOCAL_VOICE_CLASS = "/Script/OnsetVoip.OnsetVoipLocalPlayerSubsystem"
local LOCAL_VOICE_CLASS_NAME = "OnsetVoipLocalPlayerSubsystem"
local WORLD_VOICE_CLASS_NAME = "OnsetVoipWorldSubsystem"
local TALKER_CLASS = "/Script/OnsetVoip.OnsetVoipTalker"
local PLAYER_STATE_CLASS = "/Game/Blueprints/Player/BP_MyPlayerState.BP_MyPlayerState_C"
local PLAY_SOUND_2D = "/Script/Engine.GameplayStatics:PlaySound2D"
-- The click the radio key plays on the speaker's own machine (BP_MyPlayerState.SetUseRadio).
local RADIO_CLICK_NAME = "radio_static_placeholder"
local PROXIMITY_CHANNEL = 0
local RADIO_CHANNEL = 1

-- On the host: the entity's player state, whose talker stays silent for the rest of the mission; nil before one.
local silencedPlayerState = nil
-- On each machine: whether its own player drove the squid at the last check, so the game's voice hears of a change.
local wasLocalEntity = false

local function isLocalEntity()
  local controller = game.localController()
  return controller ~= nil and game.squidDrivenBy(controller) ~= nil
end

local function isEntityTalker(talker)
  if not silencedPlayerState or not silencedPlayerState:IsValid() then
    return false
  end
  local playerState = talker:GetPlayerState()
  return playerState:IsValid() and playerState:GetAddress() == silencedPlayerState:GetAddress()
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The entity's own machine
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Pre-hooks on the plugin's capture switches (native functions get pre-hooks, which may change the arguments).
local function keepEntityMicOff(_, captureParameter)
  if captureParameter:get() and isLocalEntity() then
    captureParameter:set(false)
  end
end

local function silenceEntityRadioClick(_, _, soundParameter, volumeParameter)
  local sound = soundParameter:get()
  if sound:IsValid() and sound:GetFName():ToString() == RADIO_CLICK_NAME and isLocalEntity() then
    volumeParameter:set(0)
  end
end

-- Runs about once a second on every machine: when its own player becomes the entity or stops being it, the game
-- picks the mic's channels again, through the switches above.
local function follow()
  local controller = game.localController()
  local isEntity = controller ~= nil and game.squidDrivenBy(controller) ~= nil
  if isEntity == wasLocalEntity or not controller then
    return
  end
  wasLocalEntity = isEntity
  local playerState = controller.PlayerState
  if playerState:IsValid() then
    playerState:UpdateComChannels()
  end
  game.log(isEntity and "The entity's mic is off" or "The mic is back to the game's own settings")
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The host
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Runs once a second on the host while there is an entity: silences its talker once per entity.
local function silenceEntity(entity)
  local playerState = entity.playerState
  local isSilenced = silencedPlayerState and silencedPlayerState:IsValid()
    and silencedPlayerState:GetAddress() == playerState:GetAddress()
  if isSilenced or not playerState:IsValid() then
    return
  end
  local worldVoice = FindFirstOf(WORLD_VOICE_CLASS_NAME)
  local talker = worldVoice and worldVoice:IsValid() and worldVoice:GetVoipTalker(playerState)
  if not talker or not talker:IsValid() then
    game.log("No voice talker for the entity yet; trying again in a second")
    return
  end
  silencedPlayerState = playerState
  talker:SetMutedOnVoiceChannel(true, PROXIMITY_CHANNEL)
  talker:SetMutedOnVoiceChannel(true, RADIO_CHANNEL)
  talker:SetVoiceChannel(RADIO_CHANNEL, false)
  game.log("The entity is silent to everyone, and off the crew's radio")
end

-- Pre-hooks on the entity's talker: the game sets these again (the proximity mute follows the player's own mute
-- setting, and both channels are rejoined whenever voice is switched back on), so they're held where the mod put them.
local function keepEntityMuted(context, mutedParameter)
  if isEntityTalker(context:get()) then
    mutedParameter:set(true)
  end
end

local function keepEntityOffRadio(context, channelParameter, addParameter)
  if channelParameter:get() == RADIO_CHANNEL and isEntityTalker(context:get()) then
    addParameter:set(false)
  end
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Every crew machine
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Post-hook on the game's channel pick: radio speech goes out on proximity as well.
local function alsoSendRadioNearby(context)
  local playerState = context:get()
  local controller = game.localController()
  local isOwnPlayer = controller and controller.PlayerState:IsValid()
    and controller.PlayerState:GetAddress() == playerState:GetAddress()
  if not isOwnPlayer or not playerState.want_use_radio or isLocalEntity() then
    return
  end
  local localVoice = FindFirstOf(LOCAL_VOICE_CLASS_NAME)
  if not localVoice or not localVoice:IsValid() then
    game.log("No local voice subsystem; the radio stays radio only")
    return
  end
  localVoice:ToggleVoiceCaptureWithChannels(true, { PROXIMITY_CHANNEL, RADIO_CHANNEL })
end

-- The plugin's functions are native, so they exist from the start and get pre-hooks. A game update that renames one
-- costs only that piece, which the log names, rather than the whole mod.
local function hookNative(functionPath, callback)
  local isHooked, problem = pcall(RegisterHook, functionPath, callback)
  if not isHooked then
    game.log("Could not hook %s (%s); that part of the entity's voice rules is off", functionPath, tostring(problem))
  end
end

function voice.register(takeover)
  for _, functionName in ipairs({ "ToggleVoiceCapture", "ToggleVoiceCaptureWithChannel",
    "ToggleVoiceCaptureWithChannels" }) do
    hookNative(LOCAL_VOICE_CLASS .. ":" .. functionName, keepEntityMicOff)
  end
  hookNative(PLAY_SOUND_2D, silenceEntityRadioClick)
  hookNative(TALKER_CLASS .. ":SetMutedOnVoiceChannel", keepEntityMuted)
  hookNative(TALKER_CLASS .. ":SetVoiceChannel", keepEntityOffRadio)
  game.hookWhenLoaded(PLAYER_STATE_CLASS, "UpdateComChannels", alsoSendRadioNearby)

  LoopInGameThreadWithDelay(1000, function()
    follow()
    local entity = game.isHost() and takeover.activeEntity()
    if entity then
      silenceEntity(entity)
    end
  end)
end

return voice
