-- Copyright © 2026 Jalapeno Labs

-- Capture contracts with a human entity, on the host (playtest 6). The crew must take the specimen alive in their
-- shuttle's capture cell, and killing it fails the contract. A human entity could keep away from the shuttle for good,
-- so here the entity killed anywhere off the shuttle counts as captured, and only a kill aboard fails as before. That
-- gives the entity a reason to come aboard, where the crew may only capture it, and the crew a reason to hunt.
--
-- The game ends a mission once: BP_MyGameState.BPI_GameState_FinishGame does nothing after the first. A real capture
-- marks the monster captured, then finishes the game as one (BP_Capture.CheckInside). The squid's death finishes it as
-- a kill some 15 seconds later (FinishDeath), so finishing it as a capture as the squid dies comes first. The squid's
-- Death (Server) runs the base monster's, which sets IsDead and calls OnRep_IsDead on the host.

local game = require("entity.game")

local capture = {}

local MONSTER_CLASS = "/Game/Blueprints/Monsters/BP_BaseMonster.BP_BaseMonster_C"
-- BPI_GameState_FinishGame's result for a capture.
local CAPTURED = 1

local function onMonsterDied(takeover, monster)
  local entity = takeover.activeEntity()
  local isEntityDeath = entity and monster:HasAuthority() and monster.IsDead
    and entity.monster:GetAddress() == monster:GetAddress()
  if not isEntityDeath or game.contractType() ~= game.contractTypes.Capture then
    return
  end

  local gameState = FindFirstOf(game.classNames.gameState)
  local shuttle = gameState.PlayerShip
  if shuttle:IsValid() and shuttle.MonsterInside then
    game.log("The entity was killed aboard the shuttle: the capture fails, as the game has it")
    return
  end
  monster:BPI_BasicMonster_SetIsCaptured()
  gameState:BPI_GameState_FinishGame(CAPTURED)
  game.log("The entity was killed off the shuttle: it counts as captured")
end

function capture.register(takeover)
  game.hookWhenLoaded(MONSTER_CLASS, "OnRep_IsDead", function(context)
    onMonsterDied(takeover, context:get())
  end)
end

return capture
