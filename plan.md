# Go-First 重构计划

## 目标

将 `arch_view` 重构为 **Go 为唯一核心实现** 的架构：

- **Lua 仅保留脚本接入与宿主集成能力**
- **扫描、依赖提取、校验、布局、投影、路由、导出等核心逻辑全部由 Go 实现**
- **保留现有公共 API 与 CLI 的兼容性，逐步移除 Lua fallback**

---

## 当前现状

仓库已经具备明显的 Go-first 基础，但仍处于“双引擎”阶段。

### 已有 Go 核心能力

以下能力已经存在 Go 实现：

- `cmd/archview-core/main.go`
- `internal/archcore/analyze.go`
- `internal/archcore/scan.go`
- `internal/archcore/extract.go`
- `internal/archcore/checker.go`
- `internal/archcore/layers.go`
- `internal/archcore/projection.go`
- `internal/archcore/render.go`
- `internal/archcore/route.go`
- `internal/archcore/types.go`
- `internal/archcore/luaencode.go`

这些文件已经覆盖了分析主链路的大部分核心能力。

### 仍保留 Lua 核心实现的部分

以下模块仍然属于 Lua 侧核心逻辑，和 Go 实现存在重复：

- `arch_view/build.lua`
- `arch_view/source_scan.lua`
- `arch_view/dependency_extract.lua`
- `arch_view/checker.lua`
- `arch_view/layers.lua`
- `arch_view/projection.lua`
- `arch_view/layout_renderer.lua`
- `arch_view/route_engine.lua`

### 仍需 Go 化的 Lua 应用层逻辑

以下模块虽然更偏“应用层”，但仍然承载了部分核心行为或 fallback 控制：

- `arch_view/app/engine.lua`
- `arch_view/app/config.lua`
- `arch_view/app/service.lua`
- `arch_view/app/go_bridge.lua`

---

## 重构原则

### 1. Lua 只保留接入层
Lua 应只负责：

- CLI 参数解析
- 宿主脚本调用入口
- 调用 Go 二进制
- 文件读写与简单编排
- 向旧 API 暴露兼容层

### 2. Go 成为唯一事实来源
所有架构分析结果必须以 Go 输出为准，包括：

- 配置校验
- 模块扫描
- `require` 提取
- 模块分类
- 禁止依赖检查
- 环检测
- 视图投影
- 分层布局
- 路由信息
- 导出数据

### 3. 兼容优先，删除滞后
短期内优先保留旧 Lua 模块名和 API 入口，但将其改造成薄代理；待外部接入稳定后再删除冗余实现。

### 4. 分阶段收敛
先消除运行时双实现，再收敛导出链路，最后清理遗留 Lua 核心。

---

## 目标架构

### 保留的 Lua 模块

这些模块预计保留，作为脚本接入层：

- `arch_view.lua`
- `arch_view/cli.lua`
- `arch_view/app/cli.lua`
- `arch_view/app/go_bridge.lua`
- `arch_view/support/fs.lua`
- `arch_view/support/module_path.lua`
- `arch_view/json_reader.lua`
- `arch_view/json_writer.lua`
- `bin/arch_view.lua`

### 最终应由 Go 承担的能力

以下能力最终统一收敛到 Go：

- config validate
- analyze
- check
- scan export
- viewer export
- 可能的后续 benchmark/support 输出格式

---

## 分阶段计划

## Phase 1：确立 Go 为唯一分析核心

### 目标

将分析、检查、JSON 输出统一强制走 Go，去掉 Lua fallback 在主链路中的实际作用。

### 任务

#### 1. 调整 `arch_view/app/engine.lua`
- 将 `auto` 明确收敛到 Go
- `go` 继续直接使用 Go 引擎
- `lua` 模式改为：
  - 临时兼容但标记废弃，或
  - 直接返回明确错误，提示该模式即将移除

#### 2. 调整 `arch_view/build.lua`
- 保留 `build.validate_config`
- 将 `build.analyze` 改造成调用 Go 的兼容代理
- 不再使用 Lua 的：
  - `source_scan`
  - `dependency_extract`
  - `checker`
  - `layers`
  - `projection`

#### 3. 调整 `arch_view/app/config.lua`
- 不再依赖 `build.analyze`
- 配置合法性以 Go 为准
- Lua 侧仅保留：
  - 读取 JSON
  - 基本类型检查
  - 路径解析
- 更严格的 schema 校验迁移到 Go

#### 4. 调整 `arch_view/app/service.lua`
- `analyze`
- `check`
- `write_scan`

以上流程全部统一走 Go，不再保留 Lua 核心分支。

