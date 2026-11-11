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
-- Event kind -> list of function(value), run on the player's own machine. Several modules react to the same event
-- (the HUD and the controls both care that the player became the entity).
local clientEventHandlers = {}
local pingHandler = nil

-- Host: link per controller, keyed by the controller's address (a controller's Lua wrapper is not stable):
-- { actor, spawnedOnPass }. Reconcile passes are counted so a link can be given a pass to replicate.
local linkByControllerAddress = {}
local reconcilePass = 0

function links.onCommand(command, handler)
  commandHandlers[command] = handler
end

function links.onClientEvent(kind, handler)
  clientEventHandlers[kind] = clientEventHandlers[kind] or {}
  table.insert(clientEventHandlers[kind], handler)
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

  reconcilePass = reconcilePass + 1
  local liveAddresses = {}
  for _, controller in ipairs(FindAllOf("PlayerController") or {}) do
    if controller:IsValid() then
      local address = controller:GetAddress()
      liveAddresses[address] = true
      local entry = linkByControllerAddress[address]
      if not entry or not entry.actor:IsValid() then
        local link = controller:GetWorld():SpawnActor(linkClass, controller:K2_GetActorLocation(), {})
        link:SetOwner(controller)
        linkByControllerAddress[address] = { actor = link, spawnedOnPass = reconcilePass }
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
  local entry = linkByControllerAddress[controller:GetAddress()]
  if not entry or not entry.actor:IsValid() then
    return nil
  end
  return entry.actor
end

-- Whether the controller's link has existed for a full reconcile pass. An event sent to a client on an actor that
-- hasn't replicated to it yet has nowhere to arrive, so one-off announcements wait for this.
function links.isEstablished(controller)
  local entry = linkByControllerAddress[controller:GetAddress()]
  return entry ~= nil and entry.actor:IsValid() and entry.spawnedOnPass < reconcilePass
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
    local handlers = clientEventHandlers[kind]
    if not handlers then
      game.log("Ignoring unknown client event %s", kind)
      return
    end
    -- Each module's handler runs on its own: in playtest 3 the camera's handler failed on the takeover and took the
    -- HUD's down with it, so the HUD never learned the player was the entity
    local value = valueParameter:get()
    for _, handler in ipairs(handlers) do
      local ok, failure = pcall(handler, value)
      if not ok then
        game.log("A handler for client event %s failed: %s", kind, tostring(failure))
      end
    end
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
