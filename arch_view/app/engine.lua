local build = require("arch_view.build")
local common = require("arch_view.common")
local go_bridge = require("arch_view.app.go_bridge")
local paths = require("arch_view.app.paths")

local engine = {}
local _warnings = {}

local function _text(zh, en)
  return common.bilingual(zh, en)
end

local function _warn_once(key, message)
  if _warnings[key] then
    return
  end
  _warnings[key] = true
  io.stderr:write(message, "\n")
end

local function _lua_analyze(resolved)
  local architecture, err = build.analyze(resolved.config, {
    project_root = resolved.project_root,
    config_path = resolved.config_path,
  })
  if architecture == nil then
    return nil, err
  end
  return architecture, "lua"
end

local function _go_analyze(resolved)
  local architecture, binary_path_or_err = go_bridge.analyze({
    project_root = resolved.project_root,
    config_path = resolved.config_path,
    config = resolved.config,
  }, {
    package_root = resolved.package_root or paths.package_root(),
    toolchain_root = resolved.toolchain_root,
  })
  if architecture == nil then
    return nil, binary_path_or_err
  end
  return architecture, "go", binary_path_or_err
end

function engine.analyze(resolved)
  local requested = tostring(resolved.engine or "auto")
  if requested == "lua" then
    return _lua_analyze(resolved)
  end
  if requested == "go" then
    local architecture, err, binary_path = _go_analyze(resolved)
    if architecture == nil then
      return nil, err
    end
    return architecture, "go", binary_path
  end

  local architecture, go_err, binary_path = _go_analyze(resolved)
  if architecture ~= nil then
    return architecture, "go", binary_path
  end

  _warn_once("go_fallback", _text(
    "警告: Go 分析引擎不可用，回退到 Lua 实现。原因: " .. tostring(go_err),
    "Warning: Go analysis engine unavailable, falling back to Lua implementation. Reason: " .. tostring(go_err)
  ))

  local lua_architecture, lua_err = _lua_analyze(resolved)
  if lua_architecture == nil then
    return nil, lua_err
  end
  return lua_architecture, "lua"
end

function engine.check(resolved)
  local requested = tostring(resolved.engine or "auto")
  local request = {
    project_root = resolved.project_root,
    config_path = resolved.config_path,
    config = resolved.config,
  }

  if requested == "lua" then
    local architecture, err = _lua_analyze(resolved)
    if architecture == nil then
      return nil, err
    end
    return architecture.check, "lua"
  end

  if requested == "go" then
    local check_result, err = go_bridge.check(request, {
      package_root = resolved.package_root or paths.package_root(),
      toolchain_root = resolved.toolchain_root,
    })
    if check_result == nil then
      return nil, err
    end
    return check_result, "go"
  end

  local check_result, go_err = go_bridge.check(request, {
    package_root = resolved.package_root or paths.package_root(),
    toolchain_root = resolved.toolchain_root,
  })
  if check_result ~= nil then
    return check_result, "go"
  end

  _warn_once("go_check_fallback", _text(
    "警告: Go 检查引擎不可用，回退到 Lua 实现。原因: " .. tostring(go_err),
    "Warning: Go check engine unavailable, falling back to Lua implementation. Reason: " .. tostring(go_err)
  ))

  local architecture, lua_err = _lua_analyze(resolved)
  if architecture == nil then
    return nil, lua_err
  end
  return architecture.check, "lua"
end

return engine
