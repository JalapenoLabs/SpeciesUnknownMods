-- Copyright © 2026 Jalapeno Labs

-- A stand-in for the parts of UE4SS and the game that the mod touches, so its scripts can run outside the game.
-- Objects record every method the mod calls on them (`calls`), and the test drives hooks, events and timers by
-- hand. This proves the mod's wiring and call shapes; it can't prove the game behaves as the stand-in does.

local fake = {
  hooks = {},
  watchers = {},
  customEvents = {},
  keybinds = {},
  loops = {},
  frameQueue = {},
  objects = {},
  instances = {},
  -- Each class's default object (UClass:GetCDO), by class name; an empty one unless a test gives its own.
  classDefaults = {},
  calls = {},
  isHost = true,
  now = 0,
}

local nextAddress = 1000

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Objects
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

-- A hook parameter: get reads it, and set changes it, as a pre-hook on a native function may.
function fake.param(value)
  local parameter = { value = value }
  parameter.get = function() return parameter.value end
  parameter.set = function(_, newValue) parameter.value = newValue end
  return parameter
end

function fake.name(text)
  return { ToString = function() return text end }
end

-- A game object of `className` (also findable under each name in `alsoKnownAs`, like a base class). Methods listed
-- in `methods` run; any other method called on it is recorded and returns nothing.
function fake.object(className, fields, methods, alsoKnownAs)
  nextAddress = nextAddress + 1
  local address = nextAddress
  local object = fields or {}
  local classInfo = {
    GetFName = function() return fake.name(className) end,
    GetAddress = function() return address end,
    GetCDO = function() return fake.classDefaults[className] or {} end,
  }
  local builtins = {
    IsValid = function() return object.destroyed ~= true end,
    GetAddress = function() return address end,
    GetClass = function() return classInfo end,
    HasAuthority = function() return fake.isHost end,
    GetWorld = function() return fake.world end,
  }

  setmetatable(object, {
    __index = function(_, key)
      local builtin = builtins[key] or (methods and methods[key])
      if builtin then
        return builtin
      end
      if type(key) == "string" and key:match("^%u") then
        return function(self, ...)
          table.insert(fake.calls, { object = self, method = key, args = { ... } })
          if key == "K2_DestroyActor" then
            self.destroyed = true
          end
          -- One value, like a real call: Lua treats "no value" and nil differently in places such as tostring()
          return nil
        end
      end
      return nil
    end,
  })

  for _, name in ipairs({ className, table.unpack(alsoKnownAs or {}) }) do
    fake.instances[name] = fake.instances[name] or {}
    table.insert(fake.instances[name], object)
  end
  return object
end

function fake.invalid()
  return setmetatable({}, { __index = function(_, key)
    if key == "IsValid" then
      return function() return false end
    end
    return function() end
  end })
end

function fake.array(elements)
  local array = { elements = elements }
  return setmetatable(array, {
    __len = function(self) return #self.elements end,
    __index = {
      GetArrayNum = function(self) return #self.elements end,
      ForEach = function(self, callback)
        for index, element in ipairs(self.elements) do
          if callback(index, fake.param(element)) then
            break
          end
        end
      end,
    },
  })
end

-- Gives a fake player controller what the camera code reads: the game's camera manager, with its cached crew body
-- (Player) and its BPI_CameraPlayer_ResetPlayer, and a view target that follows SetViewTargetWithBlend the way the
-- engine's does. `crewBody` starts cached, as after the crew character was possessed. The manager's look limit starts
-- at its class default, the engine's.
function fake.giveView(controller, crewBody)
  fake.classDefaults.Character_CameraBP_C = { ViewPitchMin = -89.9 }
  local manager = fake.object("Character_CameraBP_C", { Player = crewBody or fake.invalid(), ViewPitchMin = -89.9 }, {
    GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end,
  })
  -- As the game's: follow the pawn, and cache it only when it is a crew character
  manager.BPI_CameraPlayer_ResetPlayer = function(self, pawn)
    table.insert(fake.calls, { object = self, method = "BPI_CameraPlayer_ResetPlayer", args = { pawn } })
    controller:SetViewTargetWithBlend(pawn, 0, 0, 0, false)
    local isCrew = pawn:GetClass():GetFName():ToString() == "BP_Character_C"
    self.Player = isCrew and pawn or fake.invalid()
  end
  controller.PlayerCameraManager = manager
  controller.viewTarget = fake.invalid()
  controller.GetViewTarget = function(self) return self.viewTarget end
  controller.SetViewTargetWithBlend = function(self, target, ...)
    table.insert(fake.calls, { object = self, method = "SetViewTargetWithBlend", args = { target, ... } })
    self.viewTarget = target
  end