### 验收标准

- `engine=auto` 只走 Go
- `engine=go` 保持可用
- 旧公共 API 不变
- 分析与检查输出仍兼容当前调用方
- 文档中不再强调 Lua 是可用核心实现

---

## Phase 2：导出链路 Go 化

### 目标

让 viewer 导出不再依赖 Lua 组织分析结果，改为 Go 提供完整导出能力。

### 任务

#### 1. 扩展 Go CLI 命令能力
在 `cmd/archview-core` 中增加明确的导出命令，例如：

- `analyze`
- `check`
- `export-viewer`

也可以考虑进一步拆分：

- `export-json`
- `export-viewer`

#### 2. 在 Go 中实现导出编排
Go 侧完成：

- 读取配置/请求
- 生成 architecture
- 输出 `architecture.json`
- 输出 `architecture_data.js`
- 拷贝 viewer 资源到目标目录

#### 3. 精简 `arch_view/app/service.lua`
将 `service.export_viewer` 从“导出实现者”改为“导出命令桥接层”。

### 验收标准

- `viewer` 命令无需 Lua 参与分析与导出核心逻辑
- Lua 仅负责调用 Go 与可选打开输出文件
- 导出目录内容与现有产物兼容

---

## Phase 3：公共 API 与兼容层收敛

### 目标

保留现有公共接口，但内部完全代理到 Go。

### 任务

#### 1. 保持以下入口可用
- `require("arch_view")`
- `require("arch_view.build")`
- `require("arch_view.cli")`

#### 2. 将兼容层改造成薄封装
- `arch_view.build`
- `arch_view.cli`

只负责参数转换与调用应用层服务，不再包含核心算法。

#### 3. 标记废弃能力
在 README 和注释中明确：

- `engine="lua"` 废弃
- 旧的 Lua 核心模块为兼容保留，不建议新代码依赖

### 验收标准

- 对外 API 路径不变
- 旧调用方式可继续工作
- 内部执行已完全依赖 Go

---

## Phase 4：删除重复 Lua 核心实现

### 目标

清理 Go 已覆盖的 Lua 逻辑，避免双实现长期并存。

### 候选删除/降级模块

- `arch_view/source_scan.lua`
- `arch_view/dependency_extract.lua`
- `arch_view/checker.lua`
- `arch_view/layers.lua`
- `arch_view/projection.lua`
- `arch_view/layout_renderer.lua`
- `arch_view/route_engine.lua`

### 处理方式

优先顺序建议为：

1. 先停止直接引用
2. 再改成兼容代理或废弃提示
3. 最后删除文件与测试引用

### 风险控制

若外部已有用户直接 `require` 这些模块，则先不要立刻删除；应先经历一个兼容版本周期。

### 验收标准

- 仓库中不再存在一套完整的 Lua 核心分析实现
- 所有核心算法只有 Go 版本
- Lua 目录清晰地表现为“入口层/桥接层”

---

## Phase 5：测试与文档收敛

### 目标

让测试、文档、仓库叙事全部反映新的 Go-first 架构。

### 测试调整

#### Lua 测试保留
Lua 侧测试重点应改为：

- 公共 API 可调用
- CLI 参数兼容
- Go 桥接行为正确
- 错误消息与路径处理正确

#### Go 测试加强
Go 侧测试应覆盖：

- 配置校验
- 扫描行为
- `require` 提取
- 分类/校验
- 投影/布局/路由
- viewer 导出
- 回归用例

#### 删除或改写的测试
现有直接验证 Lua 核心模块行为的测试应逐步迁移或移除，例如：

- 直接调用 `source_scan`
- 直接调用 `dependency_extract`
- 直接调用 `checker`
- 直接调用 `projection`
- 直接调用 `route_engine`

### 文档调整

README 需要修改为：

- 明确 `arch_view` 是 **Lua 接入层 + Go 核心**
- 将双引擎描述改成 Go 唯一引擎
- 去掉或弱化 `engine=lua`
- 补充 Go 构建与缓存机制说明
- 补充 viewer 导出链路说明

### 验收标准

- 测试结构与系统架构一致
- README 不再描述 Lua fallback 是主要能力
- 新读者能快速理解系统为 Go-first

---

## 风险与注意事项

## 1. 兼容性风险
外部调用方可能依赖：

- `require("arch_view.build")`
- `require("arch_view.source_scan")`
- `require("arch_view.checker")`

需要通过兼容代理或废弃周期处理，而不是直接删除。

## 2. 输出一致性风险
Go 与 Lua 当前虽已较接近，但仍需确保：

