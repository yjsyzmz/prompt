---
feature: "001-system-interaction-foundation"
stage: tasks
status: revised-pending-review
plan_version: "0c9883f8385c731b0cc084d22519224eada926ea"  # 重开后的 Plan Gate 第三版修订，Solar 已 PASS（2026-07-28）
owner: "Fable (Comate), from T-028"
reviewer: "Solar, from T-028"
---

# 系统交互基础——任务清单

## 本阶段边界

- 本文件只拆解已批准 Spec 与 Plan，不新增产品范围或技术决策。
- 在用户确认本文件且 **Solar（Reviewer）** 对准确 SHA 给出 Tasks Gate `PASS` 前，任何 Agent 都不得执行以下任务。Owner（Fable）不得自审本文件。
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
6. **P5 — 验收证据：** T-032 至 T-038 可按测试环境分组执行，最后由 T-039 汇总。
7. **P6 — 恢复算法重写后的下游复核（2026-07-28 新增）：** T-040 必须先完成；T-041 至 T-045 可在 T-040 通过后并行；最后由 T-046 汇总。**T-046 通过后才可请求 Implementation Gate 最终审核**，此前 T-039 的既有汇总不构成 HANDOFF 依据。

任何停止条件触发时，后续依赖任务全部暂停，Owner 返回对应 SDD Gate 更新 research/plan/spec 或请求用户裁决，不得通过静默降级绕过。

**2026-07-28 Tasks Gate 重开影响：** T-021 与 T-022 已按 Plan Gate 第三版修订（`0c9883f`，Solar 已 PASS）重写并清空勾选。依赖它们的下游复核**已写成 P6 段的可执行任务 T-040 至 T-046**，各自带 Depends on、完成条件与 Evidence 输出：T-027 与 T-030／T-031 的自动化复核由 T-040 承载；P5 的人工与审计复核按 Solar 在 Tasks Gate REVIEW 中裁决的限定范围由 T-041 至 T-045 承载；汇总与 HANDOFF 由 T-046 承载。在 T-040 至 T-046 完成前，T-027、T-030／T-031 与 P5 相关证据项的既有勾选与结论均不代表覆盖已达成，C3、C4、C5 均为未达成，且不得直接跳到 Implementation Gate HANDOFF。本轮只修改 `tasks.md`，不修改源码或测试，也不处理旧 Implementation findings。

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

