-- Copyright © 2026 Jalapeno Labs

-- The squid's moves (BP_Monster_Poulpi), on the host, each the same function its AI uses: the lash (LMB), the leap
-- where it looks (RMB), the ultimate's guaranteed kill (E) and venting (Space). Their numbers are in its kit.

local ducts = require("entity.moves.ducts")
local kits = require("entity.kits")
local shared = require("entity.moves.shared")

local kit = kits.byId.Squid
-- The leap takes a crew member a little past where it lands.
local LEAP_TARGET_SLACK = 150

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

return {
  Primary = lash,
  Secondary = leap,
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
}
