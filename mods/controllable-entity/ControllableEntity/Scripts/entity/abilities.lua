-- Copyright © 2026 Jalapeno Labs

-- Host side of playing the squid: each command from the entity player becomes the squid's own move, the kill meter
-- decides whether a grab kills, and the meter's state goes back to the player's HUD.
--
-- Every move calls the same squid function its AI uses (mods/controllable-entity/README.md, "How the squid's moves
-- work"), so animations, damage and networking stay the game's own.

local config = require("entity.config")
local game = require("entity.game")
local hunt = require("entity.hunt")
local lair = require("entity.lair")
local links = require("entity.links")
local Meter = require("entity.meter")
local movement = require("entity.movement")
local takeover = require("entity.takeover")
local vents = require("entity.vents")

local abilities = {}

local meter = Meter.new(config.meter)
local readyAtByCommand = {}
local isPeeking = false

function abilities.meter()
  return meter
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Targets
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The crew member nearest the squid inside a cone around the aim, within reach; nil when nobody qualifies.
local function crewInCone(squid, aim, reach, coneDegrees)
  local origin = squid:K2_GetActorLocation()
  local minimumAlignment = math.cos(math.rad(coneDegrees / 2))
  local best, bestDistance = nil, reach

  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    if crewMember:IsValid() then
      local location = crewMember:K2_GetActorLocation()
      local distance = game.distance(origin, location)
      if distance > 0 and distance <= bestDistance then
        local alignment = ((location.X - origin.X) * aim.X + (location.Y - origin.Y) * aim.Y
          + (location.Z - origin.Z) * aim.Z) / distance
        if alignment >= minimumAlignment then
          best, bestDistance = crewMember, distance
        end
      end
    end
  end
  return best, bestDistance
end

-- The aim flattened onto the ground, for moves that travel along the floor.
local function horizontal(aim)
  local length = math.sqrt(aim.X * aim.X + aim.Y * aim.Y)
  if length < 1e-6 then
    return { X = 1, Y = 0, Z = 0 }
  end
  return { X = aim.X / length, Y = aim.Y / length, Z = 0 }
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Moves
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- With a crew member in reach, the AI's own attack on them. With nobody, the squid swings at the air anyway, like a
-- sword swung at nothing (playtest 6): the AI's attack needs a target (BP_BaseMonster.SetSimpleAttack does nothing
-- without one), so the swing's montage is played through the same multicast the attack ends in. Its damage comes
-- from the montage's sphere check in front of the squid (BP_ParentMonster.BasicSphereAttackDamage), which runs only
-- while the squid is attacking, so a swing at nothing hurts nobody.
local function attack(squid, aim)
  local target, distance = crewInCone(squid, aim, config.attack.reach, config.attack.coneDegrees)
  if target then
    squid:BPI_BasicMonster_SetSimpleAttack(target, target:K2_GetActorLocation(), distance)
    return true
  end

  local swing = StaticFindObject(game.paths.swingMontage)
  if not swing or not swing:IsValid() then
    game.log("No swing montage at %s; the lash only lands on a crew member in reach", game.paths.swingMontage)
    return false, "NoTarget"
  end
  squid["AttackSimpleAnim (Clients)"](squid, swing, squid.AttackSimplePlayRate, nil)
  return true
end

-- The AI's leap checks its own range and arc, then writes LastSpecialAttackPlayerLocation for SetSpecialAttack to
-- warp to. The entity leaps where they aim, so the landing point is written here instead.
local function leap(squid, aim)
  local origin = squid:K2_GetActorLocation()
  local direction = horizontal(aim)
  squid.LastSpecialAttackPlayerLocation = {
    X = origin.X + direction.X * config.leap.distance,
    Y = origin.Y + direction.Y * config.leap.distance,
    Z = origin.Z,
  }
  local target = crewInCone(squid, aim, config.leap.distance + 150, config.attack.coneDegrees)
  squid:BPI_Monster_SetSpecialAttack(target or squid)
  return true
end

-- In a room, venting climbs into the shaft above. In the ducts it takes whichever is nearer: the shaft opening below,
-- dropping out onto whoever is under it, or the foot of a step up, climbing it with the AI's own climb (playtest 6:
-- the player had no way up the elbow joints the AI climbs). Dropping out leaves the ducts, so it waits for the power
-- while the lair holds the squid; climbing stays inside them, so it doesn't.
local function vent(squid)
  local location = squid:K2_GetActorLocation()
  if not squid.InVent then
    if hunt.areVentsShut() then
      return false, "VentsShut"
    end
    local entrance = vents.nearest(location, config.vents.enterReach)
    if not entrance then
      return false, "NoVentEntrance"
    end
    squid:BPI_Monster_JumpToVent(entrance, true)
    return true
  end

  local exit, exitDistance = vents.nearest(location, config.vents.exitReach)
  local climb, climbDistance = vents.nearestClimb(location)
  if climb and (not exit or climbDistance < exitDistance) then
    isPeeking = false
    -- FromUp false: the climb up, from the step's foot
    squid:BPI_Monster_ClimbVent250(climb, false)
    return true
  end
  if not exit then
    return false, "NoVentExit"
  end
  if lair.isLeashed(squid) then
    return false, "PowerOff"
  end
  isPeeking = false
  local target = crewInCone(squid, { X = 0, Y = 0, Z = -1 }, config.vents.exitReach, 120)
  squid:BPI_Monster_AttackFromVent(exit, target)
  return true
