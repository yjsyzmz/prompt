---
feature: "001-system-interaction-foundation"
stage: tasks
status: approved
plan_version: "c5666be0aefb4523e21a2544722511f087201360"
owner: "Solar"
reviewer: "Fable"
---

# 系统交互基础——任务清单

## 本阶段边界

- 本文件只拆解已批准 Spec 与 Plan，不新增产品范围或技术决策。
- 在用户确认本文件且 Fable 对准确 SHA 给出 Tasks Gate `PASS` 前，任何 Agent 都不得执行以下任务。
- 本轮不安装依赖、不安装 Xcode、不创建工程、不编写应用代码或测试代码，也不开展人工兼容性验证。
- 001 不接入网络、模型、API Key、提示词库、账号、遥测或持久化；实现任务不得为这些范围外能力预留抽象。
- 所有实现任务都必须由前置测试、探针或验证任务驱动。发现测试无法先写时，Owner 必须暂停并在 PR 说明原因，不得直接实现。
- 测试与证据只能使用标为 `SYNTHETIC-001` 的非敏感合成文字，不得包含真实用户内容或类似凭据的字符串。

## 依赖顺序

1. **P0 — 环境与工程门禁：** T-001 → T-002 → T-003 → T-004。
2. **P1 — 高风险能力探针：** T-005 → T-006 → T-007；T-008 → T-009 → T-010。两条探针链可在 P0 后并行，但 T-007 与 T-010 均通过前不得进入 P2。
3. **P2 — 领域核心：** T-011 → T-012；T-013 → T-014。两条测试优先链可并行，均依赖 P1 通过。
4. **P3 — 系统适配器：** 权限 T-015 → T-016、剪贴板 T-017 → T-018、AX 读取 T-019 → T-020 可并行；随后执行写入与恢复 T-021 → T-022、目标监控 T-023 → T-024、几何 T-025 → T-026、预览 T-027 → T-028。
5. **P4 — 集成闭环：** T-029 → T-030 → T-031，必须在 P2、P3 全部通过后执行。
6. **P5 — 验收证据：** T-032 至 T-038 可按测试环境分组执行，最后由 T-039 汇总；T-039 通过后才可请求 Implementation Gate 最终审核。

任何停止条件触发时，后续依赖任务全部暂停，Owner 返回对应 SDD Gate 更新 research/plan/spec 或请求用户裁决，不得通过静默降级绕过。

## 需求追踪

| 需求 | 验收场景 | 测试／探针任务 | 实现任务 | 验收证据任务 |
| --- | --- | --- | --- | --- |
| FR-001 | AC-001, AC-002 | T-005, T-007 | T-006, T-028 | T-032, T-036 |
| FR-002 | AC-003 | T-015 | T-016, T-028 | T-035 |
| FR-003 | AC-004 | T-005, T-019 | T-006, T-020 | T-035, T-038 |
| FR-004 | AC-005, AC-006 | T-019, T-029, T-030 | T-020, T-031 | T-032, T-033 |
| FR-005 | AC-007 | T-019, T-027, T-030 | T-020, T-028, T-031 | T-035 |
| FR-006 | AC-005, AC-006, AC-016 | T-011, T-030 | T-012, T-031 | T-032, T-033, T-037 |
| FR-007 | AC-005, AC-006, AC-015 | T-008, T-025, T-027 | T-009, T-026, T-028 | T-032, T-033, T-036 |
| FR-008 | AC-005, AC-006, AC-008, AC-009 | T-013, T-017, T-027, T-030 | T-014, T-018, T-028, T-031 | T-032, T-033, T-035 |
| FR-009 | AC-009, AC-012, AC-013 | T-013, T-021, T-023, T-030 | T-014, T-022, T-024, T-031 | T-032, T-033, T-035 |
| FR-010 | AC-005, AC-006, AC-010 | T-017, T-021, T-030 | T-018, T-022, T-031 | T-032, T-033, T-034 |
| FR-011 | AC-011 | T-013, T-023, T-030 | T-014, T-024, T-031 | T-035 |
| FR-012 | AC-012, AC-013, AC-017 | T-013, T-021, T-030 | T-014, T-022, T-031 | T-032, T-033, T-039 |
| FR-013 | AC-014 | T-011, T-013, T-017, T-030 | T-012, T-014, T-018, T-031 | T-038 |
| NFR-001 | AC-001 | T-005, T-030 | T-006, T-031 | T-036 |
| NFR-002 | AC-003 至 AC-016 | T-013, T-021, T-030 | T-014, T-022, T-031 | T-032 至 T-038 |
| NFR-003 | AC-005, AC-006, AC-010 | T-029, T-030 | T-031 | T-032, T-033, T-034 |
| NFR-004 | AC-007, AC-016 | T-011, T-019, T-029, T-030 | T-012, T-020, T-031 | T-037 |
| NFR-005 | AC-015 | T-008, T-025, T-030 | T-009, T-026, T-031 | T-036 |
| NFR-006 | AC-003, AC-004, AC-008, AC-014 | T-011, T-017, T-030 | T-012, T-018, T-031 | T-038 |
| NFR-007 | AC-002, AC-003, AC-004, AC-007, AC-009, AC-010, AC-013 | T-011, T-013, T-015, T-027, T-030 | T-012, T-014, T-016, T-028, T-031 | T-035 |

