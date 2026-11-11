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
-- along the player's look, with a camera at its end. The arm passes through walls rather than pulling in. The engine
-- views a pawn through its camera component. Third person is the arm at full length; first person is the arm at zero
-- length, with the squid's own mesh hidden from its player.

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
-- The camera rig on the squid: { squidAddress, squid, manager, arm, view }, or nil.
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
local function buildRig(monster)
  local armClass = StaticFindObject(SPRING_ARM_CLASS)
  local cameraClass = StaticFindObject(CAMERA_CLASS)
  local existingArm = monster:GetComponentByClass(armClass)
  local existingView = monster:GetComponentByClass(cameraClass)
  local arm, view = existingArm, existingView
  local reused = arm and arm:IsValid() and view and view:IsValid()
  if not reused then
    arm = monster:AddComponentByClass(armClass, false, IDENTITY_TRANSFORM, false)
    view = monster:AddComponentByClass(cameraClass, true, IDENTITY_TRANSFORM, false)
  end
  if not arm or not arm:IsValid() or not view or not view:IsValid() then
    game.log("Could not give the squid a camera; the view stays as it is")
    return nil
  end

  -- Set on a reused rig too, so a newer version of these settings always applies
  arm:K2_SetRelativeLocation({ X = 0, Y = 0, Z = config.camera.height }, false, {}, true)
  arm.bUsePawnControlRotation = true
  -- Much of the duct network is invisible collision, which kept pulling the camera in to the squid's head (playtest
  -- 4). Clipping through walls is fine for the entity, so the arm ignores them
  arm.bDoCollisionTest = false
  view:K2_AttachToComponent(arm, FName(ARM_END_SOCKET), SNAP_TO_TARGET, SNAP_TO_TARGET, SNAP_TO_TARGET, false)
  game.log(reused and "The squid already has a camera; using it" or "Gave the squid a camera")
  return { monsterAddress = monster:GetAddress(), arm = arm, view = view }
end

-- The camera manager's own lowest look pitch, from its class default: the value it had before the mod changed it, even
-- after a hot reload of the mod.
local function defaultLowestPitch(manager)
  return manager:GetClass():GetCDO().ViewPitchMin
end

-- Applies the view: the arm's length, the squid's own mesh, and how far down the player can look.
--   - In first person the squid's mesh hides from its player, or the view is from inside its head (playtest 6). Owner
--     no-see hides it from the owner's view only, and possessing a pawn makes the controller its owner
--     (APawn::PossessedBy), so everyone else still sees the squid.
--   - In third person the arm swings up as the player looks down, and looking almost straight down took the camera up
--     through the ship's outer hull, which blacked out the screen (playtest 6). Like most third-person cameras, it
--     stops the look short of straight down (the camera manager's ViewPitchMin, which limits the control rotation);
--     first person keeps the manager's own limit.
local function applyView()
  rig.arm.TargetArmLength = isThirdPerson and config.camera.thirdPersonDistance or 0
  rig.monster.Mesh:SetOwnerNoSee(not isThirdPerson)
  local ownLowestPitch = defaultLowestPitch(rig.manager)
  rig.manager.ViewPitchMin = isThirdPerson and math.max(ownLowestPitch, config.camera.thirdPersonLowestPitch)
    or ownLowestPitch
end

-- How far the camera was from the squid at the last report, so the log shows changes, not every second.
local lastReportedDistance = nil
-- Distance changes smaller than this aren't worth a log line.
local REPORT_DISTANCE_STEP = 250

-- Playtest diagnostics: where the camera really is, relative to the squid.
local function reportDistance(controller, monster)
  local cameraLocation = controller.PlayerCameraManager:GetCameraLocation()
  local monsterLocation = monster:K2_GetActorLocation()
  local distance = game.distance(cameraLocation, monsterLocation)
  if lastReportedDistance and math.abs(distance - lastReportedDistance) < REPORT_DISTANCE_STEP then
    return
  end
  lastReportedDistance = distance
  game.log("The camera is %.0f units from the squid (camera %.0f, %.0f, %.0f; squid %.0f, %.0f, %.0f; %s)", distance,
    cameraLocation.X, cameraLocation.Y, cameraLocation.Z, monsterLocation.X, monsterLocation.Y, monsterLocation.Z,
    isThirdPerson and "third person" or "first person")
end

-- Runs when the player becomes the entity and about once a second after, while they drive the squid: builds the rig
-- once per squid, and hands the game's camera back to the squid whenever the game's own code has moved it.
function camera.follow(controller, monster)
  local manager = controller.PlayerCameraManager
  if not manager:IsValid() then
    game.log("No camera manager; the view stays as it is")
    return
  end

  if not rig or rig.monsterAddress ~= monster:GetAddress() or not rig.view:IsValid() then
    rig = buildRig(monster)
    if not rig then
      return
    end
    rig.monster = monster
    rig.manager = manager
    applyView()
  end

  local viewTarget = controller:GetViewTarget()
  local cachedCrewBody = manager.Player
  local followsMonster = viewTarget:IsValid() and viewTarget:GetAddress() == monster:GetAddress()
  if cachedCrewBody:IsValid() or not followsMonster then
    local previous = cachedCrewBody:IsValid() and cachedCrewBody or viewTarget
    game.log("The game's camera was following %s; handing it the squid", describe(previous))
    manager:BPI_CameraPlayer_ResetPlayer(monster)
  end

  reportDistance(controller, monster)
end

function camera.toggle()
  isThirdPerson = not isThirdPerson
  if rig and rig.monster:IsValid() and rig.manager:IsValid() then
    applyView()
  end
end

-- After losing: the rig goes, and the game's camera follows whoever the host points it at.
function camera.reset()
  if rig and rig.monster:IsValid() then
    rig.monster.Mesh:SetOwnerNoSee(false)
  end
  if rig and rig.manager:IsValid() then
    rig.manager.ViewPitchMin = defaultLowestPitch(rig.manager)
  end
  if rig and rig.view:IsValid() then
    rig.view:K2_DestroyComponent(rig.view)
    rig.arm:K2_DestroyComponent(rig.arm)
  end
  rig = nil
  isThirdPerson = true
  lastReportedDistance = nil
end

return camera
