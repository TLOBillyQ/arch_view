# Go-First 重构计划

## 目标

- Lua 仅保留脚本接入与宿主集成
- 扫描、依赖提取、校验、布局、投影、路由、导出全部由 Go 实现
- 保留现有公共 API，逐步移除 Lua fallback

## 现状

**Go 核心已就绪**：`cmd/archview-core`, `internal/archcore/*`

**Lua 遗留代码**：
- `source_scan.lua`, `dependency_extract.lua`, `checker.lua`
- `layers.lua`, `projection.lua`, `layout_renderer.lua`, `route_engine.lua`
- `app/engine.lua`, `app/config.lua`, `app/service.lua`（需 Go 化）

## 原则

- **Lua 只保留接入层**：CLI 解析、宿主入口、Go 调用、文件读写、API 兼容层
- **Go 唯一事实来源**：配置校验、扫描、require 提取、分类、校验、环检测、投影、布局、路由、导出
- **兼容优先**：旧 API 保留为薄代理，逐步删除实现
- **分阶段**：先消除双实现，再收敛导出链路，最后清理遗留核心

## 目标架构

**保留的 Lua 模块**：`arch_view.lua`, `arch_view/cli.lua`, `arch_view/app/*`, `support/*`, `json_*.lua`

**Go 承担的能力**：config validate, analyze, check, scan export, viewer export

## 分阶段计划

### Phase 1：Go 唯一分析核心

**任务**：
- `engine.lua`：`auto` → Go；`lua` 模式返回错误
- `build.lua`：`analyze()` 调用 `go_bridge`；移除对 `source_scan/checker/layers/projection` 的依赖
- `config.lua`：仅保留 JSON 读取、基本类型检查、路径解析
- `service.lua`：`analyze/check/write_scan` 统一走 Go

**验收**：`engine=auto/go` 正常工作，`lua` 报错；旧 API 兼容；文档更新

### Phase 2：导出链路 Go 化

**任务**：
- Go CLI 增加 `export-viewer` 命令
- Go 侧完成：配置读取 → 生成 architecture → 输出 `architecture.json` + `architecture_data.js` → 拷贝 viewer 资源
- `service.export_viewer` 改为调用 Go 桥接

**验收**：viewer 导出不依赖 Lua 核心逻辑；产物兼容

### Phase 3：公共 API 收敛

**任务**：
- 保持 `require("arch_view")`, `require("arch_view.build")`, `require("arch_view.cli")`
- `build.lua`, `cli.lua` 改为参数转换 + 调用服务层
- README 标记 `engine=lua` 废弃

**验收**：对外 API 不变，内部完全走 Go

### Phase 4：删除 Lua 核心实现

**删除模块**：`source_scan.lua`, `dependency_extract.lua`, `checker.lua`, `layers.lua`, `projection.lua`, `layout_renderer.lua`, `route_engine.lua`

**步骤**：
1. 停止内部引用
2. 改为错误提示 stub（一个版本周期）
3. 删除文件

### Phase 5：测试与文档收敛

**Lua 测试**：公共 API 调用、CLI 参数、Go 桥接行为、错误消息

**Go 测试**：配置校验、扫描、require 提取、分类/校验、投影/布局/路由、viewer 导出

**文档更新**：明确 "Lua 接入层 + Go 核心"；移除双引擎描述；补充 Go 构建机制

## 风险

- **兼容性**：外部可能直接 `require` 内部模块 → 通过废弃周期处理
- **输出一致性**：确保 JSON 字段名、空值语义、排序、viewer 数据结构兼容
- **工具链**：运行依赖 Go toolchain → 需明确部署方案
- **调试体验**：外部进程错误定位变化 → 提升 stderr 输出、Lua 错误包装

## 里程碑

| 里程碑 | 状态 |
|--------|------|
| M1: analyze/check/write_scan 全走 Go | ✅ |
| M2: viewer 导出由 Go 主导 | ✅ |
| M3: 兼容层改为薄代理 | ✅ |
| M4: 删除 Lua 核心，文档收敛 | ✅ |

## 最终结构

```
arch_view/
├── app/
│   ├── cli.lua, config.lua, engine.lua, go_bridge.lua, paths.lua, service.lua
├── support/fs.lua, support/module_path.lua
├── common.lua, json_reader.lua, json_writer.lua
├── build.lua, cli.lua              # 薄代理
└── init.lua                        # 主入口

internal/archcore/                  # Go 核心
cmd/archview-core/                  # Go CLI
viewer/                             # 静态资源
tests/test_api.lua, test_cli.lua, test_go_bridge.lua
```

> Lua 负责"接入"，Go 负责"能力"

---

**原文件 711 行 → 精简后 115 行 (-84%)**
