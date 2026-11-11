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
-- The style is set through the engine's own APlayerController.ClientSetCameraMode: in playtest 4, writing the property
-- from Lua left the camera where it was, 17,000 units from the squid. (UE4SS doesn't hand the property back as a
-- readable name either, so the mod never reads it.)
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
    controller:ClientSetCameraMode(FName(GAME_STYLE))
    return
  end
  if isThirdPerson then
    manager.FreeCamDistance = config.camera.thirdPersonDistance
    controller:ClientSetCameraMode(FName(THIRD_PERSON_STYLE))
    return
  end
  controller:ClientSetCameraMode(FName(FIRST_PERSON_STYLE))
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

local function describe(actor)
  if not actor or not actor:IsValid() then
    return "nothing"
  end
  return actor:GetClass():GetFName():ToString()
end

-- How far the camera was from the squid at the last report, so the log shows changes, not every second.
local lastReportedDistance = nil
-- Distance changes smaller than this aren't worth a log line.
local REPORT_DISTANCE_STEP = 250

-- Runs about once a second while the player drives the squid. The game's own code can move the view elsewhere (back
-- to the crew body, or to a fixed camera such as the shuttle's), so the view target and style are put back on the
-- squid whenever they've moved, and the log says what had them. It also reports where the camera really is, so a
-- playtest log shows whether the player is seeing the squid at all.
function camera.keepOnSquid(controller, squid)
  local viewTarget = controller:GetViewTarget()
  if not viewTarget:IsValid() or viewTarget:GetAddress() ~= squid:GetAddress() then
    game.log("The view was on %s; putting it back on the squid", describe(viewTarget))
    controller:SetViewTargetWithBlend(squid, 0, 0, 0, false)
  end
  apply(controller)

  local manager = controller.PlayerCameraManager
  if not manager:IsValid() then
    return
  end
  local cameraLocation = manager:GetCameraLocation()
  local squidLocation = squid:K2_GetActorLocation()
  local distance = game.distance(cameraLocation, squidLocation)
  if lastReportedDistance and math.abs(distance - lastReportedDistance) < REPORT_DISTANCE_STEP then
    return
  end
  lastReportedDistance = distance
  game.log("The camera is %.0f units from the squid (camera %.0f, %.0f, %.0f; squid %.0f, %.0f, %.0f; %s)", distance,
    cameraLocation.X, cameraLocation.Y, cameraLocation.Z, squidLocation.X, squidLocation.Y, squidLocation.Z,
    isThirdPerson and "third person" or "first person")
end

return camera
