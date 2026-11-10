-- Copyright © 2026 Jalapeno Labs

-- Host side of becoming the entity: volunteering in the lobby, forcing the squid as the mission's specimen, taking
-- control of it when the mission starts, keeping the entity player out of the crew, and noticing when they lose.
--
-- Lua state outlives map travel, so the volunteer is remembered from the lobby into the mission and back.

local game = require("entity.game")
local links = require("entity.links")

local takeover = {}

-- Who volunteered, by the game's own lobby player id (stable across travel, unlike the controller and player state
-- objects, which are rebuilt on every map).
local volunteerKey = nil
-- The entity in the current world: { key, controller, squid, playerState }, or nil.
local activeEntity = nil

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
-- Volunteering
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

-- Toggles the sender as the entity. Only the sender is told; the rest of the crew learns nothing until the mission.
local function onVolunteer(_, controller)
  local key = playerKey(controller.PlayerState)
  if not key then
    game.log("Volunteer command from a controller without a player state")
    return
  end

  if volunteerKey == key then
    volunteerKey = nil
    forceSquid(false)
    links.sendEvent(controller, "Unvolunteered")
    game.log("%s is no longer the entity", key)
    return
  end

  if volunteerKey ~= nil then
    links.sendEvent(controller, "VolunteerTaken")
    return
  end

  volunteerKey = key
  forceSquid(true)
  links.sendEvent(controller, "Volunteered")
  game.log("%s will be the entity next mission", key)
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

local function isMission()
  local gameMode = FindFirstOf("BP_PlayableGameMode_C")
  return gameMode ~= nil and gameMode:IsValid()
end

local function liveSquid()
  local squid = FindFirstOf(game.classNames.squid)
  if not squid or not squid:IsValid() then
    return nil
  end
  return squid
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

local function takeControl(controller, squid)
  local crewBody = controller.Pawn

  -- The squid's AI controller would fight the player for it; it goes away for good
  local aiController = squid.Controller
  if aiController:IsValid() and not aiController:IsPlayerController() then
    aiController:UnPossess()
    aiController:K2_DestroyActor()
  end

  controller:Possess(squid)

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

  activeEntity = {
    key = volunteerKey,
    controller = controller,
    squid = squid,
    playerState = controller.PlayerState,
    parkedBody = parkedBody,
  }
  releaseParkedBody(activeEntity)
  links.sendEvent(controller, "BecameEntity")
  game.log("%s took control of the squid", volunteerKey)
end

local function noticeLoss()
  local entity = activeEntity
  activeEntity = nil
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

-- Runs every second on the host.
function takeover.reconcile()
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

  if not volunteerKey or not isMission() then
    return
  end

  local controller = controllerForKey(volunteerKey)
  local squid = liveSquid()
  -- Both arrive during the first seconds of a mission; the next pass tries again
  if not controller or not squid then
    return
  end

  takeControl(controller, squid)
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
  game.hookWhenLoaded(game.paths.gameStateClass, "UpdateInGamePlayers", onCrewListChanged)
end

return takeover
