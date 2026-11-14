-- Copyright © 2026 Jalapeno Labs

-- The entity's fear (playtest 9: "when low health or being hunted or possibly killed, there's little 'fear' to the
-- entity player. There's no heart racing, there's no hud making you panic"): the crew's own fear effects, on the
-- entity player's machine.
--
-- The host weighs how afraid the entity is, 0 to 1, and sends it on the player's link (Fear): down or fleeing, wholly;
-- low on health, from a quarter at 30% to wholly at 10%, as the crew's heartbeat quickens; burning, and hunted (the
-- crew holding the weapon that can kill it, one of them near), partly. The entity's machine turns it into what the
-- crew feel (BP_Character):
--   - the heartbeat: the crew's beat (Heartbeat_1), one every 4 seconds at a quarter's fear down to one a second,
--     higher pitched and louder the more afraid;
--   - the red vignette: the crew's own post-process (PostProcess_Player_Mat_Inst), closing in as the health bar drains
--     (Density), wholly while down, pulsing with each beat (HeartBeat), and flashing on every hit (HitValue);
--   - the adrenaline blur: the crew's radial blur (M_RadialBlurHLSL_Inst), briefly, when knocked down, hit hard, or as
--     the flight starts.
-- The parked crew body the player drove before keeps its own vignette and heartbeat running on their machine; those
-- stop.

local config = require("entity.config")
local flee = require("entity.flee")
local game = require("entity.game")
local hunt = require("entity.hunt")
local links = require("entity.links")
local postprocess = require("entity.postprocess")

local fear = {}

local VIGNETTE_MATERIALS = { "/Game/Materials/PostProcess_Player_Mat_Inst.PostProcess_Player_Mat_Inst" }
local BLUR_MATERIALS = { "/Game/Chameleon/Materials/M_RadialBlurHLSL_Inst.M_RadialBlurHLSL_Inst" }
local HEARTBEAT_SOUND = "/Game/Sound/Player/Heartbeat_1.Heartbeat_1"
-- Below this change, a material parameter or blend weight isn't written again.
local PARAMETER_STEP = 0.01

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Host
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function mapRange(value, fromLow, fromHigh, toLow, toHigh)
  local alpha = math.max(0, math.min(1, (value - fromLow) / (fromHigh - fromLow)))
  return toLow + (toHigh - toLow) * alpha
end

local function isCrewNear(monster, distance)
  local origin = monster:K2_GetActorLocation()
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    local isAlive = crewMember:IsValid() and not crewMember.bHidden and crewMember.IsDead ~= true
    if isAlive and game.distance(origin, crewMember:K2_GetActorLocation()) <= distance then
      return true
    end
  end
  return false
end

-- How afraid the entity is, 0 to 1, given the health bar's share and whether it is down.
function fear.levelOnHost(entity, healthShare, isDown)
  if isDown or flee.isFleeing() then
    return 1
  end
  local settings = config.fear
  local level = 0
  if healthShare < settings.lowHealthShare then
    level = mapRange(healthShare, settings.lowHealthShare, settings.lowestHealthShare, settings.lowHealthFear, 1)
  end
  local burningField = entity.kit.burningField
  if burningField and entity.monster[burningField] > settings.burningHeat then
    level = math.max(level, settings.burningFear)
  end
  if level < settings.huntedFear and hunt.isHunting() and isCrewNear(entity.monster, settings.huntedDistance) then
    level = settings.huntedFear
  end
  return level
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Entity player
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The effects on this machine's entity: { monsterAddress, vignette, blur, written, nextBeatAt, beatAt, lastShare,
-- wasDown, flashAt, flashStrength, blurAt }, or nil.
local felt = nil
-- Set when the host says the flight started, for the next frame's blur.
local fleeStarted = false

local function writeScalar(effect, name, value)
  if not effect or math.abs((felt.written[name] or -1) - value) < PARAMETER_STEP then
    return
  end
  felt.written[name] = value
  effect.material:SetScalarParameterValue(FName(name), value)
end

-- The crew body the player drove before is parked, hidden, and still runs its owner's fear on this machine.
local function quietParkedBodies()
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    if crewMember:IsValid() and crewMember.bHidden then
      crewMember.PostProcess.bEnabled = false
      crewMember:BPI_Player_StopLifePulse()
    end
  end
