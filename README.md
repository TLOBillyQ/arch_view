# arch_view

`arch_view` is a Lua integration layer with a **Go-only core engine** for module-level `require` graph analysis.

- **Lua** handles host integration, CLI entry, and compatibility shims.
- **Go** is the single source of truth for scan, extraction, classification, checking, projection, layout, routing, and export data generation.

---

## What it provides

- Static scan of Lua source trees into a module dependency graph
- Rule-based component classification and forbidden dependency checks
- Projection views and layout metadata for graph exploration
- Self-contained viewer export with no external font/CDN dependency
- Stable Lua-facing API and CLI, backed by the Go core

---

## Engine model

`arch_view` now uses **Go as the only runtime analysis engine**.

- `engine="auto"` → resolves to Go
- `engine="go"` → Go
- `engine="lua"` → **deprecated and no longer supported** (returns an explicit error)

If you still pass `engine="lua"`, migrate to `engine="go"` or `engine="auto"`.

---

## Repository layout

- `arch_view.lua`: canonical public API entrypoint (`require("arch_view")`)
- `arch_view/app/*`: config loading, Go bridge, service orchestration, CLI wiring
- `arch_view/*.lua`: compatibility and helper modules
- `internal/archcore/*`: Go core implementation
- `cmd/archview-core`: Go CLI entrypoint used by the Lua bridge
- `bin/arch_view.lua`: standalone CLI entrypoint
- `viewer/*`: bundled static viewer assets copied to export directory
- `examples/*`: sample config and vendored-host usage
- `tests/*`: Lua contract/integration tests

---

## Quick start

Create `arch_view.config.json` in your project root:

```/dev/null/arch_view.config.json#L1-12
{
  "source_roots": ["src"],
  "component_rules": [
    { "name": "demo", "match": ["^src%.demo$", "^src%.demo%..+"], "component": "demo" }
  ],
  "abstract_rules": [],
  "forbidden_dependency_rules": []
}
```

Run:

```/dev/null/commands.sh#L1-3
lua bin/arch_view.lua scan --out .arch_view/architecture.json
lua bin/arch_view.lua check
lua bin/arch_view.lua viewer --out-dir .arch_view/viewer
```

If no command is provided, `lua bin/arch_view.lua` defaults to `viewer --open`.

---

## CLI

```/dev/null/cli_usage.txt#L1-4
lua bin/arch_view.lua scan --out <file> [--project-root <dir>] [--config <file>] [--engine <auto|go|lua>]
lua bin/arch_view.lua check [--project-root <dir>] [--config <file>] [--engine <auto|go|lua>]
lua bin/arch_view.lua viewer [--out-dir <dir>] [--project-root <dir>] [--config <file>] [--in-json <file>] [--engine <auto|go|lua>] [--open]
lua bin/arch_view.lua
```

> Note: `--engine lua` is deprecated/unsupported and will fail explicitly.

---

## Public API

Use `require("arch_view")` as the stable entrypoint:

```/dev/null/public_api.lua#L1-20
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
- `config`: in-memory config table
- `config_path`: config file path; defaults to `<project_root>/arch_view.config.json`
- `engine`: `auto` or `go` (`lua` deprecated/unsupported)
- `out_path`: output path for `write_scan`
- `out_dir`: export directory for `export_viewer`
- `in_json`: existing architecture JSON for `export_viewer`
- `open`: open exported viewer after generation
- `asset_root`: override viewer asset directory
- `toolchain_root`: override Go binary cache directory
- `open_path`: inject a custom opener

---

## Go core and toolchain behavior

- Core source: `internal/archcore`, entrypoint: `cmd/archview-core`
- Lua bridge builds binary on demand:
  - `go build -o <project>/.arch_view/toolchain/<goos>-<goarch>/archview-core ./cmd/archview-core`
- Cached binary is reused until Go sources/deps change
- A working local Go toolchain is required for runtime analysis/export

---

## Compatibility notes

Legacy imports remain available as compatibility layers:

- `require("arch_view.build")`
- `require("arch_view.cli")`

Some legacy Lua core modules may still exist during transition, but the main execution path is Go-only. New code should not depend on Lua core internals.

---

## Vendoring into another repo

```/dev/null/vendor_host.lua#L1-8
package.path = table.concat({
  "vendor/arch_view/?.lua",
  "vendor/arch_view/?/?.lua",
  package.path,
}, ";")

local arch_view = require("arch_view")
```

See `examples/vendor_host.lua` for a complete example.

---

## Tests

```/dev/null/test_commands.sh#L1-2
lua tests/run.lua
go test ./...
```

---

## Migration summary

If you are migrating from the old dual-engine behavior:

1. Replace any `engine="lua"` usage with `engine="auto"` or `engine="go"`.
2. Keep existing public API entrypoints; they remain compatible.
3. Treat Lua modules as integration/compatibility layers, not analysis cores.