表中 FR-009／FR-010／FR-012／NFR-002 对应的 T-021／T-022 已于 2026-07-28 按 Plan `0c9883f` 重写，覆盖关系在重新转绿前不成立。受影响需求的最终覆盖还需 P6 段的 T-040 至 T-046 完成：自动化复核见 T-040，恢复相关的人工与审计复核见 T-041 至 T-045，汇总见 T-046。

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
- [ ] **T-021 [Test] 编写重新验证、写入与恢复测试（按重开后的 Plan 算法重写）。** 本任务已于 2026-07-28 随 Plan Gate 第三版修订（`0c9883f`）重写，原"七项确认前权威检查 + 恢复不增加第二种写入策略"的表述作废，勾选状态清空，必须按下列批准算法重新建立失败优先测试：
  1. **共享前置检查 A1–A4**：应用与 PID 一致、除本应用 non-activating panel 外无其他外部目标、AX 窗口与元素有效且身份一致、元素可编辑且非 secure subrole 且 Secure Event Input 未开启。逐项覆盖各自失败时返回 `staleTarget` 或对应安全错误且 setter 计数为 0；AX 通知缺失或延迟不得放宽门禁。
  2. **路径化 settable 检查**：断言 settable 检查不在共享前置检查内，且每条路径只检查其实际写入的属性——replacement 检查捕获模式对应属性、whole-field recovery 检查 `kAXValueAttribute`、selected recovery R1 检查 `kAXSelectedTextAttribute`、selected recovery R2 由 fallback 门禁 1 检查 `kAXValueAttribute`。必须有测试证明 `kAXSelectedTextAttribute` 不可设置时**不得**阻断 R2 fallback。各路径 settable 失败时零 setter，并返回该路径对应失败状态。
  3. **replacement B1–B2**：selected 模式下 range 与 text 仍等于捕获值、whole-field 模式下完整 value 仍等于捕获值方可写入；通过后只对捕获模式对应属性执行恰好一次 setter；B1 失败返回 `staleTarget`、零 setter、不得改用其他 setter 或范围；setter 失败时原文不变并进入 `writeFailed`，不执行第二种写入策略。
  4. **recovery 入口分支**：按 `RecoverySnapshot` 的 capture mode 分派；`clipboardInput` 立即返回 `recoveryTargetChanged` 且零 setter。
  5. **whole-field recovery W1–W4**：完整 value 逐 UTF-16 code unit 等于 expected transformed text 时恢复成功，`kAXValueAttribute` setter 恰好 1 次且 selected setter 为 0；value 已变化时零 setter 返回 `recoveryTargetChanged`；`kAXValueAttribute` 不可设置时零 setter；写后回读不一致返回 `recoveryTargetChanged`；并断言该路径的 selected-range 读取调用计数为 0、从不使用 `kAXSelectedTextAttribute`、失败后不重试第二次写入。
  6. **selected recovery C1–C4 与 R1／R2／R3 分类**：C1 按"捕获 location + expected transformed text 的 UTF-16 长度"计算 expected result range；R1（当前 range 等于结果范围）检查并写 `kAXSelectedTextAttribute` 恰好一次，且选区内容须等于 expected transformed text；R2 情形 1（零长度插入点落在结果范围内含两端）与情形 2（range 属性不受支持／无值／能力探针确认不可可靠读取）进入 fallback；R3（`invalid element`、权限错误、Secure Input、timeout、`cannotComplete` 及任何非能力缺失读取失败）立即 fail-closed、零 setter、不得进入 fallback；C2 排除项——读到非零长度且不等于结果范围、或零长度插入点落在结果范围之外——一律返回 `recoveryTargetChanged` 且零 setter。
  7. **R2 语义不推断来源**：必须有测试证明结果范围内的零长度插入点无论产生原因都进入 fallback；并证明该状态下若范围内文本已被改动，由 fallback 门禁 4 拦截且零 setter。
  8. **fallback 六项门禁逐项失败测试**：① `kAXValueAttribute` 不可写零 setter；② 全文读取失败零 setter，且断言写入使用的基值是通过全部门禁后紧邻 setter 获取并校验的同一份值、不复用旧值；③ expected result range 越界（location 为负、location + UTF-16 长度超出基值长度）零 setter；④ 基值该范围内文本不等于 expected transformed text 零 setter；⑤ fallback 成功时范围外 UTF-16 code unit 与基值完全一致；⑥ 写后回读不一致返回 `recoveryTargetChanged`。另需覆盖 setter 计数（fallback 成功时 selected setter 为 0、whole-field setter 恰好 1）、whole-field setter 本身失败时返回 `recoveryTargetChanged` 且不重试其他 setter 或第二次写入、以及 A1–A4 任一失败时 fallback 也不得执行。
  9. **UTF-16 单位夹具**：使用 Emoji、组合字符与代理对构造合成夹具，验证范围计算、越界判断与子串替换均按 UTF-16 code unit 进行，且结果范围外内容保持完全一致。
  10. **失败后复制路径**：所有 recovery 失败分支都保留原文并提供复制原文动作，不得再次写入。
  — Depends on: T-020; Covers: FR-009, FR-010, FR-012, NFR-002, AC-005, AC-006, AC-009, AC-010, AC-012, AC-013, AC-017; Plan: `0c9883f` 的"目标重新验证"、"写入与恢复"与 `RecoveryTests` 条目; Evidence: 需在重写后重新产出（原 `evidence/T-021-authoritative-write-recovery-red.md` 只覆盖作废前的算法，不得作为本任务证据）

