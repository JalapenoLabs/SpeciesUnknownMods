-- Copyright © 2026 Jalapeno Labs

-- Runs the mod's real scripts as the host, against fake game objects, through a whole round: lobby, volunteering,
-- mission start, takeover, crew exclusion, commands, the grab rule, frenzy, pings and the meter.
-- Run from the repository root: lua mods/controllable-entity/tests/host_flow_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
math.randomseed(1)

local game = require("entity.game")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The lobby
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modClasses)
fake.objects[game.paths.grabInterruptedMontage] = fake.object("AnimMontage")

local gameInstance = fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0 })

local function playerState(lobbyId, name)
  return fake.object("BP_MyPlayerState_C", nil, {
    BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = lobbyId end,
    GetPlayerName = function() return { ToString = function() return name end } end,
  })
end

local hostState, crewState = playerState(0, "Host"), playerState(1, "Crew")

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
  return object
end

local hostController = controller(true, hostState)
local crewController = controller(false, crewState)

local spawnedLinks = {}
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local link = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    link.SetOwner = function(self, owner) self.Owner = owner end
    table.insert(spawnedLinks, link)
    return link
  end,
})

local crewList = fake.array({ hostState })
local gameState = fake.object("BP_MyGameState_C", {
  Contract = { ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Extraction },
  ["In Game Player State "] = crewList,
}, nil, { "GameStateBase" })

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Steps
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function linkOf(controllerObject)
  for _, link in ipairs(spawnedLinks) do
    if link.Owner == controllerObject then
      return link
    end
  end
  error("no link for controller")
end

local function command(controllerObject, name, aim)
  fake.customEvents.EntityServerCommand(fake.param(linkOf(controllerObject)), fake.param(fake.name(name)),
    fake.param(aim or { X = 1, Y = 0, Z = 0 }), fake.param(nil))
end

local function lastEvent(controllerObject)
  local events = fake.callsTo(linkOf(controllerObject), "EntityClientEvent")
  return events[#events] and events[#events].args[1]:ToString()
end

fake.runLoops()
assert(#spawnedLinks == 2, "every player gets a link")
fake.runLoops()
assert(#spawnedLinks == 2, "links are spawned once")

command(crewController, "Volunteer")
assert(gameInstance.spawnForceSessionMonster == game.squidMonsterType, "volunteering forces the squid")
assert(lastEvent(crewController) == "Volunteered")
assert(#fake.callsTo(linkOf(hostController), "EntityClientEvent") == 0, "nobody else hears about it")

command(hostController, "Volunteer")
assert(lastEvent(hostController) == "VolunteerTaken", "only one entity")

-- The mission: the squid spawns with its AI, the crew get bodies and join the crew list.
fake.object("BP_PlayableGameMode_C")
local aiController = fake.object("BP_Basic_AI_Controller_C", nil, { IsPlayerController = function() return false end })
local squid = fake.object("BP_Monster_Poulpi_C", {
  Controller = aiController, InVent = false, LastSpecialAttackPlayerLocation = nil,
}, {
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
  BPI_Monster_GetSpeedByType = function(_, speedType, out) out.Speed = 400 + speedType end,
})
local crewBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") }, {
  K2_GetActorLocation = function() return { X = 200, Y = 0, Z = 0 } end,
})
local entityBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })
crewController.Pawn = entityBody
hostController.Pawn = crewBody
crewList.elements = { hostState, crewState }

for _, classPath in ipairs({ game.paths.squidClass, game.paths.gameStateClass, game.paths.weaponClass }) do
  fake.loadClass(classPath)
end

fake.runLoops()
assert(crewController.Pawn == squid, "the volunteer drives the squid")
assert(aiController.destroyed, "the squid's AI is removed")
assert(entityBody.destroyed, "with other crew aboard, the entity player's crew body is removed")
local speedCalls = fake.callsTo(squid, "BPI_Monster_SetSpeed")
assert(#speedCalls == 1 and speedCalls[1].args[1] == 401, "combat speed comes from the out parameter")
assert(lastEvent(crewController) == "BecameEntity")

fake.runLoops()
local exclusions = fake.callsTo(gameState, "UpdateInGamePlayers")
assert(#exclusions >= 1 and exclusions[1].args[1] == crewState and exclusions[1].args[2] == false,
  "the entity is taken out of the crew list")

-- Commands
command(crewController, "Attack", { X = 1, Y = 0, Z = 0 })
assert(#fake.callsTo(squid, "BPI_BasicMonster_SetSimpleAttack") == 1, "attack hits the crew member ahead")
command(crewController, "Attack", { X = 1, Y = 0, Z = 0 })
assert(lastEvent(crewController) == "Denied.Cooldown", "attacks respect the cooldown")
command(hostController, "Attack")
assert(#fake.callsTo(squid, "BPI_BasicMonster_SetSimpleAttack") == 1, "only the entity commands the squid")

command(crewController, "Ultimate")
assert(lastEvent(crewController) == "Denied.UltimateNotReady", "the ultimate needs a full meter")

-- A grab without the ultimate is broken off
local grabHook = fake.hooks[game.paths.squidClass .. ":GrabHeadPlayer"]
grabHook(fake.param(squid), fake.param(crewBody))
assert(lastEvent(crewController) == "Denied.UltimateNotReady")
assert(#fake.callsTo(squid, "KnockBack (Clients)") == 0, "the knockback waits a frame for the grab to finish")
fake.runFrames()
local knockbacks = fake.callsTo(squid, "KnockBack (Clients)")
assert(#knockbacks == 1 and knockbacks[1].args[1] == fake.objects[game.paths.grabInterruptedMontage],
  "an unarmed grab is broken off with the grab-interrupted knockback")

-- A full meter arms the ultimate, which leaps and lets the grab kill
local abilities = require("entity.abilities")
abilities.meter().value = 1
fake.now = 10
command(crewController, "Ultimate", { X = 0, Y = 1, Z = 0 })
assert(squid.LastSpecialAttackPlayerLocation.Y > 400, "the leap lands along the aim")
assert(#fake.callsTo(squid, "BPI_Monster_SetSpecialAttack") == 1)
grabHook(fake.param(squid), fake.param(crewBody))
assert(lastEvent(crewController) == "KillStarted")
assert(abilities.meter().value == 0, "the kill spends the meter")

-- Frenzy from the black box
fake.hooks[game.paths.gameStateClass .. ":BPI_GameState_SetGrabBlackBox"](fake.param(gameState))
assert(lastEvent(crewController) == "FrenzyStarted")
fake.now = 11
assert(abilities.meter():grabKills(fake.now), "frenzy kills without meter")

-- A gunshot nearby pings the entity
local weapon = fake.object("BP_LaserGun_C", { PawnOwner = crewBody, HearingLoudness = 1.0, HearingRange = 3000 })
fake.hooks[game.paths.weaponClass .. ":MakeNoiseAI"](fake.param(weapon))
local pings = fake.callsTo(linkOf(crewController), "EntityClientPing")
assert(#pings == 1 and pings[1].args[3]:ToString() == "Gunshot", "the shot is heard")

-- The meter state reaches the entity's link
fake.runLoops(200)
assert(linkOf(crewController).Frenzy == true, "frenzy replicates through the link")

print("host flow test passed")
