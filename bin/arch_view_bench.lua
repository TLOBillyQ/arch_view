#!/usr/bin/env lua

local function normalize_path(path)
  return tostring(path or ""):gsub("\\", "/")
end

local function parent_dir(path)
  local normalized = normalize_path(path)
  return normalized:match("^(.*)/[^/]+$")
end

local function append_path(path_pattern)
  if not tostring(package.path):find(path_pattern, 1, true) then
    package.path = package.path .. ";" .. path_pattern
  end
end

local source = debug.getinfo(1, "S").source or ""
if source:sub(1, 1) == "@" then
  source = source:sub(2)
end
local script_dir = parent_dir(normalize_path(source)) or "."
local repo_root = parent_dir(script_dir) or "."
append_path(repo_root .. "/?.lua")
append_path(repo_root .. "/?/?.lua")

local arch_view = require("arch_view")
local core_bridge = require("arch_view.internal.core_bridge")
local common = require("arch_view.runtime.common")
local json_writer = require("arch_view.runtime.json_writer")

local project_root = arg[1] or "."
local config_path = arg[2] or common.join_path(project_root, "arch_view.config.json")
local iterations = tonumber(arg[3]) or 3

local function bench_api(engine_name)
  local started = os.clock()
  for _ = 1, iterations do
    local architecture, err = arch_view.analyze({
      project_root = project_root,
      config_path = config_path,
      engine = engine_name,
    })
    if architecture == nil then
      error(err)
    end
  end
  return (os.clock() - started) / iterations
end

for _, engine_name in ipairs({ "go", "auto" }) do
  local avg = bench_api(engine_name)
  io.write(string.format("%s avg: %.3f ms\n", engine_name, avg * 1000.0))
end

local config = assert(arch_view.load_config(config_path))
local binary = assert(core_bridge.ensure_binary(common.resolve_path(common.current_dir(), project_root)))
local request_path = common.make_temp_path("archview_bench", ".json")
assert(common.write_file(request_path, json_writer.encode({
  project_root = common.resolve_path(common.current_dir(), project_root),
  config_path = common.resolve_path(common.current_dir(), config_path),
  config = config,
})))

local function bench_go_core()
  local started = os.clock()
  for _ = 1, iterations do
    local result = common.run_command({
      binary,
      "analyze",
      "--request",
      request_path,
    }, {
      cwd = project_root,
    })
    if not result.ok then
      error(result.output)
    end
    assert(result.output ~= nil and result.output ~= "")
  end
  return (os.clock() - started) / iterations
end

local avg = bench_go_core()
io.write(string.format("go-core avg: %.3f ms\n", avg * 1000.0))
common.remove_path(request_path)
