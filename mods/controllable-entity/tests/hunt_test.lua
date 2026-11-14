-- Copyright © 2026 Jalapeno Labs

-- The hunt, as the host: once a crew member holds the weapon that can kill the specimen, the squid's time in the
-- vents runs down while it's inside them and refills slowly outside; when it runs out the squid is forced out and the
-- vents stay shut to it until the time has refilled partway.
-- Run from the repository root: lua mods/controllable-entity/tests/hunt_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local config = require("entity.config")
local game = require("entity.game")
local kits = require("entity.kits")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modAssets)
fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0, Contract = {} })

local function location(x, y, z)
  return { X = x, Y = y, Z = z }
end

local function playerState(lobbyId)
  return fake.object("BP_MyPlayerState_C", nil, {
    BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = lobbyId end,
  })
end

local function controller(isLocal, state)
  local object = fake.object("BP_MyPlayerController_C", { PlayerState = state, Pawn = fake.invalid() }, {
    IsLocalController = function() return isLocal end,
    IsPlayerController = function() return true end,
    K2_GetActorLocation = function() return location(0, 0, 0) end,
    GetControlRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  }, { "PlayerController" })
  object.Possess = function(self, pawn)
    self.Pawn = pawn
    pawn.Controller = self
  end
  fake.giveView(object)
  return object
end

local entityState, crewState = playerState(0), playerState(1)
local entityController = controller(true, entityState)
controller(false, crewState)

local entityLink = nil
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local link = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    link.SetOwner = function(self, owner)
      self.Owner = owner
      if owner == entityController then
        entityLink = link
      end
    end
    return link
  end,
})

-- A kill contract with the power off: a crew member at the origin, a vent near them and one far away
fake.object("BP_MyGameState_C", {
  LightStatut = game.lightStatus.Off,
  Contract = { ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Elimination },
  ["In Game Player State "] = fake.array({ entityState, crewState }),
  PlayerArray = fake.array({ entityState, crewState }),
}, nil, { "GameStateBase" })
fake.object("BP_PlayableGameMode_C")

local function vent(floorLocation, spot)
  return fake.object("BP_Vent_Up_C", {
    Point1Component = fake.object("BillboardComponent", nil, {
      K2_GetComponentLocation = function() return spot end,
    }),
    Point2Component = fake.invalid(),
    Point3Component = fake.invalid(),
    Point4Component = fake.invalid(),
  }, {
    K2_GetActorLocation = function() return floorLocation end,
  })
end
local nearVent = vent(location(300, 0, 0), location(350, 0, 400))
local farVent = vent(location(6000, 0, 0), location(6050, 0, 400))

fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") }, {
  K2_GetActorLocation = function() return location(0, 0, 0) end,
})
entityController.Pawn = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })

local squid = fake.object("BP_Monster_Poulpi_C", {
  Controller = fake.invalid(),
  InVent = false,
  ShouldCheckIfStuck = true,
  location = location(0, 500, 0),
}, {
  -- The host's own crouch, as when the host plays the entity: it applies at once
  BPI_Monster_SetInVent = function(self, inVent) self.InVent, self.bIsCrouched = inVent, inVent end,
  K2_GetActorLocation = function(self) return self.location end,
  K2_GetActorRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  K2_TeleportTo = function(self, destination)
    self.location = destination
    return true
  end,
})
fake.giveSquidState(squid)
squid.CapsuleComponent = fake.object("CapsuleComponent", nil, { GetScaledCapsuleHalfHeight = function() return 60 end })

-- The screen that restores the power, facing -X, and the navigation that finds the floor in front of it
fake.object("BP_Screen_RestorePower_C", nil, {
  K2_GetActorLocation = function() return location(7704, 0, 1200) end,
  GetActorForwardVector = function() return location(-1, 0, 0) end,
})
fake.objects["/Script/NavigationSystem.Default__NavigationSystemV1"] = fake.object("NavigationSystemV1", nil, {
  K2_ProjectPointToNavigation = function(_, _, point, projected)
    projected.X, projected.Y, projected.Z = point.X, point.Y, 1100
    return true
  end,
})
-- The squid spawns once the volunteer is signed up, as when a crew member leaves the shuttle on Hawking
local gameManager = fake.object("BP_GameManager_C", { Monster = fake.invalid() })
local weapon = fake.object("BP_LaserGun_C", { IsObjectiveWeapon = true, IsGrabbed = true })
local roarCue = fake.object("SoundCue")
fake.objects[kits.byId.Squid.cries.Roar] = roarCue

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")
for _, classPath in ipairs({ kits.byId.Squid.classPath, game.paths.gameStateClass, game.paths.weaponClass }) do
  fake.loadClass(classPath)
end

