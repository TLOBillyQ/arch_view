local fs = require("arch_view.runtime.fs")
local module_path = require("arch_view.runtime.module_path")

local paths = {}

function paths.package_root()
  local root = module_path.package_root(2)
  if tostring(root):match("/lib$") then
    return fs.parent_dir(root)
  end
  return root
end

function paths.default_asset_root()
  return fs.join_path(paths.package_root(), "viewer")
end

function paths.default_viewer_out_dir(project_root)
  return fs.join_path(project_root, ".arch_view/viewer")
end

return paths
