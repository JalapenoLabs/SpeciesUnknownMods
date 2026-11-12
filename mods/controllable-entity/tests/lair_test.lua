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
fake.installModPak(game.modAssets)
fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0, Contract = {} })

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
    GetControlRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
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
  PlayerArray = fake.array({ entityState, crewState }),
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
-- Far from the crew too, but much farther from where the game spawns the squid
vent(location(-30000, 0, 0), location(-30050, 0, 400))

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
fake.giveSquidState(squid)
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

-- Regression (playtest 7): the start was any vent far from the crew (alone, anywhere: crew quarters). It's the duct
-- nearest the game's own spawn point for its monster that is far from the crew, so the entity starts where the AI would
local farSpot = farVent.Point1Component:K2_GetComponentLocation()
assert(squid.location.X == farSpot.X and squid.location.Z == farSpot.Z,
  "the squid starts in the vent nearest its spawn that is far from the crew")
assert(lastEvent() == "Leashed", "the entity is told to wait for the power")

-- Regression (found reading BP_BaseMonster): standing still for 20 seconds made the AI's stuck check respawn the squid
assert(squid.ShouldCheckIfStuck == false, "the AI's stuck check is off for a player's squid")

-- Playing with someone, F8 as the entity is the crew's job: it neither turns the power on nor signs the entity out
fake.customEvents.EntityServerCommand(fake.param(entityLink), fake.param(fake.name("SoloPowerOn")),
  fake.param(nil), fake.param(nil))
