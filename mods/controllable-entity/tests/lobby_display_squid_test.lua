-- Copyright © 2026 Jalapeno Labs

-- Regression: in the first playtest, pressing F8 in the lobby put the volunteer straight into the squid on display
-- there. The lobby's game mode is a subclass of the mission's, so "a playable game mode exists" held in the lobby,
-- and any squid counted. Now only the mission's specimen (BP_GameManager.Monster) outside the lobby is taken.
-- Run from the repository root: lua mods/controllable-entity/tests/lobby_display_squid_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modAssets)
fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0, Contract = {} })
local hostState = fake.object("BP_MyPlayerState_C", nil, {
  BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = 0 end,
})
local hostBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })
local hostController = fake.object("BP_MyPlayerController_C", { PlayerState = hostState, Pawn = hostBody }, {
  IsLocalController = function() return true end,
  IsPlayerController = function() return true end,
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
}, { "PlayerController" })
hostController.Possess = function(self, pawn) self.Pawn = pawn end
fake.giveView(hostController)

local hostLink = nil
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    hostLink = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    hostLink.SetOwner = function(self, owner) self.Owner = owner end
    return hostLink
  end,
})
fake.object("BP_MyGameState_C", { ["In Game Player State "] = fake.array({ hostState }) }, nil, { "GameStateBase" })

-- The lobby: its game mode is also a playable game mode, and a squid stands on display
fake.object("BP_LobbyGameMode_C", nil, nil, { "BP_PlayableGameMode_C" })
local displaySquid = fake.object("BP_Monster_Poulpi_C", { Controller = fake.invalid() })

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

fake.runLoops(1000)
fake.customEvents.EntityServerCommand(fake.param(hostLink), fake.param(fake.name("Volunteer")),
  fake.param({ X = 1, Y = 0, Z = 0 }), fake.param(nil))
fake.runLoops(1000)
fake.runLoops(1000)

assert(hostController.Pawn == hostBody, "volunteering in the lobby must not take over the squid on display")
assert(#fake.callsTo(hostBody, "SetActorHiddenInGame") == 0, "the crew body stays untouched in the lobby")
assert(#fake.callsTo(displaySquid, "BPI_Monster_SetSpeed") == 0)

print("lobby display squid test passed")
