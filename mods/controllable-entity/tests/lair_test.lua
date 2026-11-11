-- Copyright © 2026 Jalapeno Labs

-- The entity's start, as the host: the squid goes into a vent away from the crew, stays in the ducts near it until
-- the power is on, and is free for good after. Also covers the AI's stuck check, which would respawn (destroy) a
-- squid that stands still.
-- Run from the repository root: lua mods/controllable-entity/tests/lair_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local config = require("entity.config")
local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modClasses)
fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0 })

local function playerState(lobbyId)
  return fake.object("BP_MyPlayerState_C", nil, {
    BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = lobbyId end,
  })
end

local function controller(isLocal, state)
  local object = fake.object("BP_MyPlayerController_C", { PlayerState = state, Pawn = fake.invalid() }, {
    IsLocalController = function() return isLocal end,
    IsPlayerController = function() return true end,
    K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
  }, { "PlayerController" })
  object.Possess = function(self, pawn)
    self.Pawn = pawn
    pawn.Controller = self
  end
  fake.giveView(object)
  return object
end

local entityState, crewState = playerState(0), playerState(1)
local entityController = controller(true, entityState)
controller(false, crewState)

local entityLink = nil
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local link = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    link.SetOwner = function(self, owner)
      self.Owner = owner
      if owner == entityController then
        entityLink = link
      end
    end
    return link
  end,
})

-- The mission, with the power off: a crew member at the origin, and two vents, one close to them and one far away
local gameState = fake.object("BP_MyGameState_C", {
  LightStatut = game.lightStatus.Off,
  ["In Game Player State "] = fake.array({ entityState, crewState }),
}, nil, { "GameStateBase" })
fake.object("BP_PlayableGameMode_C")

local function location(x, y, z)
  return { X = x, Y = y, Z = z }
end

local function vent(floorLocation, spot)
  return fake.object("BP_Vent_Up_C", {
    Point1Component = fake.object("BillboardComponent", nil, {
      K2_GetComponentLocation = function() return spot end,
    }),
    Point2Component = fake.invalid(),
    Point3Component = fake.invalid(),
    Point4Component = fake.invalid(),
  }, {
    K2_GetActorLocation = function() return floorLocation end,
  })
end

vent(location(300, 0, 0), location(350, 0, 400))
local farVent = vent(location(6000, 0, 0), location(6050, 0, 400))

fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") }, {
  K2_GetActorLocation = function() return location(0, 0, 0) end,
})
local entityBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })
entityController.Pawn = entityBody

local squid = fake.object("BP_Monster_Poulpi_C", {
  Controller = fake.invalid(),
  InVent = false,
  ShouldCheckIfStuck = true,
  location = location(0, 500, 0),
}, {
  BPI_Monster_GetSpeedByType = function(_, _, out) out.Speed = 400 end,
  BPI_Monster_SetInVent = function(self, inVent) self.InVent = inVent end,
  K2_GetActorLocation = function(self) return self.location end,
  K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  K2_TeleportTo = function(self, destination)
    self.location = destination
    return true
  end,
})
-- The squid spawns later, as when a crew member leaves the shuttle on Hawking
local gameManager = fake.object("BP_GameManager_C", { Monster = fake.invalid() })

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

local function eventsTo(link)
  local kinds = {}
  for _, call in ipairs(fake.callsTo(link, "EntityClientEvent")) do
    table.insert(kinds, call.args[1]:ToString())
  end
  return kinds
end

local function lastEvent()
  local kinds = eventsTo(entityLink)
  return kinds[#kinds]
end

local function command(name)
  fake.customEvents.EntityServerCommand(fake.param(entityLink), fake.param(fake.name(name)),
    fake.param(location(1, 0, 0)), fake.param(nil))
end

fake.runLoops(1000)
command("Volunteer")
gameManager.Monster = squid
fake.runLoops(1000)
fake.runLoops(1000)
assert(entityController.Pawn == squid, "the volunteer takes the squid")

-- It crouches into the vent state first, and moves once the crouch has applied (a frame or two later)
assert(squid.InVent, "the game knows it's in the vents")
fake.runFrames()

-- It starts inside the far vent's duct, not where the game spawned it
local farSpot = farVent.Point1Component:K2_GetComponentLocation()
assert(squid.location.X == farSpot.X and squid.location.Z == farSpot.Z,
  "the squid starts in the vent far from the crew")
assert(lastEvent() == "Leashed", "the entity is told to wait for the power")

-- Regression (found reading BP_BaseMonster): standing still for 20 seconds made the AI's stuck check respawn the squid
assert(squid.ShouldCheckIfStuck == false, "the AI's stuck check is off for a player's squid")

-- Straying past the leash, or dropping out of the ducts, puts the squid back
local insideLeash = location(farSpot.X + config.lair.leashRadius / 2, farSpot.Y, farSpot.Z)
squid.location = insideLeash
fake.runLoops(200)
assert(squid.location == insideLeash, "moving around inside the leash is fine")

squid.location = location(farSpot.X + config.lair.leashRadius * 2, farSpot.Y, farSpot.Z)
fake.runLoops(200)
fake.runFrames()
assert(squid.location.X == insideLeash.X, "past the leash, the squid goes back to where it last stood inside it")
assert(lastEvent() == "Denied.PowerOff")

squid.InVent = false
fake.now = 1
fake.runLoops(200)
fake.runFrames()
assert(squid.InVent and squid.location.X == insideLeash.X, "out of the ducts, the squid goes back in")

-- The moves that leave the ducts wait for the power
fake.now = 10
for _, move in ipairs({ "Vent", "Leap", "Ultimate" }) do
  command(move)
  assert(lastEvent() == "Denied.PowerOff", move .. " waits for the power")
end

-- The crew turns the power on: the squid is free, for good
gameState.LightStatut = game.lightStatus.On
fake.runLoops(200)
assert(lastEvent() == "PowerRestored")
gameState.LightStatut = game.lightStatus.Off
local roaming = location(farSpot.X + config.lair.leashRadius * 5, farSpot.Y, farSpot.Z)
squid.location = roaming
fake.runLoops(200)
assert(squid.location == roaming, "once the power has been on, the leash is gone")

print("lair test passed")
