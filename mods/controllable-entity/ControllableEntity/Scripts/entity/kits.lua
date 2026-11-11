-- Copyright © 2026 Jalapeno Labs

-- The playable entities: one kit per monster a player can become, and the lookups the other modules use to find a
-- monster's kit. Each kit (kits/<name>.lua) describes its monster: its Blueprint class, its MonsterList value (what the
-- game manager spawns), whether it lives in the vents, its health pools, its cries, and what its moves need. The
-- mission's monster decides which kit drives it.

local squid = require("entity.kits.squid")

local kits = {}

-- Every kit, in the order the host's picker shows them.
kits.playable = { squid }

kits.byId = {}
kits.byClassName = {}
kits.byMonsterType = {}
for _, kit in ipairs(kits.playable) do
  kits.byId[kit.id] = kit
  kits.byClassName[kit.className] = kit
  kits.byMonsterType[kit.monsterType] = kit
end

-- The kit for a monster actor, or nil for a monster no kit plays (or an actor that's gone).
function kits.forMonster(monster)
  if not monster or not monster:IsValid() then
    return nil
  end
  return kits.byClassName[monster:GetClass():GetFName():ToString()]
end

return kits
