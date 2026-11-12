-- Copyright © 2026 Jalapeno Labs

-- Host side of playing the entity: each command from the entity player becomes one of its monster's own moves
-- (moves/<name>.lua), the kill meter decides whether a grab kills, and the meter's state goes back to the player's HUD.
--
-- Every move calls the same function the monster's AI uses (mods/controllable-entity/README.md, "How the moves
-- work"), so animations, damage and networking stay the game's own.

local config = require("entity.config")
local cries = require("entity.cries")
local ducts = require("entity.moves.ducts")
local game = require("entity.game")
local hunt = require("entity.hunt")
local kits = require("entity.kits")
local lair = require("entity.lair")
local links = require("entity.links")
local Meter = require("entity.meter")
local moves = require("entity.moves")
local movement = require("entity.movement")
local takeover = require("entity.takeover")
local zones = require("entity.zones")

local abilities = {}

local meter = Meter.new(config.meter)
local readyAtByCommand = {}

function abilities.meter()
  return meter
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Commands
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The ultimate arms the guaranteed kill, then the entity's own ultimate delivers it at once: armed first, so a grab
-- the move starts right away already kills. A move that finds nobody stands the kill down again, unspent.
local function ultimate(monster, aim, now, kitMoves)
  -- Before arming, so the meter isn't spent on a kill the shuttle's approach won't allow
  if zones.isNearShuttle(monster:K2_GetActorLocation()) then
    return false, "ShuttleZone"
  end
  if not meter:arm(now) then
    return false, "UltimateNotReady"
  end
  local ok, reason = kitMoves.Ultimate(monster, aim, now)
  if not ok then
    meter:standDown()
  end
  return ok, reason
end

-- What each command does, given the entity's own moves. The four slots are the entity's (kits.slots); peeking is for
-- an entity that lives in the vents; the cries, which everyone near the entity hears, are a choice to give itself
-- away.
local moveByCommand = {
  Primary = function(monster, aim, now, kitMoves) return kitMoves.Primary(monster, aim, now) end,
  Secondary = function(monster, aim, now, kitMoves) return kitMoves.Secondary(monster, aim, now) end,
  Ultimate = ultimate,
  Mobility = function(monster, aim, now, kitMoves) return kitMoves.Mobility(monster, aim, now) end,
  Peek = function(monster, _, _, kitMoves)
    if not kitMoves.Peek then
      return false, "NotInVent"
    end
    return kitMoves.Peek(monster)
  end,
  Roar = function(monster) return cries.play(monster, "Roar", true) end,
  Curious = function(monster) return cries.play(monster, "Curious", true) end,
  Call = function(monster) return cries.play(monster, "Call", true) end,
}

-- Runs a command from the entity player: checks it came from the entity and is off cooldown, then moves the monster.
-- A slot's cooldown, and whether the lair holds it back, are the entity's own (its kit's moves); the rest are shared.
local function runCommand(command)
  return function(_, controller, aim)
    -- Asked first: it is also what takes a reloaded mod's entity back at once
    local isEntity = takeover.isEntityController(controller)
    local entity = takeover.activeEntity()
    if not isEntity or not entity then
      game.log("%s from a player who isn't the entity; ignored", command)
      return
    end

    -- Down (the squid knocked over, Mike stunned, the Terminator shut down) or in one of the game's own reactions
    -- (BasicOverrideAnim: falling over, getting up), the monster does nothing, as the AI's doesn't (its CanMove): the
    -- crew get their few seconds to finish it, and a move then cut the squid's get-up short, which left it down for
    -- good on the host (playtest 9)
    local monster = entity.monster
    if monster[entity.kit.healthFields.downed] == true or monster.BasicOverrideAnim == true then
      links.sendEvent(controller, "Denied.Down")
      return
    end

    local slotMove = entity.kit.moves[command]
    local isHeld = slotMove ~= nil and slotMove.heldByLair
    if isHeld and lair.isLeashed(entity.monster) then
      links.sendEvent(controller, lair.heldDenial())
      return
    end

    -- A move still recharging says nothing: its bar already shows it (playtest 9: "Not yet" on every vent was noise)
    local now = game.timeSeconds(entity.monster)
    if now < (readyAtByCommand[command] or 0) then
      return
    end

    local ok, reason = moveByCommand[command](entity.monster, aim, now, moves.byKitId[entity.kit.id])
    if not ok then
      -- Nor does a move that can't be made just yet (Mike's grab while he already holds someone)
      if reason ~= "Cooldown" then
        links.sendEvent(controller, "Denied." .. reason)
      end
      return
    end

    local cooldown = slotMove and slotMove.cooldown or config.cooldowns[command]
    readyAtByCommand[command] = now + cooldown
    links.sendEvent(controller, "Cooldown." .. command, cooldown)
  end
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The kill
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Every grab that kills starts in the kit's kill grab (the squid's GrabHeadPlayer, Mike's GrabPlayerVent), whichever
-- move led to it. A grab the meter doesn't allow is broken off with the monster's own "hit while grabbing" knockback,
-- which interrupts the grab on every machine: the monster lets go before the kill lands.
local function onGrabStarted(context)
  local monster = context:get()
  local entity = takeover.activeEntity()
  if not entity or not monster:HasAuthority() or monster:GetAddress() ~= entity.monster:GetAddress() then
    return
  end

  local now = game.timeSeconds(monster)
  local isNearShuttle = zones.isNearShuttle(monster:K2_GetActorLocation())
  if meter:grabKills(now) and not isNearShuttle then
    meter:spendKill(now)
    links.sendEvent(entity.controller, "KillStarted")
    return
  end

  -- One frame later, once the grab's own multicast has finished, so the knockback replaces it cleanly
  ExecuteInGameThreadAfterFrames(1, function()
    if not monster:IsValid() then
      return
    end
    local montage = StaticFindObject(entity.kit.killGrab.breakMontage)
    monster["KnockBack (Clients)"](monster, montage, 1.0)
  end)
  links.sendEvent(entity.controller, isNearShuttle and "Denied.ShuttleNoKill" or "Denied.UltimateNotReady")
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Meter
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local lastTickAt = nil
-- When each crew member last charged the meter with a hit, by their address.
local lastChargedAtByVictim = {}

