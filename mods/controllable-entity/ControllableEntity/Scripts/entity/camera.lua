-- Copyright © 2026 Jalapeno Labs

-- The entity player's view, on their own machine: third person by default, first person on request.
--
-- The game's camera manager (Character_CameraBP.BlueprintUpdateCamera) doesn't follow the view target: while it has a
-- crew body cached (its Player variable), the camera sits in that body's head, and the entity's crew body is parked,
-- not destroyed. Its own way to follow another pawn is BPI_CameraPlayer_ResetPlayer, which sets the view target and
-- caches the pawn only if it is a crew character, so handing it the squid clears the cache and the engine's normal
-- view takes over. (Playtest 4 showed the engine's CameraStyle can't be changed from Lua: neither writing the property
-- nor ClientSetCameraMode moved the camera.)
--
-- The squid has no camera of its own, so the mod gives it one on this machine: a spring arm on the squid, pointing
-- along the player's look and pulling in when a wall is in the way, with a camera at its end. The engine views a pawn
-- through its camera component. Third person is the arm at full length; first person is the arm at zero length.

local config = require("entity.config")
local game = require("entity.game")

local camera = {}

local SPRING_ARM_CLASS = "/Script/Engine.SpringArmComponent"
local CAMERA_CLASS = "/Script/Engine.CameraComponent"
-- The spring arm's socket at the end of the arm (USpringArmComponent::SocketName).
local ARM_END_SOCKET = "SpringEndpoint"
-- EAttachmentRule
local SNAP_TO_TARGET = 2
local IDENTITY_TRANSFORM = {
  Rotation = { X = 0, Y = 0, Z = 0, W = 1 },
  Translation = { X = 0, Y = 0, Z = 0 },
  Scale3D = { X = 1, Y = 1, Z = 1 },
}

local isThirdPerson = true
-- The camera rig on the squid: { squidAddress, arm, view }, or nil.
local rig = nil

local function describe(actor)
  if not actor or not actor:IsValid() then
    return "nothing"
  end
  return actor:GetClass():GetFName():ToString()
end

-- Gives the squid its spring arm and camera; nil after logging when the engine won't make them. A rig the squid
-- already has is reused: the engine views through a pawn's first camera, so a second rig (after a hot reload of the
-- mod, in playtest 4) would be one the player never sees, and the view toggle would move the wrong one.
local function buildRig(squid)
  local armClass = StaticFindObject(SPRING_ARM_CLASS)
  local cameraClass = StaticFindObject(CAMERA_CLASS)
  local existingArm = squid:GetComponentByClass(armClass)
  local existingView = squid:GetComponentByClass(cameraClass)
  if existingArm and existingArm:IsValid() and existingView and existingView:IsValid() then
    game.log("The squid already has a camera; using it")
    return { squidAddress = squid:GetAddress(), arm = existingArm, view = existingView }
  end

  local arm = squid:AddComponentByClass(armClass, false, IDENTITY_TRANSFORM, false)
  local view = squid:AddComponentByClass(cameraClass, true, IDENTITY_TRANSFORM, false)
  if not arm or not arm:IsValid() or not view or not view:IsValid() then
    game.log("Could not give the squid a camera; the view stays as it is")
    return nil
  end

  arm:K2_SetRelativeLocation({ X = 0, Y = 0, Z = config.camera.height }, false, {}, true)
  arm.bUsePawnControlRotation = true
  view:K2_AttachToComponent(arm, FName(ARM_END_SOCKET), SNAP_TO_TARGET, SNAP_TO_TARGET, SNAP_TO_TARGET, false)
  game.log("Gave the squid a camera")
  return { squidAddress = squid:GetAddress(), arm = arm, view = view }
end

local function applyDistance()
  rig.arm.TargetArmLength = isThirdPerson and config.camera.thirdPersonDistance or 0
end

-- How far the camera was from the squid at the last report, so the log shows changes, not every second.
local lastReportedDistance = nil
-- Distance changes smaller than this aren't worth a log line.
local REPORT_DISTANCE_STEP = 250

-- Playtest diagnostics: where the camera really is, relative to the squid.
local function reportDistance(controller, squid)
  local cameraLocation = controller.PlayerCameraManager:GetCameraLocation()
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

-- Runs when the player becomes the entity and about once a second after, while they drive the squid: builds the rig
-- once per squid, and hands the game's camera back to the squid whenever the game's own code has moved it.
function camera.follow(controller, squid)
  if not rig or rig.squidAddress ~= squid:GetAddress() or not rig.view:IsValid() then
    rig = buildRig(squid)
    if not rig then
      return
    end
    applyDistance()
  end

  local manager = controller.PlayerCameraManager
  if not manager:IsValid() then
    game.log("No camera manager; the view stays as it is")
    return
  end

  local viewTarget = controller:GetViewTarget()
  local cachedCrewBody = manager.Player
  local followsSquid = viewTarget:IsValid() and viewTarget:GetAddress() == squid:GetAddress()
  if cachedCrewBody:IsValid() or not followsSquid then
    local previous = cachedCrewBody:IsValid() and cachedCrewBody or viewTarget
    game.log("The game's camera was following %s; handing it the squid", describe(previous))
    manager:BPI_CameraPlayer_ResetPlayer(squid)
  end

  reportDistance(controller, squid)
end

function camera.toggle()
  isThirdPerson = not isThirdPerson
  if rig then
    applyDistance()
  end
end

-- After losing: the rig goes, and the game's camera follows whoever the host points it at.
function camera.reset()
  if rig and rig.view:IsValid() then
    rig.view:K2_DestroyComponent(rig.view)
    rig.arm:K2_DestroyComponent(rig.arm)
  end
  rig = nil
  isThirdPerson = true
  lastReportedDistance = nil
end

return camera
