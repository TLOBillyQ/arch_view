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
arch_view.run_cli(arg)
