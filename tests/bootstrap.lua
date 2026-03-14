local M = {}

local _paths_installed = false

local function _append_path(path_pattern)
  if not tostring(package.path):find(path_pattern, 1, true) then
    package.path = package.path .. ";" .. path_pattern
  end
end

function M.install_package_paths()
  if _paths_installed then
    return
  end

  _append_path("./?.lua")
  _append_path("./?/?.lua")
  _append_path("./tests/?.lua")

  _paths_installed = true
end

M.install_package_paths()

return M
