local M = {}

local _paths_installed = false

local function _is_absolute(path)
  path = tostring(path or "")
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
end

local function _normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  local prefix = ""
  if path:sub(1, 1) == "/" then
    prefix = "/"
    path = path:sub(2)
  elseif path:match("^%a:/") then
    prefix = path:sub(1, 3)
    path = path:sub(4)
  end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then
        parts[#parts] = nil
      elseif prefix == "" then
        parts[#parts + 1] = part
      end
    elseif part ~= "." and part ~= "" then
      parts[#parts + 1] = part
    end
  end
  local joined = table.concat(parts, "/")
  if prefix == "" then
    return joined == "" and "." or joined
  end
  return joined == "" and prefix:gsub("/$", "") or (prefix .. joined)
end

local function _current_dir()
  local pwd = os.getenv("PWD")
  if pwd and pwd ~= "" then
    return pwd
  end
  local handle = assert(io.popen("pwd", "r"))
  local output = handle:read("*l")
  handle:close()
  return output
end

local function _dirname(path)
  path = _normalize(path):gsub("/+$", "")
  return path:match("^(.*)/[^/]+$") or "."
end

local function _script_path()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  if not _is_absolute(source) then
    source = _current_dir() .. "/" .. source
  end
  return _normalize(source)
end

M.test_root = _dirname(_script_path())
M.project_root = _dirname(M.test_root)

local function _append_path(path_pattern)
  if not tostring(package.path):find(path_pattern, 1, true) then
    package.path = package.path .. ";" .. path_pattern
  end
end

function M.install_package_paths()
  if _paths_installed then
    return
  end

  _append_path(M.project_root .. "/lib/?.lua")
  _append_path(M.project_root .. "/lib/?/init.lua")
  _append_path(M.project_root .. "/?.lua")
  _append_path(M.test_root .. "/?.lua")

  _paths_installed = true
end

M.install_package_paths()

return M