- [ ] **T-022 [Implementation] 实现权威验证、替换与恢复（按重开后的 Plan 算法重写）。** 本任务已于 2026-07-28 随 Plan Gate 第三版修订（`0c9883f`）重写，原"只写最初选区或全文、不增加第二写入策略"的表述作废，勾选状态清空。仅实现使 T-021 失败测试转绿所需的最小代码：
  1. 在 `AccessibilityGateway` actor 内实现共享前置检查 A1–A4，并把 settable 检查下沉到 replacement／whole-field recovery／selected R1／selected R2 四条路径，每条只检查其实际写入的属性。
  2. replacement 保持严格单 setter（B1–B2），失败时不执行第二种写入策略。
  3. recovery 在入口按 capture mode 分支：新增 whole-field recovery 的独立实现（W1–W4），该路径不得计算或读取 selected range，也不得使用 `kAXSelectedTextAttribute`。
  4. selected recovery 实现 C1–C4 与 R1／R2／R3 分类，含 C2 的两类排除项；R3 立即 fail-closed。
  5. 重写现有 `restoreCollapsedSelection` 为批准后的 selected-range recovery fallback：只在 R2 判定成立时进入，逐项实现六项门禁，基值必须在全部门禁通过后紧邻 setter 获取并校验，范围计算与替换全部使用 UTF-16 code unit，写后回读确认；任一失败返回 `recoveryTargetChanged`，不得改回 selected setter 或第二次写入。
  6. 不得依赖 AXObserver 通知授权 fallback；监控只用于提前禁用按钮。
  7. 不得为消除 TOCTOU 而引入清空、模拟全选、模拟粘贴、分段写入或任何额外写入策略；残余风险按 Plan 记录接受。
  — Depends on: T-021; Covers: FR-009, FR-010, FR-012, NFR-002; Plan: `0c9883f`; Evidence: 需在转绿后重新产出（原 `evidence/T-022-authoritative-write-recovery-green.md` 对应作废前的算法）

- [x] **T-023 [Test] 编写 AXObserver 投递与隔离测试。** 先证明 observer run-loop source 挂载在 main run loop；callback 只捕获 session ID 与 target ID，再异步跳入 `AccessibilityGateway` actor；过期 callback 被忽略，监控通知只能提前禁用按钮，不能授权写入或恢复。— Depends on: T-020; Covers: FR-009, FR-011, NFR-002, AC-009, AC-011; Resolves: Plan Gate NIT-1; Evidence: `evidence/T-023-ax-observer-delivery-red.md`
- [x] **T-024 [Implementation] 实现外部目标监控。** 组合主 run loop 上的 `AXObserver` 与 `NSWorkspace` 通知，按 T-023 的 actor 隔离规则投递；注销 observer 时释放 run-loop source 和 AX 句柄。— Depends on: T-023; Covers: FR-009, FR-011, NFR-002; Evidence: `evidence/T-024-external-target-monitor-green.md`
- [x] **T-025 [Test] 编写屏幕几何转换测试。** 先覆盖光标/选区/元素/窗口/活跃显示器锚点优先级、AX 与 AppKit 坐标转换、可见区域收敛、面板大于可用区域和屏幕变化。— Depends on: T-010; Covers: FR-007, NFR-005, AC-015; Evidence: `evidence/T-025-screen-geometry-red.md`
- [x] **T-026 [Implementation] 实现几何转换与面板控制器。** 以 T-025 规则选择锚点、限制完整面板在单一活跃显示器，并保持 nonactivating 行为；不得把获取不到精确边界当作会话失败。— Depends on: T-025; Covers: FR-007, NFR-005; Evidence: `evidence/T-026-screen-geometry-green.md`
- [x] **T-027 [Test] 编写预览状态与操作测试。** 先覆盖 ready、permissionRequired、secureInput、emptyOrUnsupported、staleTarget、writeFailed、recoveryUnavailable 的文案和按钮矩阵；只有 ready 显示可用确认，所有拒绝/失败状态至少有一个安全下一步，界面不显示原始错误码或敏感内容。— Depends on: T-012, T-014, T-016, T-018, T-022, T-026; Covers: FR-005, FR-007, FR-008, NFR-007, AC-002, AC-003, AC-004, AC-007, AC-008, AC-009, AC-010, AC-013; Evidence: `evidence/T-027-preview-state-actions-red.md`
- [x] **T-028 [Implementation] 实现预览与应用生命周期装配。** 实现最小 SwiftUI 内容和 `AppLifecycleController`，接入已测试协议；提供确认、复制、取消、恢复、复制原文、打开设置和重新检测，不加入最终视觉系统或设置体验。— Depends on: T-027; Covers: FR-001, FR-002, FR-005, FR-007, FR-008, NFR-007; Evidence: `evidence/T-028-preview-lifecycle-green.md`

### P4 — 合成集成闭环

