-- Copyright © 2026 Jalapeno Labs

-- Playing the Terminator (BP_BigRobot), on the host: the host picks it, and it never enters the vents. It lies
-- powered down where the game spawned it, unable to move or act, until the power comes on; then it wakes, faces where
-- its player looks, and its moves are its own: the gatling while Shoot is held (a punch once the gun is broken, never
-- the head crush), a grenade, the arm grab the kill meter rules through GrabPlayer (Multi), and its charge. Its drones
-- stay off, its health bar is its gatling's pool while it holds one, and the camera rig leaves its own spring arm be.
-- Run from the repository root: lua mods/controllable-entity/tests/terminator_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local game = require("entity.game")
local kits = require("entity.kits")
local robotKit = kits.byId.Terminator

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.objects[game.paths.inputLibrary] = fake.object("EnhancedInputLibrary", nil, {
  Conv_InputActionValueToAxis2D = function(_, value) return value end,
  Conv_InputActionValueToBool = function(_, value) return value.pressed end,
})
local armClass = fake.object("SpringArmComponentClass")
fake.objects["/Script/Engine.SpringArmComponent"] = armClass
fake.objects["/Script/Engine.CameraComponent"] = fake.object("CameraComponentClass")
local kismet = fake.object("KismetSystemLibrary")
fake.objects["/Script/Engine.Default__KismetSystemLibrary"] = kismet
fake.installModPak(game.modAssets)
local montages = {}
for _, path in ipairs({ robotKit.swingMontage, robotKit.dashMontage, robotKit.killGrab.breakMontage }) do
  montages[path] = fake.object("AnimMontage")
  fake.objects[path] = montages[path]
end
local gameInstance = fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0 })

local function playerState(lobbyId, name)
  return fake.object("BP_MyPlayerState_C", nil, {
    BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = lobbyId end,
    GetPlayerName = function() return fake.name(name) end,
  })
end
local hostState, crewState = playerState(0, "Host"), playerState(1, "Crew")

local function controller(isLocal, state)
  local object = fake.object("BP_MyPlayerController_C", { PlayerState = state, Pawn = fake.invalid() }, {
    IsLocalController = function() return isLocal end,
    IsPlayerController = function() return true end,
    GetControlRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  }, { "PlayerController" })
  object.Possess = function(self, pawn)
    self.Pawn = pawn
    pawn.Controller = self
  end
  fake.giveView(object)
  return object
end
local hostController = controller(true, hostState)
local crewController = controller(false, crewState)

local links = {}
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local link = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    link.SetOwner = function(self, owner)
      self.Owner = owner
      links[owner] = self
    end
    return link
  end,
})
local gameState = fake.object("BP_MyGameState_C", {
  ["In Game Player State "] = fake.array({ hostState, crewState }),
  PlayerArray = fake.array({ hostState, crewState }),
  LightStatut = game.lightStatus.Off,
}, nil, { "GameStateBase" })
fake.object("BP_LobbyGameMode_C")

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")
local abilities = require("entity.abilities")
local takeover = require("entity.takeover")

local function command(name, aim)
  fake.customEvents.EntityServerCommand(fake.param(links[crewController]), fake.param(fake.name(name)),
    fake.param(aim or { X = 1, Y = 0, Z = 0 }), fake.param(nil))