## 任务

### P0 — 环境与工程门禁

- [x] **T-001 [Environment] 记录可复现工具链。** 安装并选择稳定版完整 Xcode，记录 Xcode、Swift、macOS、Mac 型号和 CPU 架构；若只有 Command Line Tools 或 Swift 6 不可用，立即停止。此任务只能在 Tasks Gate `PASS` 和用户授权 Implementation Gate 后执行。— Covers: Plan 阶段出口 1；Evidence: `evidence/T-001-toolchain.md`
- [x] **T-002 [Test] 编写工程结构失败检查。** 先定义并运行一个预期失败的结构检查，要求存在 macOS 14.0+、Swift 6、arm64+x86_64 的应用目标、单元测试目标和合成 AX 宿主目标，同时拒绝 App Sandbox、网络 entitlement、第三方运行时依赖和范围外模块。— Depends on: T-001; Covers: Constitution IV, VII; Evidence: `evidence/T-002-project-structure-red.md`
- [x] **T-003 [Implementation] 创建最小 Xcode 工程。** 只创建 T-002 要求的目标、配置和目录，不加入产品行为；使结构检查通过。— Depends on: T-002; Covers: Constitution IV, VII; Evidence: `evidence/T-003-minimal-xcode-project.md`
- [x] **T-004 [Verification] 建立基础构建基线。** 在本地与 GitHub Actions 运行 universal Debug build、单元测试发现、`sdd-check` 和 `secret-scan`；记录命令和结果，不绕过无法执行的 Xcode 检查。— Depends on: T-003; Covers: Constitution V, VI; Evidence: `evidence/T-004-build-baseline.md`

### P1 — 高风险能力探针

- [x] **T-005 [Test] 定义快捷键与 Secure Event Input 探针。** 用协议替身先覆盖注册成功、冲突、注销、重复回调、Secure Event Input 开启时零内容读取，以及从 hot-key callback 开始的单调时钟采样；测试必须证明不需要 Input Monitoring 或通用按键监听。— Depends on: T-004; Covers: FR-001, FR-003, NFR-001, AC-001, AC-002, AC-004
- [x] **T-006 [Implementation] 实现最薄快捷键与安全输入适配器。** 使用 `RegisterEventHotKey`、`UnregisterEventHotKey` 与 `IsSecureEventInputEnabled`，将状态交给协调器；不得加入键盘监听替代路径。— Depends on: T-005; Covers: FR-001, FR-003, NFR-001
- [x] **T-007 [Probe] 验证快捷键停止条件。** 在普通输入、Secure Event Input 和快捷键冲突环境人工复核；若 Secure Event Input 完全抑制回调，记录 AC-004 未满足并返回 Gate，不得声称已实现应用内拒绝。— Depends on: T-006; Covers: FR-001, FR-003, AC-001, AC-002, AC-004; Evidence: `evidence/T-007-hot-key-stop-conditions.md`
- [x] **T-008 [Test] 定义非激活面板与显示几何探针。** 先覆盖 `NSPanel` 不抢焦点、后备锚点、屏幕边缘、负坐标、副显示器、不同缩放和全屏空间的预期几何；失败样例必须可复现。— Depends on: T-004; Covers: FR-007, NFR-005, AC-015; Evidence: `evidence/T-008-panel-geometry-red.md`
- [x] **T-009 [Implementation] 实现最小面板探针。** 创建 nonactivating `NSPanel` 和最小 SwiftUI 占位内容，只验证不抢焦点、层级与几何，不实现正式交互界面。— Depends on: T-008; Covers: FR-007, NFR-005; Evidence: `evidence/T-009-panel-geometry-green.md`
- [x] **T-010 [Probe] 验证面板停止条件。** 在单屏、多屏、全屏、边缘位置和非默认缩放下记录结果；若 TextEdit 或 Chrome/ChatGPT 中无法既保持目标又显示完整面板，返回 Gate。— Depends on: T-009; Covers: FR-007, NFR-005, AC-015; Evidence: `evidence/T-010-panel-stop-conditions.md`

