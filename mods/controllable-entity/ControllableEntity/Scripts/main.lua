-- Copyright © 2026 Jalapeno Labs

-- Controllable Entity: one player becomes the mission's monster (the squid) and hunts the crew.
-- See ../../README.md for the rules and how each part works.
--
-- Every player installs the mod; the same script runs on each machine. Gameplay rules run on the host (each loop
-- checks), while each player's machine handles their own input and HUD.

local abilities = require("entity.abilities")
local config = require("entity.config")
local control = require("entity.control")
local frenzy = require("entity.frenzy")
local game = require("entity.game")
local hud = require("entity.hud")
local links = require("entity.links")
local senses = require("entity.senses")
local takeover = require("entity.takeover")

links.registerEvents()
takeover.register()
abilities.register()
frenzy.register(abilities, takeover)
senses.register(abilities, takeover)
control.register()
hud.register()
game.hookLoadedClasses()

-- Host loops: links and the takeover reconcile once a second; the meter advances five times a second.
LoopInGameThreadWithDelay(1000, function()
  if not game.isHost() then
    return
  end
  links.reconcile()
  takeover.reconcile()
end)

LoopInGameThreadWithDelay(200, function()
  if game.isHost() then
    abilities.tick()
  end
end)

game.log("Loaded. %s in the lobby volunteers to be the entity.", config.keys.volunteer)
