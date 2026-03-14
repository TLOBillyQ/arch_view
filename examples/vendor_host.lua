package.path = table.concat({
  "vendor/arch_view/?.lua",
  "vendor/arch_view/?/?.lua",
  package.path,
}, ";")

local arch_view = require("arch_view")

local architecture, err = arch_view.analyze({
  project_root = ".",
  config_path = "arch_view.config.json",
})

if architecture == nil then
  error(err)
end

local result = assert(arch_view.export_viewer({
  architecture = architecture,
  project_root = ".",
  out_dir = ".arch_view/viewer",
}))

print("arch_view viewer ok: " .. tostring(result.out_dir))