end

-- Gives a fake squid the state the mod reads from it, as the game's. Its speed: GetSpeedByType answers 400 plus the
-- speed type through its out parameter, and SetSpeed sets the walk speed and half of it crouched (calls are recorded).
-- Its health: both pools full, standing.
function fake.giveSquidState(squid)
  squid.Health, squid.MaxHealth = 100, 100
  squid.HealthTemporal, squid.MaxHealthTemporal = 60, 60
  squid.IsOnGround = false
  squid.CharacterMovement = fake.object("CharacterMovementComponent", { MaxWalkSpeed = 0, MaxWalkSpeedCrouched = 0 })
  squid.BPI_Monster_GetSpeedByType = function(_, speedType, out) out.Speed = 400 + speedType end
  squid.BPI_Monster_SetSpeed = function(self, speed)
    table.insert(fake.calls, { object = self, method = "BPI_Monster_SetSpeed", args = { speed } })
    self.CharacterMovement.MaxWalkSpeed = speed
    self.CharacterMovement.MaxWalkSpeedCrouched = speed / 2
  end
end

-- A fake WBP_EntityHUD with every element the HUD module reaches by name; each element has a fake canvas Slot.
function fake.entityHud()
  local function element(name)
    return fake.object(name, { Slot = fake.object(name .. "Slot") })
  end
  -- A key glyph's image sits in a fixed space (a size box, as in the HUD's layout)
  local function keyGlyph(name, width, height)
    local space = fake.object("SizeBox", { WidthOverride = width, HeightOverride = height })
    return fake.object(name, { Slot = fake.object(name .. "Slot") }, { GetParent = function() return space end })
  end
  local widget = fake.object("WBP_EntityHUD_C")
  local parts = {
    "Actions", "HealthBar", "StaminaBar", "ViewCone", "Hints", "PeekHint", "ViewHint", "FrenzyText", "StatusText",
    "VentTime", "VentTimeBar", "RespawnsText",
  }
  for _, name in ipairs(parts) do
    widget[name] = element(name)
  end
  for _, prefix in ipairs({ "Primary", "Secondary", "Ultimate", "Mobility" }) do
    for _, part in ipairs({ "Slot", "Icon", "Bar" }) do
      widget[prefix .. part] = element(prefix .. part)
    end
    widget[prefix .. "Key"] = keyGlyph(prefix .. "Key", 72, 32)
  end
  widget.PeekHintKey = keyGlyph("PeekHintKey", 44, 22)
  widget.ViewHintKey = keyGlyph("ViewHintKey", 44, 22)
  for pingIndex = 0, 11 do
    widget["Ping" .. pingIndex] = element("Ping" .. pingIndex)
  end
  return widget
end

-- Lets a fake actor take runtime components (AActor.AddComponentByClass), as the camera rig needs. Returns the list
-- the components are added to.
function fake.acceptComponents(actor)
  local components = {}
  local byClass = {}
  actor.AddComponentByClass = function(_, class)
    local component = fake.object("Component")
    table.insert(components, component)
    byClass[class] = byClass[class] or component
    return component
  end
  actor.GetComponentByClass = function(_, class)
    return byClass[class] or fake.invalid()
  end
  return components
end

