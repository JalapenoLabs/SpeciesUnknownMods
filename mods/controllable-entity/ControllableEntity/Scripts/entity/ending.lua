-- Copyright © 2026 Jalapeno Labs

-- The end of the mission for the entity player, on their own machine (playtest 9: the crew got the game's end screens,
-- while the entity got a banner, a false "the crew got you", or nothing, its camera left out in the snow).
--
-- The entity's own result, full screen (WBP_EntityResult), for a few seconds each, so that what the game shows next
-- (a self destruct's white flash, the white fade of a win) is seen:
--   - when it loses mid-mission, killed or captured (the host's Lost or Captured); then it watches the crew, a living
--     crew member always, since it has no pawn of its own any more;
--   - when the game finishes the mission (FinishGame(Multi), on every machine, with what the crew achieved), unless it
--     already lost: the crew escaped, alone or with the black box;
--   - when the crew is wiped out with no respawns left (GameOver(Multi)): the entity wins. The game then fades to white
--     and travels back to the lobby, with no score for anyone.
-- Then the crew's score screen, as the crew see it on their seats' screens. The game puts it up on each seat's screen
-- on every machine, and the crew's view onto their seat's, which the entity has no seat or crew body for. Once the
-- scores reach this machine (BPI_GameState_SetEndScore(Local)), a seat's score page is launched for the entity (its
-- owner flag off: the entity is never paid, and saves nothing), and a camera of its own looks at that seat's screen
-- from where a seated crew member's eyes would be. Every seat's screen shows the same page on this machine, so a seat a
-- crew member sits in serves when none is free (a crowd of five or more).

local config = require("entity.config")
local game = require("entity.game")
local links = require("entity.links")

local ending = {}

local CAMERA_CLASS = "/Script/Engine.CameraActor"
-- How often a lost entity's view is checked to be on a living crew member.
local WATCH_CHECK_SECONDS = 1

-- What the entity is shown, by result: its title, what happened, and whether it won.
local resultByKind = {
  Lost = { title = "YOU WERE KILLED", detail = "The crew hunted you down.", isWin = false },
  Captured = { title = "YOU WERE CAPTURED", detail = "The crew took you alive.", isWin = false },
  Escaped = { title = "THE CREW ESCAPED", detail = "They got away from you.", isWin = false },
  Extracted = { title = "THE CREW ESCAPED", detail = "They got the black box away.", isWin = false },
  Won = { title = "YOU WIN", detail = "The crew is dead, with no respawns left.", isWin = true },
}
-- FinishGame(Multi)'s AccomplishedType (ContractType: what the crew achieved): a kill, an escape (the destruction
-- contract's result, whatever the contract), a capture, the black box delivered.
local resultKindByAccomplished = { [0] = "Lost", [1] = "Escaped", [2] = "Captured", [3] = "Extracted" }
local lossColor = { R = 1.0, G = 0.29, B = 0.24, A = 1 }
local winColor = { R = 0.45, G = 1.0, B = 0.55, A = 1 }

-- This machine's ending in the current world: whether the player was the entity in it and whether it lost, the result
-- on screen ({ widget, kind, hidesAt }), the score screen's camera, and when a lost entity's view is next checked.
local function freshEnding(worldKey)
  return { worldKey = worldKey, wasEntity = false, hasLost = false, result = nil, camera = nil, nextWatchCheckAt = 0 }
end

local current = freshEnding(nil)

local function syncWorld(controller)
  local worldKey = controller:GetWorld():GetAddress()
  if worldKey ~= current.worldKey then
    current = freshEnding(worldKey)
  end
end

local function removeResult()
  if current.result and current.result.widget:IsValid() then
    current.result.widget:RemoveFromParent()
  end
  current.result = nil
end

-- Puts the entity's result on screen for its few seconds, with a line on what comes next.
local function showResult(controller, kind, footer)
  local widgetClass = game.loadModAsset(game.modAssets.result)
  if not widgetClass then
    return
  end
  removeResult()
  local result = resultByKind[kind]
  local widget = StaticFindObject(game.paths.widgetLibrary):Create(controller, widgetClass, controller)
  widget:AddToViewport(100)
  widget.TitleText:SetText(FText(result.title))
  widget.TitleText:SetColorAndOpacity({ SpecifiedColor = result.isWin and winColor or lossColor, ColorUseRule = 0 })
  widget.DetailText:SetText(FText(result.detail))
  widget.FooterText:SetText(FText(footer))
  current.result = { widget = widget, kind = kind, hidesAt = game.timeSeconds(controller) + config.ending.resultSeconds }
  game.log("The entity's result: %s", result.title)
end

-- Where a seated crew member's eyes are above their seat's centre: measured on a crew member sitting in one, or the
-- usual height when nobody sits yet.
local function seatedEyeHeight(seats)
  for _, seat in ipairs(seats) do
    local sitter = seat.ActualPlayer
    if sitter:IsValid() and sitter.Camera:IsValid() then
      return sitter.Camera:K2_GetComponentLocation().Z - seat.SceneCenter:K2_GetComponentLocation().Z
    end
  end
  return config.ending.seatedEyeHeight
end

-- The seat whose screen the entity watches: a free one, or, with every seat taken, the first.
local function chooseSeat(seats)
  for _, seat in ipairs(seats) do
    if not seat.ActualPlayer:IsValid() then
      return seat
    end
  end
  return seats[1]
end

local function lookRotation(from, to)
  local offsetX, offsetY, offsetZ = to.X - from.X, to.Y - from.Y, to.Z - from.Z
  local yaw = math.deg(math.atan(offsetY, offsetX))
  local pitch = math.deg(math.atan(offsetZ, math.sqrt(offsetX * offsetX + offsetY * offsetY)))
  return { Pitch = pitch, Yaw = yaw, Roll = 0 }
end

-- The crew's score screen, on a seat's screen, seen from that seat.
local function showScore(controller)
  local gameState = FindFirstOf(game.classNames.gameState)
  local ship = gameState and gameState:IsValid() and gameState.PlayerShip
  local seats = {}
  if ship and ship:IsValid() then
    ship.ChairArray:ForEach(function(_, element)
      local seat = element:get()
      if seat:IsValid() then
        table.insert(seats, seat)
      end
    end)
  end
  local seat = chooseSeat(seats)
  local screen = seat and seat.Widget:GetUserWidgetObject()
  local scorePage = screen and screen:IsValid() and screen.ScorePage
  if not scorePage or not scorePage:IsValid() then
    game.log("No seat's score page to show the entity")
    return
  end

  -- The entity's own pawn, if it still has one, lets the page pick out its tab; without one the page lists everyone
  local pawn = controller.Pawn:IsValid() and controller.Pawn or nil
  scorePage:LaunchMissionScore(false, pawn)

  local seatCentre = seat.SceneCenter:K2_GetComponentLocation()
  local eye = { X = seatCentre.X, Y = seatCentre.Y, Z = seatCentre.Z + seatedEyeHeight(seats) }
  local view = controller:GetWorld():SpawnActor(StaticFindObject(CAMERA_CLASS), eye,
    lookRotation(eye, seat.Widget:K2_GetComponentLocation()))
  if view and view:IsValid() then
    view.CameraComponent.FieldOfView = seat["Screen FOV"]
    controller:SetViewTargetWithBlend(view, config.ending.cameraBlendSeconds, 0, 0, false)
    current.camera = view
  end
  removeResult()
  game.log("The entity watches the crew's score screen")
end

-- A lost entity has no pawn: the host puts its view on a crew member, which its machine's camera manager may set back
-- to the controller when the pawn's loss arrives, and which a crew member's death takes away. Its view is kept on a
-- living crew member until the score screen's camera takes over.
local function keepWatchingCrew(controller, now)
  if not current.hasLost or current.camera or controller.Pawn:IsValid() or now < current.nextWatchCheckAt then
    return
  end
  current.nextWatchCheckAt = now + WATCH_CHECK_SECONDS
  local watched = controller:GetViewTarget()
  local isWatchingCrew = watched and watched:IsValid() and watched.IsDead ~= true
    and watched:GetClass():GetFName():ToString() == game.classNames.crewCharacter
  if isWatchingCrew then
    return
  end
  for _, crewMember in ipairs(FindAllOf(game.classNames.crewCharacter) or {}) do
    if crewMember:IsValid() and not crewMember.bHidden and crewMember.IsDead ~= true then
      controller:SetViewTargetWithBlend(crewMember, config.ending.cameraBlendSeconds, 0, 0, false)
      return
    end
  end
end

-- Runs about thirty times a second on every machine: notes whether its player is the entity in this world, keeps a
-- lost entity watching the crew, and takes a result off once its time is up, the last second fading.
function ending.follow(controller, now)
  syncWorld(controller)
  if game.monsterDrivenBy(controller) then
    current.wasEntity = true
  end
  keepWatchingCrew(controller, now)
  local result = current.result
  if not result then
    return
  end
  if not result.widget:IsValid() or now >= result.hidesAt then
    removeResult()
    return
  end
  result.widget:SetRenderOpacity(math.min(1, result.hidesAt - now))
end

-- Runs one of the game's end events on this machine, for a player who was the entity in this world.
local function forTheEntity(handler)
  return function(...)
    local controller = game.localController()
    if not controller then
      return
    end
    syncWorld(controller)
    if current.wasEntity then
      handler(controller, ...)
    end
  end
end

function ending.register()
  links.onClientEvent("BecameEntity", function()
    local controller = game.localController()
    if controller then
      syncWorld(controller)
      current.wasEntity = true
    end
  end)
  for _, kind in ipairs({ "Lost", "Captured" }) do
    links.onClientEvent(kind, forTheEntity(function(controller)
      current.hasLost = true
      showResult(controller, kind, "You're out of this mission. Watch the crew.")
    end))
  end
  game.hookWhenLoaded(game.paths.gameStateClass, "FinishGame(Multi)",
    forTheEntity(function(controller, _, _, accomplishedParameter)
      -- A loss already shown stands; otherwise the crew got away
      local kind = resultKindByAccomplished[accomplishedParameter:get()] or "Escaped"
      if current.result and current.result.kind == kind then
        return
      end
      showResult(controller, kind, "The crew's score follows.")
    end))
  game.hookWhenLoaded(game.paths.gameStateClass, "GameOver(Multi)", forTheEntity(function(controller)
    showResult(controller, "Won", "Back to the lobby.")
  end))
  game.hookWhenLoaded(game.paths.gameStateClass, "BPI_GameState_SetEndScore(Local)", forTheEntity(showScore))
end

return ending