### P2 — 领域核心

- [x] **T-011 [Test] 编写领域值与隐私契约测试。** 先覆盖确定性标记逐字符保真、中文/英文/混合/空白/多行/长文本/特殊字符、错误到可理解状态的映射、敏感值不可 `Codable`、错误和日志不得携带内容。— Depends on: T-007, T-010; Covers: FR-006, FR-013, NFR-004, NFR-006, NFR-007, AC-014, AC-016; Evidence: `evidence/T-011-domain-privacy-red.md`
- [x] **T-012 [Implementation] 实现领域值、协议与确定性转换器。** 仅实现 Plan 已定义的值类型、错误、协议和 `【系统交互验证】\n<原文>` 转换；不引用 AppKit、网络或持久化。— Depends on: T-011; Covers: FR-006, FR-013, NFR-004, NFR-006, NFR-007; Evidence: `evidence/T-012-domain-privacy-green.md`
- [x] **T-013 [Test] 编写会话状态机与副作用测试。** 先覆盖完整状态路径、一次仅一个会话、旧 session callback 无效、确认前 setter 为 0、取消零写入/零剪贴板、clipboardInput 禁止直接替换，以及 `recoverable → previewing(recoveryUnavailable)` 后只允许复制原文或关闭、不得再次写入。— Depends on: T-007, T-010; Covers: FR-008, FR-009, FR-011, FR-012, FR-013, NFR-002, NFR-007, AC-008, AC-009, AC-011, AC-012, AC-013, AC-014; Evidence: `evidence/T-013-session-coordinator-red.md`
- [x] **T-014 [Implementation] 实现会话协调器。** 以最小状态转移满足 T-013，使用 session ID 隔离旧回调，结束或替换会话时释放句柄并清除敏感内存引用。— Depends on: T-012, T-013; Covers: FR-008, FR-009, FR-011, FR-012, FR-013, NFR-002, NFR-007; Evidence: `evidence/T-014-session-coordinator-green.md`

### P3 — 系统适配器与预览