- [x] **T-029 [Test Harness] 建立合成 AX 宿主。** 只使用 `SYNTHETIC-001`，提供选区、全文、空值、只读、安全输入、元素失效、窗口切换和可控 setter 失败夹具；宿主不读取真实应用内容，不把内容写入日志或测试产物。— Depends on: T-004, T-020; Covers: FR-004, FR-013, NFR-003, NFR-004, NFR-006, AC-005, AC-006, AC-007, AC-009, AC-014, AC-016; Evidence: `evidence/T-029-synthetic-ax-host.md`
- [x] **T-030 [Test] 编写端到端集成测试。** 先以合成宿主和 spy 覆盖快捷键→权限→读取→预览→确认→单次写入→恢复，以及取消、复制、过期目标、写入失败、新会话替代、内容清除；每个路径断言确认前 setter 为 0。— Depends on: T-006, T-016, T-018, T-022, T-024, T-026, T-028, T-029; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007, AC-001 至 AC-016; Evidence: `evidence/T-030-end-to-end-red.md`
- [x] **T-031 [Implementation] 完成最小闭环装配。** 仅补齐 T-030 暴露的依赖注入、事件路由与状态同步，使合成端到端测试通过；不得借机加入未被失败测试要求的功能。— Depends on: T-030; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007; Evidence: `evidence/T-031-end-to-end-green.md`

### P5 — 真实环境验收与证据

- [x] **T-032 [Verification] 验证 TextEdit 完整闭环。** 使用合成输入记录选区前后字节不变、预览前零写入、确认后只替换选区、恢复原文和关闭恢复状态后的标准 Undo 行为。— Depends on: T-031; Covers: FR-001, FR-004, FR-006 至 FR-010, FR-012, NFR-002, NFR-003, AC-001, AC-005, AC-008, AC-009, AC-012, AC-017; Evidence: `evidence/T-032-textedit-closed-loop.md`
- [x] **T-033 [Verification] 验证 Chrome/ChatGPT 完整闭环。** 使用合成输入记录无选区时读取全文、预览前零写入、确认后只替换目标输入框、目标切换拦截、恢复原文和标准 Undo；若完整闭环失败，触发硬停止条件。— Depends on: T-031; Covers: FR-001, FR-004, FR-006 至 FR-010, FR-012, NFR-002, NFR-003, AC-001, AC-006, AC-008, AC-009, AC-012, AC-017; Evidence: `evidence/T-033-chrome-chatgpt-closed-loop.md`
- [x] **T-034 [Verification] 验证 VS Code 后备闭环。** 先记录直接读写实际能力；无可靠支持时验证用户主动剪贴板输入、明确复制结果和手动粘贴路径，证明无自动剪贴板访问且不修改无关文字。— Depends on: T-031; Covers: FR-010, NFR-002, NFR-003, NFR-006, AC-010; Evidence: `evidence/T-034-vscode-fallback-closed-loop.md`
- [x] **T-035 [Verification] 验证权限、安全与失败恢复矩阵。** 覆盖权限缺失/重新授权、设置深链降级、安全输入、快捷键冲突、空/不支持目标、过期目标、写入/恢复失败和重复触发；逐项记录可理解文案、安全下一步及写入/剪贴板计数。— Depends on: T-031; Covers: FR-001 至 FR-005, FR-008 至 FR-012, NFR-002, NFR-006, NFR-007, AC-002, AC-003, AC-004, AC-007, AC-008, AC-009, AC-010, AC-011, AC-013; Evidence: `evidence/T-035-permission-safety-recovery-matrix.md`
- [x] **T-036 [Evidence] 采集性能与显示证据。** 在 TextEdit 和 Chrome/ChatGPT 各连续触发 10 次，至少 9 次从 hot-key callback 到可见外壳/明确状态不超过 300ms；记录 callback 是可观测起点且**不包含物理按键到 callback 的操作系统投递延迟**，并记录 Mac、macOS、应用版本、全屏、显示器布局和缩放。不得为获得物理按键时间戳引入按键监听。— Depends on: T-032, T-033; Covers: FR-001, FR-007, NFR-001, NFR-005, AC-001, AC-015; Resolves: Plan Gate NIT-2; Evidence: `evidence/T-036-performance-display.md`
- [x] **T-037 [Verification] 验证代表性文字矩阵。** 在必须支持的应用中执行中文、英文、中英混合、空文本、多行、10,000 字符长文本和特殊字符；记录具体长度与应用限制，核对无崩溃、静默截断或无关修改。— Depends on: T-032, T-033, T-034; Covers: FR-006, NFR-004, AC-007, AC-016; Evidence: `evidence/T-037-representative-text-matrix.md`
- [x] **T-038 [Audit] 执行隐私与安全审计。** 检查文件、配置、日志、崩溃自定义字段、截图、测试结果和遥测均无真实内容；复核安全输入零读取/转换/展示/复制/写入，正常路径剪贴板访问次数和会话结束后的敏感引用释放。— Depends on: T-035, T-037; Covers: FR-003, FR-013, NFR-006, AC-004, AC-008, AC-014; Evidence: `evidence/T-038-privacy-security-audit.md`
- [x] **T-039 [Evidence] 汇总可复现验收包。** ⚠️ **结论已于 2026-07-28 被 Implementation Gate REVIEW 推翻，且其汇总不再构成 HANDOFF 依据**；更新与重新汇总由 T-046 承载。 汇总所有自动测试、探针、人工矩阵、性能数据、环境版本、已知限制和 Undo 观察；逐项核对本文件所有 FR/NFR/AC，运行 build、unit-tests、`sdd-check`、`secret-scan`、`git diff --check`，确认无未解释失败后再发 Implementation Gate `HANDOFF`。— Depends on: T-032 至 T-038; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007, AC-001 至 AC-017; Evidence: `evidence/T-039-acceptance-package.md`

