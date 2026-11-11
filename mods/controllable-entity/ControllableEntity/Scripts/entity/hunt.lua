-- Copyright © 2026 Jalapeno Labs

-- The hunt, on the host: once a crew member holds the weapon that can kill the specimen (kill and capture contracts),
-- the vents stop being a hiding place. A human entity could otherwise wait in them for the rest of the mission
-- (playtest 6), which the AI never does.
--
-- From then on the squid has a vent-time budget that drains while it's in the vents and refills slowly outside them.
-- When it runs out, the squid is forced out through the nearest opening, and the vents stay shut to it until the
-- budget has refilled partway. A squid still in the vents a while after being forced out (in a spot the drop can't
-- reach) is moved out to the power room.
--
-- The hunted squid is also loud: every so often it cries out, so the crew can follow it. The AI's cries come from its
-- behaviour tree, which a player's squid doesn't run, so the host plays them: the squid's own voice, replicated to
-- every machine and heard near it (cries.lua), and its far call, which only listeners well away from it hear.

local config = require("entity.config")
local cries = require("entity.cries")
local game = require("entity.game")
local lair = require("entity.lair")
local links = require("entity.links")
local vents = require("entity.vents")

local hunt = {}

local POWER_SCREEN_CLASS_NAME = "BP_Screen_RestorePower_C"
local NAVIGATION = "/Script/NavigationSystem.Default__NavigationSystemV1"
-- How far in front of the power screen the squid is put, and how far around that spot the navigation may look for
-- floor.
local POWER_SCREEN_STANDOFF = 150
local FLOOR_SEARCH_EXTENT = { X = 300, Y = 300, Z = 1500 }

-- The hunt in the current mission: { worldKey, ventSecondsLeft, isShut, forcedOutAt, lastTickAt, nextCryAt }; nil
-- until a crew member holds the special weapon.
local current = nil

-- The squid's way out when its vent time is up: down the shaft within reach, or, deeper in the ducts, to a spot
-- beside the nearest shaft on its floor first, then down that one.
local function forceOut(entity, now)
  local monster = entity.monster
  current.isShut = true
  current.forcedOutAt = now
  links.sendEvent(entity.controller, "ForcedOut")

  local location = monster:K2_GetActorLocation()
  local shaft = vents.nearest(location, config.vents.exitReach)
  if shaft then
    monster:BPI_Monster_AttackFromVent(shaft, nil)
    game.log("Vent time is up: the squid drops out of the shaft beside it")
    return
  end

  shaft = vents.nearest(location, math.huge)
  local spot = shaft and vents.spotsOf(shaft)[1]
  if not spot then
    game.log("Vent time is up, but no shaft opens near the squid's floor; it goes to the power room if it stays")
    return
  end
  vents.moveInto(monster, spot, function()
    monster:BPI_Monster_AttackFromVent(shaft, nil)
  end)
  game.log("Vent time is up: the squid is taken to the nearest shaft (%.0f, %.0f, %.0f) and drops out", spot.X,
    spot.Y, spot.Z)
end

-- The last resort for a squid the drop couldn't get out of the vents: the floor in front of the screen that restores
-- the power (BP_Screen_RestorePower, one per map), as the navigation finds it.
local function moveToPowerRoom(entity)
  local monster = entity.monster
  current.forcedOutAt = nil
  local screen = FindFirstOf(POWER_SCREEN_CLASS_NAME)
  if not screen or not screen:IsValid() then
    game.log("No power screen on this map; the squid stays where it is")
    return
  end
  local front = screen:GetActorForwardVector()
  local base = screen:K2_GetActorLocation()
  local spot = {
    X = base.X + front.X * POWER_SCREEN_STANDOFF,
    Y = base.Y + front.Y * POWER_SCREEN_STANDOFF,
    Z = base.Z,
  }
  local floor = {}
  local navigation = StaticFindObject(NAVIGATION)
  if navigation:K2_ProjectPointToNavigation(monster, spot, floor, nil, nil, FLOOR_SEARCH_EXTENT) and floor.Z then
    spot = { X = floor.X, Y = floor.Y, Z = floor.Z + monster.CapsuleComponent:GetScaledCapsuleHalfHeight() }
  else
    game.log("No floor found in front of the power screen; the squid is placed beside the screen instead")
  end
  monster:BPI_Monster_SetInVent(false)
  monster:K2_TeleportTo(spot, monster:K2_GetActorRotation())
  game.log("The squid was still in the vents after being forced out: moved to the power room (%.0f, %.0f, %.0f)",
    spot.X, spot.Y, spot.Z)
end

-- The hunted squid's cry: its roar near it, and its far call for everyone well away from it.
local function cry(monster)
  cries.play(monster, "Roar", false)
  monster["PlayVoiceFar(Multi)"](monster)
end

-- Starts the hunt in the current world. The game runs the grab again on every re-grab; the hunt starts once.
local function begin()
  local worldKey = game.currentWorldKey()
  if current and current.worldKey == worldKey then
    return
  end
  current = {
    worldKey = worldKey,
    ventSecondsLeft = config.hunt.ventSeconds,
    isShut = false,
    forcedOutAt = nil,
    lastTickAt = nil,
    nextCryAt = 0,
  }
  -- The lair can't hold a squid the vents won't keep
  lair.release()
  game.log("The crew holds the special weapon: the squid has %d seconds in the vents at a time",
    config.hunt.ventSeconds)
end

-- Whether the vents are shut to the squid: its vent time ran out and hasn't refilled enough yet.
function hunt.areVentsShut()
  return current ~= nil and current.isShut
end

-- How much of the squid's vent time is left, 0 to 1: full until the hunt starts.
function hunt.ventTimeLeft()
  if not current then
    return 1
  end
  return current.ventSecondsLeft / config.hunt.ventSeconds
end

-- Runs five times a second on the host while there is an entity: drains or refills the vent time, forces the squid
-- out when it runs out, and opens the vents again once it has refilled enough.
function hunt.tick(entity, now)
  if not current then
    return
  end
  if current.worldKey ~= entity.worldKey then
    current = nil
    return
  end

  local monster = entity.monster
  local elapsed = current.lastTickAt and now - current.lastTickAt or 0
  current.lastTickAt = now
  local isInVent = monster.InVent == true
  local budget = config.hunt.ventSeconds
  if isInVent then
    current.ventSecondsLeft = math.max(0, current.ventSecondsLeft - elapsed)
  else
    current.ventSecondsLeft = math.min(budget, current.ventSecondsLeft + elapsed / config.hunt.refillSlowdown)
    current.forcedOutAt = nil
  end

  if current.isShut and current.ventSecondsLeft >= budget * config.hunt.reopenFraction then
    current.isShut = false
    links.sendEvent(entity.controller, "VentsReopened")
    game.log("The squid's vent time has refilled enough: the vents take it again")
  end

  if now >= current.nextCryAt then
    current.nextCryAt = now + config.hunt.crySeconds
    cry(monster)
  end

  if not isInVent then
    return
  end
  if current.ventSecondsLeft <= 0 and not current.isShut then
    forceOut(entity, now)
    return
  end
  if current.forcedOutAt and now - current.forcedOutAt >= config.hunt.stuckSeconds then
    moveToPowerRoom(entity)
  end
end

function hunt.register()
  game.hookWhenLoaded(game.paths.weaponClass, "BPI_Weapon_SetGrabbed", function(context)
    if game.isSpecialWeaponGrab(context:get()) then
      begin()
    end
  end)
end

return hunt
