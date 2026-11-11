-- Copyright © 2026 Jalapeno Labs

-- The squid's own cries, as the host: a "seen you" call when the entity first spots a crew member, and the escape
-- roar when the squid gets back up after being knocked down. The cries the entity asks for are in host_flow_test.
-- Run from the repository root: lua mods/controllable-entity/tests/cries_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local kits = require("entity.kits")

local game = require("entity.game")
local cries = require("entity.cries")

local function location(x, y, z)
  return { X = x, Y = y, Z = z }
end

local seenCue, escapeCue = fake.object("SoundCue"), fake.object("SoundCue")
fake.objects[kits.byId.Squid.cries.Seen] = seenCue
fake.objects[kits.byId.Squid.cries.Escape] = escapeCue

-- The entity looks along +X; a crew member stands ahead, in its line of sight unless a wall is in the way
local hasLineOfSight = true
local controller = fake.object("BP_MyPlayerController_C", nil, {
  GetControlRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  LineOfSightTo = function() return hasLineOfSight end,
})
local squid = fake.object("BP_Monster_Poulpi_C", { IsOnGround = false }, {
  K2_GetActorLocation = function() return location(0, 0, 0) end,
})
local crewMember = fake.object("BP_Character_C", { bHidden = false, location = location(1500, 0, 0) }, {
  K2_GetActorLocation = function(self) return self.location end,
})
local entity = { monster = squid, kit = kits.byId.Squid, controller = controller }

local function cuesPlayed(cue)
  local count = 0
  for _, call in ipairs(fake.callsTo(squid, "BPI_Monster_PlayVoiceAudio")) do
    if call.args[1] == cue then
      count = count + 1
    end
  end
  return count
end

-- Playtest 7: a player's squid made none of the AI's cries. Spotting a crew member, it calls out on every machine
cries.tickHost(entity, 0)
assert(cuesPlayed(seenCue) == 1, "the entity calls out on first seeing a crew member")
local call = fake.callsTo(squid, "BPI_Monster_PlayVoiceAudio")[1]
assert(call.args[6] == true and call.args[8] == true, "on every machine, waiting for any cry already playing")
cries.tickHost(entity, 1)
assert(cuesPlayed(seenCue) == 1, "once, while the crew member stays in sight")

-- Out of sight and back: it calls again, but not more often than every few seconds
hasLineOfSight = false
cries.tickHost(entity, 2)
hasLineOfSight = true
cries.tickHost(entity, 3)
assert(cuesPlayed(seenCue) == 1, "not again so soon")
hasLineOfSight = false
cries.tickHost(entity, 9)
hasLineOfSight = true
cries.tickHost(entity, 10)
assert(cuesPlayed(seenCue) == 2, "but again after a while")

-- Behind the entity, or hidden (the entity's own parked crew body), a crew member isn't seen
hasLineOfSight = false
cries.tickHost(entity, 20)
hasLineOfSight = true
crewMember.location = location(-1500, 0, 0)
cries.tickHost(entity, 30)
crewMember.location = location(1500, 0, 0)
crewMember.bHidden = true
cries.tickHost(entity, 40)
assert(cuesPlayed(seenCue) == 2, "nobody behind it or hidden counts")

-- Knocked down and back up: the escape roar, as the AI makes it
squid.IsOnGround = true
cries.tickHost(entity, 50)
assert(cuesPlayed(escapeCue) == 0, "nothing while it's down")
squid.IsOnGround = false
cries.tickHost(entity, 51)
assert(cuesPlayed(escapeCue) == 1, "the escape roar as it gets back up")

print("cries test passed")
