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
  calls = {},
  isHost = true,
  now = 0,
}

local nextAddress = 1000

-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --
-- Objects
-- //////////////////////////////////////////////////////////////////////////////////////////////////////////// --

function fake.param(value)
  return { get = function() return value end }
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

-- Gives a fake player controller what the camera code reads: a camera manager, and a view target that follows
-- SetViewTargetWithBlend the way the engine's does.
function fake.giveView(controller, cameraManager)
  controller.PlayerCameraManager = cameraManager or fake.object("PlayerCameraManager", { FreeCamDistance = 256 }, {
    GetCameraLocation = function() return { X = 0, Y = 0, Z = 0 } end,
  })
  controller.viewTarget = fake.invalid()
  controller.GetViewTarget = function(self) return self.viewTarget end
  controller.SetViewTargetWithBlend = function(self, target, ...)
    table.insert(fake.calls, { object = self, method = "SetViewTargetWithBlend", args = { target, ... } })
    self.viewTarget = target
  end
end

-- Makes the mod's pak classes loadable the way the game would: through AssetRegistryHelpers.GetAsset, by package
-- and class name. Returns each class object by its mod class key.
function fake.installModPak(modClasses)
  local classes = {}
  local classByPackage = {}
  for key, modClass in pairs(modClasses) do
    classes[key] = fake.object(modClass.class .. "_Class")
    classByPackage[modClass.package .. "." .. modClass.class] = classes[key]
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