- JSON 字段名一致
- 空值/布尔值语义一致
- 排序顺序稳定
- viewer 数据结构完全兼容

## 3. 工具链风险
Go 成为唯一核心后，运行环境将更依赖：

- 本机 Go toolchain
- 或预构建二进制缓存
- 或后续发布打包策略

需要提前明确部署方案。

## 4. 调试体验风险
从 Lua 内嵌逻辑切换到外部 Go 进程后，错误定位方式会改变。需要提升：

- Go stderr 输出质量
- Lua 桥接错误包装
- request/response 临时文件可观测性

---

## 建议实施顺序

按收益和风险排序，建议如下：

1. **Phase 1：Go 唯一分析核心**
2. **Phase 2：viewer 导出 Go 化**
3. **Phase 3：公共 API 兼容层收敛**
4. **Phase 4：删除重复 Lua 核心**
5. **Phase 5：测试与文档收敛**

---

## 里程碑定义

### M1
- `analyze/check/write_scan` 全部由 Go 执行
- `auto` 不再 fallback 到 Lua

### M2
- `viewer` 导出链路由 Go 主导
- Lua 仅保留入口与桥接

### M3
- `build.lua` 等兼容入口全部变成薄代理
- Lua 核心模块不再被主流程使用

### M4
- 删除或冻结 Lua 核心算法模块
- README 和测试完成 Go-first 收敛

---

## 最终结果

完成后，`arch_view` 应呈现为如下结构：

- **Lua**
  - public API
  - CLI
  - host integration
  - bridge
  - compatibility shim

- **Go**
  - 唯一核心分析引擎
  - 唯一导出实现
  - 唯一规则校验实现
  - 唯一 viewer 数据生产者

即：

> Lua 负责“接入”，Go 负责“能力”。

这将显著降低双实现维护成本，减少输出漂移风险，并让系统边界更清晰。

---

# 下一阶段：清理废弃、遗留、兼容代码

## 目标

在 Go-First 架构基础上，**安全清理废弃、遗留、兼容代码**，让仓库结构清晰反映新架构。

---

## 当前状态（Go-First 重构完成后）

### 已完成的重构

- ✅ Go 成为唯一分析引擎
- ✅ viewer 导出链路由 Go 主导
- ✅ Lua 核心模块标记为废弃
- ✅ 公共 API 保持兼容
- ✅ README 和 CLI 更新

### 仍存在的遗留代码

#### 废弃的 Lua 核心模块（已标记 DEPRECATED）

```
arch_view/source_scan.lua      - 扫描逻辑
arch_view/dependency_extract.lua - 依赖提取
arch_view/checker.lua          - 校验逻辑
arch_view/layers.lua           - 分层布局
arch_view/projection.lua       - 视图投影
arch_view/layout_renderer.lua  - 布局渲染
arch_view/route_engine.lua     - 路由引擎
```

#### 测试中对废弃模块的直接引用

```
tests/arch_view_contract.lua   - 直接 require 并测试所有 Lua 核心模块
```

---

## 清理原则

### 1. 安全优先
- 不直接删除可能有外部依赖的文件
- 先添加运行时警告，再删除
- 保留至少一个版本的兼容周期

### 2. 逐步推进
1. 先移除内部引用（已完成）
2. 再迁移测试
3. 最后删除文件或改为代理

### 3. 保留必要兼容层
- `arch_view.build` 作为公共 API 保留
- `arch_view.cli` 作为公共 API 保留

---

## 清理阶段

---

## Phase 6: 迁移测试

### 目标

将 `tests/arch_view_contract.lua` 从测试 Lua 核心模块改为测试公共 API 和 Go 桥接。

### 任务

#### 1. 评估现有测试内容
- 列出所有直接引用 Lua 核心模块的测试用例
- 评估哪些测试需要保留（行为兼容性）
- 评估哪些测试可以直接删除（实现细节）

#### 2. 新建测试结构
创建新的测试文件：

```
tests/
├── test_api.lua              # 测试公共 API
├── test_go_bridge.lua        # 测试 Go 桥接
└── test_cli.lua              # 测试 CLI
```

#### 3. 迁移关键测试用例

从原测试迁移以下内容：
- 配置加载测试
- analyze API 测试
- check API 测试
- export_viewer API 测试
- CLI 参数解析测试

#### 4. 删除/归档旧测试
- 删除原 `arch_view_contract.lua` 中测试 Lua 核心实现的用例
- 或将其移动为 `tests/legacy/` 下的归档文件

### 验收标准

