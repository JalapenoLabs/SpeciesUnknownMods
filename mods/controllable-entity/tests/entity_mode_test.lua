-- Copyright © 2026 Jalapeno Labs

-- The host's choices, as the host: which entity (Random by default, a playable kit, or AI only) and who plays it
-- (Random by default, or a player the host picks). A co-op lobby forces the entity's monster; with no pick and no
-- volunteer a random player takes it, for one mission only. Playing alone, only a volunteer or the host's pick makes
-- sense. Only the host picks. (The picker panel itself is in picker_test.)
-- Run from the repository root: lua mods/controllable-entity/tests/entity_mode_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
math.randomseed(7)

local game = require("entity.game")
local kits = require("entity.kits")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modAssets)
local gameInstance = fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0, Contract = {} })

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

local takeover = require("entity.takeover")

fake.runLoops(1000)
assert(takeover.choice.entity == "Random" and takeover.choice.player == "Random", "both choices start Random")
assert(kits.byMonsterType[gameInstance.spawnForceSessionMonster] ~= nil,
  "Random rolls among the playable entities, so a co-op lobby forces one even with no volunteer")

command(crewController, "OpenPicker")
assert(lastEvent(crewController) == "Denied.HostOnly", "only the host picks the entity")

takeover.chooseEntity("AiOnly")
assert(gameInstance.spawnForceSessionMonster == 0, "with AI only, the mission rolls its own monster")
fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster == 0, "and the lobby keeps it that way")

command(crewController, "Volunteer")
assert(lastEvent(crewController) == "Denied.EntityModeOff", "nobody can volunteer while it's AI only")

takeover.chooseEntity("Squid")
assert(gameInstance.spawnForceSessionMonster == kits.byId.Squid.monsterType, "the host's entity is forced")

-- The game never sends the Terminator on a contract the crew arrives at without their main weapon, nor on the easiest
-- difficulty (its armour is beaten by those guns), so Random never rolls it there
local fields = game.contractFields
local function chooseContract(primaryWeapons, difficulty)
  gameInstance.Contract = {
    [fields.valid] = true,
    [fields.primaryWeapons] = primaryWeapons,
    [fields.difficulty] = difficulty,
  }
end
chooseContract(false, 2)
takeover.chooseEntity("Random")
for _ = 1, 40 do
  takeover.chooseEntity("Random")
  fake.runLoops(1000)
  assert(gameInstance.spawnForceSessionMonster ~= kits.byId.Terminator.monsterType,
    "no Terminator from Random without the crew's main weapons")
end
chooseContract(true, 0)
for _ = 1, 40 do
  takeover.chooseEntity("Random")
  fake.runLoops(1000)
  assert(gameInstance.spawnForceSessionMonster ~= kits.byId.Terminator.monsterType,
    "nor on the easiest difficulty")
end
-- With the main weapons, on a harder difficulty, Random may roll it; a roll the host's next contract doesn't fit is
-- rolled again
chooseContract(true, 2)
local rolledTerminator = false
for _ = 1, 40 do
  takeover.chooseEntity("Random")
  fake.runLoops(1000)
  rolledTerminator = rolledTerminator or gameInstance.spawnForceSessionMonster == kits.byId.Terminator.monsterType
  if rolledTerminator then
    break
  end
end
assert(rolledTerminator, "Random may roll the Terminator on a contract the game gives it")
chooseContract(false, 2)
fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster ~= kits.byId.Terminator.monsterType,
  "a roll the next contract doesn't fit is rolled again")

-- The host's own pick stands, but they're told once that the crew may have no way to beat it
local eventsBefore = #fake.callsTo(linkByOwner[hostController], "EntityClientEvent")
takeover.chooseEntity("Terminator")
fake.runLoops(1000)
fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster == kits.byId.Terminator.monsterType, "the host's pick stands")
local warnings = 0
for index, event in ipairs(fake.callsTo(linkByOwner[hostController], "EntityClientEvent")) do
  if index > eventsBefore and event.args[1]:ToString() == "PickedUnfit" then
    warnings = warnings + 1
  end
end
assert(warnings == 1, "and the host is warned, once")
gameInstance.Contract = {}
takeover.chooseEntity("Random")

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
fake.giveSquidState(squid)
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

-- The host picks who plays it: only the picked player is told, and a volunteer can't take their place
takeover.choosePlayer("lobby:1")
assert(lastEvent(crewController) == "PickedByHost", "the picked player is told")
command(hostController, "Volunteer")
assert(lastEvent(hostController) == "VolunteerTaken", "volunteering doesn't override the host's pick")
takeover.choosePlayer("lobby:0")
assert(lastEvent(crewController) == "Unvolunteered", "a player the host stops picking goes back to the crew")
assert(lastEvent(hostController) == "PickedByHost")
takeover.choosePlayer("lobby:1")

-- A picked player who leaves leaves the pick to chance again, and the host is told

crewController.destroyed = true
fake.runLoops(1000)
assert(takeover.choice.player == "Random" and lastEvent(hostController) == "PickedPlayerLeft",
  "the pick goes back to Random")

-- Alone, there is nobody to pick at random: the next mission is the game's own unless someone volunteers
assert(gameInstance.spawnForceSessionMonster == 0, "a solo lobby doesn't force an entity")
command(hostController, "Volunteer")
assert(kits.byMonsterType[gameInstance.spawnForceSessionMonster] ~= nil, "a solo volunteer still gets one")

print("entity mode test passed")
