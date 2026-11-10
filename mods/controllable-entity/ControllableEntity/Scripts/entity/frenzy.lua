-- Copyright © 2026 Jalapeno Labs

-- Host side of frenzy: the mission moments that change the kill rules.
--
--   Extraction    picking the black box up into a player's hands     full frenzy
--   Kill/Capture  a player getting the special (weakness) weapon     partial frenzy
--   Self destruct starting the engines                               full frenzy
--
-- The game re-runs each of these functions (every re-grab, every engine state change); Meter:raiseFrenzy only acts
-- on the first escalation, so the hooks don't keep their own once-flags.

local game = require("entity.game")
local links = require("entity.links")
local Meter = require("entity.meter")

local frenzy = {}

local function contractType()
  local gameState = FindFirstOf(game.classNames.gameState)
  if not gameState or not gameState:IsValid() then
    return nil
  end
  return gameState.Contract["ContractType_2_AD7B8E08435CF5A38556E7BA67C34760"]
end

local function raise(abilities, takeover, level, reason)
  local entity = takeover.activeEntity()
  if not entity or not abilities.meter():raiseFrenzy(level) then
    return
  end
  links.sendEvent(entity.controller, level == Meter.frenzyLevels.Full and "FrenzyStarted" or "FrenzyPartial")
  game.log("%s frenzy: %s", level, reason)
end

function frenzy.register(abilities, takeover)
  game.hookWhenLoaded(game.paths.gameStateClass, "BPI_GameState_SetGrabBlackBox", function(context)
    if not context:get():HasAuthority() or contractType() ~= game.contractTypes.Extraction then
      return
    end
    raise(abilities, takeover, Meter.frenzyLevels.Full, "the black box was picked up")
  end)

  game.hookWhenLoaded(game.paths.weaponClass, "BPI_Weapon_SetGrabbed", function(context)
    local weapon = context:get()
    local contract = contractType()
    local huntContract = contract == game.contractTypes.Elimination or contract == game.contractTypes.Capture
    if not weapon:HasAuthority() or not huntContract or not weapon.IsObjectiveWeapon or not weapon.IsGrabbed then
      return
    end
    raise(abilities, takeover, Meter.frenzyLevels.Partial, "a crew member has the special weapon")
  end)

  game.hookWhenLoaded(game.paths.engineClass, "OnRep_EngineState", function(context)
    local engine = context:get()
    local engineStarting = engine.EngineState >= 1
    if not engine:HasAuthority() or contractType() ~= game.contractTypes.Destruction or not engineStarting then
      return
    end
    raise(abilities, takeover, Meter.frenzyLevels.Full, "the engines were started")
  end)
end

return frenzy
