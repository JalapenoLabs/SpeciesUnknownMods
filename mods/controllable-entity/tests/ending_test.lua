-- Copyright © 2026 Jalapeno Labs

-- The end of the mission for the entity player, on their machine (#3): their own full-screen result when they lose
-- mid-mission, when the crew gets away, and when the crew is wiped out; then the crew's score screen on a seat's
-- screen, launched unpaid, seen through a camera at that seat. A machine whose player wasn't the entity sees none of
-- it.
-- Run from the repository root: lua mods/controllable-entity/tests/ending_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.isHost = false

local config = require("entity.config")
local ending = require("entity.ending")
local game = require("entity.game")
local links = require("entity.links")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.installModPak(game.modAssets)

-- The result widget: each made one is kept, with its texts
local results = {}
fake.objects[game.paths.widgetLibrary] = fake.object("WidgetBlueprintLibrary", nil, {
  Create = function()
    local widget = fake.object("WBP_EntityResult_C", {
      TitleText = fake.object("TextBlock"),
      DetailText = fake.object("TextBlock"),
      FooterText = fake.object("TextBlock"),
    })
    widget.RemoveFromParent = function(self) self.removed = true end
    table.insert(results, widget)
    return widget
  end,
})
local function lastText(textBlock)
  local calls = fake.callsTo(textBlock, "SetText")
  return calls[#calls].args[1].text
end

-- The camera the score screen is seen through
local cameraClass = fake.object("CameraActorClass")
fake.objects["/Script/Engine.CameraActor"] = cameraClass
local spawned = {}
fake.world = fake.object("World", nil, {
  SpawnActor = function(_, class, location, rotation)
    local camera = fake.object("CameraActor", { CameraComponent = fake.object("CameraComponent"),
      location = location, rotation = rotation, class = class })
    table.insert(spawned, camera)
    return camera
  end,
})

-- The shuttle's seats: the first taken by a seated crew member, the second free; each screen holds a score page
local function component(location)
  return fake.object("SceneComponent", nil, { K2_GetComponentLocation = function() return location end })
end
local function seat(x, sitter)
  local scorePage = fake.object("WBP_ScorePage_C")
  local screen = fake.object("WBP_Main_ShipScreen_C", { ScorePage = scorePage })
  local widget = fake.object("WidgetComponent", nil, {
    GetUserWidgetObject = function() return screen end,
    K2_GetComponentLocation = function() return { X = x + 100, Y = 0, Z = 90 } end,
  })
  return fake.object("BP_Seat_C", {
    ActualPlayer = sitter,
    SceneCenter = component({ X = x, Y = 0, Z = 40 }),
    Widget = widget,
    ["Screen FOV"] = 70,
  }), scorePage
end
local sitter = fake.object("BP_Character_C", { Camera = component({ X = 0, Y = 0, Z = 105 }) })
local takenSeat, takenPage = seat(0, sitter)
local freeSeat, freePage = seat(500, fake.invalid())
fake.object("BP_MyGameState_C", { PlayerShip = fake.object("BP_PlayerShip_C", {
  ChairArray = fake.array({ takenSeat, freeSeat }),
}) }, nil, { "GameStateBase" })

-- The entity player's machine, driving the squid
local squid = fake.object("BP_Monster_Poulpi_C")
fake.giveSquidState(squid)
local controller = fake.object("BP_MyPlayerController_C", { Pawn = squid }, {
  IsLocalController = function() return true end,
}, { "PlayerController" })
fake.giveView(controller)
local link = fake.object("BP_EntityLink_C", { Owner = controller })

links.registerEvents()
ending.register()
fake.loadClass(game.paths.gameStateClass)
local function hostSays(kind)
  fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name(kind)), fake.param(0))
end
local function gameSays(functionName, ...)
  local parameters = {}
  for _, value in ipairs({ ... }) do
    table.insert(parameters, fake.param(value))
  end
  fake.hooks[game.paths.gameStateClass .. ":" .. functionName](fake.param(FindFirstOf("GameStateBase")),
    table.unpack(parameters))
end

fake.now = 10
ending.follow(controller, fake.now)

-- Killed mid-mission: the result, full screen, for a few seconds, then the entity watches the crew
controller.Pawn = fake.invalid()
hostSays("Lost")
assert(#results == 1 and lastText(results[1].TitleText) == "YOU WERE KILLED", "the entity's own result, full screen")
assert(fake.callsTo(results[1], "AddToViewport")[1].args[1] == 100, "over everything")
fake.now = 10 + config.ending.lossSeconds - 0.5
ending.follow(controller, fake.now)
assert(fake.callsTo(results[1], "SetRenderOpacity")[1].args[1] == 0.5, "fading over its last second")
fake.now = 10 + config.ending.lossSeconds
ending.follow(controller, fake.now)
assert(results[1].removed, "then it watches the crew")

-- The game finishes the mission with the kill: the result again, until the score screen
gameSays("FinishGame(Multi)", true, 0, 2)
assert(#results == 2 and lastText(results[2].TitleText) == "YOU WERE KILLED"
  and lastText(results[2].FooterText) == "The crew's score follows.", "the mission's end, before the crew's score")

-- The scores arrive: the free seat's score page, launched with the entity unpaid, seen from that seat
gameSays("BPI_GameState_SetEndScore(Local)", {})
local launches = fake.callsTo(freePage, "LaunchMissionScore")
assert(#launches == 1 and launches[1].args[1] == false, "the score page, the entity never paid")
assert(#fake.callsTo(takenPage, "LaunchMissionScore") == 0, "on a free seat's screen")
local camera = spawned[1]
assert(camera and camera.class == cameraClass and camera.location.X == 500 and camera.location.Z == 40 + 65,
  "a camera where a seated crew member's eyes would be (measured on the one sitting)")
assert(math.abs(camera.rotation.Yaw) < 1e-9 and camera.rotation.Pitch < 0, "looking at the seat's screen")
assert(camera.CameraComponent.FieldOfView == 70, "with the seat's own field of view")
local views = fake.callsTo(controller, "SetViewTargetWithBlend")
assert(views[#views].args[1] == camera, "the entity's view moves onto it")
assert(results[2].removed, "and the result makes way")

-- A new world: the crew is wiped out with no respawns left, and the entity wins
fake.world = fake.object("World", nil, { SpawnActor = function() return fake.invalid() end })
controller.Pawn = squid
ending.follow(controller, fake.now)
gameSays("GameOver(Multi)")
local won = results[#results]
assert(lastText(won.TitleText) == "YOU WIN" and lastText(won.FooterText) == "Back to the lobby.", "the entity wins")

-- The crew escape in another mission
fake.world = fake.object("World")
ending.follow(controller, fake.now)
gameSays("FinishGame(Multi)", false, 1, 2)
assert(lastText(results[#results].TitleText) == "THE CREW ESCAPED", "the crew got away: the entity loses")

-- Every seat taken (five players or more): the entity watches the first seat's screen
freeSeat.ActualPlayer = sitter
gameSays("BPI_GameState_SetEndScore(Local)", {})
assert(#fake.callsTo(takenPage, "LaunchMissionScore") == 1, "a seat taken serves, its screen the same on this machine")

-- A machine whose player wasn't the entity sees none of it
fake.world = fake.object("World")
controller.Pawn = fake.object("BP_Character_C")
ending.follow(controller, fake.now)
local resultsBefore = #results
gameSays("GameOver(Multi)")
gameSays("FinishGame(Multi)", false, 1, 2)
assert(#results == resultsBefore, "the crew get the game's own")

print("ending test passed")
