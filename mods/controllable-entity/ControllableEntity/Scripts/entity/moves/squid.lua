-- Copyright © 2026 Jalapeno Labs

-- The squid's moves (BP_Monster_Poulpi), on the host, each the same function its AI uses: the lash (LMB), the leap
-- where it looks (RMB), the ultimate's guaranteed kill (E) and venting (Space). Their numbers are in its kit.

local ducts = require("entity.moves.ducts")
local game = require("entity.game")
local kits = require("entity.kits")
local movement = require("entity.movement")
local shared = require("entity.moves.shared")

local kit = kits.byId.Squid
-- The leap takes a crew member a little past where it lands.
local LEAP_TARGET_SLACK = 150
-- The squid gets up on its own once it is down and no longer burning (its heat at most this), a second or so later.
local BURNING_HEAT = 0.1
-- How long it may lie unburnt with nothing playing before the host gets it up itself: longer than the game's own wait.
local STUCK_DOWN_SECONDS = 3

-- When the squid began lying down, unburnt, with nothing playing; nil while it isn't.
local stuckDownSince = nil

-- The game gets a downed squid up once (BP_Monster_Poulpi's get-up check: GetUp, a refilled stagger pool). A montage
-- that interrupts that get-up leaves the squid down for good on the host, lying there and dragged along while its
-- player moves, unable to vent (playtest 9). The moves wait while it's down (abilities.lua), but the game's own
-- reactions can still interrupt it, so once it has lain unburnt with nothing playing for longer than the game waits,
-- the host gets it up the same way.
local function getUpIfStuck(entity)
  local monster = entity.monster
  local isStuckDown = monster.IsOnGround == true and monster.BasicOverrideAnim ~= true
    and monster.HeatValue <= BURNING_HEAT and monster.IsDead ~= true
  if not isStuckDown then
    stuckDownSince = nil
    return
  end
  local now = game.timeSeconds(monster)
  stuckDownSince = stuckDownSince or now
  if now - stuckDownSince < STUCK_DOWN_SECONDS then
    return
  end
  stuckDownSince = nil
  monster["GetUp (Multi)"](monster, monster.MainSpeedMultiplier)
  monster.HealthTemporal = monster.MaxHealthTemporal
  monster.ShouldFallOnGround = false
  game.log("The squid lay down with its get-up cut short; getting it up")
end

-- With a crew member in reach, the AI's own attack on them. With nobody, the swing at the air: its damage comes from
-- the montage's sphere check in front of the squid (BP_ParentMonster.BasicSphereAttackDamage), so it hurts nobody.
local function lash(monster, aim)
  local lashMove = kit.moves.Primary
  local target, distance = shared.crewInCone(monster, aim, lashMove.reach, lashMove.coneDegrees)
  if target then
    monster:BPI_BasicMonster_SetSimpleAttack(target, target:K2_GetActorLocation(), distance)
    return true
  end
  return shared.swingAtAir(monster, kit.swingMontage)
end

-- The AI's leap checks its own range and arc, then writes LastSpecialAttackPlayerLocation for SetSpecialAttack to
-- warp to. The entity leaps where they aim, so the landing point is written here instead. A crew member it lands on
-- is grabbed by the head (GrabHeadPlayer), which the kill meter rules.
local function leap(monster, aim)
  ducts.stopPeeking(monster)
  local distance = kit.moves.Secondary.distance
  local origin = monster:K2_GetActorLocation()
  local direction = shared.horizontal(aim)
  monster.LastSpecialAttackPlayerLocation = {
    X = origin.X + direction.X * distance,
    Y = origin.Y + direction.Y * distance,
    Z = origin.Z,
  }
  local target = shared.crewInCone(monster, aim, distance + LEAP_TARGET_SLACK, kit.moves.Primary.coneDegrees)
  monster:BPI_Monster_SetSpecialAttack(target or monster)
  return true
end

-- RMB: the leap, which costs stamina and can't be made out of breath. The ultimate's leap, which delivers the kill,
-- costs nothing.
local function staminaLeap(monster, aim, _, entity)
  if not movement.spendStamina(entity, kit.moves.Secondary.staminaCost) then
    return false, "OutOfBreath"
  end
  return leap(monster, aim)
end

return {
  Primary = lash,
  Secondary = staminaLeap,
  -- With the kill armed (abilities.lua), the squid leaps, or drops from the vent, at once to deliver it: both end in
  -- its head grab
  Ultimate = function(monster, aim)
    if monster.InVent then
      return ducts.vent(monster)
    end
    return leap(monster, aim)
  end,
  Mobility = ducts.vent,
  Peek = ducts.peek,
  tick = getUpIfStuck,
}
