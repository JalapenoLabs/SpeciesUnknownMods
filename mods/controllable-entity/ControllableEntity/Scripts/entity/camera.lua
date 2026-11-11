-- Copyright © 2026 Jalapeno Labs

-- The entity player's view, on their own machine: third person by default, first person on request.
--
-- The squid has no camera of its own. First person is the camera manager's normal view, from the squid's eyes. Third
-- person is the engine's built-in free camera (PlayerCameraManager.CameraStyle "FreeCam"): it sits FreeCamDistance
-- behind the view target along the player's look, and pulls in when a wall is in the way. The camera manager runs
-- on the player's own machine, so none of this touches the host.

local config = require("entity.config")
local game = require("entity.game")

local camera = {}

-- PlayerCameraManager.CameraStyle values. "Default" is the engine's normal view of the view target; this game's
-- camera manager never changes the style itself. (UE4SS doesn't hand the property back as a readable name, so the mod
-- writes it and never reads it.)
local THIRD_PERSON_STYLE = "FreeCam"
local FIRST_PERSON_STYLE = "Default"

local isThirdPerson = true

local function apply(controller)
  local manager = controller.PlayerCameraManager
  if not manager:IsValid() then
    game.log("No camera manager; the view stays as it is")
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
  isThirdPerson = true
  apply(controller)
end

function camera.toggle(controller)
  isThirdPerson = not isThirdPerson
  apply(controller)
end

-- Back to the game's own view, for watching the crew after losing.
function camera.reset(controller)
  isThirdPerson = false
  apply(controller)
end

return camera
