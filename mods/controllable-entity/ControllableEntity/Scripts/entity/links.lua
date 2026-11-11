-- Copyright © 2026 Jalapeno Labs

-- BP_EntityLink: the mod's private line between each player and the host.
--
-- The host spawns one link per player controller, owned by that controller. A link replicates only to its owner, so
-- each player can send commands to the host through their own link, and the host can answer that player alone. The
-- link's events are empty Blueprint stubs; UE4SS's RegisterCustomEvent runs the Lua below when they execute.

local game = require("entity.game")

local links = {}

-- Command name -> function(link, controller, aim, target), run on the host.
local commandHandlers = {}
-- Event kind -> function(value), run on the player's own machine.
local clientEventHandlers = {}
local pingHandler = nil

-- Host: link actor per controller, keyed by the controller's address (a controller's Lua wrapper is not stable).
local linkByControllerAddress = {}

function links.onCommand(command, handler)
  commandHandlers[command] = handler
end

function links.onClientEvent(kind, handler)
  clientEventHandlers[kind] = handler
end

function links.onPing(handler)
  pingHandler = handler
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Host
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- Spawns a link for every player controller that has none. Called every second on the host: players join, leave
-- and travel at any time, and a reconcile pass catches every case without hooking the game's travel code.
function links.reconcile()
  local linkClass = game.loadModClass(game.modClasses.link)
  if not linkClass then
    return
  end

  local liveAddresses = {}
  for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
    if controller:IsValid() then
      local address = controller:GetAddress()
      liveAddresses[address] = true
      local link = linkByControllerAddress[address]
      if not link or not link:IsValid() then
        link = controller:GetWorld():SpawnActor(linkClass, controller:K2_GetActorLocation(), {})
        link:SetOwner(controller)
        linkByControllerAddress[address] = link
      end
    end
  end

  -- Controllers that left take their links with them on map travel; forget them so their addresses can be reused
  for address in pairs(linkByControllerAddress) do
    if not liveAddresses[address] then
      linkByControllerAddress[address] = nil
    end
  end
end

-- The host's link for a controller, or nil until the next reconcile spawns it.
function links.forController(controller)
  local link = linkByControllerAddress[controller:GetAddress()]
  if not link or not link:IsValid() then
    return nil
  end
  return link
end

function links.sendEvent(controller, kind, value)
  local link = links.forController(controller)
  if not link then
    game.log("No link yet for a controller; dropped client event %s", kind)
    return
  end
  link:EntityClientEvent(FName(kind), value or 0)
end

function links.sendPing(controller, location, loudness, kind)
  local link = links.forController(controller)
  if not link then
    return
  end
  link:EntityClientPing(location, loudness, FName(kind))
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Player
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- This machine's own link: the only one a client receives, and on the host the one its local controller owns.
function links.own()
  local controller = game.localController()
  if not controller then
    return nil
  end

  local controllerAddress = controller:GetAddress()
  for _, link in ipairs(FindAllOf(game.classNames.link) or {}) do
    if link:IsValid() and link.Owner:IsValid() and link.Owner:GetAddress() == controllerAddress then
      return link
    end
  end
  return nil
end

function links.sendCommand(command, aim, target)
  local link = links.own()
  if not link then
    game.log("No link yet; dropped command %s (the host spawns links once a second)", command)
    return
  end
  link:EntityServerCommand(FName(command), aim or { X = 0, Y = 0, Z = 0 }, target)
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Event wiring
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

function links.registerEvents()
  -- Runs on the host: server events execute only there
  RegisterCustomEvent("EntityServerCommand", function(context, commandParameter, aimParameter, targetParameter)
    local link = context:get()
    local command = commandParameter:get():ToString()
    local handler = commandHandlers[command]
    if not handler then
      game.log("Ignoring unknown command %s", command)
      return
    end
    handler(link, link.Owner, aimParameter:get(), targetParameter:get())
  end)

  -- Runs on the owning player's machine
  RegisterCustomEvent("EntityClientEvent", function(_, kindParameter, valueParameter)
    local kind = kindParameter:get():ToString()
    local handler = clientEventHandlers[kind]
    if not handler then
      game.log("Ignoring unknown client event %s", kind)
      return
    end
    handler(valueParameter:get())
  end)

  RegisterCustomEvent("EntityClientPing", function(_, locationParameter, loudnessParameter, kindParameter)
    if not pingHandler then
      return
    end
    local location = locationParameter:get()
    pingHandler({ X = location.X, Y = location.Y, Z = location.Z }, loudnessParameter:get(),
      kindParameter:get():ToString())
  end)
end

return links
