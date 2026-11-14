-- Copyright © 2026 Jalapeno Labs

-- The entity's flight (playtest 9: "the squid's last phase, fleeing, never tells the crew"). In the game, once the
-- squid has an eye broken (Mike, a face) and is back up, the monster flees: BPI_Monster_SetEscaping(true, true). That
-- tells the crew it has fled (SetStayFar -> LaunchFleeTuto -> each crew member's notice, "The specimen has fled, track
-- it", once per monster, on kill and capture contracts) and sends its AI running at its top speed somewhere away from
-- the crew. A player's monster gets the call, but its run needs the AI. So for the entity:
--   - the crew are told on every map: Hawking places the game's notice in its level, which the game's own call shows;
--     Polar has none, so each crew member's machine shows the game's own text itself;
--   - the entity sees a huge red RUN with the crew's message, and gets the escape: its top speed and a full sprint for
--     config.flee.seconds, and the vents open to it with its whole vent time;
--   - the escape's cry is the one the entity makes on getting back up (cries.lua).
-- The game's chain hangs on montages finishing on the host, which a remotely driven squid's may not (the plain get-up
-- the mod's rescue uses never escapes), so an eye broken without an escape soon after gets the game's own ink get-up
-- from the host, which ends in it.

local config = require("entity.config")
local game = require("entity.game")
local hunt = require("entity.hunt")
local links = require("entity.links")
local movement = require("entity.movement")

local flee = {}

local MONSTER_CLASS = "/Game/Blueprints/Monsters/BP_BaseMonster.BP_BaseMonster_C"
local SQUID_CLASS = "/Game/Blueprints/Monsters/BP_Monster_Poulpi.BP_Monster_Poulpi_C"
-- The game's notice in a level (Hawking's), which shows the crew the flight itself.
local NOTICE_CLASS_NAME = "BP_Tuto_Notify_MonsterFlee_C"
-- The notice's text, in the player's own language, and how the game shows it (BP_Tuto_Notify_MonsterFlee.SendTuto):
-- for 15 seconds, as notification 7.
local NOTICE_STRING_TABLE = "/Game/Translations/ST_Tooltip.ST_Tooltip"
local NOTICE_TITLE_KEY = "TutoMonsterFleeText1"
local NOTICE_HINT_KEY = "TutoMonsterFleeText2"
local NOTICE_SECONDS = 15
local NOTICE_ID = 7
local NOTICE_ICON_SIZE = 64
local TEXT_LIBRARY = "/Script/Engine.Default__KismetTextLibrary"

-- On the host: the flight under way, { monsterAddress, endsAt }, or nil; the monsters whose flight the crew were told
-- of (once each, as the game tells them); and the squid whose eye broke, waiting for its escape: { monsterAddress, at }.
local fleeing = nil
local toldCrewOf = {}
local eyeBroken = nil

-- Tells every crew member's machine the specimen has fled, as the game's notice would: once per monster, on kill and
-- capture contracts, and not once the self destruct is armed (BP_BaseMonster.LaunchFleeTuto's own rules).
local function tellCrew(entity)
  local monster = entity.monster
  local address = monster:GetAddress()
  local contract = game.contractType()
  local isHuntContract = contract == game.contractTypes.Elimination or contract == game.contractTypes.Capture
  if toldCrewOf[address] or not isHuntContract or monster.IsEmergency == true then
    return
  end
  toldCrewOf[address] = true
  local entityAddress = entity.controller:GetAddress()
  for _, controller in ipairs(FindAllOf(game.classNames.playerController) or {}) do
    if controller:IsValid() and controller:GetAddress() ~= entityAddress then
      links.sendEvent(controller, "SpecimenFled")
    end
  end
end

local function start(entity, now)
  local monster = entity.monster
  fleeing = { monsterAddress = monster:GetAddress(), endsAt = now + config.flee.seconds }
  eyeBroken = nil
  movement.setFleeing(entity, true)
  hunt.refill()
  links.sendEvent(entity.controller, "Fleeing")
  tellCrew(entity)
  game.log("The entity flees: top speed and its vents open for %d seconds", config.flee.seconds)
end

-- Runs five times a second on the host while there is an entity: ends the flight when its time is up, and gets an eye
-- broken without an escape up the game's way.
function flee.tickHost(entity, now)
  local monster = entity.monster
  -- A flight or a broken eye left by an earlier entity is forgotten (a new entity's movement starts afresh)
  local address = monster:GetAddress()
  if fleeing and fleeing.monsterAddress ~= address then
    fleeing = nil
  end
  if eyeBroken and eyeBroken.monsterAddress ~= address then
    eyeBroken = nil
  end
  if fleeing and now >= fleeing.endsAt then
    fleeing = nil
    movement.setFleeing(entity, false)
    links.sendEvent(entity.controller, "FleeEnded")
  end
  if eyeBroken and now - eyeBroken.at >= config.flee.escapeWaitSeconds then
    eyeBroken = nil
    game.log("The squid's eye broke without an escape; getting it up the game's way")
    monster["GetUpWithInk (multi)"](monster, 1.0)
  end
end

-- Whether the entity is fleeing, on the host.
function flee.isFleeing()
  return fleeing ~= nil
end

-- On a crew member's machine: the game's own notice, unless the level has the game's notice actor, which shows it.
local function showCrewNotice()
  local notice = FindFirstOf(NOTICE_CLASS_NAME)
  if notice and notice:IsValid() then
    return
  end
  local controller = game.localController()
  local crewMember = controller and controller.Pawn
  if not crewMember or not crewMember:IsValid() or game.monsterDrivenBy(controller) then
    game.log("The specimen fled, but this player has no crew body to show it on")
    return
  end
  game.loadGameAsset(NOTICE_STRING_TABLE)
  local texts = StaticFindObject(TEXT_LIBRARY)
  local title = texts:TextFromStringTable(FName(NOTICE_STRING_TABLE), NOTICE_TITLE_KEY)
  local hint = texts:TextFromStringTable(FName(NOTICE_STRING_TABLE), NOTICE_HINT_KEY)
  crewMember:BPI_Player_SendNotifyHUD(title, NOTICE_SECONDS, FName("None"), FName("None"), false, NOTICE_ICON_SIZE,
    hint, NOTICE_ID, nil)
end

function flee.register(takeover)
  game.hookWhenLoaded(MONSTER_CLASS, "BPI_Monster_SetEscaping", function(context)
    local monster = context:get()
    local entity = takeover.activeEntity()
    local isEntity = entity and monster:HasAuthority() and monster:GetAddress() == entity.monster:GetAddress()
    if isEntity then
      start(entity, game.timeSeconds(monster))
    end
  end)
  game.hookWhenLoaded(SQUID_CLASS, "BreakEye (multi)", function(context)
    local monster = context:get()
    local entity = takeover.activeEntity()
    if entity and monster:HasAuthority() and monster:GetAddress() == entity.monster:GetAddress() then
      eyeBroken = { monsterAddress = monster:GetAddress(), at = game.timeSeconds(monster) }
    end
  end)
  links.onClientEvent("SpecimenFled", showCrewNotice)
end

return flee
