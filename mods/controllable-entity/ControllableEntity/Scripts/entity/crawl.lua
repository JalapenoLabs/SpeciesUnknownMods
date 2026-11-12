-- Copyright © 2026 Jalapeno Labs

-- The floor-level openings into the ducts that the crew crouch through (playtest 6), on the host.
--
-- Only a vent shaft puts a monster in its crouched vent state, and the game's own trigger at these openings
-- (BP_Trigger_Crouch, VentEnter: six on Hawking, two in crew quarters and four in the lab) crouches only a monster
-- its AI drives, so the standing monster didn't fit through. As the entity moves into one from the room, the host puts
-- it in its vent state, which crouches it on every machine (as the lair's start does). Coming back out, the game's
-- own trigger stands any monster up, so the mod crouches the entity only while it's heading into the opening.

local config = require("entity.config")
local game = require("entity.game")
local hunt = require("entity.hunt")
local zones = require("entity.zones")

local crawl = {}

local TRIGGER_CLASS_NAME = "BP_Trigger_Crouch_C"

-- Whether the entity is heading into an opening: its trigger's forward points into the duct, so the entity moves along
-- it, faster than a drift.
local function isHeadingIn(monster, trigger)
  local velocity = monster:GetVelocity()
  local forward = trigger:GetActorForwardVector()
  return velocity.X * forward.X + velocity.Y * forward.Y > config.vents.crawlEntrySpeed
end

-- Runs five times a second on the host while there is an entity.
function crawl.tickHost(entity)
  local monster = entity.monster
  -- Already crouched in the ducts, or shut out of them by the hunt (hunt.lua)
  if monster.InVent == true or hunt.areVentsShut() then
    return
  end
  local location = monster:K2_GetActorLocation()
  for _, trigger in ipairs(FindAllOf(TRIGGER_CLASS_NAME) or {}) do
    local isEntrance = trigger:IsValid() and trigger.VentEnter
    local box = isEntrance and zones.componentBox(trigger.CollisionComponent)
    if box and zones.isInside(box, location, config.vents.crawlReach) and isHeadingIn(monster, trigger) then
      monster:BPI_Monster_SetInVent(true)
      game.log("The entity crouches into a crawl opening at %.0f, %.0f, %.0f", location.X, location.Y, location.Z)
      return
    end
  end
end

return crawl
