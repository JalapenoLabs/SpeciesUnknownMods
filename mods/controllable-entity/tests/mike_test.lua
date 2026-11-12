-- Copyright © 2026 Jalapeno Labs

-- Playing Mike (BP_Monster_Michel), on the host: the host picks him, the mission spawns him, and his moves are his
-- own: the swipe, the dodge aside (never in the vents), and the ultimate's grab, which repeats his own grab check (a
-- shield in the way refuses it, unpunched) and is ruled by the kill meter through his GrabPlayerVent ( Multi), hooked
-- under its spaced name. His health bar is his one pool, clamped when it refills past full.
-- Run from the repository root: lua mods/controllable-entity/tests/mike_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()

local game = require("entity.game")
local kits = require("entity.kits")
local mikeKit = kits.byId.Mike

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modAssets)
local breakMontage = fake.object("AnimMontage")
fake.objects[mikeKit.killGrab.breakMontage] = breakMontage
-- The navigation finds floor wherever it is asked, at height 0
fake.objects[game.paths.navigation] = fake.object("NavigationSystemV1", nil, {
  K2_ProjectPointToNavigation = function(_, _, spot, out)
    out.X, out.Y, out.Z = spot.X, spot.Y, 0
    return true
  end,
})
local gameInstance = fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0 })

local function playerState(lobbyId, name)
  return fake.object("BP_MyPlayerState_C", nil, {
    BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = lobbyId end,
    GetPlayerName = function() return fake.name(name) end,
  })
end
local hostState, crewState = playerState(0, "Host"), playerState(1, "Crew")

local function controller(isLocal, state)
  local object = fake.object("BP_MyPlayerController_C", { PlayerState = state, Pawn = fake.invalid() }, {
    IsLocalController = function() return isLocal end,
    IsPlayerController = function() return true end,
    GetControlRotation = function() return { Pitch = 0, Yaw = 0, Roll = 0 } end,
  }, { "PlayerController" })
  object.Possess = function(self, pawn)
    self.Pawn = pawn
    pawn.Controller = self
  end
  fake.giveView(object)
  return object
end
local hostController = controller(true, hostState)
local crewController = controller(false, crewState)

local links = {}
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local link = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    link.SetOwner = function(self, owner)
      self.Owner = owner
      links[owner] = self
    end
    return link
  end,
})
local crewList = fake.array({ hostState, crewState })
fake.object("BP_MyGameState_C", { ["In Game Player State "] = crewList }, nil, { "GameStateBase" })
fake.object("BP_LobbyGameMode_C")

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")
local abilities = require("entity.abilities")
local takeover = require("entity.takeover")

local function command(name, aim)
  fake.customEvents.EntityServerCommand(fake.param(links[crewController]), fake.param(fake.name(name)),
    fake.param(aim or { X = 1, Y = 0, Z = 0 }), fake.param(nil))
end
local function lastEvent()
  local events = fake.callsTo(links[crewController], "EntityClientEvent")
  return events[#events] and events[#events].args[1]:ToString()
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The lobby: the host picks Mike, and the crew player to play him
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.runLoops(1000)
takeover.chooseEntity("Mike")
takeover.choosePlayer("lobby:1")
fake.runLoops(1000)
assert(gameInstance.spawnForceSessionMonster == 3, "picking Mike forces his MonsterList value")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The mission
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.instances.BP_LobbyGameMode_C = nil
fake.object("BP_PlayableGameMode_C")
local aiController = fake.object("BP_Basic_AI_Controller_C", nil, { IsPlayerController = function() return false end })
local mikeRotation = { Pitch = 0, Yaw = 45, Roll = 0 }
local mike = fake.object("BP_Monster_Michel_C", {
  Controller = aiController,
  InVent = false,
  IsGrabPlayer = false,
  -- His one pool, and his stun (his weakness)
  Health = 350,
  MaxHealth = 350,
  Electrocuted = false,
  CharacterMovement = fake.object("CharacterMovementComponent", { MaxWalkSpeed = 0, MaxWalkSpeedCrouched = 0 }),
  CapsuleComponent = fake.object("CapsuleComponent", nil, { GetScaledCapsuleHalfHeight = function() return 90 end }),
}, {
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 90 } end,
  K2_GetActorRotation = function() return mikeRotation end,
  GetVelocity = function() return { X = 0, Y = 0, Z = 0 } end,
  BPI_Monster_GetSpeedByType = function(_, speedType, out) out.Speed = 580 + speedType end,
})
-- A shield between him and the crew member, or not: his own check traces for one
local shieldUp = false
mike.CheckShieldBeforeTarget = function(self, target, haveShield)
  table.insert(fake.calls, { object = self, method = "CheckShieldBeforeTarget", args = { target } })
  haveShield.HaveShield = shieldUp
end
-- His grab runs the hooks on it, as the game's does when Lua calls it
mike["GrabPlayerVent ( Multi)"] = function(self, target)
  table.insert(fake.calls, { object = self, method = "GrabPlayerVent ( Multi)", args = { target } })
  fake.hooks[mikeKit.classPath .. ":GrabPlayerVent ( Multi)"](fake.param(self), fake.param(target))
end
fake.object("BP_GameManager_C", { Monster = mike })

local crewBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") }, {
  K2_GetActorLocation = function() return { X = 200, Y = 0, Z = 90 } end,
  BPI_Human_IsDead = function(_, out) out.IsDead = false end,
  BPI_Human_CanBeGrabbed = function(_, _, out) out.True = true end,
})
local entityBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })
entityBody.destroyed = false
crewController.Pawn = entityBody
hostController.Pawn = crewBody

fake.loadClass(mikeKit.classPath)
fake.runLoops()
assert(crewController.Pawn == mike, "the picked player drives Mike")
assert(fake.hooks[mikeKit.classPath .. ":GrabPlayerVent ( Multi)"], "his grab is hooked under its spaced name")
-- The entity's own body is gone; only the crew member's is left to find
entityBody.destroyed = true

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- His moves
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The swipe: the AI's own attack on the crew member ahead; at nobody, his swipe at the air
command("Primary")
assert(#fake.callsTo(mike, "BPI_BasicMonster_SetSimpleAttack") == 1, "the swipe lands on the crew member ahead")
assert(lastEvent() == "Cooldown.Primary", "and starts its cooldown")
local swing = fake.object("AnimMontage")
fake.objects[mikeKit.swingMontage] = swing
fake.now = 5
command("Primary", { X = -1, Y = 0, Z = 0 })
local swings = fake.callsTo(mike, "AttackSimpleAnim (Clients)")
assert(#swings == 1 and swings[1].args[1] == swing, "a swipe at nobody swings his own swipe")

-- The dodge: his own sidestep to the floor at his right, facing the aim; never in the vents
fake.now = 10
command("Secondary")
local dodges = fake.callsTo(mike, "BPI_Monster_SetDodging")
assert(#dodges == 1, "RMB dodges")
local landing = dodges[1].args[1].Translation
assert(landing.X == 0 and landing.Y == mikeKit.moves.Secondary.distance and landing.Z == 90,
  "to the floor at his right, his capsule's height above it")
local turns = fake.callsTo(mike, "K2_SetActorRotation")
assert(turns[#turns].args[1].Yaw == 0, "turned to the aim first, so his dodge plays to the right side")
mike.InVent = true
fake.now = 20
command("Secondary")
assert(lastEvent() == "Denied.DodgeInVent", "no dodging in the vents")
mike.InVent = false

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The kill
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- A grab the meter doesn't allow (his swipe at a crouched crew member) is broken off with his front hit
local grabHook = fake.hooks[mikeKit.classPath .. ":GrabPlayerVent ( Multi)"]
grabHook(fake.param(mike), fake.param(crewBody))
assert(lastEvent() == "Denied.UltimateNotReady")
fake.runFrames()
local knockbacks = fake.callsTo(mike, "KnockBack (Clients)")
assert(#knockbacks == 1 and knockbacks[1].args[1] == breakMontage, "an unarmed grab is broken off")

-- The ultimate needs a full meter
command("Ultimate")
assert(lastEvent() == "Denied.UltimateNotReady", "the ultimate needs a full meter")

-- A shield in the way refuses the grab, and the meter stays full. It deals no damage: the ultimate plays no attack,
-- and a refusal starts no cooldown, so a punch here would shred a shield as fast as E is pressed
abilities.meter().value = 1
shieldUp = true
fake.now = 30
command("Ultimate")
assert(lastEvent() == "Denied.Shielded", "a shield refuses the grab")
assert(#fake.callsTo(mike, "BPI_BasicMonster_SetHitDamageShield") == 0, "without hurting the shield")
assert(#fake.callsTo(mike, "GrabPlayerVent ( Multi)") == 0, "and nobody is grabbed")
assert(abilities.meter().value == 1 and not abilities.meter():isArmed(fake.now), "the kill stands down, unspent")

-- Without a shield, he turns to them and grabs at once, and the armed meter lets the grab kill
shieldUp = false
fake.now = 40
command("Ultimate")
local grabs = fake.callsTo(mike, "GrabPlayerVent ( Multi)")
assert(#grabs == 1 and grabs[1].args[1] == crewBody, "the ultimate grabs the crew member ahead")
assert(mike.LastAttackedTarget == crewBody, "as his own check sets them first")
assert(lastEvent() == "Cooldown.Ultimate", "the grab goes through")
local events = fake.callsTo(links[crewController], "EntityClientEvent")
local sawKill = false
for _, event in ipairs(events) do
  sawKill = sawKill or event.args[1]:ToString() == "KillStarted"
end
assert(sawKill and abilities.meter().value == 0, "the grab kills and spends the meter")
assert(#fake.callsTo(mike, "KnockBack (Clients)") == 1, "and isn't broken off")

-- Nobody close enough: refused, and the kill stands down
abilities.meter().value = 1
fake.now = 50
command("Ultimate", { X = -1, Y = 0, Z = 0 })
assert(lastEvent() == "Denied.NoTarget" and not abilities.meter():isArmed(fake.now), "no grab at nobody")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- His health
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local link = links[crewController]
mike.Health = 175
fake.runLoops(200)
assert(link.Health == 0.5 and link.Downed == false, "his one pool, standing")
mike.Electrocuted = true
fake.runLoops(200)
assert(link.Downed == true, "stunned, he is down: his head is open to the crew's fire")
-- After his second face breaks, his health refills to one and a half times its maximum
mike.Health, mike.Electrocuted = 525, false
fake.runLoops(200)
assert(link.Health == 1, "an overfull pool shows full")

print("mike test passed")
