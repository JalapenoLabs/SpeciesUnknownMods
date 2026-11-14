-- Copyright © 2026 Jalapeno Labs

-- Host side of becoming the entity: the host's choices (which entity, and who plays it: picker.lua), volunteering in
-- the lobby, forcing the chosen entity's monster as the mission's specimen, taking control of it when it spawns,
-- keeping the entity player out of the crew, and noticing when they lose.
--
-- Lua state outlives map travel, so the volunteer is remembered from the lobby into the mission; back in the lobby,
-- they're signed up no more, while the host's own choices hold for the session.

local game = require("entity.game")
local kits = require("entity.kits")
local lair = require("entity.lair")
local links = require("entity.links")
local moves = require("entity.moves")
local movement = require("entity.movement")

local takeover = {}

-- The host's choices for the session (picker.lua, playtest 8): the entity ("Random", a kit's id, or "AiOnly", when the
-- mission's monster stays the game's AI) and who plays it ("Random", or a player's key). Random rolls each mission.
takeover.choice = { entity = "Random", player = "Random" }
-- The kit Random rolled for the next mission, in the lobby among the playable kits that fit the contract; rolled again
-- for each mission.
local rolledKit = nil
-- Whether the host was told their pick is one the game wouldn't give this contract, so they're told once per pick.
local warnedUnfitPick = false
-- Who will be the entity when the host leaves it to chance, by the game's own lobby player id (stable across travel,
-- unlike the controller and player state objects, which are rebuilt on every map): a volunteer, or the player picked
-- at random this mission. The host's own pick of a player comes first (pickedController).
local volunteerKey = nil
-- True when volunteerKey came from the random pick rather than F8, which the random player can't back out of.
local chosenAtRandom = false
-- Whether a mission has been played since the lobby was last seen: back in the lobby, whoever was signed up for it
-- is signed up no more.
local hasPlayedMission = false
-- The entity in the current world: { key, controller, monster, kit, playerState, parkedBody, worldKey }, or nil.
local activeEntity = nil
-- The world the volunteer was last told their status in, so each new world tells them once.
local announcedWorldKey = nil

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Identity
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The game's lobby player id (BP_MyPlayerState's BPI_PlayerState_GetLobbyPlayerID, as the pause menu uses it). The
-- player name is the fallback for player states that aren't the game's own; two players could share a name.
local function playerKey(playerState)
  if not playerState or not playerState:IsValid() then
    return nil
  end

  local out = {}
  local ok = pcall(function()
    playerState:BPI_PlayerState_GetLobbyPlayerID(out)
  end)
  if ok and out.ID ~= nil and out.ID >= 0 then
    return "lobby:" .. tostring(out.ID)
  end

  game.log("No lobby id for a player state; identifying it by name")
  return "name:" .. playerState:GetPlayerName():ToString()
end


local function controllerForKey(key)
  for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
    if controller:IsValid() and playerKey(controller.PlayerState) == key then
      return controller
    end
  end
  return nil
end

function takeover.activeEntity()
  if not activeEntity or not activeEntity.monster:IsValid() then
    return nil
  end
  return activeEntity
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Players
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function playerControllers()
  return FindAllOf(game.classNames.playerController) or {}
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Entity mode and volunteering
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- BP_MyGameInstance.spawnForceSessionMonster: when set (not 0 or 1), BP_GameManager spawns that monster instead of
-- a random one. The game never sets it itself. Nil leaves the mission's own roll.
local function forceMonster(kit)
  local gameInstance = FindFirstOf(game.classNames.gameInstance)
  if not gameInstance or not gameInstance:IsValid() then
    game.log("No game instance; can't force the mission's monster")
    return
  end
  gameInstance.spawnForceSessionMonster = kit and kit.monsterType or 0
end

-- The player the host picked, while they're in the session; nil when the host leaves it to chance.
local function pickedController()
  if takeover.choice.player == "Random" then
    return nil
  end
  return controllerForKey(takeover.choice.player)
