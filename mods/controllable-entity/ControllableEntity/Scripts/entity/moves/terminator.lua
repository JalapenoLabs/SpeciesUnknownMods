-- Copyright © 2026 Jalapeno Labs

-- The Terminator's moves (BP_BigRobot), on the host: its gatling while Shoot is held (a punch once the crew has broken
-- it), a grenade (RMB), the arm grab that crushes a head (E) and its charge (Space). Their numbers are in its kit.
--
-- What its AI did for it that a player's robot still needs is here too: it faces where its player looks (its own
-- turning falls back to world yaw 0 without an AI), its drones stay off, it wakes when the lair says so, and its
-- gatling stops when the robot can no longer hold it.

local game = require("entity.game")
local kits = require("entity.kits")
local shared = require("entity.moves.shared")

local kit = kits.byId.Terminator
-- How far along the aim the point it faces lies.
local LOOK_DISTANCE = 2000
-- Its plain grenade throw (BPI_BigRobot_ThrowGrenade's SearchType); 1 to 3 are its throws into vents and up ladders.
local BASE_THROW = 0
-- Its AI's behaviour types (BehaviorEnum): any but Wait (6) powers it up. Patrol does so without combat, which would
-- start the action music for everyone.
local BEHAVIOUR_PATROL = 0
local KISMET_SYSTEM = "/Script/Engine.Default__KismetSystemLibrary"

-- Whether its gatling is firing, on the host: Shoot held, and nothing has stopped it since.
local isFiring = false

local function stopFiring(monster)
  if isFiring then
    monster:BPI_BigRobot_SetFiring(false)
    isFiring = false
  end
end

-- Once the crew has broken its gatling: its punch on the crew member nearest the aim, or at the air. Never its other
-- close attack (atk_front03), which crushes the head of whoever it lands on, a kill the meter can't rule; so never
-- SetSimpleAttack either, which picks that one once the gatling is gone.
local function punch(monster, aim)
  local punchMove = kit.moves.Primary
  local target = shared.crewInCone(monster, aim, punchMove.reach, punchMove.coneDegrees)
  local swing = game.loadGameAsset(kit.swingMontage)
  if not swing then
    return false, "NoTarget"
  end
  monster["AttackSimpleAnim (Clients)"](monster, swing, monster.AttackSimplePlayRate, target)
  return true
end

-- Shoot: the gatling fires while it is held, through its own trigger (BPI_BigRobot_SetFiring), which spins it up and
-- fires along its muzzle. The muzzle points where the robot faces: its arm only turns toward a target in combat, which
-- the player's robot never enters (see BEHAVIOUR_PATROL), so the shots fly level.
local function fire(monster, aim)
  if not monster.HaveGatling then
    return punch(monster, aim)
  end
  local able = {}
  monster:BPI_BigRobot_IsAbleToShoot(able)
  if not monster.CanShoot or not able.True then
    return false, "CantShoot"
  end
  monster:BPI_BigRobot_SetFiring(true)
  isFiring = true
  return true
end

-- RMB: a grenade, lobbed at the crew member nearest the aim, or ahead along it onto the floor. The crew member it
-- throws at stays its LastAttackedTarget, which its throw follows; with nobody, that's cleared, or the last one would
-- take over the aim.
local function grenade(monster, aim)
  local throw = kit.moves.Secondary
  local origin = monster:K2_GetActorLocation()
  local target = shared.crewInCone(monster, aim, throw.range, throw.coneDegrees)
  local location = target and target:K2_GetActorLocation()
  if not location then
    local ahead = shared.horizontal(aim)
    local floorHeight = origin.Z - monster.CapsuleComponent:GetScaledCapsuleHalfHeight()
    location = {
      X = origin.X + ahead.X * throw.aheadDistance,
      Y = origin.Y + ahead.Y * throw.aheadDistance,
      Z = floorHeight,
    }
  end
  if game.distance(origin, location) < throw.safeDistance then
    return false, "TooClose"
  end

  local canThrow = {}
  monster:BPI_BigRobot_CanThrowGrenade(BASE_THROW, location, target, canThrow)
  if not canThrow.True then
    return false, "NoThrow"
  end
  stopFiring(monster)
  monster.LastAttackedTarget = target
  monster:BPI_BigRobot_ThrowGrenade(location, BASE_THROW)
  return true
end

-- E: the arm grab (BPI_Monster_SetSpecialAttack), which reaches for the crew member given after a half-second windup
-- and grabs only them. The kill meter is armed first (abilities.lua), so the grab kills.
local function armGrab(monster, aim)
  local grab = kit.moves.Ultimate
  local target = shared.crewInCone(monster, aim, grab.reach, grab.coneDegrees)
  if not target then
    return false, "NoTarget"
  end
  stopFiring(monster)
  monster:BPI_Monster_SetSpecialAttack(target)
  return true
end

-- Space: its charge, the AI's dash played through the same multicast, along where it faces; it hurts whoever it runs
-- through, and the crew member nearest the aim is its target.
local function charge(monster, aim)
  local chargeMove = kit.moves.Mobility
  local dash = game.loadGameAsset(kit.dashMontage)
  if not dash then
    return false, "NoTarget"
  end
  stopFiring(monster)
  local target = shared.crewInCone(monster, aim, chargeMove.reach, chargeMove.coneDegrees)
  monster["AttackSimpleAnim (Clients)"](monster, dash, monster.AttackSimplePlayRate, target)
  return true
end

-- The pool hits are draining, for the HUD's health bar, and whether it is down (stunned and unhurtable): its
-- gatling's while it holds one (BP_Gatling.MainHealth, which takes every hit then), its body's once the gun is broken.
local function healthShare(monster)
  local downed = monster[kit.healthFields.downed] == true
  local gatling = monster.HaveGatling and monster.Gatling
  if gatling and gatling:IsValid() and gatling.MaxHealth > 0 then
    return math.min(1, gatling.MainHealth / gatling.MaxHealth), downed
  end
  if monster.MaxHealth <= 0 then
    return 1, downed
  end
  return math.min(1, monster.Health / monster.MaxHealth), downed
end

return {
  Primary = fire,
  PrimaryRelease = stopFiring,
  Secondary = grenade,
  Ultimate = armGrab,
  Mobility = charge,
  healthShare = healthShare,

  -- At the takeover, and when a reload of the mod takes it back. Its drones (BP_SphereBot) hunt for it near crew far
  -- away, spawned by a timer that every possession starts again a moment later (ReceivePossessed), the player's too.
  -- The timer checks its off switch first, so that switch stops them for good; the running timer goes as well, and
  -- drones already out flee. A knockback can throw a grenade at its MainTarget on its own, so it keeps none.
  begin = function(entity)
    local monster = entity.monster
    isFiring = false
    monster["[DEBUG]NoSphereSpawn"] = true
    StaticFindObject(KISMET_SYSTEM):K2_ClearTimer(monster, "CheckPlayersForSpawnSphere")
    monster:ClearSphereBot()
    monster.MainTarget = nil
  end,

  -- Powers it up, when the lair lets it go (lair.lua): it gets up off the floor.
  wake = function(monster)
    monster:BPI_Monster_SwitchBehavior(BEHAVIOUR_PATROL)
  end,

  -- About thirty times a second on the host: it faces where its player looks, as its AI faced its target (its own
  -- turning, MoveFaceToTarget, turns toward that point every tick), and its gatling stops when the robot can no longer
  -- fire it: broken, stunned or electrocuted (only electrocution stops it in the game's own code).
  tick = function(entity)
    local monster = entity.monster
    if isFiring and (not monster.HaveGatling or monster.IsStunt or monster.IsElectrocuted) then
      stopFiring(monster)
    end
    -- Lying powered down, it faces nowhere
    if not monster[kit.poweredFlag] then
      return
    end
    local origin = monster:K2_GetActorLocation()
    local aim = game.rotationDirection(entity.controller:GetControlRotation())
    local point = {
      X = origin.X + aim.X * LOOK_DISTANCE,
      Y = origin.Y + aim.Y * LOOK_DISTANCE,
      Z = origin.Z + aim.Z * LOOK_DISTANCE,
    }
    monster:BPI_BasicMonster_LookAtLocation(true, point, false)
  end,
}
