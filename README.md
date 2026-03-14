# arch_view

`arch_view` is a standalone Lua architecture scanner for module-level `require` graphs.
It is designed to be vendored into another repo or run directly as a small CLI tool.

## What it provides

- Static scan of Lua source trees into a module dependency graph
- Rule-based component classification and forbidden dependency checks
- Projection views and layout metadata for interactive graph exploration
- Self-contained viewer export with no external font or CDN dependency

## Repository layout

- `arch_view.lua`: canonical public API entrypoint (`require("arch_view")`)
- `arch_view/build.lua`: low-level analysis compatibility layer
- `arch_view/cli.lua`: compatibility CLI adapter for legacy host injection
- `arch_view/app/*`: config loading, viewer export, CLI wiring
- `arch_view/support/*`: runtime helpers for file/path/module resolution
- `arch_view/*.lua`: scanner, checker, projection, layout, JSON, and shared primitives
- `bin/arch_view.lua`: standalone CLI entrypoint
- `viewer/*`: bundled static viewer assets copied into exported reports
- `examples/*`: sample config and vendored-host usage

## Quick start

Create `arch_view.config.lua` in the project root:

```lua
return {
  source_roots = { "src" },
  component_rules = {
    { name = "demo", match = { "^src%.demo$", "^src%.demo%..+" }, component = "demo" },
  },
  abstract_rules = {},
  forbidden_dependency_rules = {},
}
```

Then run:

```sh
lua bin/arch_view.lua scan --out .arch_view/architecture.json
lua bin/arch_view.lua check
lua bin/arch_view.lua viewer --out-dir .arch_view/viewer
```

If you omit the command, `lua bin/arch_view.lua` defaults to `viewer --open`.

## Public API

Use `require("arch_view")` as the stable entrypoint:

```lua
local arch_view = require("arch_view")

local architecture = assert(arch_view.analyze({
  project_root = ".",
  config_path = "arch_view.config.lua",
}))

assert(arch_view.write_scan({
  architecture = architecture,
  project_root = ".",
  config_path = "arch_view.config.lua",
  out_path = ".arch_view/architecture.json",
}))

assert(arch_view.export_viewer({
  architecture = architecture,
  project_root = ".",
  out_dir = ".arch_view/viewer",
}))
```

Available entrypoints:

- `load_config(path)`
- `analyze(opts)`
- `write_scan(opts)`
- `export_viewer(opts)`
- `run_cli(args, opts)`

Common `opts` fields:

- `project_root`: project root to scan; defaults to current working directory
- `config`: config table, if already loaded in memory
- `config_path`: config file path; defaults to `<project_root>/arch_view.config.lua`
- `out_path`: JSON output path for `write_scan`
- `out_dir`: viewer export directory for `export_viewer`
- `in_json`: existing architecture JSON for `export_viewer`
- `open`: open exported viewer after generation
- `asset_root`: override bundled viewer assets directory
- `open_path`: inject a custom file opener

## Vendoring into another repo

Add the repo to `package.path` and require `arch_view` directly:

```lua
package.path = table.concat({
  "vendor/arch_view/?.lua",
  "vendor/arch_view/?/?.lua",
  package.path,
}, ";")

local arch_view = require("arch_view")
```

See `examples/vendor_host.lua` for a complete example.

## Compatibility notes

Legacy imports still work, but they are compatibility layers now:

- `require("arch_view.build")`
- `require("arch_view.cli")`

The old injected CLI defaults (`env.script_dir`, `env.default_project_root`, `env.default_config_path`) are still accepted through `arch_view.cli`, but new code should pass explicit `project_root`, `config_path`, and `asset_root` instead.

## Tests

```sh
lua tests/run.lua
```