- [x] **T-015 [Test] 编写 Accessibility 权限流程测试。** 先覆盖已授权、未授权、打开具体设置成功、深链失败降级到通用设置、重新检测，以及权限缺失时 AX 读取/写入调用均为 0；剪贴板路径必须由用户点击启动。— Depends on: T-014; Covers: FR-002, NFR-007, AC-003; Evidence: `evidence/T-015-accessibility-permission-red.md`
- [x] **T-016 [Implementation] 实现权限适配器。** 使用系统信任检查与用户动作驱动的设置跳转，实现说明、重新检测和安全降级，不缓存虚假的授权状态。— Depends on: T-015; Covers: FR-002, NFR-007; Evidence: `evidence/T-016-accessibility-permission-green.md`
- [x] **T-017 [Test] 编写剪贴板显式访问测试。** 先用 spy 精确验证取消/普通预览/安全输入的读写次数为 0；只有“从剪贴板读取”“复制结果”“复制原文”分别发生一次预期访问，并要求 `currentHostOnly`。— Depends on: T-014; Covers: FR-008, FR-010, FR-013, NFR-006, AC-003, AC-004, AC-008, AC-010, AC-014; Evidence: `evidence/T-017-clipboard-policy-red.md`
- [x] **T-018 [Implementation] 实现剪贴板适配器。** 封装显式读写和 `NSPasteboard.WritingOptions.currentHostOnly`；不得后台轮询、自动读取或通过模拟粘贴替代 AX 写入。— Depends on: T-017; Covers: FR-008, FR-010, FR-013, NFR-006; Evidence: `evidence/T-018-clipboard-policy-green.md`
- [x] **T-019 [Test] 编写 AX 捕获测试。** 先覆盖安全元素拒绝、非空选区优先、零长度选区回退全文、空文本、不支持/只读目标、空白有效、边界可用与不可用、内容读取错误；安全输入路径不得创建任何内容值。— Depends on: T-014; Covers: FR-003, FR-004, FR-005, NFR-004, AC-004, AC-005, AC-006, AC-007, AC-016; Evidence: `evidence/T-019-ax-target-capture-red.md`
- [x] **T-020 [Implementation] 实现 AX 目标捕获。** 在 `AccessibilityGateway` actor 内持有原始 AX 引用，只向领域层返回不可持久化的句柄和值；按 T-019 规则读取，不做写入。— Depends on: T-019; Covers: FR-003, FR-004, FR-005, NFR-004; Evidence: `evidence/T-020-ax-target-capture-green.md`
- [x] **T-021 [Test] 编写重新验证、写入与恢复测试。** 先覆盖 Plan 的七项确认前权威检查、原文变化、应用/窗口/元素/范围变化、单一 setter、setter 失败时原文不变、成功后恢复、恢复前结果变化，以及失败后复制路径；证明任何失败都 fail-closed。— Depends on: T-020; Covers: FR-009, FR-010, FR-012, NFR-002, AC-005, AC-006, AC-009, AC-010, AC-012, AC-013, AC-017; Evidence: `evidence/T-021-authoritative-write-recovery-red.md`
- [x] **T-022 [Implementation] 实现权威验证、替换与恢复。** 在 actor 内按固定顺序重新获取并比较目标，只写最初选区或全文；恢复时仅当目标内容仍等于预期验证结果才写回原文，不增加清空、粘贴或第二写入策略。— Depends on: T-021; Covers: FR-009, FR-010, FR-012, NFR-002; Evidence: `evidence/T-022-authoritative-write-recovery-green.md`
- [ ] **T-023 [Test] 编写 AXObserver 投递与隔离测试。** 先证明 observer run-loop source 挂载在 main run loop；callback 只捕获 session ID 与 target ID，再异步跳入 `AccessibilityGateway` actor；过期 callback 被忽略，监控通知只能提前禁用按钮，不能授权写入或恢复。— Depends on: T-020; Covers: FR-009, FR-011, NFR-002, AC-009, AC-011; Resolves: Plan Gate NIT-1
- [ ] **T-024 [Implementation] 实现外部目标监控。** 组合主 run loop 上的 `AXObserver` 与 `NSWorkspace` 通知，按 T-023 的 actor 隔离规则投递；注销 observer 时释放 run-loop source 和 AX 句柄。— Depends on: T-023; Covers: FR-009, FR-011, NFR-002
- [ ] **T-025 [Test] 编写屏幕几何转换测试。** 先覆盖光标/选区/元素/窗口/活跃显示器锚点优先级、AX 与 AppKit 坐标转换、可见区域收敛、面板大于可用区域和屏幕变化。— Depends on: T-010; Covers: FR-007, NFR-005, AC-015
- [ ] **T-026 [Implementation] 实现几何转换与面板控制器。** 以 T-025 规则选择锚点、限制完整面板在单一活跃显示器，并保持 nonactivating 行为；不得把获取不到精确边界当作会话失败。— Depends on: T-025; Covers: FR-007, NFR-005
- [ ] **T-027 [Test] 编写预览状态与操作测试。** 先覆盖 ready、permissionRequired、secureInput、emptyOrUnsupported、staleTarget、writeFailed、recoveryUnavailable 的文案和按钮矩阵；只有 ready 显示可用确认，所有拒绝/失败状态至少有一个安全下一步，界面不显示原始错误码或敏感内容。— Depends on: T-012, T-014, T-016, T-018, T-022, T-026; Covers: FR-005, FR-007, FR-008, NFR-007, AC-002, AC-003, AC-004, AC-007, AC-008, AC-009, AC-010, AC-013
- [ ] **T-028 [Implementation] 实现预览与应用生命周期装配。** 实现最小 SwiftUI 内容和 `AppLifecycleController`，接入已测试协议；提供确认、复制、取消、恢复、复制原文、打开设置和重新检测，不加入最终视觉系统或设置体验。— Depends on: T-027; Covers: FR-001, FR-002, FR-005, FR-007, FR-008, NFR-007

