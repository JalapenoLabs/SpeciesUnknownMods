-- Copyright © 2026 Jalapeno Labs

-- The entity's unstuck (playtest 9: fallen into Polar's forbidden underground, the entity had no way back up). Holding
-- F7 for five seconds, still and unhurt, moves a vent entity into the nearest safe duct spot (never on forbidden floor)
-- and any other back where the game spawned it; moving, being hurt or letting go cancels it; it then waits before it
-- works again. The entity player's machine only says when the key goes down and up.
-- Run from the repository root: lua mods/controllable-entity/tests/unstuck_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local config = require("entity.config")
local game = require("entity.game")
local kits = require("entity.kits")
local links = require("entity.links")
local unstuck = require("entity.unstuck")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
-- The forbidden check's filter loads; the floor the navigation allows is everywhere but the underground (X < -5000)
fake.objects["/Game/Blueprints/Monsters/IA/NavAssets/QuerryFilter_CheckForbidden.QuerryFilter_CheckForbidden_C"] =
  fake.object("NavigationQueryFilter")
fake.objects[game.paths.navigation] = fake.object("NavigationSystemV1", nil, {
  K2_ProjectPointToNavigation = function(_, _, spot, out, _, filter)
    out.X, out.Y, out.Z = spot.X, spot.Y, spot.Z
    return filter == nil or spot.X > -5000
  end,
})

local function location(x, y, z)
  return { X = x, Y = y, Z = z }
end
-- Two vent shafts with a duct spot each: one in the forbidden underground, nearer, and a safe one further away
local function vent(spot)
  return fake.object("BP_Vent_Up_C", {
    bHidden = false,
    Point1Component = fake.object("BillboardComponent", nil, { K2_GetComponentLocation = function() return spot end }),
    Point2Component = fake.invalid(),
    Point3Component = fake.invalid(),
    Point4Component = fake.invalid(),
  }, { K2_GetActorLocation = function() return location(spot.X, spot.Y, spot.Z - 300) end })
end
vent(location(-6000, 0, 300))
vent(location(2000, 0, 300))

local controller = fake.object("BP_MyPlayerController_C", { Pawn = fake.invalid() }, {
  IsLocalController = function() return false end,
  K2_GetActorLocation = function() return location(0, 0, 0) end,
}, { "PlayerController" })
-- The host spawns the player's link, as it does every second
fake.installModPak(game.modAssets)
local link = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Health = 1 })
link.SetOwner = function(self, owner) self.Owner = owner end
fake.world = fake.object("World", nil, { SpawnActor = function() return link end })
local squid = fake.object("BP_Monster_Poulpi_C", { location = location(-6500, 0, -200) }, {
  K2_GetActorLocation = function(self) return self.location end,
  K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  K2_TeleportTo = function(self, destination)
    table.insert(fake.calls, { object = self, method = "K2_TeleportTo", args = { destination } })
    self.location = destination
    return true
  end,
})
fake.giveSquidState(squid)
local entity = {
  controller = controller,
  monster = squid,
  kit = kits.byId.Squid,
  startLocation = location(500, 500, 0),
}
local takeover = {
  isEntityController = function(sender) return sender == controller end,
  activeEntity = function() return entity end,
}

links.registerEvents()
links.reconcile()
unstuck.register(takeover)

local function command(name)
  fake.customEvents.EntityServerCommand(fake.param(link), fake.param(fake.name(name)), fake.param(location(1, 0, 0)),
    fake.param(nil))
end
local function lastEvent()
  local events = fake.callsTo(link, "EntityClientEvent")
  return events[#events] and events[#events].args[1]:ToString()
end
local function tickAt(now)
  fake.now = now
  unstuck.tickHost(entity, now)
end

-- Held for five seconds, still and unhurt: into the nearest duct spot that isn't on forbidden floor
fake.now = 100
command("UnstuckStart")
assert(lastEvent() == "UnstuckStarted", "the player is told to keep holding")
tickAt(102)
assert(#fake.callsTo(squid, "K2_TeleportTo") == 0, "nothing happens before five seconds")
tickAt(100 + config.unstuck.holdSeconds)
fake.runFrames()
local teleports = fake.callsTo(squid, "K2_TeleportTo")
assert(#teleports == 1 and teleports[1].args[1].X == 2000, "into the safe duct, not the nearer one underground")
assert(squid.InVent, "in the ducts")
assert(lastEvent() == "Unstuck", "and told so")
command("UnstuckStop")
assert(lastEvent() == "Unstuck", "letting go afterwards changes nothing")

-- It then waits before it works again
fake.now = 110
command("UnstuckStart")
assert(lastEvent() == "Denied.UnstuckCooldown", "not again so soon")

-- Moving, being hurt or letting go cancels it
fake.now = 300
command("UnstuckStart")
squid.location = location(2000 + config.unstuck.stillDistance + 10, 0, 300)
tickAt(301)
assert(lastEvent() == "UnstuckCancelled", "moving cancels it")
command("UnstuckStart")
link.Health = 0.5
tickAt(302)
assert(lastEvent() == "UnstuckCancelled", "being hurt cancels it")
link.Health = 1
command("UnstuckStart")
command("UnstuckStop")
assert(lastEvent() == "UnstuckCancelled", "letting go cancels it")
tickAt(310)
assert(#fake.callsTo(squid, "K2_TeleportTo") == 1, "and a cancelled unstuck never goes through")
squid.IsOnGround = true
command("UnstuckStart")
assert(lastEvent() == "Denied.Down", "a downed entity can't")
squid.IsOnGround = false

-- An entity that doesn't live in the vents goes back where the game spawned it
entity.kit = kits.byId.Terminator
squid.IsStunt = false
fake.now = 400
command("UnstuckStart")
tickAt(400 + config.unstuck.holdSeconds)
teleports = fake.callsTo(squid, "K2_TeleportTo")
assert(teleports[#teleports].args[1].X == 500, "the Terminator goes back where the game spawned it")
entity.kit = kits.byId.Squid

-- The entity player's machine says when F7 goes down and comes back up, once each
local held = false
controller.IsLocalController = function() return true end
controller.IsInputKeyDown = function(_, key)
  return key.KeyName:ToString() == config.keys.unstuck and held
end
local function serverCommands()
  local names = {}
  for _, call in ipairs(fake.callsTo(link, "EntityServerCommand")) do
    table.insert(names, call.args[1]:ToString())
  end
  return names
end
unstuck.followPlayer(controller)
assert(#serverCommands() == 0, "nothing while F7 is up")
held = true
unstuck.followPlayer(controller)
unstuck.followPlayer(controller)
assert(#serverCommands() == 1 and serverCommands()[1] == "UnstuckStart", "F7 down starts it, once")
held = false
unstuck.followPlayer(controller)
assert(#serverCommands() == 2 and serverCommands()[2] == "UnstuckStop", "F7 up stops it")

print("unstuck test passed")
