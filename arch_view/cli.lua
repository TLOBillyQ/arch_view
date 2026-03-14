local app_cli = require("arch_view.app.cli")
local common = require("arch_view.common")

local cli = {}

local function _copy_args(args)
  return common.copy_array(args or {})
end

function cli.run(args, env)
  env = env or {}

  local opts = {
    cwd = env.cwd,
    open_path = env.open_path,
    default_project_root = env.default_project_root,
    default_config_path = env.default_config_path,
  }

  if env.script_dir ~= nil then
    opts.asset_root = common.join_path(env.script_dir, "viewer")
  end

  return app_cli.run(_copy_args(args), opts)
end

return cli
