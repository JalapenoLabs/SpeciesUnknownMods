-- Copyright © 2026 Jalapeno Labs

-- Host side of becoming the entity: entity mode, volunteering in the lobby (or a random pick), forcing the squid as
-- the mission's specimen, taking control of it when it spawns, keeping the entity player out of the crew, and noticing
-- when they lose.
--
-- Lua state outlives map travel, so the volunteer is remembered from the lobby into the mission and back.

local game = require("entity.game")
local lair = require("entity.lair")
local links = require("entity.links")

local takeover = {}

-- Entity mode, which the host turns on or off for the session. While it's on, every co-op mission has an entity.
local entityModeOn = true
-- Who will be the entity, by the game's own lobby player id (stable across travel, unlike the controller and player
-- state objects, which are rebuilt on every map): a volunteer, or the player picked at random this mission.
local volunteerKey = nil
-- True when volunteerKey came from the random pick, which lasts one mission; a volunteer stays until they back out.
local chosenAtRandom = false
-- The entity in the current world: { key, controller, squid, playerState, parkedBody, worldKey }, or nil.
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

-- Identifies the current world: its game state is rebuilt on every map, so its address changes with the world.
local function currentWorldKey()
  local gameState = FindFirstOf("GameStateBase")
  if not gameState or not gameState:IsValid() then
    return nil
  end
  return gameState:GetAddress()
end

local function controllerForKey(key)
  for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
    if controller:IsValid() and playerKey(controller.PlayerState) == key then
      return controller
    end
  end
  return nil
end

function takeover.isEntityController(controller)
  return activeEntity ~= nil and controller ~= nil and controller:IsValid()
    and activeEntity.controller:IsValid() and controller:GetAddress() == activeEntity.controller:GetAddress()
end

function takeover.activeEntity()
  if not activeEntity or not activeEntity.squid:IsValid() then
    return nil
  end
  return activeEntity
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Where we are
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

local function exists(className)
  local object = FindFirstOf(className)
  return object ~= nil and object:IsValid()
end

-- The lobby's game mode (BP_LobbyGameMode) is a subclass of the mission's (BP_PlayableGameMode), so "a playable game
-- mode exists" is true in the lobby too; the lobby has to be ruled out by name.
local function isLobby()
  return exists(game.classNames.lobbyGameMode)
end

local function isMission()
  return not isLobby() and exists(game.classNames.missionGameMode)
end

local function isMainMenu()
  return exists(game.classNames.mainMenuGameMode)
end

local function playerControllers()
  return FindAllOf(game.classNames.playerController) or {}
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Entity mode and volunteering
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- BP_MyGameInstance.spawnForceSessionMonster: when set (not 0 or 1), BP_GameManager spawns that monster instead of
-- a random one. The game never sets it itself.
local function forceSquid(enabled)
  local gameInstance = FindFirstOf(game.classNames.gameInstance)
  if not gameInstance or not gameInstance:IsValid() then
    game.log("No game instance; can't force the squid")
    return
  end
  gameInstance.spawnForceSessionMonster = enabled and game.squidMonsterType or 0
end