### P6 — 恢复算法重写后的下游复核（2026-07-28 新增）

本段任务因 Plan Gate 第三版修订（`0c9883f`）与 T-021／T-022 重写而新增。
P5 的人工复核范围由 Solar 在 Tasks Gate REVIEW 中裁决为"按影响面限定"，
下列 T-041 至 T-045 即该裁决的完整范围，不得再自行收窄。
原 Implementation REVIEW 的 Finding 1、2、4、5、6 的实际修复若触及恢复
之外的行为，必须按各自 diff 另行扩大复核范围；本段不预先豁免。

- [ ] **T-040 [Verification] 自动化下游复核。** 在 T-022 转绿后，运行 T-027、T-030／T-031 所在的完整相关测试，并运行全量 `./scripts/build.sh`、`./scripts/unit-tests.sh`、`./scripts/project-structure-check.sh`、`./scripts/sdd-check.sh`、`./scripts/secret-scan.sh` 与 `git diff --check`。完成条件：上述测试与门禁连续两次全绿、无未解释失败，且记录测试总数与前后差异；在此之前 C3 与 C4 均为未达成。— Depends on: T-022; Covers: FR-005, FR-007, FR-008, FR-009, FR-010, FR-012, NFR-002, AC-009, AC-012, AC-013; Evidence: `evidence/T-040-downstream-automation-revalidation.md`
- [ ] **T-041 [Verification] 复核 TextEdit selected recovery。** 在真实 TextEdit 中复核选区捕获→替换→恢复原文的完整闭环：恢复后原文逐字节还原、expected result range 之外的内容保持完全不变、目标应用标准 ⌘Z Undo 行为。完成条件：三项均记录实测结果，并注明走的是 R1 还是 R2 fallback 分支。— Depends on: T-040; Covers: FR-012, NFR-002, NFR-003, AC-005, AC-012, AC-017; Evidence: `evidence/T-041-textedit-selected-recovery-revalidation.md`
- [ ] **T-042 [Verification] 复核 Chrome／ChatGPT whole-field recovery。** W1–W4 是本轮新增的独立算法，不得沿用 T-033 旧证据。在真实 Chrome／ChatGPT 中复核无选区全文捕获→替换→恢复原文闭环与标准 ⌘Z Undo。完成条件：记录 W1–W4 各步实测表现（含回读确认）、恢复后内容逐字节还原、Undo 行为。— Depends on: T-040; Covers: FR-012, NFR-002, NFR-003, AC-006, AC-012, AC-017; Evidence: `evidence/T-042-chatgpt-wholefield-recovery-revalidation.md`
- [ ] **T-043 [Verification] 复核恢复相关状态与访问计数。** 复核恢复成功后的面板状态、恢复失败后保留原文并提供复制原文的路径，以及两条路径的 setter 与剪贴板访问计数。完成条件：成功与失败两条路径的面板文案、按钮矩阵、AX setter 次数与剪贴板读写次数均逐项记录，失败路径确认零额外写入。— Depends on: T-040; Covers: FR-008, FR-012, NFR-002, NFR-006, NFR-007, AC-008, AC-012, AC-013; Evidence: `evidence/T-043-recovery-state-and-counts-revalidation.md`
- [ ] **T-044 [Verification] 复核 UTF-16 范围相关的特殊字符夹具。** 只重跑与新 UTF-16 范围算法直接相关的 TextEdit selected recovery 夹具，至少包含 Emoji、Unicode 组合字符与代理对；不重跑完整文字矩阵。完成条件：每类夹具记录具体码点构成、替换与恢复后逐 UTF-16 code unit 一致、范围外内容完全不变。— Depends on: T-040; Covers: FR-006, FR-012, NFR-004, AC-016; Evidence: `evidence/T-044-utf16-recovery-fixtures-revalidation.md`
- [ ] **T-045 [Audit] 定向隐私与安全审计。** 只针对本轮恢复实现变更执行定向审计，确认未新增内容日志、持久化、敏感附件或遥测，且恢复路径的基值与原文引用在会话结束时释放；不重跑与恢复无关的审计步骤。完成条件：逐项列出被审计的新增／修改代码位置与结论。— Depends on: T-040; Covers: FR-013, NFR-006, AC-014; Evidence: `evidence/T-045-recovery-privacy-audit.md`
- [ ] **T-046 [Evidence] 更新验收包并重新发布 Implementation Gate HANDOFF。** 更新 `evidence/T-039-acceptance-package.md` 的汇总、需求映射与已知风险（含 R2 不可区分与 whole-field setter 的 TOCTOU 残余风险披露），纳入 T-040 至 T-045 结果与原 Implementation REVIEW Finding 1、2、4、5、6 的修复证据；运行完整 build、unit-tests、`sdd-check`、`secret-scan`、`git diff --check`，确认无未解释失败后才可针对新 SHA 发布 Implementation Gate `HANDOFF`。— Depends on: T-040, T-041, T-042, T-043, T-044, T-045; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007, AC-001 至 AC-017; Evidence: `evidence/T-039-acceptance-package.md`

