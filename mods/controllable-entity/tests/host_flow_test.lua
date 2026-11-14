-- Copyright © 2026 Jalapeno Labs

-- Runs the mod's real scripts as the host, against fake game objects, through a whole round: lobby, volunteering,
-- mission start, takeover, crew exclusion, commands, the grab rule, frenzy, pings and the meter.
-- Run from the repository root: lua mods/controllable-entity/tests/host_flow_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
math.randomseed(1)

local game = require("entity.game")
local kits = require("entity.kits")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- The lobby
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modAssets)
fake.objects[kits.byId.Squid.killGrab.breakMontage] = fake.object("AnimMontage")
fake.objects[kits.byId.Squid.killGrab.brokenGrabHit.damageType] = fake.object("DamageType_Punch_C")

local gameInstance = fake.object("BP_MyGameInstance_C", { spawnForceSessionMonster = 0, Contract = {} })

local function playerState(lobbyId, name)
  return fake.object("BP_MyPlayerState_C", nil, {
    BPI_PlayerState_GetLobbyPlayerID = function(_, out) out.ID = lobbyId end,
    GetPlayerName = function() return { ToString = function() return name end } end,
  })
end

local hostState, crewState = playerState(0, "Host"), playerState(1, "Crew")

local function controller(isLocal, state)
  local object = fake.object("BP_MyPlayerController_C", { PlayerState = state, Pawn = fake.invalid() }, {
    IsLocalController = function() return isLocal end,
    IsPlayerController = function() return true end,
    K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
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

local spawnedLinks = {}
fake.world = fake.object("World", nil, {
  SpawnActor = function()
    local link = fake.object("BP_EntityLink_C", { Owner = fake.invalid(), Meter = 0, Frenzy = false })
    link.SetOwner = function(self, owner) self.Owner = owner end
    table.insert(spawnedLinks, link)
    return link
  end,
})

local crewList = fake.array({ hostState })
local gameState = fake.object("BP_MyGameState_C", {
  Contract = { ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Extraction },
  ["In Game Player State "] = crewList,
}, nil, { "GameStateBase" })

dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Steps
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function linkOf(controllerObject)
  for _, link in ipairs(spawnedLinks) do
    if link.Owner == controllerObject then
      return link
    end
  end
  error("no link for controller")
end

local function command(controllerObject, name, aim)
  fake.customEvents.EntityServerCommand(fake.param(linkOf(controllerObject)), fake.param(fake.name(name)),
    fake.param(aim or { X = 1, Y = 0, Z = 0 }), fake.param(nil))
end

local function lastEvent(controllerObject)
  local events = fake.callsTo(linkOf(controllerObject), "EntityClientEvent")
  return events[#events] and events[#events].args[1]:ToString()
end

fake.runLoops()
assert(#spawnedLinks == 2, "every player gets a link")
fake.runLoops()
assert(#spawnedLinks == 2, "links are spawned once")

command(crewController, "Volunteer")
assert(kits.byMonsterType[gameInstance.spawnForceSessionMonster] ~= nil, "volunteering forces a playable entity")
assert(lastEvent(crewController) == "Volunteered")
assert(#fake.callsTo(linkOf(hostController), "EntityClientEvent") == 0, "nobody else hears about it")

command(hostController, "Volunteer")
assert(lastEvent(hostController) == "VolunteerTaken", "only one entity")

-- The mission: the squid spawns with its AI, the crew get bodies and join the crew list.
fake.object("BP_PlayableGameMode_C")
local aiController = fake.object("BP_Basic_AI_Controller_C", nil, { IsPlayerController = function() return false end })
local squid = fake.object("BP_Monster_Poulpi_C", {
  Controller = aiController, InVent = false, LastSpecialAttackPlayerLocation = nil,
}, {
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
  BPI_Monster_GetSpeedByType = function(_, speedType, out) out.Speed = 400 + speedType end,
})
fake.giveSquidState(squid)
fake.object("BP_GameManager_C", { Monster = squid })
local crewBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") }, {
  K2_GetActorLocation = function() return { X = 200, Y = 0, Z = 0 } end,
})
local entityBody = fake.object("BP_Character_C", { CharacterMovement = fake.object("CharacterMovementComponent") })
crewController.Pawn = entityBody
hostController.Pawn = crewBody
crewList.elements = { hostState, crewState }

-- The voice plugin's talkers, one per player (the crew player becomes the entity)
local function talker(playerState)
  return fake.object("OnsetVoipTalker", nil, { GetPlayerState = function() return playerState end })
end
local entityTalker, hostTalker = talker(crewState), talker(hostState)
fake.object("OnsetVoipWorldSubsystem", nil, {
  GetVoipTalker = function(_, playerState) return playerState == crewState and entityTalker or hostTalker end,
})

for _, classPath in ipairs({
  kits.byId.Squid.classPath, game.paths.gameStateClass, game.paths.weaponClass, game.paths.characterClass,
}) do
  fake.loadClass(classPath)
end

fake.runLoops()
assert(crewController.Pawn == squid, "the volunteer drives the squid")
assert(aiController.destroyed, "the squid's AI is removed")
assert(entityBody.destroyed, "with other crew aboard, the entity player's crew body is removed")
local speedCalls = fake.callsTo(squid, "BPI_Monster_SetSpeed")
assert(speedCalls[1].args[1] == 401, "combat speed comes from the out parameter")
local config = require("entity.config")
assert(math.abs(squid.CharacterMovement.MaxWalkSpeedCrouched - 401 / 2 * config.movement.ventSpeedMultiplier) < 1e-6,
  "the squid is faster in the vents than the game's crouched speed")
assert(lastEvent(crewController) == "BecameEntity")

fake.runLoops()
local exclusions = fake.callsTo(gameState, "UpdateInGamePlayers")
assert(#exclusions >= 1 and exclusions[1].args[1] == crewState and exclusions[1].args[2] == false,
  "the entity is taken out of the crew list")

-- Playtest 6: the entity is silent to everyone and off the crew's radio, and stays so when the game sets them again
local mutes = fake.callsTo(entityTalker, "SetMutedOnVoiceChannel")
assert(#mutes == 2 and mutes[1].args[1] == true and mutes[2].args[1] == true, "the entity is muted on both channels")
local channels = fake.callsTo(entityTalker, "SetVoiceChannel")
assert(#channels == 1 and channels[1].args[1] == 1 and channels[1].args[2] == false, "and taken off the radio")
local talkerPath = "/Script/OnsetVoip.OnsetVoipTalker:"
local muted = fake.param(false)
fake.hooks[talkerPath .. "SetMutedOnVoiceChannel"](fake.param(entityTalker), muted, fake.param(0))
assert(muted:get() == true, "the game can't unmute the entity")
local crewMuted = fake.param(false)
fake.hooks[talkerPath .. "SetMutedOnVoiceChannel"](fake.param(hostTalker), crewMuted, fake.param(0))
assert(crewMuted:get() == false, "the crew's own mute settings are theirs")
local rejoins = fake.param(true)
fake.hooks[talkerPath .. "SetVoiceChannel"](fake.param(entityTalker), fake.param(1), rejoins)
assert(rejoins:get() == false, "nor put the entity back on the radio")
local proximity = fake.param(true)
fake.hooks[talkerPath .. "SetVoiceChannel"](fake.param(entityTalker), fake.param(0), proximity)
assert(proximity:get() == true, "the entity stays in the proximity channel, to hear the crew nearby")

-- Commands
command(crewController, "Primary", { X = 1, Y = 0, Z = 0 })
assert(#fake.callsTo(squid, "BPI_BasicMonster_SetSimpleAttack") == 1, "attack hits the crew member ahead")
local eventsBeforeCooldown = #fake.callsTo(linkOf(crewController), "EntityClientEvent")
command(crewController, "Primary", { X = 1, Y = 0, Z = 0 })
assert(#fake.callsTo(squid, "BPI_BasicMonster_SetSimpleAttack") == 1, "attacks respect the cooldown")
-- Playtest 9: "Not yet" on every early press was noise; the move's bar already shows it recharging
assert(#fake.callsTo(linkOf(crewController), "EntityClientEvent") == eventsBeforeCooldown, "and say nothing")
command(hostController, "Primary")
assert(#fake.callsTo(squid, "BPI_BasicMonster_SetSimpleAttack") == 1, "only the entity commands the squid")

-- Playtest 7: the 1, 2 and 3 keys cry out, on every machine, each with its own cooldown
local roarCue = fake.object("SoundCue")
fake.objects[kits.byId.Squid.cries.Roar] = roarCue
command(crewController, "Roar")
local roars = fake.callsTo(squid, "BPI_Monster_PlayVoiceAudio")
assert(#roars == 1 and roars[1].args[1] == roarCue and roars[1].args[6] == true, "the roar plays for everyone")
assert(roars[1].args[4] == true, "cutting off whatever the squid was saying")
command(crewController, "Roar")
assert(#fake.callsTo(squid, "BPI_Monster_PlayVoiceAudio") == 1, "and waits its cooldown")

-- Regression (playtest 6): with nobody in reach the lash was refused; the squid swings at the air instead
local swingMontage = fake.object("AnimMontage")
fake.objects[kits.byId.Squid.swingMontage] = swingMontage
fake.now = 5
command(crewController, "Primary", { X = -1, Y = 0, Z = 0 })
local swings = fake.callsTo(squid, "AttackSimpleAnim (Clients)")
assert(#swings == 1 and swings[1].args[1] == swingMontage and swings[1].args[3] == nil, "a lash at nobody still swings")
assert(#fake.callsTo(squid, "BPI_BasicMonster_SetSimpleAttack") == 1, "without picking a target")
fake.now = 0

command(crewController, "Ultimate")
assert(lastEvent(crewController) == "Denied.UltimateNotReady", "the ultimate needs a full meter")

-- A grab without the ultimate is broken off
local grabHook = fake.hooks[kits.byId.Squid.classPath .. ":GrabHeadPlayer"]
grabHook(fake.param(squid), fake.param(crewBody))
assert(lastEvent(crewController) == "Denied.UltimateNotReady")
assert(#fake.callsTo(squid, "KnockBack (Clients)") == 0, "the knockback waits a frame for the grab to finish")
fake.runFrames()
local knockbacks = fake.callsTo(squid, "KnockBack (Clients)")
assert(#knockbacks == 1 and knockbacks[1].args[1] == fake.objects[kits.byId.Squid.killGrab.breakMontage],
  "an unarmed grab is broken off with the grab-interrupted knockback")
-- Playtest 9: the leap bounced off a crew member for nothing. A broken grab lands as a lash would, through the squid's
-- own sphere attack, before the knockback
local sphereAttacks = fake.callsTo(squid, "BPI_BasicMonster_BasicSphereAttackDamage")
assert(#sphereAttacks == 1 and sphereAttacks[1].args[4] == kits.byId.Squid.killGrab.brokenGrabHit.damage
  and sphereAttacks[1].args[5] == fake.objects[kits.byId.Squid.killGrab.brokenGrabHit.damageType]
  and sphereAttacks[1].args[6] == true, "the broken grab lands a lash's hit, forced past the attack's own gate")
local hitBeforeKnockback = false
for _, call in ipairs(fake.calls) do
  if call.object == squid and call.method == "KnockBack (Clients)" then
    break
  end
  hitBeforeKnockback = hitBeforeKnockback
    or (call.object == squid and call.method == "BPI_BasicMonster_BasicSphereAttackDamage")
end
assert(hitBeforeKnockback, "while it still holds them")

-- Playtest 9: the meter filled far too fast on time alone. A hit the entity lands on a crew member charges it, once
-- per crew member a second however many times one swing hits; another monster's hit doesn't
local abilities = require("entity.abilities")
abilities.meter().value = 0
local crewHit = fake.hooks[game.paths.characterClass .. ":HitDamageFromMonster"]
assert(crewHit, "a crew member's hit from a monster is hooked")
local function hitCrew(causer)
  crewHit(fake.param(crewBody), fake.param({}), fake.param(40), fake.param(nil), fake.param(causer))
end
fake.now = 5
hitCrew(squid)
assert(math.abs(abilities.meter().value - config.meter.hitCharge) < 1e-9, "a landed hit charges the meter")
hitCrew(squid)
assert(math.abs(abilities.meter().value - config.meter.hitCharge) < 1e-9, "the same swing's next tick doesn't")
fake.now = 5 + config.meter.hitChargeSeconds
hitCrew(fake.object("BP_Monster_Poulpi_C"))
assert(math.abs(abilities.meter().value - config.meter.hitCharge) < 1e-9, "another monster's hit doesn't")
hitCrew(squid)
assert(math.abs(abilities.meter().value - 2 * config.meter.hitCharge) < 1e-9, "the next swing does")
fake.now = 0

-- A full meter arms the ultimate, which leaps and lets the grab kill
abilities.meter().value = 1
fake.now = 10
command(crewController, "Ultimate", { X = 0, Y = 1, Z = 0 })
assert(squid.LastSpecialAttackPlayerLocation.Y > 400, "the leap lands along the aim")
assert(#fake.callsTo(squid, "BPI_Monster_SetSpecialAttack") == 1)
grabHook(fake.param(squid), fake.param(crewBody))
assert(lastEvent(crewController) == "KillStarted")
assert(abilities.meter().value == 0, "the kill spends the meter")

-- Frenzy from the black box
fake.hooks[game.paths.gameStateClass .. ":BPI_GameState_SetGrabBlackBox"](fake.param(gameState))
assert(lastEvent(crewController) == "FrenzyStarted")
fake.now = 11
assert(abilities.meter():grabKills(fake.now), "frenzy kills without meter")

-- A gunshot nearby pings the entity
local weapon = fake.object("BP_LaserGun_C", { PawnOwner = crewBody, HearingLoudness = 1.0, HearingRange = 3000 })
fake.hooks[game.paths.weaponClass .. ":MakeNoiseAI"](fake.param(weapon))
local pings = fake.callsTo(linkOf(crewController), "EntityClientPing")
assert(#pings == 1 and pings[1].args[3]:ToString() == "Gunshot", "the shot is heard")
assert(pings[1].args[1].X == 200 and pings[1].args[4] == crewBody,
  "exactly where the shooter is, with the shooter, whose body the entity's machine shows through walls (#18)")

-- Playtest 9: lost in the vents with nothing heard, the entity had nothing to go on. After a quiet spell it senses
-- every living crew member, roughly, and again after every quiet spell
fake.now = 11 + config.senses.senseSeconds - 1
fake.runLoops(200)
assert(#fake.callsTo(linkOf(crewController), "EntityClientPing") == 1, "not before the quiet has lasted")
fake.now = 11 + config.senses.senseSeconds + 0.2
fake.runLoops(200)
pings = fake.callsTo(linkOf(crewController), "EntityClientPing")
assert(#pings == 2 and pings[2].args[3]:ToString() == "Sense", "the entity senses the crew member")
local sensed = pings[2].args[1]
assert(math.abs(sensed.X - 200) <= config.senses.senseBlurMax, "roughly where they are")
fake.runLoops(200)
assert(#fake.callsTo(linkOf(crewController), "EntityClientPing") == 2, "once per quiet spell")
crewBody.IsDead = true
fake.now = fake.now + config.senses.senseSeconds + 0.2
fake.runLoops(200)
assert(#fake.callsTo(linkOf(crewController), "EntityClientPing") == 2, "and never a dead one")
crewBody.IsDead = false

-- The meter state reaches the entity's link
fake.runLoops(200)
assert(linkOf(crewController).Frenzy == true, "frenzy replicates through the link")

-- So does the health pool the squid is on, which the game doesn't replicate (playtest 6): the stagger pool while it
-- stands, its real health once it's down
squid.HealthTemporal, squid.MaxHealthTemporal = 30, 60
squid.Health, squid.MaxHealth = 20, 100
fake.runLoops(200)
assert(linkOf(crewController).Health == 0.5 and linkOf(crewController).Downed == false, "standing: the stagger pool")
squid.IsOnGround = true
fake.runLoops(200)
assert(linkOf(crewController).Health == 0.2 and linkOf(crewController).Downed == true, "down: the real health")
-- Regression (playtest 9): a friend's lash while the squid was down cut its get-up short, and the game never got it up
-- again: on the host it lay there for good, dragged along, unable to vent. Down, it does nothing, as the AI's doesn't
local setSimpleAttacks = #fake.callsTo(squid, "BPI_BasicMonster_SetSimpleAttack")
fake.now = 50
command(crewController, "Primary", { X = 1, Y = 0, Z = 0 })
assert(lastEvent(crewController) == "Denied.Down", "a downed squid can't lash")
assert(#fake.callsTo(squid, "BPI_BasicMonster_SetSimpleAttack") == setSimpleAttacks, "and nothing is played")
squid.IsOnGround, squid.BasicOverrideAnim = false, true
command(crewController, "Mobility")
assert(lastEvent(crewController) == "Denied.Down", "nor vent while it gets up")
squid.BasicOverrideAnim = false

-- And if its get-up is cut short anyway, the host gets it up once it has lain unburnt with nothing playing for longer
-- than the game's own wait
squid.IsOnGround, squid.HealthTemporal = true, 0
fake.runLoops(33)
fake.now = 52
fake.runLoops(33)
assert(#fake.callsTo(squid, "GetUp (Multi)") == 0, "the game's own get-up gets its chance")
squid.HeatValue = 0.5
fake.now = 60
fake.runLoops(33)
assert(#fake.callsTo(squid, "GetUp (Multi)") == 0, "and a burning squid stays down, as the game keeps it")
squid.HeatValue = 0
fake.runLoops(33)
fake.now = 63.5
fake.runLoops(33)
assert(#fake.callsTo(squid, "GetUp (Multi)") == 1, "a squid stuck down is got up")
assert(squid.HealthTemporal == squid.MaxHealthTemporal, "with its stagger pool refilled, as the game's own get-up does")
-- Playtest 9: the squid healed too fast to fight. Its stagger pool's own refill, a little every host frame, is halved;
-- the game's full refills stay whole
squid.IsOnGround, squid.HealthTemporal = false, 30
fake.runLoops(33)
squid.HealthTemporal = 31
fake.runLoops(33)
assert(squid.HealthTemporal == 30.5, "half of the pool's own refill is taken back")
squid.HealthTemporal = squid.MaxHealthTemporal
fake.runLoops(33)
assert(squid.HealthTemporal == squid.MaxHealthTemporal, "a full refill stays whole")
squid.IsOnGround = false
assert(linkOf(crewController).Stamina == 1, "and the stamina, full before any sprint")

-- Sprinting: top speed while Shift is held, until the stamina runs out
fake.now = 100
fake.runLoops(200)
command(crewController, "SprintStart")
command(hostController, "SprintStart")
fake.now = 101
fake.runLoops(200)
assert(squid.CharacterMovement.MaxWalkSpeed == 404, "the entity sprints at the squid's top speed")
fake.now = 101 + config.movement.sprintSeconds
fake.runLoops(200)
assert(lastEvent(crewController) == "Sprint.Tired", "a full sprint runs out of breath")
assert(linkOf(crewController).Stamina == 0, "with the stamina on the entity's HUD spent")
assert(squid.CharacterMovement.MaxWalkSpeed == 401, "and the squid slows to combat speed")
-- Playtest 9: the leap kept the entity up with a fleeing crew member while nearly out of stamina. Out of breath, it
-- can't leap; rested, a leap costs a share of the stamina
local leapsBefore = #fake.callsTo(squid, "BPI_Monster_SetSpecialAttack")
command(crewController, "Secondary", { X = 0, Y = 1, Z = 0 })
assert(lastEvent(crewController) == "Denied.OutOfBreath", "no leap out of breath")
assert(#fake.callsTo(squid, "BPI_Monster_SetSpecialAttack") == leapsBefore, "the squid stays put")
fake.now = fake.now + config.movement.staminaRefillSeconds
fake.runLoops(200)
assert(lastEvent(crewController) == "Sprint.Rested", "catching its breath while Shift is still held")
fake.now = fake.now + 0.2
fake.runLoops(200)
assert(squid.CharacterMovement.MaxWalkSpeed == 404, "then it sprints again")
command(crewController, "SprintStop")
fake.now = fake.now + config.movement.staminaRefillSeconds
fake.runLoops(200)
command(crewController, "Secondary", { X = 0, Y = 1, Z = 0 })
assert(#fake.callsTo(squid, "BPI_Monster_SetSpecialAttack") == leapsBefore + 1, "rested, it leaps")
fake.runLoops(200)
assert(math.abs(linkOf(crewController).Stamina - (1 - kits.byId.Squid.moves.Secondary.staminaCost)) < 1e-9,
  "for a share of its stamina")

-- Playtest 9 (#14): the squid's last phase never told the crew. Back up after an eye breaks, the game sets it escaping:
-- the entity flees at its top speed, Shift or not, for a while, and the crew are told once, on a hunt contract
local monsterPath = "/Game/Blueprints/Monsters/BP_BaseMonster.BP_BaseMonster_C"
local squidPath = kits.byId.Squid.classPath
fake.loadClass(monsterPath)
local contractBeforeFlight = gameState.Contract
gameState.Contract = { ContractType_2_AD7B8E08435CF5A38556E7BA67C34760 = game.contractTypes.Elimination }
fake.now = fake.now + 1
fake.hooks[monsterPath .. ":BPI_Monster_SetEscaping"](fake.param(squid), fake.param(true), fake.param(true))
assert(lastEvent(crewController) == "Fleeing", "the entity is told to run")
assert(lastEvent(hostController) == "SpecimenFled", "the crew are told the specimen has fled")
fake.runLoops(200)
assert(squid.CharacterMovement.MaxWalkSpeed == 404 and linkOf(crewController).Stamina == 1,
  "fleeing, it runs at its top speed with a full sprint, Shift or not")
local fledTold = #fake.callsTo(linkOf(hostController), "EntityClientEvent")
fake.hooks[monsterPath .. ":BPI_Monster_SetEscaping"](fake.param(squid), fake.param(true), fake.param(true))
assert(#fake.callsTo(linkOf(hostController), "EntityClientEvent") == fledTold, "the crew are told once per monster")
fake.now = fake.now + config.flee.seconds
fake.runLoops(200)
assert(lastEvent(crewController) == "FleeEnded", "the flight runs out")
fake.runLoops(200)
assert(squid.CharacterMovement.MaxWalkSpeed == 401, "back to its combat speed")
-- The game's escape hangs on montages finishing on the host: an eye broken without one gets the game's ink get-up
fake.loadClass(squidPath)
fake.hooks[squidPath .. ":BreakEye (multi)"](fake.param(squid), fake.param(false))
fake.runLoops(200)
assert(#fake.callsTo(squid, "GetUpWithInk (multi)") == 0, "the game gets its own chance first")
fake.now = fake.now + config.flee.escapeWaitSeconds
fake.runLoops(200)
assert(#fake.callsTo(squid, "GetUpWithInk (multi)") == 1, "then the host gets it up the game's way, into its escape")
fake.runLoops(200)
assert(#fake.callsTo(squid, "GetUpWithInk (multi)") == 1, "once")
gameState.Contract = contractBeforeFlight

-- Playtest 9 (#19, #9): a door's alarm reaches the entity across the map, on every difficulty, with the door, for as
-- long as it sounds (each beat of it)
local doorPath = "/Game/Blueprints/Polar/Doors/BP_BigDoor_POLAR.BP_BigDoor_POLAR_C"
fake.loadClass(doorPath)
local farDoor = fake.object("BP_BigDoor_POLAR_C", nil, {
  K2_GetActorLocation = function() return { X = 90000, Y = 0, Z = 0 } end,
})
local pingsBefore = #fake.callsTo(linkOf(crewController), "EntityClientPing")
fake.hooks[doorPath .. ":LightSwitchOpenning"](fake.param(farDoor))
pings = fake.callsTo(linkOf(crewController), "EntityClientPing")
assert(#pings == pingsBefore + 1 and pings[#pings].args[3]:ToString() == "Alarm" and pings[#pings].args[4] == farDoor,
  "a door's alarm reaches the entity at any distance")
-- The door's own report to the AI, on the harder difficulties, is left to its alarm
fake.hooks[game.paths.gameStateClass .. ":BPI_GameState_ForceSound"](fake.param(gameState), fake.param(farDoor),
  fake.param({ X = 100, Y = 0, Z = 0 }), fake.param(0), fake.param(0))
assert(#fake.callsTo(linkOf(crewController), "EntityClientPing") == pingsBefore + 1, "and isn't told twice")

-- The engines: their start is told once (both start together), with a sound and a line, and their overload reaches
-- the entity at any distance every second while it builds, with the engine
fake.loadClass(game.paths.engineClass)
local function engine(x)
  return fake.object("BP_Engine_C", { EngineState = 1 }, {
    K2_GetActorLocation = function() return { X = x, Y = 0, Z = 0 } end,
  })
end
local engineA, engineB = engine(-90000), engine(-91000)
fake.hooks[game.paths.engineClass .. ":OnRep_EngineState"](fake.param(engineA))
fake.hooks[game.paths.engineClass .. ":OnRep_EngineState"](fake.param(engineB))
local startsTold = 0
for _, event in ipairs(fake.callsTo(linkOf(crewController), "EntityClientEvent")) do
  if event.args[1]:ToString() == "EnginesStarted" then
    startsTold = startsTold + 1
  end
end
assert(startsTold == 1, "the engines' start is told once")
local function overloadPings()
  local found = {}
  for _, ping in ipairs(fake.callsTo(linkOf(crewController), "EntityClientPing")) do
    if ping.args[3]:ToString() == "Overload" then
      table.insert(found, ping.args[4])
    end
  end
  return found
end
fake.now = fake.now + config.areas.rescanSeconds
fake.runLoops(200)
local overloads = overloadPings()
assert(#overloads == 2 and overloads[1] ~= overloads[2], "each overloading engine pings, across the map")
fake.runLoops(200)
assert(#overloadPings() == 2, "once a second")
engineA.EngineState, engineB.EngineState = 3, 3
fake.now = fake.now + config.senses.overloadPingSeconds
fake.runLoops(200)
assert(#overloadPings() == 2, "and no more once both are critical")

-- Regression (playtest 9): a dying squid lost its movement component a moment before the takeover noticed it was
-- gone, and the host's speed tripped over it every tick. Its systems leave it be meanwhile
local movementBeforeDeath = squid.CharacterMovement
-- As UE4SS gives it: a component that's gone answers each field with an object, never a number, and keeps no writes
squid.CharacterMovement = setmetatable({}, {
  __index = function(_, key)
    if key == "IsValid" then
      return function() return false end
    end
    return fake.invalid()
  end,
  __newindex = function() end,
})
fake.runLoops(200)
fake.runLoops(33)
squid.CharacterMovement = movementBeforeDeath

-- Playtest 6: once the entity has lost, its player talks to everyone again ("You kill it and then it can talk")
squid.destroyed = true
fake.runLoops()
fake.runLoops()
assert(lastEvent(crewController) == "Lost", "the crew killed the entity")
local released = fake.callsTo(entityTalker, "SetMutedOnVoiceChannel")
assert(released[#released].args[1] == false and released[#released - 1].args[1] == false,
  "the lost entity is unmuted on both channels")
local rejoined = fake.callsTo(entityTalker, "SetVoiceChannel")
assert(rejoined[#rejoined].args[1] == 1 and rejoined[#rejoined].args[2] == true, "and back on the crew's radio")
local unmuted = fake.param(false)
fake.hooks[talkerPath .. "SetMutedOnVoiceChannel"](fake.param(entityTalker), unmuted, fake.param(0))
assert(unmuted:get() == false, "and the game's own mute settings are theirs again")

-- Playtest 9: the game's capture flow replaces a captured specimen with a fresh one, which went straight back to the
-- same player. Once the entity has lost, its player is out for the rest of the mission: a monster the game spawns
-- afterwards stays the game's own AI
local freshAi = fake.object("BP_Basic_AI_Controller_C", nil, { IsPlayerController = function() return false end })
local freshSquid = fake.object("BP_Monster_Poulpi_C", { Controller = freshAi, InVent = false }, {
  K2_GetActorLocation = function() return { X = 0, Y = 0, Z = 0 } end,
  BPI_Monster_GetSpeedByType = function(_, speedType, out) out.Speed = 400 + speedType end,
})
fake.giveSquidState(freshSquid)
FindFirstOf("BP_GameManager_C").Monster = freshSquid
fake.runLoops()
fake.runLoops()
assert(freshSquid.Controller == freshAi, "a specimen the game spawns after the loss keeps its AI")
assert(lastEvent(crewController) == "Lost", "and the lost player doesn't become it")
freshSquid.destroyed = true

-- Regression (playtest 9): a hot reload of the mod forgot the links but left them in the world, and the host spawned a
-- second one per player. It wrote the HUD's values to the new link while the entity's machine read the old one, whose
-- stamina and vent-time bars stayed frozen. After a reload, the links already in the world are taken back
local linksBeforeReload = #spawnedLinks
for name in pairs(package.loaded) do
  if name:match("^entity%.") then
    package.loaded[name] = nil
  end
end
fake.loops, fake.customEvents, fake.hooks = {}, {}, {}
dofile("mods/controllable-entity/ControllableEntity/Scripts/main.lua")
fake.runLoops(1000)
fake.runLoops(1000)
assert(#spawnedLinks == linksBeforeReload, "no second link is spawned after a reload")
-- And a second link left by an earlier run is removed
local secondLink = fake.object("BP_EntityLink_C", { Owner = crewController })
fake.runLoops(1000)
assert(secondLink.destroyed and not linkOf(crewController).destroyed, "a player's second link is removed")

print("host flow test passed")
