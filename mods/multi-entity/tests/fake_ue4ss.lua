-- Copyright © 2026 Jalapeno Labs

-- A stand-in for the parts of UE4SS and the game that Multi Entity touches, so its scripts run outside the game.
-- Objects record every method the mod calls on them (`calls`), and a test drives hooks, watchers and timers by hand.
-- It proves the mod's wiring and call shapes; only a playtest proves the game behaves as the stand-in does.

local fake = {
  hooks = {},
  watchers = {},
  loops = {},
  delayed = {},
  objects = {},
  instances = {},
  calls = {},
  isHost = true,
  now = 0,
}

local nextAddress = 1000

function fake.name(text)
  return { ToString = function() return text end, text = text }
end

-- A UE4SS hook parameter: get() reads the value, set() writes it back.
function fake.param(value)
  local param = { value = value }
  param.get = function() return param.value end
  param.set = function(_, newValue) param.value = newValue end
  return param
end

-- A game object of `className`, findable by that name and every name in `alsoKnownAs`. Methods in `methods` run
-- (ahead of the built-in IsValid, GetClass and the like); any other capitalised method is recorded in `fake.calls`
-- and returns nothing.
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
    GetFName = function() return fake.name(className) end,
    HasAuthority = function() return fake.isHost end,
  }

  setmetatable(object, {
    __index = function(_, key)
      local method = (methods and methods[key]) or builtins[key]
      if method then
        return method
      end
      if type(key) == "string" and key:match("^%u") then
        return function(self, ...)
          table.insert(fake.calls, { object = self, method = key, args = { ... } })
          if key == "K2_DestroyActor" then
            self.destroyed = true
          end
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

-- Blueprint arrays need no stand-in: UE4SS shows a TArray as 1-based, with `#` for its length, and a write one past
-- the end grows it, which is what a plain Lua table does.

-- A data table as UE4SS's UDataTable shows it: FindRow returns the row itself (by reference); AddRow copies the
-- given row under a new name, replacing any row of that name.
function fake.dataTable(name, rows)
  local dataTable = fake.object(name, { rows = rows or {} }, {
    FindRow = function(self, rowName) return self.rows[rowName] end,
    AddRow = function(self, rowName, row)
      local copy = {}
      for key, value in pairs(row) do
        copy[key] = value
      end
      self.rows[rowName] = copy
    end,
  })
  return dataTable
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

-- Pretends an instance of the class at `classPath` was created: the class object exists from now on, and its
-- NotifyOnNewObject watchers fire.
function fake.spawnInstanceOf(classPath)
  fake.objects[classPath] = fake.objects[classPath] or fake.object("Class:" .. classPath)
  for _, watcher in ipairs(fake.watchers[classPath] or {}) do
    watcher(fake.object("Instance"))
  end
end

-- Pretends a class finished loading without any instance of it (a function library).
function fake.loadClassQuietly(classPath)
  fake.objects[classPath] = fake.objects[classPath] or fake.object("Class:" .. classPath)
end

-- Runs a registered post-hook as UE4SS would after the game ran `functionPath`.
function fake.runHook(functionPath, ...)
  local hook = fake.hooks[functionPath]
  assert(hook, "no hook registered on " .. functionPath)
  hook(...)
end

function fake.runLoops()
  for _, loop in ipairs(fake.loops) do
    loop.callback()
  end
end

function fake.install()
  _G.FName = function(text) return fake.name(text) end
  _G.FText = function(text) return { text = text } end
  _G.RegisterHook = function(path, callback) fake.hooks[path] = callback end
  _G.NotifyOnNewObject = function(path, callback)
    fake.watchers[path] = fake.watchers[path] or {}
    table.insert(fake.watchers[path], callback)
  end
  _G.ExecuteInGameThread = function(callback) callback() end
  _G.ExecuteInGameThreadWithDelay = function(delay, callback)
    table.insert(fake.delayed, { delay = delay, callback = callback })
  end
  _G.LoopInGameThreadWithDelay = function(delay, callback)
    table.insert(fake.loops, { delay = delay, callback = callback })
  end
  _G.LoadAsset = function(path)
    table.insert(fake.calls, { method = "LoadAsset", args = { path } })
  end
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

  fake.objects["/Script/Engine.Default__GameplayStatics"] = fake.object("GameplayStatics", nil, {
    GetTimeSeconds = function() return fake.now end,
  })
  fake.object("BP_MyGameState_C", nil, nil, { "GameStateBase" })
end

return fake