## 检查点

- **C0 — 工具链可执行：** T-004 通过；完整 Xcode、目标配置、CI 与基础测试发现均可复现。
- **C1 — 高风险假设成立：** T-007 与 T-010 已通过；快捷键/安全输入和非激活面板没有触发 Plan 的硬停止条件。
- **C2 — 领域安全不变量成立：** T-014 通过；确认前零 setter、单会话、会话清理及 `recoverable → previewing(recoveryUnavailable)` 已由失败优先测试证明。
- **C3 — 系统边界可控：** T-028 通过；权限、剪贴板、AX、observer、几何和预览各自有测试，并且权威写入验证未被监控事件取代。**2026-07-28 起本检查点回退为未达成**，需在重写后的 T-021／T-022 转绿并由 T-040 自动化下游复核确认后重新判定。
- **C4 — 合成闭环通过：** T-031 通过；全部生产装配由 T-030 的端到端失败测试驱动。**2026-07-28 起本检查点回退为未达成**：T-021／T-022 已按 Plan `0c9883f` 重写，T-027 与 T-030／T-031 的既有结果不代表覆盖已达成，须待 T-040 自动化下游复核重新转绿后判定。
- **C5 — 真实验收完整：** T-039 通过；TextEdit 与 Chrome/ChatGPT 完整闭环、VS Code 后备闭环、性能/显示/输入/隐私证据均可复现。 ~~已达成（2026-07-28）~~ **已回退为未达成**：Implementation Gate 审核结论为 CHANGES REQUESTED，且 T-021／T-022 已重写；须待 T-040 至 T-046 全部完成后重新判定。原记录：121 tests 全绿，build/structure/sdd/secret/diff-check 五道门禁通过，7 项已知限制已如实披露，详见 `evidence/T-039-acceptance-package.md`。

## Plan Gate NIT 处置约束

| Finding | Tasks Gate 的强制落实 | 关闭条件 |
| --- | --- | --- |
| NIT-1 | T-023/T-024 明确 AXObserver source 挂载于 main run loop，callback 再跳入 actor，监控不是写入授权 | Fable 确认任务表述覆盖并在 Tasks Gate 关闭 |
| NIT-2 | T-036 明确 300ms 证据从 hot-key callback 起算，不包含 OS 投递延迟，且禁止增加按键监听 | Fable 确认测量边界可审计并在 Tasks Gate 关闭 |
| NIT-3 | T-013/T-014 明确测试并实现 `recoverable → previewing(recoveryUnavailable)`，仅允许复制原文或关闭 | Fable 确认状态、动作与禁止写入均被覆盖后关闭 |

## Tasks Gate 记录