end

local function setUp(monster)
  local monsterAddress = monster:GetAddress()
  if felt and felt.monsterAddress == monsterAddress then
    return
  end
  quietParkedBodies()
  felt = {
    monsterAddress = monsterAddress,
    vignette = postprocess.add(monster, VIGNETTE_MATERIALS, 1.0, "fear vignette"),
    blur = postprocess.add(monster, BLUR_MATERIALS, 0, "adrenaline blur"),
    written = {},
    nextBeatAt = 0,
    beatAt = -math.huge,
    lastShare = nil,
    wasDown = false,
    flashAt = -math.huge,
    flashStrength = 0,
    blurAt = -math.huge,
  }
end

-- The crew's beat envelope: up to its peak in 0.2 s, held to 0.3 s, gone by 1 s.
local function pulseOf(age)
  if age < 0 or age >= 1 then
    return 0
  end
  if age < 0.2 then
    return age / 0.2
  end
  if age < 0.3 then
    return 1
  end
  return 1 - (age - 0.3) / 0.7
end

local function beat(monster, level, now)
  local settings = config.fear
  felt.beatAt = now
  felt.nextBeatAt = now + 1 / math.max(settings.lowHealthFear, level)
  local sound = game.loadGameAsset(HEARTBEAT_SOUND)
  if sound then
    local volume = mapRange(level, 0, 1, settings.quietestBeat, 1)
    local pitch = mapRange(level, 0, 1, settings.lowestPitch, settings.highestPitch)
    StaticFindObject(game.paths.gameplayStatics):PlaySound2D(monster, sound, volume, pitch, 0, nil, nil, true)
  end
end

-- The blur: in over 0.2 s, held to 1 s, out by 1.5 s, its width easing from 3 to 0.75 from 0.5 s on.
local function drawBlur(now)
  local age = now - felt.blurAt
  local weight = 0
  if age < 0.2 then
    weight = age / 0.2
  elseif age < 1.0 then
    weight = 1
  elseif age < 1.5 then
    weight = 1 - (age - 1.0) / 0.5
  end
  if felt.blur and math.abs((felt.written.blurWeight or -1) - weight) >= PARAMETER_STEP then
    felt.written.blurWeight = weight
    felt.blur.component.BlendWeight = weight
  end
  if weight > 0 then
    writeScalar(felt.blur, "BlurWidth", mapRange(age, 0.5, 1.5, 3.0, 0.75))
  end
end

-- Runs about thirty times a second on the entity player's machine while they drive the entity.
function fear.follow(monster, link, now)
  setUp(monster)
  if not link then
    return
  end
  local settings = config.fear
  -- An older pak's link has no Fear: its machine shows the vignette and flashes, but no heartbeat
  local share, isDown, level = link.Health, link.Downed == true, link.Fear or 0

  -- A hit drains the bar: a flash as strong as the hit, and the blur for a hard one; and the blur on going down, or as
  -- the flight starts
  local drop = felt.lastShare and felt.lastShare - share or 0
  if drop >= settings.hitShare then
    felt.flashAt, felt.flashStrength = now, mapRange(drop, 0, 0.5, 0.75, 2.0)
  end
  if drop >= settings.hardHitShare or (isDown and not felt.wasDown) or fleeStarted then
    felt.blurAt = now
  end
  felt.lastShare, felt.wasDown, fleeStarted = share, isDown, false

  if level > 0 and now >= felt.nextBeatAt then
    beat(monster, level, now)
  end
  local density = isDown and 2.0 or 2 * (1 - share)
  writeScalar(felt.vignette, "Density", density)
  writeScalar(felt.vignette, "HeartBeat", 0.5 * pulseOf(now - felt.beatAt))
  writeScalar(felt.vignette, "HitValue", felt.flashStrength * math.max(0, 1 - (now - felt.flashAt) / 0.5))
  drawBlur(now)
end

-- Once the player no longer drives the entity, the effects go.
function fear.forget()
  if not felt then
    return
  end
  postprocess.remove(felt.vignette)
  postprocess.remove(felt.blur)
  felt = nil
end

function fear.register()
  links.onClientEvent("Fleeing", function()
    fleeStarted = true
  end)
end

return fear
