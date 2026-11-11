-- Copyright © 2026 Jalapeno Labs

-- Multi Entity: contracts can carry a second and a third entity, for extra bounty, and each arrives a set time after
-- the ship's power comes on. See ../../README.md for the rules and how each part works.
--
-- The same script runs on every machine. The host rolls the modifiers onto contracts and spawns the entities; each
-- machine shows the modifiers on its own screens and pays its own player their bounty, because the game pays every
-- player from their own machine.

local contracts = require("multi.contracts")
local game = require("multi.game")
local screens = require("multi.screens")
local spawner = require("multi.spawner")

contracts.register()
screens.register()
spawner.register()
game.hookLoadedClasses()

LoopInGameThreadWithDelay(1000, game.guarded("The spawn loop", function()
  if not game.isHost() then
    return
  end
  spawner.tick()
end))

game.log("Loaded. Contracts can carry a second and a third entity; the host decides and spawns them.")