-- Decides the next mission's specimen, from the lobby. The mission rolls its monster seconds after it loads, before
-- every player has even arrived, so the squid is forced whenever the mission will have an entity: a volunteer, or a
-- random pick among two or more players. Playing alone, only a volunteer makes sense.
local function syncForcedSquid()
  forceSquid(entityModeOn and (volunteerKey ~= nil or #playerControllers() >= 2))
end

local function forgetVolunteer()
  volunteerKey = nil
  chosenAtRandom = false
  announcedWorldKey = nil
end

-- Toggles the sender as the entity. Only the sender is told; the rest of the crew learns nothing until the mission.
local function onVolunteer(_, controller)
  if not entityModeOn then
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
    syncForcedSquid()
    links.sendEvent(controller, "Unvolunteered")
    game.log("%s is no longer the entity", key)
    return
  end

  if volunteerKey ~= nil then
    links.sendEvent(controller, "VolunteerTaken")
    return
  end

  volunteerKey = key
  announcedWorldKey = currentWorldKey()
  syncForcedSquid()
  links.sendEvent(controller, "Volunteered")
  game.log("%s will be the entity next mission", key)
end

-- Turns entity mode on or off; only the host may. Turning it off releases the volunteer, so the next mission is the
-- game's own. An entity already playing keeps playing until the mission ends.
local function onToggleEntityMode(_, controller)
  -- On the host, the host's own controller is the only local one
  if not controller:IsLocalController() then
    links.sendEvent(controller, "Denied.HostOnly")
    return
  end

  entityModeOn = not entityModeOn
  if not entityModeOn and volunteerKey then
    local volunteer = controllerForKey(volunteerKey)
    if volunteer then
      links.sendEvent(volunteer, "Unvolunteered")
    end
    forgetVolunteer()
  end
  if isLobby() then
    syncForcedSquid()
  end

  links.sendEvent(controller, entityModeOn and "EntityModeOn" or "EntityModeOff")
  game.log("Entity mode is %s", entityModeOn and "on" or "off")
end

-- With no volunteer, a co-op mission's entity is a player picked at random once the squid is there to take.
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

-- The mission's specimen, when it is the squid: the monster BP_GameManager spawned (its Monster property). Other
-- squids exist too, like the specimen on display in the lobby, and must never be taken over.
local function missionSquid()
  local gameManager = FindFirstOf(game.classNames.gameManager)
  if not gameManager or not gameManager:IsValid() then
    return nil
  end
  local monster = gameManager.Monster
  if not monster:IsValid() or monster:GetClass():GetFName():ToString() ~= game.classNames.squid then
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

local function takeControl(controller, squid, worldKey)
  local crewBody = controller.Pawn

  -- The squid's AI controller would fight the player for it; it goes away for good
  local aiController = squid.Controller
  if aiController:IsValid() and not aiController:IsPlayerController() then
    aiController:UnPossess()
    aiController:K2_DestroyActor()
  end

  controller:Possess(squid)
  -- Possession moves the camera only when the camera manager follows the pawn on its own, which this game's doesn't:
  -- in the first playtest the view stayed in the hidden crew body. Set on the host, the view target replicates to
  -- the player's machine
  controller:SetViewTargetWithBlend(squid, 0, 0, 0, false)

  local parkedBody = nil
  if crewBody:IsValid() and crewBody:GetAddress() ~= squid:GetAddress() then
    parkBody(crewBody)
    parkedBody = crewBody
  end

  -- Combat speed (MonsterSpeed_DataTable type 1) suits a player better than the AI's patrol walk. The speed comes
  -- back through an out parameter, which UE4SS fills into a table
  local speed = {}
  squid:BPI_Monster_GetSpeedByType(1, speed)
  squid:BPI_Monster_SetSpeed(speed.Speed)

  -- The AI's stuck check (BP_BaseMonster."Check If Stuck", every second) respawns a monster that hasn't moved for 20
  -- seconds, through BP_GameManager.InitMonster, which destroys it. A player lying in wait stands still for longer
  -- than that, and losing the squid would end their game
  squid.ShouldCheckIfStuck = false

  activeEntity = {
    key = volunteerKey,
    controller = controller,
    squid = squid,
    playerState = controller.PlayerState,
    parkedBody = parkedBody,
    worldKey = worldKey,
  }
  releaseParkedBody(activeEntity)
  links.sendEvent(controller, "BecameEntity")
  game.log("%s took control of the squid", volunteerKey)
  lair.begin(squid, controller)
end

-- A hot reload of the mod (UE4SS's Ctrl+R) forgets who the entity is, while the player still drives the squid. Their
-- controller is the proof: the squid's AI was destroyed at the takeover, so only the entity player can be driving it.
-- They're taken back as the entity where they are; the lair isn't rebuilt, so the leash is gone until the next mission.
local function adoptAfterReload(squid, worldKey)
  local controller = game.playerControllerOf(squid)
  if not controller then
    return false
  end
  volunteerKey = playerKey(controller.PlayerState)
  activeEntity = {
    key = volunteerKey,
    controller = controller,
    squid = squid,
    playerState = controller.PlayerState,
    parkedBody = nil,
    worldKey = worldKey,
  }
  squid.ShouldCheckIfStuck = false
  game.log("%s is driving the squid; taken back as the entity after a reload", volunteerKey)
  return true
end

local function noticeLoss()
  local entity = activeEntity
  activeEntity = nil
  lair.forget()
  if not entity.controller:IsValid() then
    return
  end

  links.sendEvent(entity.controller, "Lost")
  game.log("The entity lost: the squid is gone")

  -- Watch the surviving crew; the player is out of this mission
  local crewMember = FindFirstOf(game.classNames.crewCharacter)
  if crewMember and crewMember:IsValid() then
    entity.controller:SetViewTargetWithBlend(crewMember, 0.5, 0, 0, false)
  end
end


-- Tells the volunteer their status once per world, after their link has had time to reach them: in the lobby that
-- they're signed up, in a mission that the squid is still to come.
local function announceVolunteer(controller, worldKey)
  if announcedWorldKey == worldKey or not links.isEstablished(controller) then
    return
  end
  announcedWorldKey = worldKey
  links.sendEvent(controller, isMission() and "WaitingForSquid" or "Volunteered")
end

-- Runs every second on the host.
function takeover.reconcile()
  local worldKey = currentWorldKey()

  -- A map change took the entity's world with it (a mission ending normally travels back to the lobby): that's not
  -- a loss, so the entity is forgotten quietly
  if activeEntity and activeEntity.worldKey ~= worldKey then
    activeEntity = nil
    lair.forget()
  end

  -- Back at the main menu the session is over: nobody is the entity any more, and the next session's mission must
  -- roll its monster normally
  if isMainMenu() then
    if volunteerKey then
      game.log("%s is no longer the entity (back at the main menu)", volunteerKey)
      forgetVolunteer()
    end
    forceSquid(false)
    return
  end

  -- A random pick lasts one mission; back in the lobby, the next mission picks again
  if chosenAtRandom and not isMission() then
    forgetVolunteer()
  end
  if isLobby() then
    syncForcedSquid()
  end

  if activeEntity then
    local squidAlive = activeEntity.squid:IsValid() and activeEntity.controller:IsValid()
      and activeEntity.controller.Pawn:IsValid()
      and activeEntity.controller.Pawn:GetAddress() == activeEntity.squid:GetAddress()
    if not squidAlive then
      noticeLoss()
      return
    end
    releaseParkedBody(activeEntity)
    excludeFromCrew(activeEntity)
    return
  end

  if not entityModeOn then
    return
  end

  -- On Hawking the squid spawns only once a crew member leaves the shuttle
  local squid = isMission() and missionSquid() or nil
  if squid and adoptAfterReload(squid, worldKey) then
    return
  end

  if not volunteerKey then
    local chosen = squid and pickAtRandom() or nil
    if chosen then
      takeControl(chosen, squid, worldKey)
    end
    return
  end

  -- The volunteer's controller arrives during the first seconds of every map; the next pass tries again
  local controller = controllerForKey(volunteerKey)
  if not controller then
    return
  end
  announceVolunteer(controller, worldKey)
  if squid then
    takeControl(controller, squid, worldKey)
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
  links.onCommand("ToggleEntityMode", onToggleEntityMode)
  game.hookWhenLoaded(game.paths.gameStateClass, "UpdateInGamePlayers", onCrewListChanged)
end

return takeover
