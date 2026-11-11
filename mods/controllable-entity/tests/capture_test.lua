-- Copyright © 2026 Jalapeno Labs

-- Capture contracts with a human entity, as the host: the entity killed off the shuttle counts as captured, and a
-- kill aboard fails the contract as the game has it.
-- Run from the repository root: lua mods/controllable-entity/tests/capture_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local game = require("entity.game")
local capture = require("entity.capture")

local shuttle = fake.object("BP_PlayerShip_C", { MonsterInside = false })
local gameState = fake.object("BP_MyGameState_C", {
  Contract = { ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Capture },
  PlayerShip = shuttle,
})
local squid = fake.object("BP_Monster_Poulpi_C", { IsDead = true })
local aiSquid = fake.object("BP_Monster_Poulpi_C", { IsDead = true })
local entity = { squid = squid }
local takeover = { activeEntity = function() return entity end }

capture.register(takeover)
local monsterClass = "/Game/Blueprints/Monsters/BP_BaseMonster.BP_BaseMonster_C"
fake.loadClass(monsterClass)
local died = fake.hooks[monsterClass .. ":OnRep_IsDead"]

local function finishes()
  return fake.callsTo(gameState, "BPI_GameState_FinishGame")
end

-- Regression (playtest 6): a human entity could keep away from the shuttle and make a capture impossible. Killed off
-- the shuttle, it counts as captured, the way a real capture ends
died(fake.param(squid))
assert(#finishes() == 1 and finishes()[1].args[1] == 1, "the entity killed off the shuttle counts as captured")
assert(#fake.callsTo(squid, "BPI_BasicMonster_SetIsCaptured") == 1, "and is marked captured, as in the cell")

-- Killed aboard, the contract fails as before: the game's own kill result stands
shuttle.MonsterInside = true
died(fake.param(squid))
assert(#finishes() == 1, "a kill aboard the shuttle is left to the game")
shuttle.MonsterInside = false

-- Only the entity, only in capture contracts
died(fake.param(aiSquid))
assert(#finishes() == 1, "the AI's squid dies as the game has it")
gameState.Contract.ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Elimination
died(fake.param(squid))
assert(#finishes() == 1, "a kill contract's kill is the crew's win already")

print("capture test passed")