end

-- Whether the game itself would give a kit's monster the contract chosen at the lobby's terminal. Its roll never gives
-- the Terminator a contract the crew arrives at without their main weapon, nor the easiest difficulty
-- (BP_GameManager.Get Random). Before a contract is chosen, every kit fits.
local function fitsContract(kit)
  if not kit.needsCrewMainWeapons then
    return true
  end
  local gameInstance = FindFirstOf(game.classNames.gameInstance)
  if not gameInstance or not gameInstance:IsValid() then
    game.log("No game instance; can't tell whether the %s fits the contract", kit.displayName)
    return true
  end
  local contract = gameInstance.Contract
  if not contract[game.contractFields.valid] then
    return true
  end
  return contract[game.contractFields.primaryWeapons] == true and contract[game.contractFields.difficulty] ~= 0
end

-- Random's entity: rolled among the playable kits that fit the chosen contract, once per mission, and rolled again if
-- the host then chooses a contract it doesn't fit.
local function rollEntity()
  if rolledKit and fitsContract(rolledKit) then
    return rolledKit
  end
  local fitting = {}
  for _, kit in ipairs(kits.playable) do
    if fitsContract(kit) then
      table.insert(fitting, kit)
    end
  end
  rolledKit = fitting[math.random(#fitting)]
  return rolledKit
end

-- The host's own pick stands even on a contract the game wouldn't give its monster; they're told once, since the crew
-- may have no way to beat it.
local function warnIfUnfit(kit)
  local fits = fitsContract(kit)
  if not fits and not warnedUnfitPick then
    local host = game.localController()
    if host then
      links.sendEvent(host, "PickedUnfit")
    end
    game.log("The host's pick, the %s, isn't one the game gives this contract", kit.displayName)
  end
  warnedUnfitPick = not fits
end

-- Decides the next mission's specimen, from the lobby. The mission rolls its monster seconds after it loads, before
-- every player has even arrived, and places what belongs to it (the special weapon for its weakness) as it loads, so
-- the entity's monster is forced whenever the mission will have an entity: one the host picked, a volunteer, or a
-- random pick among two or more players. Playing alone, only a volunteer or the host's pick makes sense. Random rolls
-- among the playable kits rather than leaving a roll that may land on a monster no kit plays.
local function syncForcedMonster()
  local hasPlayer = pickedController() ~= nil or volunteerKey ~= nil or #playerControllers() >= 2
  if takeover.choice.entity == "AiOnly" or not hasPlayer then
    forceMonster(nil)
    return
  end
  if takeover.choice.entity == "Random" then
    forceMonster(rollEntity())
    return
  end
  local picked = kits.byId[takeover.choice.entity]
  warnIfUnfit(picked)
  forceMonster(picked)
end

local function forgetVolunteer()
  volunteerKey = nil
  chosenAtRandom = false
  announcedWorldKey = nil
end

-- Toggles the sender as the entity. Only the sender is told; the rest of the crew learns nothing until the mission.
local function onVolunteer(_, controller)
  -- The entity's own F8 is the solo power switch (lair.lua); it never signs the entity out mid-mission
  if takeover.isEntityController(controller) then
    return
  end
  if takeover.choice.entity == "AiOnly" then
    links.sendEvent(controller, "Denied.EntityModeOff")
    return
  end

  local key = playerKey(controller.PlayerState)
  if not key then
    game.log("Volunteer command from a controller without a player state")
    return
  end

  if volunteerKey == key and not chosenAtRandom then
    forgetVolunteer()
    syncForcedMonster()
    links.sendEvent(controller, "Unvolunteered")
    game.log("%s is no longer the entity", key)
    return
  end

  local picked = pickedController()
  local isPickedByHost = picked and picked:GetAddress() == controller:GetAddress()
  if volunteerKey ~= nil or (picked and not isPickedByHost) then
    links.sendEvent(controller, "VolunteerTaken")
    return
  end

  volunteerKey = key
  announcedWorldKey = game.currentWorldKey()
  syncForcedMonster()
  links.sendEvent(controller, "Volunteered")
  game.log("%s will be the entity next mission", key)
end

-- The host's F9 opens the picker on its own machine (picker.lua); anyone else's reaches here and is told it's the
-- host's.
local function onOpenPicker(_, controller)
  if not controller:IsLocalController() then
    links.sendEvent(controller, "Denied.HostOnly")
  end
end

-- The host picks the entity: Random, a kit's id, or AiOnly. AI only releases the volunteer, so the next mission is the
-- game's own; an entity already playing keeps playing until the mission ends.
function takeover.chooseEntity(choice)
  takeover.choice.entity = choice
  rolledKit = nil
  warnedUnfitPick = false
  if choice == "AiOnly" and volunteerKey then
    local volunteer = controllerForKey(volunteerKey)
    if volunteer then
      links.sendEvent(volunteer, "Unvolunteered")
    end
    forgetVolunteer()
  end
  if game.isLobby() then
    syncForcedMonster()
  end
  game.log("The host picked the entity: %s", choice)
end

-- The host picks who plays the entity: Random, or a player's key. The picked player is told (only they are); a
-- player the host picked before and no longer is goes back to the crew.
function takeover.choosePlayer(choice)
  local previous = pickedController()
  takeover.choice.player = choice
  local picked = pickedController()
  if previous and not (picked and picked:GetAddress() == previous:GetAddress()) then
    links.sendEvent(previous, "Unvolunteered")
  end
  if picked then
    links.sendEvent(picked, "PickedByHost")
  end
  if game.isLobby() then
    syncForcedMonster()
  end
  game.log("The host picked who plays the entity: %s", choice)
end

-- The session's players, for the host's picker: { key, name } each, in the order the game lists them.
function takeover.players()
  local players = {}
  for _, controller in ipairs(playerControllers()) do
    local key = controller:IsValid() and playerKey(controller.PlayerState)
    if key then
      table.insert(players, { key = key, name = controller.PlayerState:GetPlayerName():ToString() })
    end
  end
  return players
end

-- With no volunteer, a co-op mission's entity is a player picked at random once the monster is there to take.
local function pickAtRandom()
  local controllers = {}
  for _, controller in ipairs(playerControllers()) do
    if controller:IsValid() and playerKey(controller.PlayerState) then
      table.insert(controllers, controller)
    end
  end
  if #controllers < 2 then
    return nil
  end

  local chosen = controllers[math.random(#controllers)]
  volunteerKey = playerKey(chosen.PlayerState)
  chosenAtRandom = true
  game.log("%s was picked at random to be the entity", volunteerKey)
  return chosen
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Crew exclusion
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function crewList(gameState)
  return gameState["In Game Player State "]
end

local function crewContains(gameState, playerState)
  local found = false
  local address = playerState:GetAddress()
  crewList(gameState):ForEach(function(_, element)
    local member = element:get()
    if member:IsValid() and member:GetAddress() == address then
      found = true
      return true
    end
  end)
  return found
end

-- Removes the entity player from the crew list through the game's own function, so the change replicates and the
-- shuttle's screens update. Removing the last crew member makes the game call GameOver, so the entity waits until
-- someone else is aboard.
local function excludeFromCrew(entity)
  local gameState = FindFirstOf(game.classNames.gameState)
  if not gameState or not gameState:IsValid() or not crewContains(gameState, entity.playerState) then
    return
  end

  if #crewList(gameState) <= 1 then
    return
  end

  gameState:UpdateInGamePlayers(entity.playerState, false)
  game.log("Kept the entity out of the crew")
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Taking control
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- The mission's specimen, when it is the entity: the monster BP_GameManager spawned (its Monster property). Other
-- monsters of its class exist too, like the specimen on display in the lobby, and must never be taken over.
local function missionMonster()
  local gameManager = FindFirstOf(game.classNames.gameManager)
  if not gameManager or not gameManager:IsValid() then
    return nil
  end
  local monster = gameManager.Monster
  if not kits.forMonster(monster) then
    return nil
  end
  return monster
end

-- The entity player's crew body can't simply be destroyed: BP_MyGameState sends everyone back to the lobby when
-- its list of player bodies (ActualPlayersPawn) empties, and destroying a body takes it off that list. So the body is
-- parked first (hidden, without collision, frozen so it can't fall out of the map) and destroyed only once another
-- crew body exists. Alone in a mission (testing solo), it stays parked.
local function parkBody(body)
  body:SetActorHiddenInGame(true)
  body:SetActorEnableCollision(false)
  body.CharacterMovement:DisableMovement()
end

local function anotherCrewBodyExists(body)
  local bodyAddress = body:GetAddress()
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    if crewMember:IsValid() and crewMember:GetAddress() ~= bodyAddress then
      return true
    end
  end
  return false
end

local function releaseParkedBody(entity)
  local body = entity.parkedBody
  if not body or not body:IsValid() or not anotherCrewBodyExists(body) then
    return
  end
  body:K2_DestroyActor()
  entity.parkedBody = nil
  game.log("Removed the entity's parked crew body")
end

-- Runs one of an entity's own steps (its moves' begin or finish, moves.lua), if it has it. They call into the game by
-- names only research has seen, and one that fails must not stop the takeover or the loss half done.
local function runKitStep(entity, stepName)
  local step = moves.byKitId[entity.kit.id][stepName]
  if not step then
    return
  end
  local ok, failure = pcall(step, entity)
  if not ok then
    game.log("The %s's %s step failed: %s", entity.kit.displayName, stepName, tostring(failure))
  end
end

local function takeControl(controller, monster, worldKey)
  local crewBody = controller.Pawn

  -- The monster's AI controller would fight the player for it; it goes away for good
  local aiController = monster.Controller
  if aiController:IsValid() and not aiController:IsPlayerController() then
    aiController:UnPossess()
    aiController:K2_DestroyActor()
  end

  controller:Possess(monster)
  -- Possession moves the camera only when the camera manager follows the pawn on its own, which this game's doesn't:
  -- in the first playtest the view stayed in the hidden crew body. Set on the host, the view target replicates to
  -- the player's machine
  controller:SetViewTargetWithBlend(monster, 0, 0, 0, false)

  local parkedBody = nil
  if crewBody:IsValid() and crewBody:GetAddress() ~= monster:GetAddress() then
    parkBody(crewBody)
    parkedBody = crewBody
  end

  -- Combat speed suits a player better than the AI's patrol walk (movement.lua keeps it up to date from here on)
  movement.resetHost()
  movement.apply(monster, false)

  -- The AI's stuck check (BP_BaseMonster."Check If Stuck", every second) respawns a monster that hasn't moved for 20
  -- seconds, through BP_GameManager.InitMonster, which destroys it. A player lying in wait stands still for longer
  -- than that, and losing the monster would end their game
  monster.ShouldCheckIfStuck = false

  -- The AI may have left the monster turning at another rate (Mike's AI turns him by hand in the vents, through his
  -- CharacterMovement.RotationRate); the player's monster turns at its class's own
  local defaultMovement = monster:GetClass():GetCDO().CharacterMovement
  if defaultMovement and defaultMovement:IsValid() then
    local rate = defaultMovement.RotationRate
    monster.CharacterMovement.RotationRate = { Pitch = rate.Pitch, Yaw = rate.Yaw, Roll = rate.Roll }
  else
    game.log("No class default movement for %s; it keeps the turn rate its AI left",
      kits.forMonster(monster).displayName)
  end

  local spawnLocation = monster:K2_GetActorLocation()
  activeEntity = {
    key = playerKey(controller.PlayerState),
    controller = controller,
    monster = monster,
    kit = kits.forMonster(monster),
    playerState = controller.PlayerState,
    parkedBody = parkedBody,
    worldKey = worldKey,
    -- Where the game spawned the monster, before the lair moves it: somewhere it can stand (unstuck.lua)
    startLocation = { X = spawnLocation.X, Y = spawnLocation.Y, Z = spawnLocation.Z },
  }
  releaseParkedBody(activeEntity)
  links.sendEvent(controller, "BecameEntity")
  game.log("%s took control of the monster: %s", activeEntity.key, activeEntity.kit.displayName)
  runKitStep(activeEntity, "begin")
  lair.begin(activeEntity, moves.byKitId[activeEntity.kit.id])
end

-- A hot reload of the mod (UE4SS's Ctrl+R) forgets who the entity is, while the player still drives the monster. Their
-- controller is the proof: the monster's AI was destroyed at the takeover, so only the entity player can be driving it.
-- They're taken back as the entity where they are. The ducts' lair isn't rebuilt, so its leash is gone until the next
-- mission (rebuilding it would move the monster into a vent); one lying powered down is still held until the power is
-- on, or it would never wake.
local function adoptAfterReload(monster, worldKey)
  local controller = game.playerControllerOf(monster)
  if not controller then
    return false
  end
  volunteerKey = playerKey(controller.PlayerState)
  local location = monster:K2_GetActorLocation()
  activeEntity = {
    key = volunteerKey,
    controller = controller,
    monster = monster,
    kit = kits.forMonster(monster),
    playerState = controller.PlayerState,
    parkedBody = nil,
    worldKey = worldKey,
    -- Where the game spawned it is forgotten with the reload; where it is now stands in (unstuck.lua)
    startLocation = { X = location.X, Y = location.Y, Z = location.Z },
  }
  monster.ShouldCheckIfStuck = false
  movement.resetHost()
  runKitStep(activeEntity, "begin")
  if not activeEntity.kit.usesVents then
    lair.begin(activeEntity, moves.byKitId[activeEntity.kit.id])
  end
  game.log("%s is driving the monster; taken back as the entity after a reload", volunteerKey)
  return true
end

-- Whether a command comes from the entity. A command from the player driving the mission's monster takes them back as
-- the entity at once after a reload, rather than at the next reconcile: a sprint started in that second was lost
-- (playtest 6), and Shift only sends a command when it changes.
function takeover.isEntityController(controller)
  if not activeEntity and controller and controller:IsValid() and game.isMission() then
    local monster = missionMonster()
    local driver = monster and game.playerControllerOf(monster)
    if driver and driver:GetAddress() == controller:GetAddress() then
      adoptAfterReload(monster, game.currentWorldKey())
    end
  end
  return activeEntity ~= nil and controller ~= nil and controller:IsValid()
    and activeEntity.controller:IsValid() and controller:GetAddress() == activeEntity.controller:GetAddress()
end

local function noticeLoss()
  local entity = activeEntity
  activeEntity = nil
  -- What the entity left running stops with it (the Terminator's gatling: nothing in the game stops a firing gun)
  if entity.monster:IsValid() then
    runKitStep(entity, "finish")
  end
  lair.forget()
  if not entity.controller:IsValid() then
    return
  end

  links.sendEvent(entity.controller, "Lost")
  game.log("The entity lost: its monster is gone")

  -- Watch the surviving crew; the player is out of this mission
  local crewMember = FindFirstOf(game.classNames.crewCharacter)
  if crewMember and crewMember:IsValid() then
    entity.controller:SetViewTargetWithBlend(crewMember, 0.5, 0, 0, false)
  end
end


-- Tells the volunteer their status once per world, after their link has had time to reach them: in the lobby that
-- they're signed up, in a mission that the monster they'll take is still to come.
local function announceVolunteer(controller, worldKey)
  if announcedWorldKey == worldKey or not links.isEstablished(controller) then
    return
  end
  announcedWorldKey = worldKey
  links.sendEvent(controller, game.isMission() and "WaitingForMonster" or "Volunteered")
end

-- Runs every second on the host.
function takeover.reconcile()
  local worldKey = game.currentWorldKey()

  -- A map change took the entity's world with it (a mission ending normally travels back to the lobby): that's not
  -- a loss, so the entity is forgotten quietly
  if activeEntity and activeEntity.worldKey ~= worldKey then
    activeEntity = nil
    lair.forget()
  end

  -- Back at the main menu the session is over: nobody is the entity any more, the host's choices go back to Random,
  -- and the next session's mission must roll its monster normally
  if game.isMainMenu() then
    if volunteerKey then
      game.log("%s is no longer the entity (back at the main menu)", volunteerKey)
      forgetVolunteer()
    end
    takeover.choice = { entity = "Random", player = "Random" }
    rolledKit = nil
    forceMonster(nil)
    return
  end

  -- Random rolls its entity again for every mission
  if game.isMission() then
    rolledKit = nil
    hasPlayedMission = true
  end
  if game.isLobby() then
    -- Back from a mission, nobody is signed up any more: a volunteer or a random pick lasts one mission, and someone
    -- presses F8 again to volunteer for the next (playtest 9: a volunteer stayed the entity mission after mission).
    -- The host's own pick of a player is a setting, and holds
    if hasPlayedMission and volunteerKey then
      game.log("%s is no longer the entity (the mission is over)", volunteerKey)
      forgetVolunteer()
    end
    hasPlayedMission = false
    -- A player the host picked who has left the session leaves the choice to chance again, and the host is told
    if takeover.choice.player ~= "Random" and not pickedController() then
      game.log("%s, whom the host picked, has left; the entity's player is random again", takeover.choice.player)
      takeover.choice.player = "Random"
      local host = game.localController()
      if host then
        links.sendEvent(host, "PickedPlayerLeft")
      end
    end
    syncForcedMonster()
  end

  if activeEntity then
    local monsterAlive = activeEntity.monster:IsValid() and activeEntity.controller:IsValid()
      and activeEntity.controller.Pawn:IsValid()
      and activeEntity.controller.Pawn:GetAddress() == activeEntity.monster:GetAddress()
    if not monsterAlive then
      noticeLoss()
      return
    end
    releaseParkedBody(activeEntity)
    excludeFromCrew(activeEntity)
    return
  end

  if takeover.choice.entity == "AiOnly" then
    return
  end

  -- On Hawking the monster spawns only once a crew member leaves the shuttle
  local monster = game.isMission() and missionMonster() or nil
  if monster and adoptAfterReload(monster, worldKey) then
    return
  end

  -- The host's pick, then a volunteer, then a player picked at random
  local chosenKey = takeover.choice.player ~= "Random" and takeover.choice.player or volunteerKey
  if not chosenKey then
    local chosen = monster and pickAtRandom() or nil
    if chosen then
      takeControl(chosen, monster, worldKey)
    end
    return
  end

  -- The chosen player's controller arrives during the first seconds of every map; the next pass tries again
  local controller = controllerForKey(chosenKey)
  if not controller then
    return
  end
  announceVolunteer(controller, worldKey)
  if monster then
    takeControl(controller, monster, worldKey)
  end
end

-- The crew character adds its player to the crew list once it is possessed (BP_Character.ReceivePossessed). If that
-- lands after the takeover, the entity is taken out again on the spot.
local function onCrewListChanged(context, playerStateParameter, conditionParameter)
  local entity = takeover.activeEntity()
  if not entity or not conditionParameter:get() then
    return
  end
  local playerState = playerStateParameter:get()
  if playerState:IsValid() and playerState:GetAddress() == entity.playerState:GetAddress() then
    excludeFromCrew(entity)
  end
end

function takeover.register()
  links.onCommand("Volunteer", onVolunteer)
  links.onCommand("OpenPicker", onOpenPicker)
  game.hookWhenLoaded(game.paths.gameStateClass, "UpdateInGamePlayers", onCrewListChanged)
end

return takeover