### P4 — 合成集成闭环

- [ ] **T-029 [Test Harness] 建立合成 AX 宿主。** 只使用 `SYNTHETIC-001`，提供选区、全文、空值、只读、安全输入、元素失效、窗口切换和可控 setter 失败夹具；宿主不读取真实应用内容，不把内容写入日志或测试产物。— Depends on: T-004, T-020; Covers: FR-004, FR-013, NFR-003, NFR-004, NFR-006, AC-005, AC-006, AC-007, AC-009, AC-014, AC-016
- [ ] **T-030 [Test] 编写端到端集成测试。** 先以合成宿主和 spy 覆盖快捷键→权限→读取→预览→确认→单次写入→恢复，以及取消、复制、过期目标、写入失败、新会话替代、内容清除；每个路径断言确认前 setter 为 0。— Depends on: T-006, T-016, T-018, T-022, T-024, T-026, T-028, T-029; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007, AC-001 至 AC-016
- [ ] **T-031 [Implementation] 完成最小闭环装配。** 仅补齐 T-030 暴露的依赖注入、事件路由与状态同步，使合成端到端测试通过；不得借机加入未被失败测试要求的功能。— Depends on: T-030; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007

### P5 — 真实环境验收与证据

- [ ] **T-032 [Verification] 验证 TextEdit 完整闭环。** 使用合成输入记录选区前后字节不变、预览前零写入、确认后只替换选区、恢复原文和关闭恢复状态后的标准 Undo 行为。— Depends on: T-031; Covers: FR-001, FR-004, FR-006 至 FR-010, FR-012, NFR-002, NFR-003, AC-001, AC-005, AC-008, AC-009, AC-012, AC-017
- [ ] **T-033 [Verification] 验证 Chrome/ChatGPT 完整闭环。** 使用合成输入记录无选区时读取全文、预览前零写入、确认后只替换目标输入框、目标切换拦截、恢复原文和标准 Undo；若完整闭环失败，触发硬停止条件。— Depends on: T-031; Covers: FR-001, FR-004, FR-006 至 FR-010, FR-012, NFR-002, NFR-003, AC-001, AC-006, AC-008, AC-009, AC-012, AC-017
- [ ] **T-034 [Verification] 验证 VS Code 后备闭环。** 先记录直接读写实际能力；无可靠支持时验证用户主动剪贴板输入、明确复制结果和手动粘贴路径，证明无自动剪贴板访问且不修改无关文字。— Depends on: T-031; Covers: FR-010, NFR-002, NFR-003, NFR-006, AC-010
- [ ] **T-035 [Verification] 验证权限、安全与失败恢复矩阵。** 覆盖权限缺失/重新授权、设置深链降级、安全输入、快捷键冲突、空/不支持目标、过期目标、写入/恢复失败和重复触发；逐项记录可理解文案、安全下一步及写入/剪贴板计数。— Depends on: T-031; Covers: FR-001 至 FR-005, FR-008 至 FR-012, NFR-002, NFR-006, NFR-007, AC-002, AC-003, AC-004, AC-007, AC-008, AC-009, AC-010, AC-011, AC-013
- [ ] **T-036 [Evidence] 采集性能与显示证据。** 在 TextEdit 和 Chrome/ChatGPT 各连续触发 10 次，至少 9 次从 hot-key callback 到可见外壳/明确状态不超过 300ms；记录 callback 是可观测起点且**不包含物理按键到 callback 的操作系统投递延迟**，并记录 Mac、macOS、应用版本、全屏、显示器布局和缩放。不得为获得物理按键时间戳引入按键监听。— Depends on: T-032, T-033; Covers: FR-001, FR-007, NFR-001, NFR-005, AC-001, AC-015; Resolves: Plan Gate NIT-2
- [ ] **T-037 [Verification] 验证代表性文字矩阵。** 在必须支持的应用中执行中文、英文、中英混合、空文本、多行、10,000 字符长文本和特殊字符；记录具体长度与应用限制，核对无崩溃、静默截断或无关修改。— Depends on: T-032, T-033, T-034; Covers: FR-006, NFR-004, AC-007, AC-016
- [ ] **T-038 [Audit] 执行隐私与安全审计。** 检查文件、配置、日志、崩溃自定义字段、截图、测试结果和遥测均无真实内容；复核安全输入零读取/转换/展示/复制/写入，正常路径剪贴板访问次数和会话结束后的敏感引用释放。— Depends on: T-035, T-037; Covers: FR-003, FR-013, NFR-006, AC-004, AC-008, AC-014
- [ ] **T-039 [Evidence] 汇总可复现验收包。** 汇总所有自动测试、探针、人工矩阵、性能数据、环境版本、已知限制和 Undo 观察；逐项核对本文件所有 FR/NFR/AC，运行 build、unit-tests、`sdd-check`、`secret-scan`、`git diff --check`，确认无未解释失败后再发 Implementation Gate `HANDOFF`。— Depends on: T-032 至 T-038; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007, AC-001 至 AC-017

