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
- `arch_view/cli.lua`: public CLI facade (`require("arch_view.cli")`)
- `arch_view/internal/*`: config loading, core bridge, service orchestration, CLI wiring
- `arch_view/runtime/*`: host/runtime helpers for filesystem, JSON, and path handling
- `internal/core/*`: Go core implementation
- `cmd/arch-view-core`: Go CLI entrypoint used by the Lua bridge
- `bin/arch_view.lua`: standalone CLI entrypoint
- `viewer/*`: bundled static viewer assets copied to export directory
- `examples/*`: sample config and vendored-host usage
- `tests/*`: Lua contract/integration tests
- `docs/architecture/go-first-refactor.md`: architecture notes for the Go-first layout

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
- `check(opts)`
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

- Core source: `internal/core`, entrypoint: `cmd/arch-view-core`
- Lua bridge builds binary on demand:
  - `go build -o <project>/.arch_view/toolchain/<goos>-<goarch>/arch-view-core ./cmd/arch-view-core`
- Cached binary is reused until Go sources/deps change
- A working local Go toolchain is required for runtime analysis/export

---

## Compatibility notes

- Supported public entrypoints remain:
  - `require("arch_view")`
  - `require("arch_view.cli")`
- Internal Lua module paths are intentionally private to this repository layout. Depend on the public API only.

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

---

## 中文文档

`arch_view` 是一个用于模块级 `require` 依赖图分析的 Lua 集成层，核心引擎完全由 **Go** 实现。

- **Lua** 负责宿主集成、CLI 入口和兼容性封装。
- **Go** 是扫描、提取、分类、检查、投影、布局、路由和导出数据生成的唯一真实来源。

### 主要功能

- 将 Lua 源代码树静态扫描为模块依赖图
- 基于规则的组件分类和禁止依赖检查
- 投影视图和布局元数据，用于图探索
- 独立的查看器导出，无外部字体/CDN 依赖
- 稳定的 Lua 面向 API 和 CLI，由 Go 核心支持

### 引擎模型

`arch_view` 现在使用 **Go 作为唯一的运行时分析引擎**。

- `engine="auto"` → 解析为 Go
- `engine="go"` → Go
- `engine="lua"` → **已弃用且不再支持**（返回显式错误）

### 快速开始

在项目根目录创建 `arch_view.config.json`：

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

运行：

```bash
lua bin/arch_view.lua scan --out .arch_view/architecture.json
lua bin/arch_view.lua check
lua bin/arch_view.lua viewer --out-dir .arch_view/viewer
```

### CLI 命令

```bash
lua bin/arch_view.lua scan --out <file> [--project-root <dir>] [--config <file>] [--engine <auto|go|lua>]
lua bin/arch_view.lua check [--project-root <dir>] [--config <file>] [--engine <auto|go|lua>]
lua bin/arch_view.lua viewer [--out-dir <dir>] [--project-root <dir>] [--config <file>] [--in-json <file>] [--engine <auto|go|lua>] [--open]
```
