# arch_view

`arch_view` is a standalone Lua static architecture scanner for module-level `require` graphs.

## Layout

- `arch_view/*.lua`: reusable scanner, checker, projection, layout, JSON, and CLI modules
- `viewer/*`: static viewer assets copied into exported reports
- `tests/run.lua`: minimal contract/smoke suite for the standalone repo

## Run tests

```sh
lua tests/run.lua
```

## Consume from another repo

Add the repo to `package.path` and require `arch_view.cli` or `arch_view.build`. Host repos can provide:

- `env.script_dir`: tool root that contains `viewer/*`
- `env.default_project_root`: default scan root
- `env.default_config_path`: host-specific config path

Monopoly uses this repo as a git submodule under `vendor/arch_view` and keeps its own `scripts/arch/config.lua` plus generated viewer snapshots.
