local build = require("arch_view.build")
local common = require("arch_view.common")
local fs = require("arch_view.support.fs")

local config = {}

local function _text(zh, en)
  return common.bilingual(zh, en)
end

function config.default_path(project_root)
  return fs.join_path(project_root, "arch_view.config.lua")
end

function config.load(path)
  local chunk, err = loadfile(path)
  if not chunk then
    return nil, err
  end
  local loaded = chunk()
  if type(loaded) ~= "table" then
    return nil, _text(
      "架构配置无效: " .. tostring(path),
      "Invalid architecture config: " .. tostring(path)
    )
  end
  local ok, validate_err = build.validate_config(loaded)
  if not ok then
    return nil, validate_err
  end
  return loaded
end

function config.resolve(opts)
  opts = opts or {}
  local project_root = fs.resolve_path(fs.current_dir(), opts.project_root or fs.current_dir())
  if opts.config ~= nil then
    local ok, err = build.validate_config(opts.config)
    if not ok then
      return nil, err
    end
    return {
      project_root = project_root,
      config = opts.config,
      config_path = opts.config_path and fs.resolve_path(fs.current_dir(), opts.config_path) or nil,
    }
  end

  local config_path = opts.config_path and fs.resolve_path(fs.current_dir(), opts.config_path)
    or config.default_path(project_root)

  if not fs.path_exists(config_path) then
    return nil, _text(
      "未找到架构配置: " .. tostring(config_path),
      "Missing architecture config: " .. tostring(config_path)
    )
  end

  local loaded, err = config.load(config_path)
  if loaded == nil then
    return nil, err
  end

  return {
    project_root = project_root,
    config = loaded,
    config_path = config_path,
  }
end

return config
