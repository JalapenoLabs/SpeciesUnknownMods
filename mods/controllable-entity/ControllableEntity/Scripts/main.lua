-- Copyright © 2026 Jalapeno Labs

-- Controllable Entity: one player becomes the mission's monster (the squid or Mike) and hunts the crew.
-- See ../../README.md for the rules and how each part works.
--
-- Every player installs the mod; the same script runs on each machine. Gameplay rules run on the host (each loop
-- checks), while each player's machine handles their own input and HUD.

local abilities = require("entity.abilities")
local capture = require("entity.capture")
local crawl = require("entity.crawl")
local cries = require("entity.cries")
local config = require("entity.config")
local control = require("entity.control")
local flee = require("entity.flee")
local frenzy = require("entity.frenzy")
local game = require("entity.game")
local hud = require("entity.hud")
local hunt = require("entity.hunt")
local lair = require("entity.lair")
local links = require("entity.links")
local movement = require("entity.movement")
local picker = require("entity.picker")
local puzzles = require("entity.puzzles")
local senses = require("entity.senses")
local takeover = require("entity.takeover")
local unstuck = require("entity.unstuck")
local voice = require("entity.voice")
local zones = require("entity.zones")

links.registerEvents()
takeover.register()
abilities.register()
frenzy.register(abilities, takeover)
hunt.register()
voice.register(takeover)
capture.register(takeover)
flee.register(takeover)
lair.register(takeover)
unstuck.register(takeover)
movement.register(takeover.isEntityController)
senses.register(abilities, takeover)
control.register()
hud.register()
picker.register()
game.hookLoadedClasses()

-- Host loops: links, the takeover and the puzzles' sizes reconcile once a second; the entity's speed, the meter and the lair's leash run
-- five times a second.
LoopInGameThreadWithDelay(1000, function()
  if not game.isHost() then
    return
  end
  links.reconcile()
  takeover.reconcile()
  puzzles.tickHost(takeover.activeEntity())
end)

LoopInGameThreadWithDelay(200, function()
  if not game.isHost() then
    return
  end
  -- The speed, stamina and vent time first, so the link the meter's tick fills carries this tick's values. A monster
  -- on its way out (dying, or the map ending) loses its components a moment before the takeover notices; its systems
  -- leave it be meanwhile (playtest 9: the speed tripped over its gone movement component)
  local entity = takeover.activeEntity()
  local isPresent = entity and entity.monster:IsValid() and entity.monster.CharacterMovement:IsValid()
  if isPresent then
    local now = game.timeSeconds(entity.monster)
    movement.tickHost(entity, now)
    hunt.tick(entity, now)
    zones.tickHost(entity, now)
    -- Only an entity that lives in the vents crouches into the crawl openings
    if entity.kit.usesVents then
      crawl.tickHost(entity)
    end
    cries.tickHost(entity, now)
    unstuck.tickHost(entity, now)
    senses.tickHost(entity, now)
    flee.tickHost(entity, now)
  end
  abilities.tick()
  lair.tick()
end)

game.log("Loaded. %s in the lobby volunteers to be the entity; the host's %s picks the entity and its player.",
  config.keys.volunteer, config.keys.picker)