end
local function lastEvent()
  local events = fake.callsTo(links[crewController], "EntityClientEvent")
  return events[#events] and events[#events].args[1]:ToString()
end
local function lastCall(object, method)
  local calls = fake.callsTo(object, method)
  return calls[#calls] and calls[#calls].args
end
local moveHook = nil
-- The entity player's machine moves their monster: their own controller is the local one there
local function moveOnTheEntityMachine()
  crewController.IsLocalController = function() return true end
  moveHook(fake.param(crewController), fake.param({ X = 0, Y = 1 }))
  crewController.IsLocalController = function() return false end
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The lobby: the host picks the Terminator, and the crew player to play it
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.runLoops(1000)
takeover.chooseEntity("Terminator")
takeover.choosePlayer("lobby:1")
fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster == 7, "picking the Terminator forces its MonsterList value")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The mission: it spawns powered down, lying where the game put it
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.instances.BP_LobbyGameMode_C = nil
fake.object("BP_PlayableGameMode_C")
local aiController = fake.object("BP_Basic_AI_Controller_C", nil, { IsPlayerController = function() return false end })
local gatling = fake.object("BP_Gatling_C", { MainHealth = 400, MaxHealth = 400 })
local canThrow = true
local robot = fake.object("BP_BigRobot_C", {
  Controller = aiController,
  InVent = false,
  IsPowered = false,
  HaveGatling = true,
  Gatling = gatling,
  CanShoot = true,
  IsStunt = false,
  IsElectrocuted = false,
  Health = 1000,
  MaxHealth = 1000,
  MainTarget = crewController,
  AttackSimplePlayRate = 1,
  Mesh = fake.object("SkeletalMeshComponent"),
  CharacterMovement = fake.object("CharacterMovementComponent", { MaxWalkSpeed = 0, MaxWalkSpeedCrouched = 0 }),
  CapsuleComponent = fake.object("CapsuleComponent", nil, { GetScaledCapsuleHalfHeight = function() return 120 end }),
}, {
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 120 } end,
  GetVelocity = function() return { X = 0, Y = 0, Z = 0 } end,
  BPI_Monster_GetSpeedByType = function(_, speedType, out) out.Speed = 250 + speedType end,
  BPI_BigRobot_IsAbleToShoot = function(_, out) out.True = true end,
  BPI_BigRobot_CanThrowGrenade = function(self, throwType, location, target, out)
    table.insert(fake.calls, { object = self, method = "BPI_BigRobot_CanThrowGrenade",
      args = { throwType, location, target } })
    out.True = canThrow
  end,
})
-- Waking it powers it up, as the game's own switch does
robot.BPI_Monster_SwitchBehavior = function(self, behaviour)
  table.insert(fake.calls, { object = self, method = "BPI_Monster_SwitchBehavior", args = { behaviour } })
  self.IsPowered = behaviour ~= 6
end
-- Its own spring arm, the ceiling probe it ducks with, was there before the mod's camera rig
local robotComponents = fake.acceptComponents(robot)
local ownArm = robot:AddComponentByClass(armClass)
fake.object("BP_GameManager_C", { Monster = robot })

local crewLocation = { X = 1000, Y = 0, Z = 120 }
local crewBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") }, {
  K2_GetActorLocation = function() return crewLocation end,
})
local entityBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })
crewController.Pawn = entityBody
hostController.Pawn = crewBody
-- A crawl opening beside it: only an entity that lives in the vents crouches into one
fake.object("BP_Trigger_Crouch_C", { VentEnter = true, CollisionComponent = fake.object("BoxComponent") })

fake.loadClass(robotKit.classPath)
fake.loadClass(game.paths.controllerClass, { "InpActEvt_IA_Move_K2Node_EnhancedInputActionEvent_27" })
moveHook = fake.hooks[game.paths.controllerClass .. ":InpActEvt_IA_Move_K2Node_EnhancedInputActionEvent_27"]
fake.runLoops()
assert(crewController.Pawn == robot, "the picked player drives the Terminator")
assert(fake.hooks[robotKit.classPath .. ":GrabPlayer (Multi)"], "its grab is hooked under its spaced name")
entityBody.destroyed = true