-- A monster's hit reaches a crew member through their HitDamageFromMonster (BP_ParentMonster.HitDamageSimple, on the
-- host): one the entity landed charges the kill meter (playtest 9). One swing hits several times as its damage ticks,
-- so each crew member charges it at most once every hitChargeSeconds. A shield in the way takes the hit itself, so it
-- never charges it. Other monsters' hits don't either.
local function onCrewHit(context, _, _, _, damageCauserParameter)
  local entity = takeover.activeEntity()
  local causer = damageCauserParameter:get()
  local isEntityHit = entity and game.isHost() and causer and causer:IsValid()
    and causer:GetAddress() == entity.monster:GetAddress()
  if not isEntityHit then
    return
  end
  local victim = context:get()
  local now = game.timeSeconds(victim)
  local victimKey = victim:GetAddress()
  if now - (lastChargedAtByVictim[victimKey] or -math.huge) < config.meter.hitChargeSeconds then
    return
  end
  lastChargedAtByVictim[victimKey] = now
  meter:addCharge(config.meter.hitCharge)
end

-- The share of the pool that hits are draining, for the HUD's health bar, and whether the entity is down: the squid's
-- stagger while it stands and its real health once a hit has knocked it down; an entity with one pool (Mike) always
-- shows that. Mike's refills past its maximum after his second face breaks, so the share is clamped.
local function healthShare(monster, fields)
  local downed = monster[fields.downed] == true
  local onStagger = fields.stagger ~= nil and not downed
  local current = onStagger and monster[fields.stagger] or monster[fields.health]
  local maximum = onStagger and monster[fields.maxStagger] or monster[fields.maxHealth]
  if not maximum or maximum <= 0 then
    return 1, downed
  end
  return math.min(1, current / maximum), downed
end

-- Runs about five times a second on the host. Meter reads "how ready the kill is": the meter outside full frenzy,
-- the re-arm progress inside it.
function abilities.tick()
  local entity = takeover.activeEntity()
  if not entity then
    lastTickAt = nil
    return
  end

  local now = game.timeSeconds(entity.monster)
  meter:advance(now, lastTickAt and now - lastTickAt or 0)
  lastTickAt = now
  ducts.tick(entity.monster)

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

  local kitMoves = moves.byKitId[entity.kit.id]
  if kitMoves.healthShare then
    link.Health, link.Downed = kitMoves.healthShare(entity.monster)
  else
    link.Health, link.Downed = healthShare(entity.monster, entity.kit.healthFields)
  end
  link.Stamina = movement.stamina()
  link.VentTime = hunt.ventTimeLeft()
end

-- Letting go of a move that is held (the Terminator's gatling, on Shoot) stops it, cooldown or not. An entity whose
-- Primary isn't held has nothing to let go of.
local function onPrimaryRelease(_, controller)
  local entity = takeover.isEntityController(controller) and takeover.activeEntity()
  if not entity then
    game.log("PrimaryRelease from a player who isn't the entity; ignored")
    return
  end
  local release = moves.byKitId[entity.kit.id].PrimaryRelease
  if release then
    release(entity.monster)
  end
end

function abilities.register()
  for command in pairs(moveByCommand) do
    links.onCommand(command, runCommand(command))
  end
  links.onCommand("PrimaryRelease", onPrimaryRelease)
  for _, kit in ipairs(kits.playable) do
    game.hookWhenLoaded(kit.classPath, kit.killGrab.functionName, onGrabStarted)
  end
  game.hookWhenLoaded(game.paths.characterClass, "HitDamageFromMonster", onCrewHit)

  -- What an entity's moves do on their own between commands (the Terminator faces where its player looks): about
  -- thirty times a second, for a turn that keeps up with the mouse
  LoopInGameThreadWithDelay(33, function()
    local entity = game.isHost() and takeover.activeEntity()
    local kitMoves = entity and moves.byKitId[entity.kit.id]
    if kitMoves and kitMoves.tick then
      kitMoves.tick(entity)
    end
  end)
end

return abilities