local function lastEvent()
  local calls = fake.callsTo(entityLink, "EntityClientEvent")
  return calls[#calls] and calls[#calls].args[1]:ToString()
end

local function command(name)
  fake.customEvents.EntityServerCommand(fake.param(entityLink), fake.param(fake.name(name)),
    fake.param(location(1, 0, 0)), fake.param(nil))
end

-- Five host ticks a second, from `from` to `to` seconds
local function runSeconds(from, to)
  for tenths = from * 10, to * 10, 2 do
    fake.now = tenths / 10
    fake.runLoops(200)
  end
end

fake.runLoops(1000)
command("Volunteer")
gameManager.Monster = squid
fake.runLoops(1000)
fake.runLoops(1000)
fake.runFrames()
assert(entityController.Pawn == squid and squid.InVent, "the volunteer takes the squid, in its lair")

-- Before the crew holds the weapon, the vents are the squid's for as long as it likes
runSeconds(0, 60)
assert(entityLink.VentTime == 1, "no vent time runs down before the hunt")
assert(lastEvent() ~= "ForcedOut")

-- A crew member grabs the special weapon: the hunt begins, and the lair lets the squid go
local grab = fake.hooks[game.paths.weaponClass .. ":BPI_Weapon_SetGrabbed"]
grab(fake.param(weapon))
squid.InVent = false
squid.location = location(0, 900, 0)
runSeconds(60, 60)
assert(squid.location.X == 0 and not squid.InVent, "the lair no longer holds the squid in the ducts")
squid.InVent = true
squid.location = location(6050, 0, 400)
runSeconds(60.2, 70)
assert(math.abs(entityLink.VentTime - 0.5) < 0.02, "ten seconds in the vents use half the vent time")

-- Regression (playtest 6): a human entity could hide in the vents for good. Once the time runs out the squid is forced
-- out; with no shaft in reach, it's taken to the nearest one on its floor first and drops out of that
grab(fake.param(weapon))
runSeconds(70, 80.2)
assert(lastEvent() == "ForcedOut", "the squid is told its vent time is up")
fake.runFrames()
local drops = fake.callsTo(squid, "BPI_Monster_AttackFromVent")
assert(#drops == 1 and drops[1].args[1] == farVent, "it drops out of the nearest shaft")
assert(squid.location.X == farVent.Point1Component:K2_GetComponentLocation().X, "from beside that shaft's top")

-- Out of the vents, they stay shut until the time has refilled halfway: ten seconds back, at one for every six
squid.InVent = false
squid.location = location(300, 0, 0)
runSeconds(80.4, 100)
command("Mobility")
assert(lastEvent() == "Denied.VentsShut", "the vents won't take the squid back yet")
assert(#fake.callsTo(squid, "BPI_Monster_JumpToVent") == 0)
runSeconds(100.2, 141)
assert(lastEvent() == "VentsReopened", "the vents open again once half the time is back")
command("Mobility")
local climbs = fake.callsTo(squid, "BPI_Monster_JumpToVent")
assert(#climbs == 1 and climbs[1].args[1] == nearVent, "and the squid can climb in")

-- The hunted squid is loud: every 12 seconds it cries out, near it and far from it, so the crew can follow it
local cries = fake.callsTo(squid, "BPI_Monster_PlayVoiceAudio")
assert(#cries >= 6 and #cries <= 8 and cries[1].args[1] == roarCue and cries[1].args[6] == true,
  "the squid's roar plays on every machine, every 12 seconds of the hunt")
assert(#fake.callsTo(squid, "PlayVoiceFar(Multi)") == #cries, "with its far call for the crew well away")

-- Should the forced drop not get the squid out (a spot it can't reach), it's moved to the power room 10 seconds later
squid.InVent = true
squid.location = location(6050, 0, 400)
runSeconds(141.2, 162)
assert(lastEvent() == "ForcedOut")
assert(not squid.InVent and squid.location.X == 7704 - 150 and squid.location.Z == 1100 + 60,
  "the stuck squid stands on the floor in front of the power screen")

-- Playtest 9: knocked down by the crew and burnt, the squid got up with its vent time as it was. Getting back up, it
-- has the whole of it back, and the vents open to it again: its chance to run
squid.InVent = false
squid.location = location(300, 0, 0)
runSeconds(162.2, 170)
assert(entityLink.VentTime < 1, "some vent time was used")
squid.IsOnGround = true
runSeconds(170.2, 175)
squid.IsOnGround = false
runSeconds(175.2, 175.4)
assert(entityLink.VentTime == 1 and lastEvent() == "BackUp", "back up, the vent time is full again")
command("Mobility")
assert(lastEvent() ~= "Denied.VentsShut", "and the vents take the squid")

-- #12: a stun the crew can repeat every few seconds (Mike's weakness) doesn't refill the vents each time: getting back
-- up refills them at most once a minute
squid.InVent = true
runSeconds(175.6, 180)
squid.InVent = false
squid.IsOnGround = true
runSeconds(180.2, 181)
squid.IsOnGround = false
runSeconds(181.2, 181.4)
assert(entityLink.VentTime < 1 and lastEvent() ~= "BackUp", "back up again so soon, no second refill")
squid.InVent = true
runSeconds(181.6, 183)
squid.InVent = false
squid.IsOnGround = true
runSeconds(175.2 + 60, 175.2 + 61)
squid.IsOnGround = false
runSeconds(175.2 + 61.2, 175.2 + 61.4)
assert(entityLink.VentTime == 1 and lastEvent() == "BackUp", "a minute on, getting up refills them again")

print("hunt test passed")
