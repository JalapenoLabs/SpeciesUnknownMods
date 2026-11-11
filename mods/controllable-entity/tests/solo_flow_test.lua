-- Copyright © 2026 Jalapeno Labs

-- Testing alone: the host volunteers with nobody else in the game. Destroying the only crew body would empty
-- BP_MyGameState.ActualPlayersPawn and send the game back to the lobby, so the body must stay, parked, until another
-- crew body exists. Run from the repository root: lua mods/controllable-entity/tests/solo_flow_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local game = require("entity.game")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modClasses)
local gameInstance = fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0 })

local hostState = fake.object("BP_MyPlayerState_C", nil, {
  BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = 0 end,
})
local hostController = fake.object("BP_MyPlayerController_C", { PlayerState = hostState, Pawn = fake.invalid() }, {
  IsLocalController = function() return true end,
  IsPlayerController = function() return true end,
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
}, { "PlayerController" })
hostController.Possess = function(self, pawn)
  self.Pawn = pawn
  pawn.Controller = self
end

local hostLink = nil
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    hostLink = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    hostLink.SetOwner = function(self, owner) self.Owner = owner end
    return hostLink
  end,
})
local gameState = fake.object("BP_MyGameState_C", { ["In Game Player State "] = fake.array({ hostState }) }, nil,
  { "GameStateBase" })

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

fake.runLoops()
fake.customEvents.EntityServerCommand(fake.param(hostLink), fake.param(fake.name("Volunteer")),
  fake.param({ X = 1, Y = 0, Z = 0 }), fake.param(nil))

fake.object("BP_PlayableGameMode_C")
local squid = fake.object("BP_Monster_Poulpi_C", { Controller = fake.invalid() }, {
  BPI_Monster_GetSpeedByType = function(_, _, out) out.Speed = 400 end,
})
fake.object("BP_GameManager_C", { Monster = squid })
local movement = fake.object("CharacterMovementComponent")
local hostBody = fake.object("BP_Character_C", { CharacterMovement = movement })
hostController.Pawn = hostBody

fake.runLoops()
fake.runLoops()
assert(hostController.Pawn == squid, "the host drives the squid")
assert(not hostBody.destroyed, "the only crew body stays, or the game would return to the lobby")
assert(#fake.callsTo(hostBody, "SetActorHiddenInGame") == 1, "the parked body is hidden")
assert(#fake.callsTo(hostBody, "SetActorEnableCollision") == 1, "the parked body doesn't block anything")
assert(#fake.callsTo(movement, "DisableMovement") == 1, "the parked body can't fall out of the map")
assert(#fake.callsTo(gameState, "UpdateInGamePlayers") == 0, "the only crew member stays on the crew list")

-- A friend's body appears: the parked one can go now
fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })
fake.runLoops()
assert(hostBody.destroyed, "once another crew body exists, the parked body is removed")

-- The mission ends and the game travels on: a new world (new game state). That's not a loss.
local function lastEventKind()
  local events = fake.callsTo(hostLink, "EntityClientEvent")
  return events[#events] and events[#events].args[1]:ToString()
end
gameState.destroyed = true
squid.destroyed = true
fake.object("GameStateBase")
fake.runLoops(1000)
assert(lastEventKind() ~= "Lost", "travelling to a new map is not losing")

-- Regression (playtest 2): back at the main menu the volunteer must be forgotten, and the squid no longer forced
fake.object("BP_MainMenuGameMode_C")
fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster == 0, "the main menu clears the forced squid")

print("solo flow test passed")
