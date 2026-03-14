# arch_view

`arch_view` is a standalone Lua architecture scanner for module-level `require` graphs.
It keeps the viewer and host-facing Lua API, while the default analysis core runs through a Go engine.

## What it provides

- Static scan of Lua source trees into a module dependency graph
- Rule-based component classification and forbidden dependency checks
- Projection views and layout metadata for interactive graph exploration
- Self-contained viewer export with no external font or CDN dependency
- Dual-engine analysis: `auto` (default), `go`, or `lua`

## Repository layout

- `arch_view.lua`: canonical public API entrypoint (`require("arch_view")`)
- `arch_view/app/*`: config loading, engine bridge, viewer export, CLI wiring
- `arch_view/*.lua`: Lua fallback engine and shared runtime helpers
- `internal/archcore/*`: Go analysis core
- `cmd/archview-core`: Go CLI entrypoint used by the Lua bridge
- `bin/arch_view.lua`: standalone CLI entrypoint
- `bin/arch_view_bench.lua`: quick benchmark helper for `lua` vs `go`
- `viewer/*`: bundled static viewer assets copied into exported reports
- `examples/*`: sample config and vendored-host usage

## Quick start

Create `arch_view.config.json` in the project root:

```json
{
  "source_roots": ["src"],
  "component_rules": [
    { "name": "demo", "match": ["^src%.demo$", "^src%.demo%..+"], "component": "demo" }
  ],
  "abstract_rules": [],
  "forbidden_dependency_rules": []
}
```

Then run:

```sh
lua bin/arch_view.lua scan --out .arch_view/architecture.json
lua bin/arch_view.lua check
lua bin/arch_view.lua viewer --out-dir .arch_view/viewer
```

If you omit the command, `lua bin/arch_view.lua` defaults to `viewer --open`.
By default the CLI uses `--engine auto`, which prefers the Go core, builds it into `/.arch_view/toolchain/...` when needed, and falls back to Lua only if Go is unavailable.

## Public API

Use `require("arch_view")` as the stable entrypoint:

```lua
local arch_view = require("arch_view")

local architecture = assert(arch_view.analyze({
  project_root = ".",
  config_path = "arch_view.config.json",
  engine = "auto",
}))

assert(arch_view.write_scan({
  architecture = architecture,
  project_root = ".",
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
- `config_path`: config file path; defaults to `<project_root>/arch_view.config.json`
- `engine`: `auto`, `go`, or `lua`
- `out_path`: JSON output path for `write_scan`
- `out_dir`: viewer export directory for `export_viewer`
- `in_json`: existing architecture JSON for `export_viewer`
- `open`: open exported viewer after generation
- `asset_root`: override bundled viewer assets directory
- `toolchain_root`: override the Go binary cache directory
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

## Go engine

- Source is committed under `internal/archcore` and `cmd/archview-core`
- The Lua bridge builds with `go build -o <host>/.arch_view/toolchain/<goos>-<goarch>/archview-core ./cmd/archview-core`
- `engine="go"` requires a working Go toolchain and never falls back
- `engine="auto"` prefers Go and falls back to Lua with a warning if build/run fails

## Benchmark

```sh
lua bin/arch_view_bench.lua /path/to/project /path/to/arch_view.config.json 5
```

## Compatibility notes

Legacy imports still work, but they are compatibility layers now:

- `require("arch_view.build")`
- `require("arch_view.cli")`

The old injected CLI defaults (`env.script_dir`, `env.default_project_root`, `env.default_config_path`) are still accepted through `arch_view.cli`, but new code should pass explicit `project_root`, `config_path`, `engine`, and `asset_root` instead.

## Tests

```sh
lua tests/run.lua
go test ./...
```