-- Makes the mod's pak assets loadable the way the game would: through AssetRegistryHelpers.GetAsset, by package
-- and asset name. Returns each asset object by its mod asset key.
function fake.installModPak(modAssets)
  local classes = {}
  local classByPackage = {}
  for key, modAsset in pairs(modAssets) do
    classes[key] = fake.object(modAsset.name .. "_Class")
    classByPackage[modAsset.package .. "." .. modAsset.name] = classes[key]
  end
  fake.objects["/Script/AssetRegistry.Default__AssetRegistryHelpers"] = fake.object("AssetRegistryHelpers", nil, {
    GetAsset = function(_, assetData)
      return classByPackage[assetData.PackageName:ToString() .. "." .. assetData.AssetName:ToString()] or fake.invalid()
    end,
  })
  return classes
end

-- Calls recorded on `object` for `method`, in order.
function fake.callsTo(object, method)
  local matching = {}
  for _, call in ipairs(fake.calls) do
    if call.object == object and call.method == method then
      table.insert(matching, call)
    end
  end
  return matching
end

-- Pretends the class at `classPath` finished loading: its NotifyOnNewObject watchers fire.
function fake.loadClass(classPath, functionNames)
  local class = fake.object("Class")
  class.ForEachFunction = function(_, callback)
    for _, functionName in ipairs(functionNames or {}) do
      callback({ GetFName = function() return fake.name(functionName) end })
    end
  end
  fake.objects[classPath] = class
  for _, watcher in ipairs(fake.watchers[classPath] or {}) do
    watcher(fake.object("Instance"))
  end
end

-- Runs every timer once, or only those with `delayMilliseconds` when given.
function fake.runLoops(delayMilliseconds)
  for _, loop in ipairs(fake.loops) do
    if delayMilliseconds == nil or loop.delay == delayMilliseconds then
      loop.callback()
    end
  end
end

function fake.runFrames()
  local queued = fake.frameQueue
  fake.frameQueue = {}
  for _, callback in ipairs(queued) do
    callback()
  end
end

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- UE4SS globals
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

function fake.install()
  -- UMG's libraries, for any test whose player ends up with a HUD; a test that checks the HUD installs its own
  fake.objects["/Script/UMG.Default__WidgetBlueprintLibrary"] = fake.object("WidgetBlueprintLibrary", nil, {
    Create = function() return fake.entityHud() end,
  })
  fake.objects["/Script/UMG.Default__WidgetLayoutLibrary"] = fake.object("WidgetLayoutLibrary", nil, {
    GetViewportScale = function() return 1 end,
    GetViewportSize = function() return { X = 1920, Y = 1080 } end,
  })
  _G.FName = function(text) return fake.name(text) end
  _G.FText = function(text) return { text = text } end
  _G.Key = setmetatable({}, { __index = function(_, key) return key end })
  _G.RegisterHook = function(path, callback) fake.hooks[path] = callback end
  _G.NotifyOnNewObject = function(path, callback)
    fake.watchers[path] = fake.watchers[path] or {}
    table.insert(fake.watchers[path], callback)
  end
  _G.RegisterCustomEvent = function(name, callback) fake.customEvents[name] = callback end
  _G.RegisterKeyBind = function(key, callback) fake.keybinds[key] = callback end
  _G.ExecuteInGameThread = function(callback) callback() end
  _G.ExecuteInGameThreadAfterFrames = function(_, callback) table.insert(fake.frameQueue, callback) end
  _G.LoopInGameThreadWithDelay = function(delay, callback)
    table.insert(fake.loops, { delay = delay, callback = callback })
  end
  _G.LoadAsset = function() end
  _G.StaticFindObject = function(path) return fake.objects[path] end
  _G.FindAllOf = function(name)
    local live = {}
    for _, object in ipairs(fake.instances[name] or {}) do
      if object.destroyed ~= true then
        table.insert(live, object)
      end
    end
    return #live > 0 and live or nil
  end
  _G.FindFirstOf = function(name)
    local all = FindAllOf(name)
    return all and all[1] or fake.invalid()
  end
end

return fake