end

local function peek(squid)
  if not squid.InVent then
    return false, "NotInVent"
  end
  local grate = vents.nearest(squid:K2_GetActorLocation(), config.vents.exitReach)
  if not grate then
    return false, "NoVentExit"
  end
  isPeeking = not isPeeking
  squid:BPI_Monster_LookFromVent(grate, isPeeking, false)
  return true
end

-- The ultimate arms the guaranteed kill, then leaps (or drops from the vent) at once to deliver it.
local function ultimate(squid, aim, now)
  if not meter:arm(now) then
    return false, "UltimateNotReady"
  end
  if squid.InVent then
    return vent(squid, aim)
  end
  return leap(squid, aim)
end

local moveByCommand = {
  Attack = attack,
  Leap = leap,
  Vent = vent,
  Peek = peek,
  Ultimate = ultimate,
}

-- Runs a command from the entity player: checks it came from the entity and is off cooldown, then moves the squid.
local function runCommand(command)
  return function(_, controller, aim)
    -- Asked first: it is also what takes a reloaded mod's entity back at once
    local isEntity = takeover.isEntityController(controller)
    local entity = takeover.activeEntity()
    if not isEntity or not entity then
      game.log("%s from a player who isn't the entity; ignored", command)
      return
    end

    if config.lair.heldMoves[command] and lair.isLeashed(entity.squid) then
      links.sendEvent(controller, "Denied.PowerOff")
      return
    end

    local now = game.timeSeconds(entity.squid)
    if now < (readyAtByCommand[command] or 0) then
      links.sendEvent(controller, "Denied.Cooldown")
      return
    end

    local ok, reason = moveByCommand[command](entity.squid, aim, now)
    if not ok then
      links.sendEvent(controller, "Denied." .. reason)
      return
    end

    readyAtByCommand[command] = now + config.cooldowns[command]
    links.sendEvent(controller, "Cooldown." .. command, config.cooldowns[command])
  end
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The kill
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Every grab starts in GrabHeadPlayer, from the leap or the vent drop. A grab the meter doesn't allow is broken off
-- with the game's own "hit while grabbing" knockback, which releases the player on every machine and clears the
-- squid's IsGrabPlayer, the flag its decapitation checks before killing.
local function onGrabStarted(context)
  local squid = context:get()
  local entity = takeover.activeEntity()
  if not entity or not squid:HasAuthority() or squid:GetAddress() ~= entity.squid:GetAddress() then
    return
  end

  local now = game.timeSeconds(squid)
  if meter:grabKills(now) then
    meter:spendKill(now)
    links.sendEvent(entity.controller, "KillStarted")
    return
  end

  -- One frame later, once the grab's own multicast has finished, so the knockback replaces it cleanly
  ExecuteInGameThreadAfterFrames(1, function()
    if not squid:IsValid() then
      return
    end
    local montage = StaticFindObject(game.paths.grabInterruptedMontage)
    squid["KnockBack (Clients)"](squid, montage, 1.0)
  end)
  links.sendEvent(entity.controller, "Denied.UltimateNotReady")
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Meter
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local lastTickAt = nil

-- Runs about five times a second on the host. Meter reads "how ready the kill is": the meter outside full frenzy,
-- the re-arm progress inside it.
function abilities.tick()
  local entity = takeover.activeEntity()
  if not entity then
    lastTickAt = nil
    return
  end

  local now = game.timeSeconds(entity.squid)
  meter:advance(now, lastTickAt and now - lastTickAt or 0)
  lastTickAt = now

  local link = links.forController(entity.controller)
  if not link then
    return
  end
  local inFullFrenzy = meter.frenzy == Meter.frenzyLevels.Full
  link.Frenzy = inFullFrenzy
  if inFullFrenzy then
    link.Meter = 1 - meter:frenzyRearmRemaining(now) / config.meter.frenzyRearm
  else
    link.Meter = meter.value
  end

  -- The HUD's health bar shows the pool the squid is on: stagger while standing, real health while down
  local squid = entity.squid
  local fields = game.squidHealthFields
  local downed = squid[fields.downed] == true
  local current = downed and squid[fields.health] or squid[fields.stagger]
  local maximum = downed and squid[fields.maxHealth] or squid[fields.maxStagger]
  link.Downed = downed
  link.Health = (maximum and maximum > 0) and current / maximum or 1
  link.Stamina = movement.stamina()
  link.VentTime = hunt.ventTimeLeft()
end

function abilities.register()
  for command in pairs(moveByCommand) do
    links.onCommand(command, runCommand(command))
  end
  game.hookWhenLoaded(game.paths.squidClass, "GrabHeadPlayer", onGrabStarted)
end

return abilities
