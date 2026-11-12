-- Copyright © 2026 Jalapeno Labs

-- Each playable entity's moves, on the host: one module per kit (moves/<name>.lua) with a function for each of the
-- entity's slots (kits.slots), and Peek for an entity that lives in the vents. The kit (kits/<name>.lua) holds what the
-- moves need to know as data; the moves hold what they do, apart from the kit because they call into the game modules
-- that themselves look kits up.

return {
  byKitId = {
    Squid = require("entity.moves.squid"),
    Mike = require("entity.moves.mike"),
  },
}
