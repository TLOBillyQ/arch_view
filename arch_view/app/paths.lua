local fs = require("arch_view.support.fs")
local module_path = require("arch_view.support.module_path")

local paths = {}

function paths.package_root()
  return module_path.package_root(2)
end

function paths.default_asset_root()
  return fs.join_path(paths.package_root(), "viewer")
end

function paths.default_viewer_out_dir(project_root)
  return fs.join_path(project_root, ".arch_view/viewer")
end

function paths.default_toolchain_root(project_root)
  return fs.join_path(project_root, ".arch_view/toolchain")
end

return paths
