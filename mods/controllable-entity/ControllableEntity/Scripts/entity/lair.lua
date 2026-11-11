-- Copyright © 2026 Jalapeno Labs

-- Host side of where the entity starts. The squid goes straight into a vent away from the crew (its lair) and stays in
-- the ducts near it until the crew turns the power on: the game's own grace period, in which the crew is safe. Some
-- contracts start with the power on, and then the squid is free at once.

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")
local vents = require("entity.vents")

local lair = {}

-- The current lair: { squid, controller, anchor, lastInside, leashed, lastWarnedAt }, or nil.
local current = nil

local function isPowerOff()
  local gameState = FindFirstOf(game.classNames.gameState)
  return gameState:IsValid() and gameState.LightStatut == game.lightStatus.Off
end

-- Where the crew stands. The entity player's own parked body is hidden, and doesn't count.
local function crewLocations()
  local locations = {}
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    if crewMember:IsValid() and not crewMember.bHidden then
      table.insert(locations, crewMember:K2_GetActorLocation())
    end
  end
  return locations
end

-- A random vent spot at least minimumCrewDistance from every crew member, or the spot farthest from the crew when
-- none is that far. Nil when the map has no vents.
local function chooseStartSpot()
  local crew = crewLocations()
  local farEnough = {}
  local farthestSpot, farthestDistance = nil, -1

  for _, vent in ipairs(vents.all()) do
    local spot = vents.spotsOf(vent)[1]
    if spot then
      local nearestCrewDistance = math.huge
      for _, location in ipairs(crew) do
        nearestCrewDistance = math.min(nearestCrewDistance, game.distance(spot, location))
      end
      if nearestCrewDistance >= config.lair.minimumCrewDistance then
        table.insert(farEnough, spot)
      end
      if nearestCrewDistance > farthestDistance then
        farthestSpot, farthestDistance = spot, nearestCrewDistance
      end
    end
  end

  if #farEnough > 0 then
    return farEnough[math.random(#farEnough)]
  end
  return farthestSpot
end

-- Frames to wait between asking the squid to crouch and teleporting it: the crouch applies on its next movement
-- update, and only the crouched capsule fits the ducts.
local CROUCH_FRAMES = 2

-- Puts the squid inside the ducts at a spot. SetInVent is what the vents' own trigger calls: it replicates the state
-- and crouches the squid. The teleport waits for the crouch to apply; a teleport that still finds no room places the
-- squid without the check, and says so in the log.
local function moveIntoVent(squid, spot)
  squid:BPI_Monster_SetInVent(true)
  ExecuteInGameThreadAfterFrames(CROUCH_FRAMES, function()
    if not squid:IsValid() then
      game.log("The squid was gone before it could be moved into the vents")
      return
    end
    if squid:K2_TeleportTo(spot, squid:K2_GetActorRotation()) then
      return
    end
    game.log("No room to teleport the squid to %.0f, %.0f, %.0f; placing it there", spot.X, spot.Y, spot.Z)
    squid:K2_SetActorLocation(spot, false, {}, true)
  end)
end

-- Starts the entity in its lair, right after the takeover.
function lair.begin(squid, controller)
  local spot = chooseStartSpot()
  if not spot then
    game.log("No vent on this map; the squid starts where the game spawned it")
    current = nil
    return
  end

  moveIntoVent(squid, spot)
  local leashed = isPowerOff()
  current = {
    squid = squid,
    controller = controller,
    anchor = spot,
    lastInside = spot,
    leashed = leashed,
    lastWarnedAt = -math.huge,
  }
  if leashed then
    links.sendEvent(controller, "Leashed")
  end
  game.log("The squid starts in a vent at %.0f, %.0f, %.0f%s", spot.X, spot.Y, spot.Z,
    leashed and ", held there until the power is on" or "")
end

function lair.forget()
  current = nil
end

-- Whether the squid is still held in its lair: the power hasn't come on yet.
function lair.isLeashed(squid)
  return current ~= nil and current.leashed and current.squid:IsValid()
    and current.squid:GetAddress() == squid:GetAddress()
end

-- Runs about five times a second on the host. While the power is off, a squid that leaves the ducts or strays past
-- the leash goes back to the last spot it stood at inside the leash; once the power is on, it is free for good, even
-- if the crew turns the power off again.
function lair.tick()
  if not current or not current.leashed then
    return
  end
  local squid = current.squid
  if not squid:IsValid() then
    current = nil
    return
  end

  if not isPowerOff() then
    current.leashed = false
    links.sendEvent(current.controller, "PowerRestored")
    game.log("The power is on: the entity may leave the vents")
    return
  end

  local location = squid:K2_GetActorLocation()
  local distance = game.distance(location, current.anchor)
  if squid.InVent and distance <= config.lair.leashRadius then
    current.lastInside = { X = location.X, Y = location.Y, Z = location.Z }
    return
  end

  moveIntoVent(squid, current.lastInside)
  local now = game.timeSeconds(squid)
  if now - current.lastWarnedAt >= config.lair.warningInterval then
    current.lastWarnedAt = now
    links.sendEvent(current.controller, "Denied.PowerOff")
    game.log("Pulled the squid back into its lair: %s (at %.0f, %.0f, %.0f, %.0f units from its start)",
      squid.InVent and "past the leash" or "out of the ducts", location.X, location.Y, location.Z, distance)
  end
end

return lair
