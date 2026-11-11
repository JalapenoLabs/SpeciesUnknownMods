-- Copyright © 2026 Jalapeno Labs

-- Entity mode, as the host: only the host's F9 turns it on or off; while it's on, a co-op lobby forces the squid, and
-- with no volunteer a random player takes it, for one mission only. Playing alone, only a volunteer makes sense.
-- Run from the repository root: lua mods/controllable-entity/tests/entity_mode_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
math.randomseed(7)

local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modClasses)
local gameInstance = fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0 })

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

local hostState, crewState = playerState(0), playerState(1)
local hostController = controller(true, hostState)
local crewController = controller(false, crewState)

local linkByOwner = {}
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local link = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    link.SetOwner = function(self, owner)
      self.Owner = owner
      linkByOwner[owner] = link
    end
    return link
  end,
})

local gameState = fake.object("BP_MyGameState_C", { ["In Game Player State "] = fake.array({}) }, nil,
  { "GameStateBase" })
local lobbyGameMode = fake.object("BP_LobbyGameMode_C")

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

local function command(sender, name)
  fake.customEvents.EntityServerCommand(fake.param(linkByOwner[sender]), fake.param(fake.name(name)),
    fake.param({ X = 1, Y = 0, Z = 0 }), fake.param(nil))
end

local function lastEvent(receiver)
  local events = fake.callsTo(linkByOwner[receiver], "EntityClientEvent")
  return events[#events] and events[#events].args[1]:ToString()
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- In the lobby
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster == game.squidMonsterType,
  "entity mode starts on, so a co-op lobby forces the squid even with no volunteer")

command(crewController, "ToggleEntityMode")
assert(lastEvent(crewController) == "Denied.HostOnly", "only the host turns entity mode on or off")
assert(gameInstance.spawnForceSessionMonster == game.squidMonsterType, "a client's press changes nothing")

command(hostController, "ToggleEntityMode")
assert(lastEvent(hostController) == "EntityModeOff", "the host sees the new mode")
assert(gameInstance.spawnForceSessionMonster == 0, "with entity mode off, the mission rolls its own monster")
fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster == 0, "and the lobby keeps it that way")

command(crewController, "Volunteer")
assert(lastEvent(crewController) == "Denied.EntityModeOff", "nobody can volunteer while it's off")

command(hostController, "ToggleEntityMode")
assert(lastEvent(hostController) == "EntityModeOn")
assert(gameInstance.spawnForceSessionMonster == game.squidMonsterType)

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- A mission with no volunteer
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

lobbyGameMode.destroyed = true
gameState.destroyed = true
gameState = fake.object("BP_MyGameState_C", { ["In Game Player State "] = fake.array({ hostState, crewState }) }, nil,
  { "GameStateBase" })
fake.object("BP_PlayableGameMode_C")
local gameManager = fake.object("BP_GameManager_C", { Monster = fake.invalid() })
hostController.Pawn = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })
crewController.Pawn = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })

fake.runLoops(1000)
assert(hostController.Pawn:GetClass():GetFName():ToString() == "BP_Character_C"
  and crewController.Pawn:GetClass():GetFName():ToString() == "BP_Character_C",
  "nobody is picked before the squid is there to take")

local squid = fake.object("BP_Monster_Poulpi_C", { Controller = fake.invalid() }, {
  BPI_Monster_GetSpeedByType = function(_, _, out) out.Speed = 400 end,
})
gameManager.Monster = squid
fake.runLoops(1000)

local chosen = squid.Controller
assert(chosen == hostController or chosen == crewController, "a player picked at random takes the squid")
assert(lastEvent(chosen) == "BecameEntity", "and only they are told")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Back in the lobby: the pick was for one mission
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

squid.destroyed = true
gameState.destroyed = true
fake.object("BP_MyGameState_C", { ["In Game Player State "] = fake.array({}) }, nil, { "GameStateBase" })
lobbyGameMode = fake.object("BP_LobbyGameMode_C")
fake.runLoops(1000)
assert(lastEvent(chosen) ~= "Lost", "the mission ending is not a loss")

command(crewController, "Volunteer")
assert(lastEvent(crewController) == "Volunteered", "the random pick doesn't hold the entity slot into the next mission")
command(crewController, "Volunteer")
assert(lastEvent(crewController) == "Unvolunteered")

-- Alone, there is nobody to pick at random: the next mission is the game's own unless someone volunteers
crewController.destroyed = true
fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster == 0, "a solo lobby doesn't force the squid")
command(hostController, "Volunteer")
assert(gameInstance.spawnForceSessionMonster == game.squidMonsterType, "a solo volunteer still gets the squid")

print("entity mode test passed")
