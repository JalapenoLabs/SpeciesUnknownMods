-- Copyright © 2026 Jalapeno Labs

-- Each playable entity's moves, on the host: one module per kit (moves/<name>.lua). The kit (kits/<name>.lua) holds
-- what the moves need to know as data; the moves hold what they do, apart from the kit because they call into the
-- game modules that themselves look kits up.
--
-- A module has a function for each of the entity's slots (kits.slots), and Peek for an entity that lives in the vents.
-- It may also have:
--   - PrimaryRelease(monster): letting go of Shoot, for a Primary that is held;
--   - begin(entity): at the takeover, and when a reload of the mod takes the entity back;
--   - finish(entity): when it stops being the entity (it lost, or its monster was captured);
--   - wake(monster): for an entity the lair keeps powered down (lair.lua);
--   - tick(entity): about thirty times a second on the host while it is the entity;
--   - healthShare(monster): the HUD's health bar and whether it is down, for an entity whose pools aren't its kit's
--     healthFields alone.

return {
  byKitId = {
    Squid = require("entity.moves.squid"),
    Mike = require("entity.moves.mike"),
    Terminator = require("entity.moves.terminator"),
  },
}