- Plan Gate 通过提交（当前权威）：`0c9883f8385c731b0cc084d22519224eada926ea`
  —— 重开后的 Plan Gate 第三版修订，Solar `PASS`（2026-07-28，REVIEW 见 PR #2 issuecomment-5112794473）
- Plan Gate 通过提交（历史，首次 Plan Gate，已被上述修订取代）：`c5666be0aefb4523e21a2544722511f087201360`
- 用户授权：已授权编写 `tasks.md`；未授权安装依赖、创建工程或开发
- 用户书面确认：2026-07-20 已确认本任务清单，可以交给 Fable 进行 Tasks Gate 审核
- Review commit SHA 与 Reviewer 结论：以 PR #2 中后续结构化 `HANDOFF` 和 `REVIEW` 评论为权威记录
- 审核更新规则：任何 `HANDOFF` 后的新提交都会使旧审核请求失效，Owner 必须针对新的准确 SHA 重新发布 `HANDOFF`
- PR 审核位置：PR #2
- Implementation Gate：已获用户逐项授权，当前完成 T-001 至 T-027，C1、C2 已达成；T-027 已建立七种预览状态的中文说明、按钮矩阵、仅 ready 可确认、安全下一步与无原始错误/敏感内容的稳定 RED 边界，连续两次因缺少 T-028 预览展示契约而按预期失败，生产构建与仓库门禁保持绿色；T-028 已获用户授权并完成——最薄预览展示契约、最小 SwiftUI 内容与 `AppLifecycleController` 装配使 T-027 五个测试连续两次转绿（89 tests, 0 failures），证据见 `evidence/T-028-preview-lifecycle-green.md`；用户于 2026-07-25 授权：跳过逐任务 Reviewer 审核，剩余任务全部完成后统一审核；T-029 已完成——合成 AX 宿主夹具与 9 个自检测试连续两次通过（98 tests, 0 failures），证据见 `evidence/T-029-synthetic-ax-host.md`；T-030 已完成——11 个合成端到端集成测试建立稳定 RED（连续两次 exit 65，错误仅指向缺失的 T-031 集成契约），证据见 `evidence/T-030-end-to-end-red.md`；T-031 已完成——最小闭环装配（GatewaySessionTextTarget 桥接、捕获/监控/清理路由、恢复呈现）使 11 个端到端测试连续两次转绿（109 tests, 0 failures），C4 达成，build/structure/sdd/secret 门禁全绿，证据见 `evidence/T-031-end-to-end-green.md`；T-032、T-033 已于 2026-07-28 完成真实环境人工验证（证据见 `evidence/T-032-textedit-closed-loop.md`、`evidence/T-033-chrome-chatgpt-closed-loop.md`），NFR-003 最低兼容标准达标、硬停止未触发；用户于 2026-07-28 决策（方案 A）：Chrome 选区替换与「所有输入框无差别可用」两项硬需求超出本 Feature 范围，作为新 Feature 走独立 Spec Gate，Feature 001 按现有规格收尾（决策与微信范围外观察见 `evidence/out-of-scope-observations.md`）；T-034 已于 2026-07-28 完成——VS Code 直接读写不受支持并 fail-closed，用户主动剪贴板后备路径（复制→使用剪贴板→复制结果→手动粘贴）输出正确，AC-010 达成，证据见 `evidence/T-034-vscode-fallback-closed-loop.md`；T-035 已于 2026-07-28 完成——十项矩阵（空/不支持目标、过期拦截、重复触发、恢复、权限缺失、深链降级、重新授权、安全输入、快捷键冲突）全部通过，拒绝路径零写入，记录两项已知限制（辅助功能设置深链停在通用页、面板按钮未暴露 AX 标题），证据见 `evidence/T-035-permission-safety-recovery-matrix.md`；T-036 已于 2026-07-28 完成——为满足 300ms 可观测起点新增最小延迟仪器（PresentationLatencyRecording + os_log，仅记录毫秒不含内容，由 PresentationLatencyInstrumentationTests 驱动，118 tests 全绿），TextEdit 与 ChatGPT 各连续 10 次触发全部 20 个样本均在 300ms 内（最大 118.4ms），Plan Gate NIT-2 关闭，证据见 `evidence/T-036-performance-display.md`；T-037 已于 2026-07-28 完成——TextEdit 六类（中文/英文/混合/多行/特殊字符含 emoji 与组合字符/10,000 字符长文本）与 ChatGPT 两类（混合+特殊字符、10,000 字符长文本）逐字保真、无截断无无关修改，空文本引用 T-035，证据见 `evidence/T-037-representative-text-matrix.md`；T-038 已于 2026-07-28 完成——六个审计维度（仓库文件与配置、日志/崩溃/遥测、敏感值不可序列化、安全输入零处理、剪贴板三个显式入口、会话结束引用释放）全部通过，无真实内容或凭据，证据见 `evidence/T-038-privacy-security-audit.md`；T-039 已于 2026-07-28 完成——逐项核对 13 条 FR、7 条 NFR、17 个 AC 全部达成，121 tests 全绿，五道门禁无未解释失败，C5 达成；P5 期间由测试驱动产生两处生产变更（`8b75e6f` 延迟仪器、`4b25cd1` 修复 FR-001/AC-002 快捷键冲突静默失效缺口）；证据见 `evidence/T-039-acceptance-package.md`；Solar 于 2026-07-28 对 `ebb6978` 的 Implementation Gate 审核结论为 CHANGES REQUESTED（6 项 MUST），T-039 原判定已推翻，Tasks 与 Implementation Gate 随 Plan Gate 重开一并重开。**⚠️ 以上进度段截至 2026-07-28 Implementation Gate 审核前，其中关于"当前阶段"的描述已全部失效**，本文件的当前阶段以下方 2026-07-28 Tasks Gate 记录为唯一权威
- **2026-07-28 Tasks Gate 重开与修订：** Plan Gate 第三版修订
  `0c9883f8385c731b0cc084d22519224eada926ea` 已获 Solar `PASS`
  （REVIEW 见 PR #2 issuecomment-5112794473）。据此重写 T-021 与 T-022：
  T-021 按共享前置检查 A1–A4、路径化 settable 检查、replacement B1–B2、
  recovery 入口分支、whole-field recovery W1–W4、selected recovery
  C1–C4 与 R1／R2／R3 分类、R2 不推断来源语义、fallback 六项门禁逐项失败
  测试、UTF-16 夹具与失败后复制路径共十组要求重建失败优先测试；
  T-022 只实现使上述测试转绿所需的最小代码，并重写现有
  `restoreCollapsedSelection` 为批准后的 selected-range recovery fallback。
  两个任务的勾选状态已清空，原证据文件不再作为其覆盖依据。
  `plan_version` 已同步为 `0c9883f`，本文件 status 改为
  `revised-pending-review`。本轮只修改 `tasks.md`，未修改源码或测试，
  也未处理旧 Implementation findings；Tasks Gate 取得 `PASS` 后才会进入
  实现修复。
