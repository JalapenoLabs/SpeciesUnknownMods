-- Copyright © 2026 Jalapeno Labs

-- The entity's way out when the map holds it somewhere it can't leave (playtest 9: fallen into Polar's forbidden
-- underground, it had no way back up). The game has none of its own. Holding F7 for five seconds while keeping still
-- and unhurt moves the entity somewhere safe: an entity that lives in the vents to the duct spot nearest it that is
-- clear of the crew and of forbidden floor (as the lair picks its start), any other to where the game spawned it.
-- Moving, being hurt or going down cancels it, so it's no escape from a fight, and it waits a while before it works
-- again.
--
-- The entity player's machine says when F7 goes down and comes back up; the host decides the rest.

local config = require("entity.config")
local game = require("entity.game")
local lair = require("entity.lair")
local links = require("entity.links")
local vents = require("entity.vents")
local zones = require("entity.zones")

local unstuck = {}

-- On the host: the unstuck under way, { startedAt, location, health }, or nil; and when it may next start.
local pending = nil
local readyAt = 0

-- On the entity player's machine: whether F7 was held at the last check.
local wasHeld = false

-- The share of the entity's health its HUD shows (abilities.lua fills it on the link), or nil without a link.
local function healthOf(entity)
  local link = links.forController(entity.controller)
  return link and link.Health
end

-- Moves the entity somewhere safe: into the ducts near it, clear of the crew and of forbidden floor, or, for an entity
-- that doesn't live in the vents (or a map without a safe duct), back where the game spawned it.
local function moveToSafety(entity)
  local monster = entity.monster
  local location = monster:K2_GetActorLocation()
  if entity.kit.usesVents then
    local spot = lair.safeDuctSpot(location, function(candidate)
      return not zones.isForbiddenAt(monster, candidate)
    end)
    if spot then
      vents.moveInto(monster, spot)
      game.log("Unstuck the entity from %.0f, %.0f, %.0f into the ducts at %.0f, %.0f, %.0f", location.X, location.Y,
        location.Z, spot.X, spot.Y, spot.Z)
      return
    end
    game.log("No safe duct spot to unstuck the entity to; it goes back where the game spawned it")
  end

  local start = entity.startLocation
  if monster.InVent == true then
    monster:BPI_Monster_SetInVent(false)
  end
  if not monster:K2_TeleportTo(start, monster:K2_GetActorRotation()) then
    game.log("No room where the game spawned the entity (%.0f, %.0f, %.0f); placing it there", start.X, start.Y,
      start.Z)
    monster:K2_SetActorLocation(start, false, {}, true)
  end
  game.log("Unstuck the entity from %.0f, %.0f, %.0f back where the game spawned it", location.X, location.Y,
    location.Z)
end

local function cancel(entity)
  pending = nil
  links.sendEvent(entity.controller, "UnstuckCancelled")
end

-- Runs five times a second on the host while there is an entity: the unstuck under way goes through once the key has
-- been held long enough, or is cancelled when the entity has moved, been hurt or gone down meanwhile.
function unstuck.tickHost(entity, now)
  if not pending then
    return
  end
  local monster = entity.monster
  local hasMoved = game.distance(monster:K2_GetActorLocation(), pending.location) > config.unstuck.stillDistance
  local health = healthOf(entity)
  local isHurt = health ~= nil and pending.health ~= nil and health < pending.health
  local isDown = monster[entity.kit.healthFields.downed] == true
  if hasMoved or isHurt or isDown then
    cancel(entity)
    return
  end
  if now - pending.startedAt < config.unstuck.holdSeconds then
    return
  end
  pending = nil
  readyAt = now + config.unstuck.cooldownSeconds
  moveToSafety(entity)
  links.sendEvent(entity.controller, "Unstuck")
end

-- Runs about ten times a second on the entity player's machine while they drive the entity: tells the host when the
-- unstuck key goes down and comes back up.
function unstuck.followPlayer(controller)
  local isHeld = controller:IsInputKeyDown({ KeyName = FName(config.keys.unstuck) }) == true
  if isHeld == wasHeld then
    return
  end
  wasHeld = isHeld
  links.sendCommand(isHeld and "UnstuckStart" or "UnstuckStop", nil, nil)
end

-- Once the player no longer drives the entity, the key starts over.
function unstuck.forgetPlayer()
  wasHeld = false
end

function unstuck.register(takeover)
  links.onCommand("UnstuckStart", function(_, controller)
    local isEntity = takeover.isEntityController(controller)
    local entity = takeover.activeEntity()
    if not isEntity or not entity then
      game.log("An unstuck from a player who isn't the entity; ignored")
      return
    end
    local monster = entity.monster
    local now = game.timeSeconds(monster)
    if now < readyAt then
      links.sendEvent(controller, "Denied.UnstuckCooldown")
      return
    end
    if monster[entity.kit.healthFields.downed] == true then
      links.sendEvent(controller, "Denied.Down")
      return
    end
    local location = monster:K2_GetActorLocation()
    pending = {
      startedAt = now,
      location = { X = location.X, Y = location.Y, Z = location.Z },
      health = healthOf(entity),
    }
    links.sendEvent(controller, "UnstuckStarted")
  end)

  links.onCommand("UnstuckStop", function(_, controller)
    local entity = takeover.activeEntity()
    if pending and entity and takeover.isEntityController(controller) then
      cancel(entity)
    end
  end)
end

return unstuck