- [ ] 新测试覆盖公共 API 主要路径
- [ ] 新测试通过 Go 引擎验证行为
- [ ] 旧测试不再直接引用废弃模块 或 被明确标记为 legacy

---

## Phase 7: 简化 build.lua

### 目标

将 `arch_view/build.lua` 进一步简化为纯代理层。

### 当前状态

```lua
-- build.lua 当前包含：
- validate_config()  - 基本类型检查
- analyze()          - 调用 go_bridge
```

### 任务

#### 1. 评估 validate_config
- 当前 Lua 侧只有基本类型检查
- 考虑是否完全委托给 Go 进行校验
- 或保留轻量级预校验

#### 2. 统一入口
确保 `build.analyze()` 是 `go_bridge.analyze()` 的薄代理。

### 验收标准

- [ ] `build.lua` 不含任何核心算法
- [ ] 所有分析调用都通过 `go_bridge`

---

## Phase 8: 废弃模块处理

### 目标

处理标记为 DEPRECATED 的 Lua 核心模块。

### 方案选择

#### 方案 A: 直接删除（如果确定无外部引用）

直接删除文件：
```bash
git rm arch_view/source_scan.lua
git rm arch_view/dependency_extract.lua
...
```

#### 方案 B: 改为代理/错误（推荐，更安全）

将废弃模块改为返回错误：

```lua
-- arch_view/source_scan.lua
return function()
    error("source_scan is deprecated. Use arch_view.app.go_bridge or arch_view.app.service instead.")
end
```

或改为代理到 Go：

```lua
-- arch_view/source_scan.lua
local go_bridge = require("arch_view.app.go_bridge")
-- 代理到 Go 实现
```

#### 方案 C: 移动到 legacy/ 目录

```
arch_view/
├── legacy/
│   ├── source_scan.lua
│   ├── dependency_extract.lua
│   └── ...
```

### 推荐方案

对外部用户最安全的是 **方案 B - 改为错误提示**，给一个版本周期后再删除。

### 验收标准

- [ ] 废弃模块不再包含可运行的核心代码
- [ ] 调用废弃模块会返回明确的迁移提示
- [ ] 仓库中不再存在两套完整的核心实现

---

## Phase 9: 最终清理

### 目标

删除所有遗留代码，完成架构收敛。

### 任务

#### 1. 删除废弃模块
在确认无外部引用后，彻底删除：
- `arch_view/source_scan.lua`
- `arch_view/dependency_extract.lua`
- `arch_view/checker.lua`
- `arch_view/layers.lua`
- `arch_view/projection.lua`
- `arch_view/layout_renderer.lua`
- `arch_view/route_engine.lua`

#### 2. 清理测试归档
删除 `tests/legacy/`（如果之前归档了旧测试）

#### 3. 更新文档
- README 中移除废弃模块的提及
- 添加迁移指南（如果用户之前依赖内部模块）

### 验收标准

- [ ] 仓库中只保留一套核心实现（Go）
- [ ] Lua 目录清晰表示为接入层
- [ ] 所有测试通过

---

## 风险与回滚策略

### 风险

1. **外部依赖**: 如果用户直接 `require("arch_view.checker")` 等内部模块
2. **Submodule 引用**: 如果 repo 被作为 submodule 使用

### 回滚策略

- 每个 Phase 单独提交
- 保留 `legacy/` 分支或 tag 作为备份
- 在 CHANGELOG 中明确标注破坏性变更

---

## 实施建议顺序

1. **Phase 6**: 迁移测试（确保新测试覆盖核心行为）
2. **Phase 7**: 简化 build.lua（清理入口层）
3. **Phase 8**: 废弃模块改为错误提示（给用户迁移时间）
4. **Phase 9**: 最终删除（确认安全后执行）

---

## 预计最终结构

```
arch_view/
├── app/
│   ├── cli.lua           # CLI 入口
│   ├── config.lua        # 配置加载
│   ├── engine.lua        # 引擎调度（Go-only）
│   ├── go_bridge.lua     # Go 桥接
│   ├── paths.lua         # 路径管理
│   └── service.lua       # 服务编排
├── support/
│   ├── fs.lua            # 文件系统
│   └── module_path.lua   # 模块路径
├── common.lua            # 公共工具
├── json_reader.lua       # JSON 读取
├── json_writer.lua       # JSON 写入
├── build.lua             # 兼容层（薄代理）
├── cli.lua               # 兼容层（薄代理）
└── init.lua              # 主入口

internal/archcore/        # Go 核心实现
cmd/archview-core/        # Go CLI
viewer/                   # 静态资源
tests/
├── test_api.lua
├── test_go_bridge.lua
└── test_cli.lua
```