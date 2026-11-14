-- Copyright © 2026 Jalapeno Labs

-- The entity's flight as other machines see it (#14): a crew member's machine shows the game's own "the specimen has
-- fled" notice where the level has none of its own (Polar), and leaves it to the game's where it does (Hawking).
-- Run from the repository root: lua mods/controllable-entity/tests/flee_test.lua

package.path = "mods/controllable-entity/ControllableEntity/Scripts/?.lua;mods/controllable-entity/tests/?.lua;"
  .. package.path

local fake = require("fake_ue4ss")
fake.install()
fake.isHost = false

local game = require("entity.game")
local links = require("entity.links")
local flee = require("entity.flee")

fake.objects[game.paths.gameplayStatics] = fake.object("GameplayStatics", nil, {
  GetTimeSeconds = function() return fake.now end,
})
fake.objects["/Game/Translations/ST_Tooltip.ST_Tooltip"] = fake.object("StringTable")
fake.objects["/Script/Engine.Default__KismetTextLibrary"] = fake.object("KismetTextLibrary", nil, {
  TextFromStringTable = function(_, tableId, key)
    assert(tableId:ToString() == "/Game/Translations/ST_Tooltip.ST_Tooltip", "the game's own string table")
    return { text = key }
  end,
})

-- A crew member's machine: its controller drives a crew body, and its link has arrived
local crewBody = fake.object("BP_Character_C")
local controller = fake.object("BP_MyPlayerController_C", { Pawn = crewBody }, {
  IsLocalController = function() return true end,
}, { "PlayerController" })
local link = fake.object("BP_EntityLink_C", { Owner = controller })
fake.world = fake.object("World")

links.registerEvents()
flee.register({ activeEntity = function() return nil end })

local function hostSays(kind)
  fake.customEvents.EntityClientEvent(fake.param(link), fake.param(fake.name(kind)), fake.param(0))
end

-- Polar: no notice in the level, so the crew member's machine shows the game's own, as the game would
hostSays("SpecimenFled")
local notices = fake.callsTo(crewBody, "BPI_Player_SendNotifyHUD")
assert(#notices == 1, "the crew member is told the specimen has fled")
assert(notices[1].args[1].text == "TutoMonsterFleeText1" and notices[1].args[7].text == "TutoMonsterFleeText2",
  "in the game's own words, in the player's language")
assert(notices[1].args[2] == 15 and notices[1].args[8] == 7, "for the game's 15 seconds, as its notice")

-- Hawking: the level's own notice shows it, through the game's own call
fake.object("BP_Tuto_Notify_MonsterFlee_C")
hostSays("SpecimenFled")
assert(#fake.callsTo(crewBody, "BPI_Player_SendNotifyHUD") == 1, "the game's notice shows it, and only once")

print("flee test passed")