- **2026-07-28 Tasks Gate 第二轮修订（回应 Solar 对 `ae99e29` 的两项 MUST）：**
  ① 修正权威角色与基线记录——阶段边界改为由 Solar 对准确 SHA 给出 Tasks Gate
  `PASS` 且 Owner 不得自审；"Plan Gate 通过提交"更新为 `0c9883f`（旧
  `c5666be` 明确标为历史首次 Plan Gate）；旧 Implementation 进度段末尾关于
  "当前阶段"的描述明确标记为失效，确保本文件只有一个当前阶段。
  ② 把下游复核写成 P6 段的可执行任务 T-040 至 T-046，全部未勾选并带
  Depends on、完成条件与 Evidence；其中 T-040 承载 T-027 与 T-030／T-031 的
  完整相关测试与全量门禁复核，T-041 至 T-045 承载 Solar 裁决的限定 P5 范围
  （TextEdit selected recovery、ChatGPT whole-field recovery、恢复状态与
  setter／剪贴板计数、UTF-16 特殊字符夹具、定向隐私审计），T-046 承载验收包
  更新与 Implementation Gate HANDOFF；依赖顺序新增 P6 且明确 T-046 通过前
  不得请求 Implementation Gate 最终审核。
  ③ 检查点 C4 回退为未达成，C3 与 C5 保持未达成，均以 T-040 至 T-046 的
  结果为重新判定依据。
  ④ Open question 已由 Solar 裁决：允许按影响面限定 P5，但 Owner 原提议范围
  过窄，最终范围以 T-041 至 T-045 为准，不得再自行收窄；T-034、T-036、
  权限矩阵中与恢复无关的项、完整显示矩阵与完整文字矩阵不因本次恢复算法
  重跑；原 Implementation REVIEW Finding 1、2、4、5、6 的修复若触及其他行为，
  须按各自 diff 另行扩大复核范围。