-- Its drones stay off: the timer the AI's possession started is cleared, and those already out flee
assert(robot["[DEBUG]NoSphereSpawn"] == true, "no new drones")
local cleared = lastCall(kismet, "K2_ClearTimer")
assert(cleared and cleared[1] == robot and cleared[2] == "CheckPlayersForSpawnSphere", "their timer is cleared")
assert(#fake.callsTo(robot, "ClearSphereBot") == 1, "drones already out flee")
assert(rawget(robot, "MainTarget") == nil, "it keeps no target a knockback could throw a grenade at")

-- Powered down until the power is on, where the game spawned it: no vents
assert(lastEvent() == "Dormant", "the player is told it lies powered down")
assert(#fake.callsTo(robot, "BPI_Monster_SwitchBehavior") == 0, "and it isn't woken")
assert(#fake.callsTo(robot, "BPI_Monster_SetInVent") == 0, "and never put in the vents")
for _, slot in ipairs(kits.slots) do
  command(slot)
  assert(lastEvent() == "Denied.Dormant", slot .. " waits for it to wake")
end
moveOnTheEntityMachine()
assert(#fake.callsTo(robot, "AddMovementInput") == 0, "lying powered down, it doesn't move")
fake.runLoops(33)
assert(#fake.callsTo(robot, "BPI_BasicMonster_LookAtLocation") == 0, "nor turn")

-- The power comes on: it wakes, without combat (which would start the action music for everyone)
gameState.LightStatut = game.lightStatus.On
fake.runLoops(200)
local switches = fake.callsTo(robot, "BPI_Monster_SwitchBehavior")
assert(#switches == 1 and switches[1].args[1] == 0, "it wakes on patrol, not in combat")
assert(lastEvent() == "Awake", "and its player is told")
moveOnTheEntityMachine()
assert(#fake.callsTo(robot, "AddMovementInput") == 2, "awake, it moves")

-- It faces where its player looks, or its own turning would swing it to world yaw 0
fake.runLoops(33)
local look = lastCall(robot, "BPI_BasicMonster_LookAtLocation")
assert(look and look[1] == true and look[2].X == 2000 and look[2].Y == 0 and look[3] == false,
  "it faces the point along the aim")

-- No crawl openings for it
fake.runLoops(200)
assert(#fake.callsTo(robot, "BPI_Monster_SetInVent") == 0, "it never crouches into a crawl opening")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Its moves
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The gatling fires while Shoot is held
command("Primary")
assert(lastCall(robot, "BPI_BigRobot_SetFiring")[1] == true, "Shoot starts the gatling")
command("PrimaryRelease")
assert(lastCall(robot, "BPI_BigRobot_SetFiring")[1] == false, "letting go stops it")
local firings = #fake.callsTo(robot, "BPI_BigRobot_SetFiring")
command("PrimaryRelease")
assert(#fake.callsTo(robot, "BPI_BigRobot_SetFiring") == firings, "letting go when it isn't firing does nothing")
robot.CanShoot = false
fake.now = 1
command("Primary")
assert(lastEvent() == "Denied.CantShoot", "it won't fire while the game says it can't")
robot.CanShoot = true

-- The game stops the gatling only for electrocution; broken, it would fire on
fake.now = 2
command("Primary")
robot.HaveGatling = false
fake.runLoops(33)
assert(lastCall(robot, "BPI_BigRobot_SetFiring")[1] == false, "a broken gatling stops firing")

robot.HaveGatling = true
-- Dead, it lies there as its player's until the game removes it: a gatling still firing stops
fake.now = 2.5
command("Primary")
robot.IsDead = true
fake.runLoops(33)
assert(lastCall(robot, "BPI_BigRobot_SetFiring")[1] == false, "a dead robot's gatling stops firing")
robot.IsDead = false
robot.HaveGatling = false

-- Without its gatling, Shoot punches: its plain punch, never the head crush, and never through the game's own pick
fake.now = 3
command("Primary")
local swings = fake.callsTo(robot, "AttackSimpleAnim (Clients)")
assert(#swings == 1 and swings[1].args[1] == montages[robotKit.swingMontage], "it punches")
assert(#fake.callsTo(robot, "BPI_BasicMonster_SetSimpleAttack") == 0, "never through SetSimpleAttack")

-- The grenade: at the crew member along the aim, whom the throw follows
command("Secondary")
local throws = fake.callsTo(robot, "BPI_BigRobot_ThrowGrenade")
assert(#throws == 1 and throws[1].args[1] == crewLocation and throws[1].args[2] == 0, "a grenade at the crew member")
assert(robot.LastAttackedTarget == crewBody, "whom the throw follows")
-- Too close, the blast would hit its own gatling; with no clear arc, nothing is thrown
crewLocation = { X = 300, Y = 0, Z = 120 }
fake.now = 20
command("Secondary")
assert(lastEvent() == "Denied.TooClose", "never at its own feet")
crewLocation = { X = 1000, Y = 0, Z = 120 }
canThrow = false
command("Secondary")
assert(lastEvent() == "Denied.NoThrow", "nor without a clear throw")
canThrow = true
-- With nobody along the aim, it lands ahead on the floor
fake.now = 40
command("Secondary", { X = 0, Y = 1, Z = 0 })
throws = fake.callsTo(robot, "BPI_BigRobot_ThrowGrenade")
local ahead = throws[#throws].args[1]
assert(ahead.Y == robotKit.moves.Secondary.aheadDistance and ahead.Z == 0, "ahead along the aim, on the floor")
assert(rawget(robot, "LastAttackedTarget") == nil, "following nobody")

-- The charge, at the crew member along the aim
command("Mobility")
swings = fake.callsTo(robot, "AttackSimpleAnim (Clients)")
assert(swings[#swings].args[1] == montages[robotKit.dashMontage] and swings[#swings].args[3] == nil,
  "it charges; the crew member is out of its reach")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The kill
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local grabHook = fake.hooks[robotKit.classPath .. ":GrabPlayer (Multi)"]
grabHook(fake.param(robot), fake.param(crewBody))
assert(lastEvent() == "Denied.UltimateNotReady")
fake.runFrames()
local knockbacks = fake.callsTo(robot, "KnockBack (Clients)")
assert(#knockbacks == 1 and knockbacks[1].args[1] == montages[robotKit.killGrab.breakMontage],
  "an unarmed grab is broken off with its light hit")

crewLocation = { X = 200, Y = 0, Z = 120 }
abilities.meter().value = 1
fake.now = 60
command("Ultimate")
local grabs = fake.callsTo(robot, "BPI_Monster_SetSpecialAttack")
assert(#grabs == 1 and grabs[1].args[1] == crewBody, "the ultimate reaches for the crew member ahead")
grabHook(fake.param(robot), fake.param(crewBody))
assert(lastEvent() == "KillStarted" and abilities.meter().value == 0, "the armed grab kills and spends the meter")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Its health
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local link = links[crewController]
robot.HaveGatling = true
gatling.MainHealth = 200
fake.runLoops(200)
assert(link.Health == 0.5 and link.Downed == false, "while it holds its gatling, the gun's pool")
robot.HaveGatling = false
robot.Health = 250
robot.IsStunt = true
fake.runLoops(200)
assert(link.Health == 0.25 and link.Downed == true, "then its body's, and down while stunned")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Losing it with the gun firing
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- A gatling firing when the robot stops being the entity (captured, or its player no longer drives it) stops: the
-- host's tick no longer runs for it, and nothing in the game stops a firing gun
robot.HaveGatling, robot.IsStunt = true, false
fake.now = 80
command("Primary")
assert(lastCall(robot, "BPI_BigRobot_SetFiring")[1] == true, "firing")
crewController.Pawn = fake.invalid()
fake.runLoops(1000)
assert(require("entity.takeover").activeEntity() == nil, "the entity is lost")
assert(lastCall(robot, "BPI_BigRobot_SetFiring")[1] == false, "and its gatling stops with it")
crewController.Pawn = robot

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The camera, on its player's machine
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Regression: the rig took a monster's own spring arm for its own after a reload, and would have moved the
-- Terminator's ceiling probe. The rig's arm is the one its camera hangs from
local camera = require("entity.camera")
camera.follow(crewController, robot)
assert(#robotComponents == 3, "the rig is the mod's own arm and camera, beside the robot's arm")
package.loaded["entity.camera"] = nil
require("entity.camera").follow(crewController, robot)
assert(#robotComponents == 3, "a reloaded mod reuses its rig")
assert(ownArm.bDoCollisionTest == nil and ownArm.bUsePawnControlRotation == nil, "and leaves the robot's arm be")

print("terminator test passed")
