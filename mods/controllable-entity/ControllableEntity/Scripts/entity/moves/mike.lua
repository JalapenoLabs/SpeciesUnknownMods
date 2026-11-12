-- Copyright © 2026 Jalapeno Labs

-- Mike's moves (BP_Monster_Michel), on the host: the swipe (LMB), a dodge aside (RMB), the grab that eats a face (E)
-- and venting (Space). He has no leap: his Blueprint switches it off (AllowSpecialAttack). Their numbers are in his
-- kit.

local ducts = require("entity.moves.ducts")
local game = require("entity.game")
local kits = require("entity.kits")
local shared = require("entity.moves.shared")

local kit = kits.byId.Mike
-- His dodge at its own speed: the AI's play rate, before the 1.1 it uses against a crew member holding his weakness.
local DODGE_SPEED = 1.0
-- How far around the dodge's landing the navigation may look for floor.
local DODGE_FLOOR_EXTENT = { X = 60, Y = 60, Z = 200 }
-- What a shield in the way takes instead of the grab, as his own grab check deals it.
local SHIELD_PUNCH_DAMAGE = 100
local PUNCH_DAMAGE_TYPE = "/Game/Blueprints/DamageType/DamageType_Punch.DamageType_Punch_C"

-- A quaternion turning by a yaw (degrees) about the vertical, for a transform's rotation.
local function yawQuaternion(yaw)
  local halfAngle = math.rad(yaw) / 2
  return { X = 0, Y = 0, Z = math.sin(halfAngle), W = math.cos(halfAngle) }
end

local function yawTowards(from, to)
  return math.deg(math.atan(to.Y - from.Y, to.X - from.X))
end

-- Turns him to a yaw on the host; his movement replicates it.
local function face(monster, yaw)
  local rotation = monster:K2_GetActorRotation()
  monster:K2_SetActorRotation({ Pitch = rotation.Pitch, Yaw = yaw, Roll = rotation.Roll }, false)
end

-- With a crew member in reach, the AI's own attack on them: standing, one of his two swipes; crouched (in a crawl
-- space), his grab instead (his GetAttackSimpleAnim), which the kill meter rules like any grab. With nobody in reach,
-- the swing at the air sets him attacking, so it hurts whoever it does sweep.
local function swipe(monster, aim)
  local swipeMove = kit.moves.Primary
  local target, distance = shared.crewInCone(monster, aim, swipeMove.reach, swipeMove.coneDegrees)
  if target then
    monster:BPI_BasicMonster_SetSimpleAttack(target, target:K2_GetActorLocation(), distance)
    return true
  end
  return shared.swingAtAir(monster, kit.swingMontage)
end

-- The floor beside him on one side (1 right, -1 left of the aim), as the navigation finds it, or nil.
local function dodgeLanding(monster, facing, side)
  local origin = monster:K2_GetActorLocation()
  local distance = kit.moves.Secondary.distance
  local spot = {
    X = origin.X - facing.Y * side * distance,
    Y = origin.Y + facing.X * side * distance,
    Z = origin.Z,
  }
  local floor = {}
  local navigation = StaticFindObject(game.paths.navigation)
  if not navigation:K2_ProjectPointToNavigation(monster, spot, floor, nil, nil, DODGE_FLOOR_EXTENT) or not floor.Z then
    return nil
  end
  return { X = floor.X, Y = floor.Y, Z = floor.Z + monster.CapsuleComponent:GetScaledCapsuleHalfHeight() }
end

-- His own sidestep (BPI_Monster_SetDodging), its root motion warped to a spot beside him, as the AI's dodge is
-- (BTService_CheckDodging). It goes the way the player is moving across their view (A or D held), and right when
-- they aren't; a side with no floor gives way to the other. He turns to the aim first: his dodge plays left or right
-- by where the spot lies against his own facing, which follows his movement.
local function dodge(monster, aim)
  if monster.InVent then
    return false, "DodgeInVent"
  end
  local facing = shared.horizontal(aim)
  local velocity = monster:GetVelocity()
  local sideways = -facing.Y * velocity.X + facing.X * velocity.Y
  local preferred = sideways < 0 and -1 or 1

  local landing = dodgeLanding(monster, facing, preferred) or dodgeLanding(monster, facing, -preferred)
  if not landing then
    return false, "NoRoom"
  end
  local yaw = math.deg(math.atan(facing.Y, facing.X))
  face(monster, yaw)
  local finalTransform = {
    Rotation = yawQuaternion(yaw),
    Translation = landing,
    Scale3D = { X = 1, Y = 1, Z = 1 },
  }
  monster:BPI_Monster_SetDodging(finalTransform, landing, DODGE_SPEED)
  return true
end

-- Whether a crew member can be grabbed: what his own grab check asks before grabbing (his ContinusSphereCheck), for
-- the ultimate's grab, which skips the check's sphere. A crew member behind a shield isn't; the shield takes his
-- punch instead, as it does from his own check (forced: his punch counts only mid-attack otherwise).
local function grabbable(monster, target)
  local dead = {}
  target:BPI_Human_IsDead(dead)
  local canBeGrabbed = {}
  target:BPI_Human_CanBeGrabbed(false, canBeGrabbed)
  if dead.IsDead or not canBeGrabbed.True then
    return false, "NoTarget"
  end

  local haveShield, hitShield = {}, {}
  monster:CheckShieldBeforeTarget(target, haveShield, hitShield)
  if haveShield.HaveShield then
    local punch = game.loadGameAsset(PUNCH_DAMAGE_TYPE)
    monster:BPI_BasicMonster_SetHitDamageShield(hitShield.HitShield, SHIELD_PUNCH_DAMAGE, punch, true)
    return false, "Shielded"
  end
  return true
end

-- The ultimate's grab: the crew member nearest the aim, close in, grabbed at once with his own grab (GrabPlayerVent,
-- which pulls them to him and eats their face). The kill meter is armed first (abilities.lua), so the grab kills. In
-- the ducts it reaches a crew member crouched in a crawl space; the crew in the rooms below are out of reach until
-- he drops.
local function devour(monster, aim)
  if monster.IsGrabPlayer then
    return false, "Cooldown"
  end
  local devourMove = kit.moves.Ultimate
  local target = shared.crewInCone(monster, aim, devourMove.reach, devourMove.coneDegrees)
  if not target then
    return false, "NoTarget"
  end
  local ok, reason = grabbable(monster, target)
  if not ok then
    return false, reason
  end

  ducts.stopPeeking(monster)
  face(monster, yawTowards(monster:K2_GetActorLocation(), target:K2_GetActorLocation()))
  monster.LastAttackedTarget = target
  monster["GrabPlayerVent ( Multi)"](monster, target)
  return true
end

return {
  Primary = swipe,
  Secondary = dodge,
  Ultimate = devour,
  Mobility = ducts.vent,
  Peek = ducts.peek,
}
