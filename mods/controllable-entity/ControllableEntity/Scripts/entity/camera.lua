-- Copyright © 2026 Jalapeno Labs

-- The entity player's view, on their own machine: third person by default, first person on request.
--
-- The game's camera manager (Character_CameraBP.BlueprintUpdateCamera) ignores the view target: while its crew body
-- exists, the camera sits in that body's head, and the entity's crew body is parked, not destroyed. The engine's
-- built-in camera styles bypass that override (PlayerCameraManager.UpdateViewTarget only calls it for the default
-- style), so both views use one:
-- - Third person, "FreeCam": FreeCamDistance behind the view target along the player's look, pulled in when a wall is
--   in the way.
-- - First person, "FirstPerson": through the view target's eyes (GetActorEyesViewPoint).
-- The camera manager runs on the player's own machine, so none of this touches the host.

local config = require("entity.config")
local game = require("entity.game")

local camera = {}

-- PlayerCameraManager.CameraStyle values. "Default" is the game's own camera, which this game never changes itself.
-- (UE4SS doesn't hand the property back as a readable name, so the mod writes it and never reads it.)
local THIRD_PERSON_STYLE = "FreeCam"
local FIRST_PERSON_STYLE = "FirstPerson"
local GAME_STYLE = "Default"

local isThirdPerson = true
-- False once the player has lost: the game's own camera follows the crew again.
local isEntityView = false

local function apply(controller)
  local manager = controller.PlayerCameraManager
  if not manager:IsValid() then
    game.log("No camera manager; the view stays as it is")
    return
  end

  if not isEntityView then
    manager.CameraStyle = FName(GAME_STYLE)
    return
  end
  if isThirdPerson then
    manager.FreeCamDistance = config.camera.thirdPersonDistance
    manager.CameraStyle = FName(THIRD_PERSON_STYLE)
    return
  end
  manager.CameraStyle = FName(FIRST_PERSON_STYLE)
end

-- Starts the entity's view: third person, the easier view for a body that big.
function camera.begin(controller)
  isEntityView = true
  isThirdPerson = true
  apply(controller)
end

function camera.toggle(controller)
  isThirdPerson = not isThirdPerson
  apply(controller)
end

-- Back to the game's own view, for watching the crew after losing.
function camera.reset(controller)
  isEntityView = false
  apply(controller)
end

return camera