assert(#fake.callsTo(gameState, "ChangeLightStatut") == 0, "with a crew, F8 leaves the power to them")
command("Volunteer")
assert(entityController.Pawn == squid, "and the entity stays the entity")
assert(lastEvent() == "Denied.NotAlone", "and says so")

-- Regression (playtest 7): a radius around the start pulled the squid back from ducts it could see and crawl into.
-- The whole duct network is the squid's; only dropping out of the ducts puts it back
local farInTheDucts = location(farSpot.X + 20000, farSpot.Y, farSpot.Z)
squid.location = farInTheDucts
fake.runLoops(200)
assert(squid.location == farInTheDucts, "anywhere in the ducts is fine")

squid.InVent = false
fake.now = 1
fake.runLoops(200)
fake.runFrames()
assert(squid.InVent and squid.location.X == farInTheDucts.X, "out of the ducts, the squid goes back where it stood")
assert(lastEvent() == "Denied.PowerOff")

-- The moves that leave the ducts wait for the power: dropping out of the vent the squid is over, the leap and the
-- ultimate
fake.now = 10
squid.location = location(farSpot.X, farSpot.Y, farSpot.Z)
for _, move in ipairs({ "Mobility", "Secondary", "Ultimate" }) do
  command(move)
  assert(lastEvent() == "Denied.PowerOff", move .. " waits for the power")
end

-- Regression (playtest 6): the player couldn't climb the steps inside the ducts that the AI climbs. At the foot of
-- one, venting climbs it with the squid's own climb, and climbing stays in the ducts, so the lair allows it. The
-- step's foot is 75 units to its navigation link's left
local step = fake.object("Nav_Link_VentPoint_Up250_C", nil, {
  K2_GetActorLocation = function() return location(farSpot.X, farSpot.Y + 75, farSpot.Z - 30) end,
  GetActorRightVector = function() return location(0, 1, 0) end,
})
command("Mobility")
local climbs = fake.callsTo(squid, "BPI_Monster_ClimbVent250")
assert(#climbs == 1 and climbs[1].args[1] == step and climbs[1].args[2] == false,
  "the squid climbs up the step nearer than the vent opening")
assert(lastEvent() == "Cooldown.Mobility", "even while the lair holds it")
-- Regression (playtest 8): the squid could climb a step but not back down, and was stranded above two of them. At the
-- top, 75 units to the link's right and 250 up, venting climbs back down
squid.location = location(farSpot.X, farSpot.Y + 150, farSpot.Z - 30 + 250)
fake.now = 20
command("Mobility")
climbs = fake.callsTo(squid, "BPI_Monster_ClimbVent250")
assert(#climbs == 2 and climbs[2].args[1] == step and climbs[2].args[2] == true, "at the top, the squid climbs down")
-- Away from both ends, there's nothing to climb
squid.location = location(farSpot.X + 2000, farSpot.Y, farSpot.Z)
fake.now = 30
command("Mobility")
assert(#fake.callsTo(squid, "BPI_Monster_ClimbVent250") == 2, "away from both ends, nothing to climb")
assert(lastEvent() == "Denied.NoVentExit")

-- Playing alone, F8 as the entity turns the power on, for testing past the lair
gameState.PlayerArray = fake.array({ entityState })
fake.customEvents.EntityServerCommand(fake.param(entityLink), fake.param(fake.name("SoloPowerOn")),
  fake.param(nil), fake.param(nil))
local switches = fake.callsTo(gameState, "ChangeLightStatut")
assert(#switches == 1 and switches[1].args[1] == game.lightStatus.On, "alone, F8 turns the power on")
gameState.PlayerArray = fake.array({ entityState, crewState })

-- The crew turns the power on: the squid is free, for good
gameState.LightStatut = game.lightStatus.On
fake.runLoops(200)
assert(lastEvent() == "PowerRestored")
gameState.LightStatut = game.lightStatus.Off
local roaming = location(farSpot.X + 300, farSpot.Y, 0)
squid.InVent = false
squid.location = roaming
fake.runLoops(200)
assert(squid.location == roaming and not squid.InVent, "once the power has been on, the squid may leave the ducts")
squid.InVent = true

-- Regression (playtest 8): crawling away from a peek kept the squid in its peeking pose as it moved, and the leap kept
-- it too. Moving away ends the peek with the game's own call, and so does the leap
squid.location = location(farSpot.X, farSpot.Y, farSpot.Z)
fake.now = 40
command("Peek")
local looks = fake.callsTo(squid, "BPI_Monster_LookFromVent")
assert(#looks == 1 and looks[1].args[1] == farVent and looks[1].args[2] == true, "C peeks through the grate")
fake.runLoops(200)
assert(#fake.callsTo(squid, "BPI_Monster_LookFromVent") == 1, "standing still, the peek holds")
squid.location = location(farSpot.X + 200, farSpot.Y, farSpot.Z)
fake.runLoops(200)
looks = fake.callsTo(squid, "BPI_Monster_LookFromVent")
assert(#looks == 2 and looks[2].args[1] == farVent and looks[2].args[2] == false, "crawling away ends the peek")
fake.now = 41
command("Peek")
fake.now = 50
command("Secondary")
looks = fake.callsTo(squid, "BPI_Monster_LookFromVent")
assert(#looks == 4 and looks[4].args[2] == false, "the leap ends a peek first")
assert(#fake.callsTo(squid, "BPI_Monster_SetSpecialAttack") == 1, "and then leaps")

-- Regression (playtest 5): a hot reload of the mod (Ctrl+R) forgot who the entity was, so every move was ignored while
-- the player still drove the squid. UE4SS drops the old scripts' hooks and loops and runs fresh copies
for name in pairs(package.loaded) do
  if name:match("^entity%.") then
    package.loaded[name] = nil
  end
end
fake.loops, fake.customEvents, fake.hooks = {}, {}, {}
dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")
-- Links come back on the first pass of the host's loops; the takeover's own second hasn't come round yet
links = require("entity.links")
links.reconcile()
fake.now = 30
-- Regression (playtest 6): a command in the first second after a reload was ignored, before the next reconcile took
-- the player back. The command itself takes them back
command("Primary")
assert(lastEvent() == "Denied.NoTarget", "after a reload, the player driving the squid is the entity at once")

print("lair test passed")
