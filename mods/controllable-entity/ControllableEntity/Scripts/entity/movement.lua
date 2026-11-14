-- Copyright © 2026 Jalapeno Labs

-- How fast the entity moves: the game's combat speed, faster in the vents, and a sprint on Shift that runs on stamina.
--
-- The entity's speed is its CharacterMovement's MaxWalkSpeed, and MaxWalkSpeedCrouched in the vents (SetInVent crouches
-- it). BPI_Monster_SetSpeed sets both from a speed and the game's own multipliers (difficulty, the frost gun's slow),
-- but only on the machine that calls it, so the host (which moves the entity for real) and the entity player's machine
-- (which predicts the movement) each apply the same speed. Re-applied a few times a second, so a slow the game puts
-- on the entity still counts, and the mod's vent bonus survives the game setting the speed itself.
--
-- The host owns the stamina: the player's machine asks to sprint while Shift is held, and the host says when the
-- entity is out of breath and when it has caught it again, so both machines agree on whether it sprints.

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")
local zones = require("entity.zones")

local movement = {}

-- MonsterSpeed_DataTable speed types (BTTask_SetSpeedType): 1 combat, 4 the entity's top speed.
local COMBAT_SPEED = 1
local TOP_SPEED = 4

-- Applies the entity's speed on this machine.
function movement.apply(monster, sprinting)
  local speed = {}
  monster:BPI_Monster_GetSpeedByType(sprinting and TOP_SPEED or COMBAT_SPEED, speed)
  monster:BPI_Monster_SetSpeed(speed.Speed)
  local characterMovement = monster.CharacterMovement
  characterMovement.MaxWalkSpeedCrouched = characterMovement.MaxWalkSpeedCrouched * config.movement.ventSpeedMultiplier
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Host: stamina
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The entity's sprint on the host: whether they hold Shift, whether they're out of breath, and the stamina (0 to 1).
local host = { wantsToSprint = false, isTired = false, stamina = 1, lastTickAt = nil }

function movement.stamina()
  return host.stamina
end

-- Runs about five times a second on the host while there is an entity.
function movement.tickHost(entity, now)
  local elapsed = host.lastTickAt and now - host.lastTickAt or 0
  host.lastTickAt = now

  -- No sprinting near the crew's shuttle (zones.lua), so they can get to it and away from it
  local isNearShuttle = zones.isNearShuttle(entity.monster:K2_GetActorLocation())
  local sprinting = host.wantsToSprint and not host.isTired and not isNearShuttle
  if sprinting then
    host.stamina = math.max(0, host.stamina - elapsed / config.movement.sprintSeconds)
    if host.stamina == 0 then
      host.isTired = true
      sprinting = false
      links.sendEvent(entity.controller, "Sprint.Tired")
    end
  else
    host.stamina = math.min(1, host.stamina + elapsed / config.movement.staminaRefillSeconds)
    if host.isTired and host.stamina >= config.movement.staminaToSprintAgain then
      host.isTired = false
      links.sendEvent(entity.controller, "Sprint.Rested")
    end
  end

  movement.apply(entity.monster, sprinting)
end

-- A move that costs stamina (the squid's leap, playtest 9): refused while the entity is out of breath, and otherwise
-- spends its share, leaving the entity out of breath if that empties it. Returns whether the move may go ahead.
function movement.spendStamina(entity, share)
  if host.isTired then
    return false
  end
  host.stamina = math.max(0, host.stamina - share)
  if host.stamina == 0 then
    host.isTired = true
    links.sendEvent(entity.controller, "Sprint.Tired")
  end
  return true
end

-- A new entity starts rested.
function movement.resetHost()
  host = { wantsToSprint = false, isTired = false, stamina = 1, lastTickAt = nil }
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Entity player: Shift
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The entity player's side: whether Shift was held at the last check, and whether the host says they're out of breath.
local player = { holdsSprint = false, isTired = false }

-- Crouches the monster in the ducts and stands it up outside them, on the entity player's own machine. A character
-- another player drives crouches only when their machine says so: its moves carry the crouch to the host and override
-- the host's own Crouch, which is all the game's SetInVent does (it crouches on the host alone). Without this, a
-- friend's monster stood up in the ducts, didn't fit, and fell out of the vent it was put in (playtest 9).
local function followVentCrouch(monster)
  local inVent = monster.InVent == true
  if inVent == (monster.CharacterMovement.bWantsToCrouch == true) then
    return
  end
  if inVent then
    monster:Crouch(false)
    return
  end
  monster:UnCrouch(false)
end

-- Runs about ten times a second on the entity player's machine while they drive the entity.
function movement.followPlayer(controller, monster)
  followVentCrouch(monster)
  -- An FKey is its name to Lua; UE4SS builds the struct from the table
  local holdsSprint = controller:IsInputKeyDown({ KeyName = FName(config.keys.sprint) }) == true
  if holdsSprint ~= player.holdsSprint then
    player.holdsSprint = holdsSprint
    links.sendCommand(holdsSprint and "SprintStart" or "SprintStop", nil, nil)
  end
  -- The host applies the speed itself; a separate client applies the same speed for its own prediction
  if not game.isHost() then
    local isNearShuttle = zones.isNearShuttle(monster:K2_GetActorLocation())
    movement.apply(monster, holdsSprint and not player.isTired and not isNearShuttle)
  end
end

function movement.register(isEntityController)
  local function setWantsToSprint(wantsToSprint)
    return function(_, controller)
      if not isEntityController(controller) then
        game.log("A sprint from a player who isn't the entity; ignored")
        return
      end
      host.wantsToSprint = wantsToSprint
    end
  end
  links.onCommand("SprintStart", setWantsToSprint(true))
  links.onCommand("SprintStop", setWantsToSprint(false))

  links.onClientEvent("Sprint.Tired", function() player.isTired = true end)
  links.onClientEvent("Sprint.Rested", function() player.isTired = false end)
end

return movement