## 检查点

- **C0 — 工具链可执行：** T-004 通过；完整 Xcode、目标配置、CI 与基础测试发现均可复现。
- **C1 — 高风险假设成立：** T-007 与 T-010 已通过；快捷键/安全输入和非激活面板没有触发 Plan 的硬停止条件。
- **C2 — 领域安全不变量成立：** T-014 通过；确认前零 setter、单会话、会话清理及 `recoverable → previewing(recoveryUnavailable)` 已由失败优先测试证明。
- **C3 — 系统边界可控：** T-028 通过；权限、剪贴板、AX、observer、几何和预览各自有测试，并且权威写入验证未被监控事件取代。
- **C4 — 合成闭环通过：** T-031 通过；全部生产装配由 T-030 的端到端失败测试驱动。
- **C5 — 真实验收完整：** T-039 通过；TextEdit 与 Chrome/ChatGPT 完整闭环、VS Code 后备闭环、性能/显示/输入/隐私证据均可复现。

## Plan Gate NIT 处置约束

| Finding | Tasks Gate 的强制落实 | 关闭条件 |
| --- | --- | --- |
| NIT-1 | T-023/T-024 明确 AXObserver source 挂载于 main run loop，callback 再跳入 actor，监控不是写入授权 | Fable 确认任务表述覆盖并在 Tasks Gate 关闭 |
| NIT-2 | T-036 明确 300ms 证据从 hot-key callback 起算，不包含 OS 投递延迟，且禁止增加按键监听 | Fable 确认测量边界可审计并在 Tasks Gate 关闭 |
| NIT-3 | T-013/T-014 明确测试并实现 `recoverable → previewing(recoveryUnavailable)`，仅允许复制原文或关闭 | Fable 确认状态、动作与禁止写入均被覆盖后关闭 |

## Tasks Gate 记录

- Plan Gate 通过提交：`c5666be0aefb4523e21a2544722511f087201360`
- 用户授权：已授权编写 `tasks.md`；未授权安装依赖、创建工程或开发
- 用户书面确认：2026-07-20 已确认本任务清单，可以交给 Fable 进行 Tasks Gate 审核
- Review commit SHA 与 Reviewer 结论：以 PR #2 中后续结构化 `HANDOFF` 和 `REVIEW` 评论为权威记录
- 审核更新规则：任何 `HANDOFF` 后的新提交都会使旧审核请求失效，Owner 必须针对新的准确 SHA 重新发布 `HANDOFF`
- PR 审核位置：PR #2
- Implementation Gate：已获用户逐项授权，当前完成 T-001 至 T-022，C1、C2 已达成；T-021 的 14 项权威重新验证、单次 setter 与恢复契约测试已转绿，全套 68 项单元测试连续两次通过；T-023 及后续任务未获授权
