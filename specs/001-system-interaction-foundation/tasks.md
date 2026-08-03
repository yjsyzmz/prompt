---
feature: "001-system-interaction-foundation"
stage: tasks
status: revised-pending-review  # Tasks Gate 第三次重开第三版修订（2026-08-03）：P8 为 T-058、T-063、T-064、T-061、T-062，须取得 Tasks PASS 才能开工；ChatGPT 修复须经 T-064 后的新一轮 Tasks Gate 定义
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
| FR-007 | AC-005, AC-006, AC-015 | T-008, T-025, T-027, T-053 | T-009, T-026, T-028, T-053 | T-032, T-033, T-036, T-055, T-057 |
| FR-008 | AC-005, AC-006, AC-008, AC-009 | T-013, T-017, T-027, T-030, T-054 | T-014, T-018, T-028, T-031, T-053, T-054 | T-032, T-033, T-035, T-055, T-057 |
| FR-009 | AC-009, AC-012, AC-013 | T-013, T-021, T-023, T-030, T-054 | T-014, T-022, T-024, T-031, T-053, T-054 | T-032, T-033, T-035, T-055, T-057 |
| FR-010 | AC-005, AC-006, AC-010 | T-017, T-021, T-030, T-054 | T-018, T-022, T-031, T-053 | T-032, T-033, T-034, T-055, T-057 |
| FR-011 | AC-011 | T-013, T-023, T-030 | T-014, T-024, T-031 | T-035 |
| FR-012 | AC-012, AC-013, AC-017 | T-013, T-021, T-030 | T-014, T-022, T-031 | T-032, T-033, T-039, T-055, T-057 |
| FR-013 | AC-014 | T-011, T-013, T-017, T-030, T-052 | T-012, T-014, T-018, T-031, T-052 | T-038, T-057 |
| NFR-001 | AC-001 | T-005, T-030 | T-006, T-031 | T-036 |
| NFR-002 | AC-003 至 AC-016 | T-013, T-021, T-030, T-053 | T-014, T-022, T-031, T-053 | T-032 至 T-038, T-055, T-057 |
| NFR-003 | AC-005, AC-006, AC-010 | T-029, T-030, T-054 | T-031, T-053 | T-032, T-033, T-034, T-055, T-057 |
| NFR-004 | AC-007, AC-016 | T-011, T-019, T-029, T-030 | T-012, T-020, T-031 | T-037 |
| NFR-005 | AC-015 | T-008, T-025, T-030 | T-009, T-026, T-031 | T-036 |
| NFR-006 | AC-003, AC-004, AC-008, AC-014 | T-011, T-017, T-030, T-052 | T-012, T-018, T-031, T-052 | T-038, T-057 |
| NFR-007 | AC-002, AC-003, AC-004, AC-007, AC-009, AC-010, AC-013 | T-011, T-013, T-015, T-027, T-030, T-054 | T-012, T-014, T-016, T-028, T-031, T-054 | T-035, T-055, T-057 |

表中 FR-009／FR-010／FR-012／NFR-002 对应的 T-021／T-022 已于 2026-07-28 按 Plan `0c9883f` 重写，覆盖关系在重新转绿前不成立。受影响需求的最终覆盖还需 P6 段的 T-040 至 T-046 完成：自动化复核见 T-040，恢复相关的人工与审计复核见 T-041 至 T-045，汇总见 T-046。

**P7 对追踪表的影响（2026-07-31，Tasks Gate 第二次重开第三版）**：T-050 与 T-046 的验收证据结论已被 `5070607` 的 Implementation REVIEW 推翻，表中凡以 T-039／T-046 为验收证据的行，其覆盖在 T-057 重建验收包之前均不成立。新增覆盖关系：FR-013／NFR-006 的隐私边界由 T-052 重新落实；FR-007／FR-008／NFR-002 的目标有效性判定由 T-053 重新落实；FR-008／NFR-007 的失败呈现由 T-054 重新落实；FR-007／FR-008／FR-012／NFR-002／NFR-007 与 AC-005／AC-006／AC-012／AC-013／AC-017 的真实环境证据由 T-055 以真人驱动重建；全部需求的最终出口唯一收敛到 T-057。凡由 AXPress 驱动的既有证据均不覆盖预览面板成为 key window 的真人路径，须在 T-057 中逐项标注。

**P8 对追踪表的影响（2026-08-03，第二版修订）**：T-055 已取得的 (a)(b) 结果因后续
代码变更而失效，须由 T-062 在最终代码上重取，因此**凡以 T-055 为验收证据的行，其
覆盖在 T-062 完成前均不成立**。新增覆盖关系：FR-013／NFR-006／NFR-007 的诊断可见性
由 T-058 落实（监听器路径，遵守 observer 回调只带 session ID 与 target ID 的边界）；
FR-008／NFR-007 的回读确认边界由 T-061 落实（有界、单次 setter、超时 fail-closed；
**与 AC-008、NFR-001 无关**——NFR-001 的 300ms 只约束确认前的预览呈现）；
FR-007／FR-008／FR-012／NFR-007 与 AC-005／AC-006／AC-012／AC-013／AC-017 的真实
环境证据由 T-062 重建。Google 搜索框选区兼容依 `BLOCKER` 移出 001，不出现在本表。

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
- [x] **T-021 [Test] 编写重新验证、写入与恢复测试（按重开后的 Plan 算法重写）。** 本任务已于 2026-07-28 随 Plan Gate 第三版修订（`0c9883f`）重写，原"七项确认前权威检查 + 恢复不增加第二种写入策略"的表述作废，勾选状态清空，必须按下列批准算法重新建立失败优先测试：
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
  — Depends on: T-020; Covers: FR-009, FR-010, FR-012, NFR-002, AC-005, AC-006, AC-009, AC-010, AC-012, AC-013, AC-017; Plan: `0c9883f` 的"目标重新验证"、"写入与恢复"与 `RecoveryTests` 条目; Evidence: `evidence/T-021-recovery-algorithm-red.md`（2026-07-28 稳定 RED：149 tests、27 failures，失败全部集中在新增 `AXRecoveryAlgorithmTests.swift` 且逐项指向缺失的 T-022 算法；原 `evidence/T-021-authoritative-write-recovery-red.md` 只覆盖作废前的算法，不作为本任务证据）

- [x] **T-022 [Implementation] 实现权威验证、替换与恢复（按重开后的 Plan 算法重写）。** 本任务已于 2026-07-28 随 Plan Gate 第三版修订（`0c9883f`）重写，原"只写最初选区或全文、不增加第二写入策略"的表述作废，勾选状态清空。仅实现使 T-021 失败测试转绿所需的最小代码：
  1. 在 `AccessibilityGateway` actor 内实现共享前置检查 A1–A4，并把 settable 检查下沉到 replacement／whole-field recovery／selected R1／selected R2 四条路径，每条只检查其实际写入的属性。
  2. replacement 保持严格单 setter（B1–B2），失败时不执行第二种写入策略。
  3. recovery 在入口按 capture mode 分支：新增 whole-field recovery 的独立实现（W1–W4），该路径不得计算或读取 selected range，也不得使用 `kAXSelectedTextAttribute`。
  4. selected recovery 实现 C1–C4 与 R1／R2／R3 分类，含 C2 的两类排除项；R3 立即 fail-closed。
  5. 重写现有 `restoreCollapsedSelection` 为批准后的 selected-range recovery fallback：只在 R2 判定成立时进入，逐项实现六项门禁，基值必须在全部门禁通过后紧邻 setter 获取并校验，范围计算与替换全部使用 UTF-16 code unit，写后回读确认；任一失败返回 `recoveryTargetChanged`，不得改回 selected setter 或第二次写入。
  6. 不得依赖 AXObserver 通知授权 fallback；监控只用于提前禁用按钮。
  7. 不得为消除 TOCTOU 而引入清空、模拟全选、模拟粘贴、分段写入或任何额外写入策略；残余风险按 Plan 记录接受。
  — Depends on: T-021; Covers: FR-009, FR-010, FR-012, NFR-002; Plan: `0c9883f`; Evidence: `evidence/T-022-recovery-algorithm-green.md`（2026-07-28：149 tests、0 failures，连续两次一致；原 `evidence/T-022-authoritative-write-recovery-green.md` 对应作废前的算法，不作为本任务证据）

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

- [x] **T-040 [Verification] 自动化下游复核。** 在 T-022 转绿后，运行 T-027、T-030／T-031 所在的完整相关测试，并运行全量 `./scripts/build.sh`、`./scripts/unit-tests.sh`、`./scripts/project-structure-check.sh`、`./scripts/sdd-check.sh`、`./scripts/secret-scan.sh` 与 `git diff --check`。完成条件：上述测试与门禁连续两次全绿、无未解释失败，且记录测试总数与前后差异；在此之前 C3 与 C4 均为未达成。— Depends on: T-022; Covers: FR-005, FR-007, FR-008, FR-009, FR-010, FR-012, NFR-002, AC-009, AC-012, AC-013; Evidence: `evidence/T-040-downstream-automation-revalidation.md`（2026-07-30：172 tests 与五道门禁连续两次全绿，测试总数 109→172 净增 63，无回退）
- [x] **T-041 [Verification] 复核 TextEdit selected recovery。** 在真实 TextEdit 中复核选区捕获→替换→恢复原文的完整闭环：恢复后原文逐字节还原、expected result range 之外的内容保持完全不变、目标应用标准 ⌘Z Undo 行为。完成条件：三项均记录实测结果，并注明走的是 R1 还是 R2 fallback 分支。— Depends on: T-040; Covers: FR-012, NFR-002, NFR-003, AC-005, AC-012, AC-017; Evidence: `evidence/T-041-textedit-selected-recovery-revalidation.md`（2026-07-30：替换与恢复闭环通过，恢复经确认走 R2 fallback 且命中「含两端」边界，范围外逐 code unit 不变）
- [x] **T-042 [Verification] 复核 Chrome／ChatGPT whole-field recovery。** W1–W4 是本轮新增的独立算法，不得沿用 T-033 旧证据。在真实 Chrome／ChatGPT 中复核无选区全文捕获→替换→恢复原文闭环与标准 ⌘Z Undo。完成条件：记录 W1–W4 各步实测表现（含回读确认）、恢复后内容逐字节还原、Undo 行为。— Depends on: T-040; Covers: FR-012, NFR-002, NFR-003, AC-006, AC-012, AC-017; Evidence: `evidence/T-042-chatgpt-wholefield-recovery-revalidation.md`（2026-07-30：W1–W4 逐步实测通过，恢复后指纹与原文完全一致；⌘Z 在 Chrome 中会撤销 AX 写入，与 TextEdit 相反）
- [x] **T-043 [Verification] 复核恢复相关状态与访问计数。** 复核恢复成功后的面板状态、恢复失败后保留原文并提供复制原文的路径，以及两条路径的 setter 与剪贴板访问计数。完成条件：成功与失败两条路径的面板文案、按钮矩阵、AX setter 次数与剪贴板读写次数均逐项记录，失败路径确认零额外写入。— Depends on: T-040; Covers: FR-008, FR-012, NFR-002, NFR-006, NFR-007, AC-008, AC-012, AC-013; Evidence: `evidence/T-043-recovery-state-and-counts-revalidation.md`（2026-07-30：成功路径各阶段恰好一次写入；失败路径 2 按钮、零额外写入、按原因细化文案；剪贴板指纹前后一致）
- [x] **T-044 [Verification] 复核 UTF-16 范围相关的特殊字符夹具。** 只重跑与新 UTF-16 范围算法直接相关的 TextEdit selected recovery 夹具，至少包含 Emoji、Unicode 组合字符与代理对；不重跑完整文字矩阵。完成条件：每类夹具记录具体码点构成、替换与恢复后逐 UTF-16 code unit 一致、范围外内容完全不变。— Depends on: T-040; Covers: FR-006, FR-012, NFR-004, AC-016; Evidence: `evidence/T-044-utf16-recovery-fixtures-revalidation.md`（2026-07-30：代理对与组合字符夹具，replacedSpanExact=true，恢复后指纹与原文完全相同，第二次命中 R2「含两端」边界）
- [x] **T-045 [Audit] 定向隐私与安全审计。** 只针对本轮恢复实现变更执行定向审计，确认未新增内容日志、持久化、敏感附件或遥测，且恢复路径的基值与原文引用在会话结束时释放；不重跑与恢复无关的审计步骤。完成条件：逐项列出被审计的新增／修改代码位置与结论。— Depends on: T-040; Covers: FR-013, NFR-006, AC-014; Evidence: `evidence/T-045-recovery-privacy-audit.md`（2026-07-30：五项审计通过，本轮变更零新增日志/持久化/遥测，AXMonitoringTarget 不携带文本，引用在正常与竞态两路径均释放）
- [x] **T-046 [Evidence] 更新验收包并重新发布 Implementation Gate HANDOFF。** ✅ **2026-07-30 完成**：验收包已重写（172 tests 与五道门禁全绿，13 FR／7 NFR／17 AC 逐项核对达成，10 项已知限制与残余风险如实披露），C3／C4／C5 达成。 更新 `evidence/T-039-acceptance-package.md` 的汇总、需求映射与已知风险（含 R2 不可区分与 whole-field setter 的 TOCTOU 残余风险披露），纳入 T-040 至 T-045 结果与原 Implementation REVIEW Finding 1、2、4、5、6 的修复证据；运行完整 build、unit-tests、`sdd-check`、`secret-scan`、`git diff --check`，确认无未解释失败后才可针对新 SHA 发布 Implementation Gate `HANDOFF`。— Depends on: T-040, T-041, T-042, T-043, T-044, T-045; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007, AC-001 至 AC-017; Evidence: `evidence/T-039-acceptance-package.md`

### P7 — 第二轮 Implementation Gate REVIEW 的三项 MUST，及真机复测暴露的焦点归属缺陷链（2026-07-31 新增）

**Tasks Gate 第二次重开（2026-07-31）。** Solar 对 `5070607` 的第三次
Implementation Gate REVIEW 判定 `CHANGES REQUESTED`，Finding 1（MUST）指出：
T-047 至 T-051 是在已批准 Tasks SHA `a8d0327` 之后新增并执行的带依赖、覆盖与
完成条件的任务，属 AGENTS.md 第 4 节的 material change，会重开 Tasks Gate 与
全部下游 Gate。因此：

- T-047 至 T-051 虽已执行完毕，**其任务定义本身尚未取得 Tasks PASS**，需在本次
  重开的 Tasks Gate 中一并追认。
- T-052 至 T-056 依据本轮 REVIEW 的 Finding 2 至 6 新增，**在 Tasks PASS 之前
  不得开工**；T-057 依 Tasks Gate REVIEW 的要求新增，承担 T-050 已失效的最终
  验收与 HANDOFF 职责。
- 下游 Implementation Gate 随之重开；C3、C4、C5 全部回退为未达成（见「检查点」）。
- 聊天中的口头授权不能替代仓库里的 Gate 记录。

**Tasks Gate 第二次重开的第二版修订（2026-07-31）。** Solar 对 `7229940` 的
Tasks Gate REVIEW 判定 `CHANGES REQUESTED`，要求四项修改，本版已全部落实：
① T-047 至 T-051 补入准确的历史状态与失效说明；② 四项裁决写入 T-052／T-053／
T-054；③ T-055 按裁定范围重写（TextEdit、Chrome/ChatGPT 加关键失败场景，不重跑
全部 P5，不要求 VS Code）；④ 回退 C3、C4、C5 并新增 T-057。四项待决问题的裁决
已逐条写入对应任务正文，不再留待实施期解释。

**第三版修订（2026-07-31）。** Solar 对 `37b0ae4` 的 Tasks Gate REVIEW 再判
`CHANGES REQUESTED`，三项 MUST，本版已全部落实：① T-053 补入「在 MainActor 上、
按 session／target／当前动作即时授权，不得缓存为可复用布尔」的边界，T-054 补入
逐项固化的失败映射分组（含 `.writeFailed` 的独占约束）；② T-055 恢复已裁定的
完整范围——TextEdit 与 Chrome/ChatGPT 各连续五次、Undo 行为、范围保真、恢复后
的外部变化，仍不含 VS Code、不重跑全部 P5；③ 更新需求追踪表（新增 P7 影响段落
并把 T-052 至 T-057 落入对应行）、把 C5 改为五项可逐条核验的达成条件、为 T-057
写出十一项完整的最终检查出口。

**第四版修订（2026-07-31）。** Solar 对 `c6b191e` 的 Tasks Gate REVIEW 再判
`CHANGES REQUESTED`，三处遗漏，本版已全部补齐：① T-054 补入贯穿
gateway → coordinator → presentation 的真实路由测试要求，以及非写入类失败必须
断言 `setterAttemptCount == 0`、写入类必须 `> 0` 的次数约束；② T-055 纠正关键
场景时序——改动结果须发生在**替换成功之后、恢复之前**再验证恢复被拒，并把
ChatGPT 多行从「至少三次」提高到「五次全部」，补入窗口变化（A3）与元素变化
（A4）两个场景；③ 追踪表补入 FR-009、FR-010、NFR-003 三行，T-057 增至十四项
出口，新增连续两次测试且计数一致、门禁命令须在分支内 `scripts/` 执行、
以及同步更新 PR #2 描述的 head SHA 与任务总数。本轮无新增范围。

本段任务因 Solar 对 `9bb221e` 的第二轮 Implementation Gate REVIEW（`CHANGES
REQUESTED`，3 项 MUST）而新增。开工前核对发现：上一次会话报告的 MUST 2／MUST 3
完成情况不成立（所称 commit 不存在，工作区处于无法编译的半成品状态，干净基线
的真实测试数为 172 而非 193），因此三项 MUST 均从 `9bb221e` 重做。

- [x] **T-047 [Fix] 保留并正确呈现 replacement 的具体失败（MUST 2）。** ✅ **2026-07-31 完成（`d505e32`）**：RED 为 180 tests／6 failures，实测五种未调用 setter 的拒绝全部显示「未能安全替换原文」且 `setterAttemptCount == 0`；GREEN 引入 `PreviewCapability.replacementRejected`、`replace` 返回 `Result<Void, DomainFailure>`、`PreviewStatus.targetNotWritable` 与 `replacementRejectionStatus(for:)`。连带更正 `EndToEndIntegrationTests` 中一条断言错误行为的既有断言。— Depends on: T-046; Covers: FR-008, NFR-007, AC-008; Evidence: `evidence/T-047-second-review-must-fixes.md`
  - **历史状态与失效说明（2026-07-31 Tasks Gate 第二次重开）**：任务定义未经
    Tasks Gate 批准即执行，须在本次重开中追认。产出**部分失效**：
    `replacementRejectionStatus(for:)` 的映射被第三次 Implementation REVIEW
    Finding 4 判定不完整（非目标失败落入 `default → .staleTarget`，且「不可达」
    无测试证明），该部分由 T-054 重做；`replacementRejected` 分类本身与
    `EndToEndIntegrationTests` 的断言更正不受影响。已在 `5070607` 推送。
- [x] **T-048 [Fix] 剪贴板重试必须重试原始那次复制（MUST 3）。** ✅ **2026-07-31 完成（`8f72296`）**：RED 为 184 tests／5 failures，核心失败为重试后复制次数仍为 1；根因是失败面板的「重试」指向 `.retry`（重新捕获目标），恢复被拒后会丢掉用户唯一还能拿回的原文。GREEN 引入 `PreviewUserAction.retryCopy` 与 `pendingCopyRetry`。— Depends on: T-047; Covers: NFR-007, AC-013; Evidence: `evidence/T-047-second-review-must-fixes.md`
  - **历史状态与失效说明（2026-07-31 Tasks Gate 第二次重开）**：任务定义未经
    Tasks Gate 批准即执行，须在本次重开中追认。产出**未被失效**：第三次
    Implementation REVIEW 未对 `retryCopy` 与 `pendingCopyRetry` 提出 Finding。
    但其自动化证据由 AXPress 驱动，不覆盖真人点击路径，故复制失败重试的关键
    失败场景纳入 T-055 的真人复核范围。已在 `5070607` 推送。
- [x] **T-049 [Fix] 不含内容的分级诊断与真实环境稳定性数据（MUST 1）。** ✅ **2026-07-31 完成（`f1bda7a`、`2792b1d`）**：RED 为编译器逐项点名缺失的生产 API；GREEN 引入覆盖 11 个拒绝点的 `ReplacementStage`、类型上不含 `String` 的 `ReplacementStageReport`、同步的 `ReplacementDiagnosticsRecording`，并经 `makeReplacementDiagnostics()` 进入生产装配。真实环境采集 40 次 ChatGPT 多行触发：37 次进入替换路径且全部 `completed`，`failure != none` 为 0；3 次捕获阶段失败经延长粘贴沉降间隔后消失。同时撤回 T-037 后续文件中"失败发生在 A1–A4 之一"的无证据归因。— Depends on: T-048; Covers: FR-013, NFR-006, NFR-007; Evidence: `evidence/T-047-second-review-must-fixes.md`、`evidence/T-037-chatgpt-multiline-followup.md`
  - **历史状态与失效说明（2026-07-31 Tasks Gate 第二次重开）**：任务定义未经
    Tasks Gate 批准即执行，须在本次重开中追认。产出**部分失效**：
    `ReplacementStageReport` 携带 `expectedLength`／`observedLength` 并以
    `.public` 写入 `os_log`，被第三次 Implementation REVIEW Finding 2 判定违反
    FR-013／NFR-006，长度字段由 T-052 完全删除。阶段枚举与同步记录的设计不受
    影响。**40 次稳定性数据同时失效**：其全部由 AXPress 驱动，而 AXPress 不使
    面板成为 key window，因此那 37 次 `completed` 未经过真人必经路径，不能作为
    多行闭环稳定性的证据；相关记述由 T-055 与 T-057 重建。已在 `5070607` 推送。
- [x] **T-050 [Evidence] 更新验收包并重新发布 Implementation Gate HANDOFF。** ✅ **2026-07-31 完成**：验收包已更新（199 tests 与五道门禁全绿，已知限制由 10 项增至 12 项，含稳定性样本覆盖面与分级诊断长度元数据两项新披露），第七节第 3 项的归因已更正。— Depends on: T-047, T-048, T-049; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007, AC-001 至 AC-017; Evidence: `evidence/T-039-acceptance-package.md`
  - **历史状态与失效说明（2026-07-31 Tasks Gate 第二次重开）**：任务定义未经
    Tasks Gate 批准即执行，须在本次重开中追认。产出**整体失效**：其产物是第三次
    Implementation Gate 的 HANDOFF 与验收包，而该 Gate 已被判定
    `CHANGES REQUESTED`（6 项 MUST）且 Tasks Gate 重开；验收包中 199 tests 的
    计数、长度元数据的「风险披露」以及「结构脚本不存在」的更正段落均不成立。
    最终验收与 HANDOFF 改由 T-057 承担。已在 `5070607` 推送。
- [x] **T-051 [Fix] 修复键盘焦点归属引发的连锁缺陷。** ✅ **2026-07-31 完成（`d90ba37`、`153eb41`、`efc73e6`、`6093146`）**：分级诊断上线后用户手动复测仍失败，诊断把失败定位到 A2；加入不含内容的 `focusedApplicationIsSelf` 字段后实测 `focus-is-self=true`——预览面板为让内部按钮可点而设 `canBecomeKey = true`，用户鼠标点击时面板合法持有键盘焦点，导致所有基于系统级焦点的目标校验失败。四处同源缺陷：① `validate` 的 A2 缺少 `plan.md:197` 已批准的自身豁免；② A3／A4 经 `AXUIElementCreateSystemWide()` 解析「当前元素」，改为经 `AXUIElementCreateApplication(pid)` 问目标应用自身；③ `sharedPrechecks` 的 A2 同样缺少豁免，致替换成功而「恢复原文」失败；④ A1–A4 存在两份独立拷贝使缺陷可再生，已抽出共用的 `frontmostApplicationIsAcceptable(pid:)`。修复后真机手动完成「确认替换 → 恢复原文」完整闭环，203 tests 全绿。属实现不符合已批准 Plan 的符合性修复，不触发 Plan Gate 重开。缺陷 ② 的真实 AX 解析路径无法单元测试，唯一证据为真机验证，已在证据文件中披露。— Depends on: T-049; Covers: FR-007, FR-008, FR-012, NFR-002, NFR-007, AC-005, AC-006, AC-012; Evidence: `evidence/T-048-focus-ownership-defect-chain.md`
  - **历史状态与失效说明（2026-07-31 Tasks Gate 第二次重开）**：任务定义未经
    Tasks Gate 批准即执行，须在本次重开中追认。产出**部分失效**：缺陷 ① 与 ③
    的修复把豁免写成整个本进程（`focusedPID == ProcessInfo.processInfo.processIdentifier`），
    被第三次 Implementation REVIEW Finding 3 判定超出 `plan.md:197` 批准范围，
    由 T-053 改为按当前会话 `NSPanel` 的 AppKit 对象身份判定。缺陷 ② 的 A3／A4
    解析改用 `AXUIElementCreateApplication(pid)` 与缺陷 ④ 的去重未被 Finding
    质疑，予以保留。当次真机闭环仅一轮、且在长度字段与面板豁免收窄之前完成，
    不足以作为验收证据，由 T-055 重做。已在 `5070607` 推送。
- [x] **T-052 [Fix] 从分级诊断中完全删除用户文字长度字段（REVIEW Finding 2，MUST）。** ✅ **2026-07-31 完成**：RED 为 205 tests／3 failures，失败信息逐项点名 `expectedLength of type Int` 与 `observedLength of type Optional<Int>`，并有一条断言证明输出确实含数字；GREEN 后 205 tests／0 failures。`ReplacementStageReport` 现在既无 `String` 也无数值成员，仅存 `stage`、`failure` 与 A2 独有的 `focusedApplicationIsSelf`；`os_log` 输出格式变为 `replacement-stage=… failure=… focus-is-self=…`。T-037／T-047／T-039 中依赖长度的记述已同步更正。`AccessibilityGateway` 中另一处同名局部变量属恢复算法的范围数学，与诊断无关，未改动。 修复前的违规事实：`SystemInteractionAdapters.swift` 曾把 `expectedLength` 与 `observedLength` 以 `.public` 写入 `os_log`，`DomainContracts.swift` 的 `ReplacementStageReport` 亦以长度为字段。长度是用户文字的可观测元数据，违反 FR-013／NFR-006 的明文隐私边界；已批准 Plan 未授权以「风险披露」豁免该边界。**Tasks Gate 裁决（Solar，2026-07-31）：完全删除长度字段，不允许等级化表示。** 任务要求：先写失败测试断言 `ReplacementStageReport` 不含任何长度字段、且 `os_log` 输出不含任何数字化的内容度量，再删除 `expectedLength`、`observedLength` 与 `SyntheticAXTextHost` 侧相关断言；同步删除 T-047／T-049／T-051 证据文件与验收包中依赖长度的记述。**接受的代价**：B1 阶段将不再输出 expected 与 observed 的可比信息，内容不一致只能报「已变化」而无法给出量级，定位能力相应下降。— Depends on: Tasks PASS; Covers: FR-013, NFR-006; Evidence: 新增 `evidence/T-052-diagnostics-privacy-fix.md`
- [x] **T-053 [Fix] A2 豁免收窄为当前会话预览面板的对象身份（REVIEW Finding 3，MUST）。** ✅ **2026-08-03 完成**：RED 先由编译器点名缺失的 `PanelFocusAuthorization` 与 `panelFocus:` 参数，再由两条行为测试提供——「聚焦应用是本进程但面板非 key 时必须拒绝且零 setter」与「替换成功后面板失去焦点则恢复必须被拒且内容不变」，旧实现在这两条下都会放行。GREEN 后 210 tests／0 failures。实现：`PanelFocusAuthorization` 为单次动作值，`PreviewPanelFocusOwnership` 由 `PreviewPanelController` 以 `NSApp.keyWindow === panel` 实现，`GatewaySessionTextTarget` 在每次 `replace`／`restore` 内现场求值且不写入任何属性（`testPanelFocusIsReevaluatedForEveryAction` 断言询问次数 0→1→2），生产入口刻意不设默认值。**实测发现面板是全应用单实例、跨会话复用**，故「会话失效」只能靠每次动作重新求值而非对象比较，该分析已写入证据。过程中修正一处自身缺陷：首版在拒绝分支二次读取聚焦应用，被既有调用序列断言捕获，已收敛为单次读取。 现行 `frontmostApplicationIsAcceptable(pid:)` 豁免整个本进程，而 `plan.md:197` 批准的是「除工具自身 non-activating panel 外」。**Tasks Gate 裁决（Solar，2026-07-31）：以当前会话 `NSPanel` 的 AppKit 对象身份判定面板，不得使用整个进程豁免。** 任务要求：先写失败测试覆盖两类场景——(a) 本进程但非当前会话面板的窗口持有焦点时必须拒绝；(b) 当前会话面板持有焦点时必须放行——再把判定改为对当前会话的 `NSPanel` 实例做对象同一性比较（`===`），不得退化为按进程、按窗口标题或按窗口层级判断。会话结束或面板重建后旧引用必须失效。**即时授权边界（Tasks Gate REVIEW 追加约束）**：对象同一性只能在 `MainActor` 上、于「确认替换」或「恢复原文」动作实际发生的那一刻即时求值；**不得**把结果缓存为可跨动作、跨 target 或跨 session 复用的布尔授权。会话替换、目标替换、面板关闭与面板重建均使授权立即失效。测试须覆盖：同一 session 内先求值一次再执行第二个动作时必须重新求值；面板关闭或重建后旧引用不得再放行。— Depends on: Tasks PASS; Covers: FR-007, FR-008, NFR-002, AC-005; Evidence: 新增 `evidence/T-053-a2-panel-scoped-exemption.md`
- [x] **T-054 [Fix] 替换失败按实际原因分流，并为不可达取值提供测试证明（REVIEW Finding 4，MUST）。** ✅ **2026-08-03 完成**：RED 先由编译器点名三个缺失状态与 `DomainFailure.allCases`，补齐后跑出 218 tests／7 failures——`PreviewStateActionTests` 两张穷举矩阵各缺三项，以及我在 MUST 2 阶段写的 `testExternalContentEditBeforeWriteIsNotPresentedAsWriteFailure` 断言 B1 → `staleTarget`，**该断言编码的正是被本次裁决否定的旧分组**，已更正。GREEN 后 218 tests／0 failures。映射从 `AppLifecycleController` 私有方法搬到 `PreviewPresentationMapper.status(forReplacementRejection:)`，`switch` 不带 `default` 且 `DomainFailure` 加 `CaseIterable`，新增取值会同时触发编译失败与映射表测试失败。新增 `sourceOrSelectionChanged`、`targetTemporarilyUnavailable`（提供重试／复制／关闭）、`unspecifiedFailure`（fail-closed）三个状态。十二条真实路由贯穿 gateway → coordinator → presentation 且各断言 `setterAttemptCount == 0`，`writeFailed` 反向断言 `> 0`；合成宿主的 `failNextContentReads` 增加 `with failure:` 参数以使后四类可达。不可达证明用十四种注入覆盖，并在证据中如实标注该证明的边界（"在这十四种条件下不出现"而非数学不可达）。 现行 `replacementRejectionStatus(for:)` 仅显式映射四类失败，其余落入 `default → .staleTarget`，把非目标失效的原因也说成「原输入位置已经变化」。**Tasks Gate 裁决（Solar，2026-07-31）：替换失败必须按实际原因分流；被判定不可达的 `DomainFailure` 取值需要测试证明其不可达；同时必须保留安全兜底分支。** 任务要求：先写失败测试逐一覆盖 `DomainFailure` 在替换路径上可达的每个取值并断言呈现可区分；对判定不可达的取值（如 `emptySource`、`pasteboardReadFailed`、`pasteboardWriteFailed`、`panelPlacementFallback`）编写测试证明其在替换路径上不会产生；`default` 兜底保留但必须映射到不声称发生过写入、且不误导目标状态的安全文案。**已裁定的分组边界（Tasks Gate REVIEW 追加，逐项固化，不得在实施期扩大解释）**：`invalidTarget → staleTarget`；`sourceChanged → 原文／选区已变化`（与 `staleTarget` 区分，须为独立文案）；`secureInputActive → secureInput`；`accessibilityPermissionRequired → permissionRequired`；`attributeNotSettable` 与 `unsupportedTarget → targetNotWritable`；`axTimedOut` 与 `axCannotComplete → 目标暂不可用`，动作须提供重试／复制结果／关闭；`unknown → fail-closed 通用状态`，不得声称目标已变化或已发生写入。**只有 setter 与 readback 失败（`.writeFailed`）才可呈现为写入失败**，其余任何取值均不得进入写入失败文案。不得为上述分组之外的情形新增状态。**真实路由测试与 setter 次数约束（本轮追加）**：每一类失败都必须有一条贯穿 `AccessibilityGateway → InteractionSessionCoordinator → PreviewPresentationMapper／AppLifecycleController` 的真实路由测试，断言从 gateway 返回的 `DomainFailure` 最终落到指定的面板状态与动作集合；不得只测映射函数本身或只测面板文案。同时每条非写入类失败的测试必须断言 `setterAttemptCount == 0`，写入类失败（`.writeFailed`）必须断言 `setterAttemptCount > 0`，以证明「未发生写入」不是推断而是实测。— Depends on: Tasks PASS; Covers: FR-008, NFR-007, AC-008; Evidence: 新增 `evidence/T-054-failure-mapping-completeness.md`
- [ ] **T-055 [Verify] 真人鼠标／触控板复核受影响闭环（REVIEW Finding 5，MUST）。** AXPress 驱动不会使预览面板成为 key window，因此既有脚本驱动的闭环证据不覆盖真人必经路径。**Tasks Gate 裁决（Solar，2026-07-31）的范围边界：限定为 TextEdit、Chrome/ChatGPT 两处闭环加关键失败场景；不重跑全部 P5；不要求 VS Code。** 任务要求：在 T-052／T-053／T-054 全部落地并重建二进制后，由真人以鼠标或触控板执行并逐次记录面板文案与分级诊断阶段。**本轮 Tasks Gate REVIEW 判定上一版缩窄了已裁定范围，现恢复为：** (a) **TextEdit 连续五次**「确认替换 → 恢复原文」，五次全部成功方算通过，任一次失败须记录阶段并停止；(b) **Chrome/ChatGPT 连续五次**同上，且**五次全部使用多行文本**；(c) **Undo 行为**：替换后与恢复后分别执行应用自身的撤销，记录撤销栈的实际表现（AX 写入是否进入该应用的 undo 栈），两处应用的结论分别记录，不得互相推断（AC-017）；(d) **范围保真**：选中替换后校验未选中部分（前缀与后缀）逐字未被改动，且选区边界未漂移；含 emoji 与组合字符的样本至少一次（AC-012）；(e) **恢复后的外部变化**：恢复完成后由真人在目标应用中继续编辑，确认会话已结束、不再有任何后续写入，且面板不再提供恢复动作；(f) **关键失败场景，时序必须严格按下列顺序执行**：(f1) 确认前切换到另一应用，再点「确认替换」——A2 必须拒绝且 `setterAttemptCount` 为 0；(f2) 确认前在目标应用中外部改动原文，再点「确认替换」——B1 必须拒绝并显示「原文／选区已变化」而非 `staleTarget`；(f3) **替换成功之后、点「恢复原文」之前**，由真人在目标应用中修改已写入的结果，然后点「恢复原文」——恢复必须被拒绝并显示「目标应用、窗口或输入位置已经变化，无法直接恢复」，且不得发生任何写入；(f4) 在 f3 的被拒面板上点「复制原文」，制造剪贴板写入失败后重试——须走 T-048 的 `retryCopy` 路径且重放的是原文而非结果；(f5) **窗口变化**：替换成功后、恢复前切换目标应用的窗口（或新建窗口）再点恢复——A3 必须拒绝；(f6) **元素变化**：替换成功后、恢复前点击目标应用内的另一个输入位置再点恢复——A4 必须拒绝。每项须记录真实面板文案原文与对应 `replacement-stage` 记录；禁止以 AXPress 或 AppleScript 点击替代真人点击。**不重跑全部 P5，不要求 VS Code。**— Depends on: T-052, T-053, T-054; Covers: FR-007, FR-008, FR-012, NFR-007, AC-005, AC-006, AC-012, AC-013; Evidence: 新增 `evidence/T-055-human-driven-revalidation.md`
  - **进度（2026-08-03，未完成）**：代码状态 `a645769` 下由真人鼠标执行。(a) TextEdit 连续五次通过；(b) Chrome/ChatGPT 连续五次多行通过；阶段记录 19 条 `completed` 与之一致。**(c)(d)(e) 与 f1–f6 共九项未执行，不计入通过。** 本轮暴露三项缺陷：Google 搜索框在预览期间被判目标变化、ChatGPT 二次替换被判目标变化、ChatGPT 三次 `readback failure=writeFailed`。前两项**无法归因**——22 条阶段记录中 A1–A4 拒绝为零条，说明替换从未被请求，文案来自 `AppLifecycleController.swift:364` 监听器路径，而该路径无埋点。已排除写入失败与 B1 拒绝（T-054 已使 `sourceChanged` 具备独立文案）。补埋点与修复见 P8，本任务不自行开工。
- [ ] **T-056 [Evidence] 更正「工程结构脚本不存在」的记录错误（REVIEW Finding 6，MUST）。** 该判断有误：`scripts/project-structure-check.sh` 在本功能分支中存在，本轮已独立运行通过（`Project structure check passed.`，exit 0）。此前的错误源于在主 worktree（`/Users/daidong/Documents/prompt/scripts/`）下查找，该目录不含此脚本。任务要求：撤回 `evidence/T-039-acceptance-package.md` 第二节的相关「更正」段落，恢复该脚本为独立门禁，并复核本轮五道门禁的执行入口记录是否一致。— Depends on: Tasks PASS; Covers: 无新增需求（记录准确性）; Evidence: `evidence/T-039-acceptance-package.md`
- [ ] **T-057 [Evidence] 重建最终验收包并发布 Implementation Gate HANDOFF（REVIEW 要求新增）。** T-050 的产出已整体失效，最终验收改由本任务承担。任务要求：(a) 依 T-052 至 T-056 的实际结果重写 `evidence/T-039-acceptance-package.md`，删除长度元数据的「风险披露」、撤回「结构脚本不存在」的错误更正、更新真实测试计数；(b) 重新逐项核对 13 条 FR、7 条 NFR、17 个 AC，并明确区分哪些证据由真人驱动、哪些由脚本驱动；(c) 重新评估既有 P5／P6 证据的证明力并如实标注受 AXPress 局限影响的项；(d) 五道门禁全部从**分支内** `scripts/` 执行并记录（含 `project-structure-check.sh`）；(e) C3、C4、C5 依实际结果重新判定；(f) 提交推送后发布 Implementation Gate HANDOFF。**完整的最终检查出口（唯一，逐项均须在验收包中留痕）**：① `build.sh` → `BUILD SUCCEEDED`；② `unit-tests.sh` → 全绿，记录真实测试计数；③ `project-structure-check.sh` → passed；④ `sdd-check.sh` → exit 0；⑤ `secret-scan.sh` → 无命中；⑥ `git diff --check` → 无输出；⑦ 以上六项全部从**分支内** `scripts/` 执行，不得使用主 worktree 的脚本；⑧ 诊断输出经 `log stream` 实测确认不含任何长度或内容度量；⑨ 13 条 FR、7 条 NFR、17 个 AC 逐项核对且每项标明证据来源为真人驱动或脚本驱动；⑩ C3、C4、C5 依实际结果重新判定并写明依据；⑪ 已知限制清单重建，删除长度元数据「风险披露」与「结构脚本不存在」两处错误记述；⑫ **`unit-tests.sh` 须连续执行两次且两次全绿、计数一致**，以排除偶发；⑬ **所有门禁命令的执行位置须记录为 `.worktrees/fable` 下的分支内 `scripts/`（即 `bash scripts/<name>.sh`），禁止使用 `../../scripts/` 指向主 worktree**；⑭ **同步更新 PR #2 的描述**：head SHA 改为本次 HANDOFF 的准确 SHA、任务总数改为 60、并移除仍指向 `9bb221e` 与 46 个任务的过时表述。 **2026-08-03 追加（P8）**：⑮ T-058 与 T-061 的证据已归档；⑯ T-062 的完整 T-055 重跑结果已归档且逐项标注真人驱动；⑰ 已知限制清单补入「Google 搜索框选区兼容已移出 001，见 `evidence/out-of-scope-observations.md` 观察 5」。任一项未留痕即不得发布 HANDOFF。— Depends on: T-052, T-053, T-054, T-056, **以及 P8 全部完成**——T-058、T-063、T-064、T-061、T-062，以及 T-064 写回并经新一轮 Tasks Gate `PASS` 的 ChatGPT 修复任务。**T-055 不再单独作为 T-057 的前置**：其证据已由 T-062 在最终代码上重取取代。缺 P8 任一项即不得发起最终 Implementation Gate 审核。; Covers: FR-001 至 FR-013, NFR-001 至 NFR-007, AC-001 至 AC-017; Evidence: `evidence/T-039-acceptance-package.md`


### P8 — T-055 真人复核暴露的缺陷（2026-08-03 新增，第二版修订待审）

**第二版修订（2026-08-03）。** Solar 对 `fa194a5` 的 Tasks Gate REVIEW 判定
`CHANGES REQUESTED`，含一项 `BLOCKER`，本版已全部落实：① Google 搜索框选区兼容
依 `BLOCKER` 移出 001，记入 `out-of-scope-observations.md`；② T-058 只做诊断，
修复任务须经新一轮 Tasks Gate 定义，不得在本次 PASS 后临时定义即开发；③ T-058
必须遵守 observer 回调只携带 session ID 与 target ID 的 Plan 边界；④ T-061 更正
错误引用的 AC-008 与 NFR-001，改为有界、单次 setter、超时 fail-closed；⑤ T-062
改为在最终代码上重跑**完整** T-055；⑥ P8 已接入需求追踪表、C3／C4／C5 与 T-057
出口。

**第三版修订（2026-08-03）。** Solar 对 `d154767` 的 Tasks Gate REVIEW 再判
`CHANGES REQUESTED`，三项 MUST 加一项 SHOULD，本版已全部落实：① 新增 T-063
（Probe/Evidence，固定环境与固定次数复现，Google 仅作范围外对照）与 T-064
（Decision，只依证据判根因、判是否触及批准 Plan、把具体 Fix 任务写回 tasks.md
并发起新一轮 Tasks Gate），补齐「诊断 → 复现证据 → 根因决策 → 新 Tasks Gate」的
可执行闭环；② T-061 补入单调时钟 deadline、有界退避、逐 UTF-16 code unit 比较、
session／target 失效立即停止、禁止换用其他 setter、禁止把 setter 成功视为最终成功、
超时安全后备、诊断不记内容或长度，并明确「延迟后最终一致」与「直到 deadline 仍
不一致」两条必备失败优先测试；③ T-062 补入 ChatGPT 二次替换回归项与按尝试逐条
列表的证据要求，T-057 依赖改为「P8 全部完成」且 T-055 不再单独作为前置，C3／C4
各补 P8 达成条件，杜绝绕过 P8 直接发起最终审核；④（SHOULD）T-055 证据文件的
「已完成并通过」已醒目标注为仅 `a645769` 的历史观察、对最终 Gate 失效，并如实
说明 10 个闭环与 22 条记录的计数关系当时无法自洽、须由 T-062 重取时逐条说明。

**Tasks Gate 第三次重开。** T-055 执行中由真人在 Google 搜索框与 ChatGPT 二次替换
场景发现两项缺陷，另有三次 ChatGPT `readback` 写入失败。用户明确选择「严格守流程、
但快速推进」，因此本段先提交任务定义，**Tasks PASS 前不动生产代码**。

诊断顺序是本段的关键约束：**T-058 是纯诊断任务，必须先完成并取得阶段数据，
T-059 与 T-060 的修复方案才能被定义。** 现在就写修复方案等于凭推断行事——上一轮
已因此付出七个外部探针加一个被撤回结论的代价，不再重复。

- [ ] **T-058 [Fix] 为目标变化监听器路径补上不含内容的分级诊断（诊断前置，MUST）。** `AppLifecycleController.swift:364` 在监听器触发且会话处于 `previewing(.ready)` 时直接 `present(.staleTarget)`，该路径**没有任何埋点**，导致 T-055 暴露的两项缺陷无法归因（22 条阶段记录中 A1–A4 拒绝为零条，证明替换从未被请求）。任务要求：先写失败测试断言监听器触发导致的拒绝会产生一条可辨认的诊断记录，且该记录能区分「窗口变化／元素变化／焦点应用变化」三种依据；再实现。**沿用 T-052 的隐私边界：只记阶段标识与判定依据，不得含任何内容或长度。** 本任务不改变监听器的判定行为，只让原因可见。**必须继续遵守 Plan 的 observer 边界：`AXObserver` 回调只允许携带 session ID 与 target ID，不得为诊断向回调增加任何字段**——判定依据在控制器侧记录，不得回填进回调载荷。**本任务只做诊断：T-060（ChatGPT 二次替换）等修复任务须在本任务数据取得后经新一轮 Tasks Gate 定义，不得在本次 PASS 后临时定义并直接开发。** 观测对象须至少覆盖 ChatGPT 二次替换场景。— Depends on: Tasks PASS; Covers: FR-013, NFR-006, NFR-007; Evidence: 新增 `evidence/T-058-monitor-path-diagnostics.md`
- [ ] **T-063 [Probe/Evidence] 在固定环境与固定次数下复现 ChatGPT 二次替换拒绝（MUST）。** 依 T-058 的埋点采集证据，为 T-064 的根因判断提供唯一依据。完成条件：① 记录 Chrome 与 ChatGPT 的**具体版本号**、macOS 版本、应用 SHA；② 使用**固定的合成夹具**（`SYNTHETIC-001` 标记，文本内容写入证据文件，保证可复现）；③ 由真人以鼠标／触控板复现二次替换场景**至少 10 次**，每次记录：尝试编号、是否为二次替换、面板文案原文、监听器判定依据的原因分类、以及该次是否产生替换阶段记录；④ Google 搜索框**仅作范围外对照**，各跑 3 次并单独成表，不参与 001 的结论；⑤ 逐次记录**不得含任何内容或长度**，只记原因分类与结果。**本任务只采集，不分析根因、不改任何实现。** — Depends on: T-058; Covers: FR-013, NFR-006, NFR-007; Evidence: 新增 `evidence/T-063-second-replacement-probe.md`
- [ ] **T-064 [Decision] 依 T-063 证据判定根因并把具体 Fix 任务写回 tasks.md（MUST）。** 完成条件：① **只依据 T-063 的记录**判定根因，不得引入未采集的推断；② 判定该根因是否触及已批准的 Plan `0c9883f`——若触及，必须先重开 Plan Gate 而非直接改实现；③ 列出所需的失败优先测试与**最小**修复范围，明确哪些变化应被容忍、哪些必须继续拒绝，不得为让场景通过而放宽写入安全约束；④ 把具体 Fix 任务（含依赖、覆盖、完成条件、Evidence 出口）写回 `tasks.md`；⑤ 提交新 SHA 并发起**新一轮 Tasks Gate HANDOFF**。**新 Tasks Gate `PASS` 之前不得实施任何 ChatGPT 修复。** 若 T-063 的证据不足以支撑判定，本任务的正确输出是「证据不足」并补充采集，不得以推断填补。— Depends on: T-063; Covers: 无新增需求（决策与任务定义）; Evidence: 新增 `evidence/T-064-second-replacement-root-cause.md`
- **已移除（依 Solar Tasks Gate REVIEW，2026-08-03）**：原 T-059（Google 搜索框预览期被判目标变化）依 `BLOCKER` 移出 Feature 001——用户已在本会话早期将「Chrome 页内选区替换」与「所有输入框一致工作」划入后续 Feature，不得重新作为 001 的必须修复项；该现象已记入 `evidence/out-of-scope-observations.md` 观察 5。原 T-060（ChatGPT 二次替换被判目标变化）属 001 范围内缺陷，但其**修复任务须在 T-058 诊断数据取得后经新一轮 Tasks Gate 定义**，不得在本次 PASS 后临时定义并直接开发；本轮仅将其列为 T-058 必须覆盖的观测对象。
- [ ] **T-061 [Fix] 把回读确认改为有界、单次 setter、超时 fail-closed（MUST）。** T-055 抓到 3 条 `replacement-stage=readback failure=writeFailed`：setter 报告成功但回读未确认，现有五次重试预算耗尽。这与 T-058 观测的拒绝是不同问题（那些从未到达 setter）。已知事实：Chromium 异步应用写入，立即回读返回写入前的值（T-037 已记录）。**依 Solar Tasks Gate REVIEW 更正引用**：本任务与 AC-008、NFR-001 无关——NFR-001 的 300ms 只约束确认前的预览呈现，**不包含确认之后的回读**，因此不存在需要协商的时间上限。任务要求：先写失败测试固定下列**全部**条件，再改实现。**回读预算**：(1) 使用**单调时钟**（`ContinuousClock` 或 `DispatchTime`）计算 deadline，**不得使用墙钟**，以免系统时间调整影响预算；(2) 回读之间采用**有界退避**，次数与总时长均有明确上界并写入证据文件。**比较**：(3) 每次回读须逐 **UTF-16 code unit** 与 expected result 比较相等，不得用规范化比较、前缀比较或长度比较代替。**写入约束**：(4) **setter 只调用一次**，重试只重复回读；(5) **不得换用其他 setter**（例如从 `kAXSelectedText` 改为 `kAXValue`）作为"重试"手段；(6) **不得把 setter 返回成功视为最终成功**——唯一的成功判据是回读一致。**中止与后备**：(7) 回读期间若 session 或 target 失效（含面板关闭、目标应用退出、窗口／元素身份变化），必须**立即停止**回读，不得继续等待 deadline；(8) 达到 deadline 仍不一致时 **fail-closed**，报告写入未确认，并给出安全后备动作（保留结果可复制、不声称已写入、不自动重试写入）。**隐私**：(9) 回读诊断只记阶段与结果，**不得记录内容或长度**（沿用 T-052 边界）。**必须包含的两条失败优先测试**：(a) 「延迟后最终一致」——setter 后前若干次回读不一致、deadline 内某次一致，须报成功且 setter 仅调用一次；(b) 「直到 deadline 仍不一致」——须 fail-closed 报未确认，且不得追加写入。**不得以放弃回读确认的方式让测试通过。** — Depends on: Tasks PASS; Covers: FR-008, FR-013, NFR-006, NFR-007; Evidence: 新增 `evidence/T-061-readback-confirmation-bound.md`
- [ ] **T-062 [Verify] 在最终代码上重跑完整 T-055（MUST）。** **依 Solar Tasks Gate REVIEW 更正范围**：不是只补九个未执行项，而是在 T-058、T-061 及后续新一轮 Tasks Gate 定义的修复全部落地后的**最终代码**上，由真人以鼠标／触控板重跑 T-055 的**全部**内容——(a) TextEdit 连续五次、(b) Chrome/ChatGPT 连续五次多行、(c) Undo、(d) 范围保真、(e) 恢复后外部变化、(f1) 至 (f6)。此前在 `a645769` 上取得的 (a)(b) 结果因代码已变更而不再具备证明力，须重取。逐项记录面板文案原文与对应阶段记录；时序约束不变，f3／f5／f6 必须发生在替换成功之后、恢复之前；禁止以 AXPress 或 AppleScript 代点。**追加：必须包含 ChatGPT 二次替换的回归项**——在同一输入框连续完成两轮「确认替换 → 恢复原文」，第二轮必须成功；该项与 (b) 的五次多行分别记录，不得互相顶替。**证据须按尝试逐条列出**：尝试编号、目标应用、是否二次替换、是否重试、最终结果、以及该次对应的阶段记录条数，并使闭环次数、`completed` 条数与失败条数三者的算术关系在文中显式成立。— Depends on: T-058, T-063, T-064, T-061, 以及 T-064 写回 tasks.md 并经**新一轮 Tasks Gate `PASS`** 的 ChatGPT 修复任务（缺任一项即不得开工）; Covers: FR-007, FR-008, FR-012, NFR-007, AC-005, AC-006, AC-012, AC-013, AC-017; Evidence: `evidence/T-055-human-driven-revalidation.md`

## 检查点

- **C0 — 工具链可执行：** T-004 通过；完整 Xcode、目标配置、CI 与基础测试发现均可复现。
- **C1 — 高风险假设成立：** T-007 与 T-010 已通过；快捷键/安全输入和非激活面板没有触发 Plan 的硬停止条件。
- **C2 — 领域安全不变量成立：** T-014 通过；确认前零 setter、单会话、会话清理及 `recoverable → previewing(recoveryUnavailable)` 已由失败优先测试证明。
- **C3 — 系统边界可控：** T-028 通过；权限、剪贴板、AX、observer、几何和预览各自有测试，并且权威写入验证未被监控事件取代。~~2026-07-28 起回退为未达成~~ **已于 2026-07-30 重新达成**：T-021／T-022 按批准算法转绿，T-040 自动化复核确认权限、剪贴板、AX、observer、几何与预览各套件全部通过。 **2026-07-31 再次回退为未达成**：Tasks Gate 第二次重开使下游 Implementation Gate 一并重开；且第三次 Implementation REVIEW 的 Finding 3 判定 A2 豁免超出批准范围，系统边界的判定依据本身需按 T-053 重做。 **2026-08-03 追加（P8）**：重新达成还须 T-058 的监听器路径诊断与 T-061 的回读确认边界完成，且 T-064 判定的根因若触及已批准 Plan 则先重开 Plan Gate；缺任一项 C3 不得判定达成。
- **C4 — 合成闭环通过：** T-031 通过；全部生产装配由 T-030 的端到端失败测试驱动。~~2026-07-28 起回退为未达成~~ **已于 2026-07-30 重新达成**：T-040 的两次运行中 T-027 与 T-030／T-031 套件全部通过。 **2026-07-31 再次回退为未达成**：Tasks Gate 第二次重开使下游 Implementation Gate 一并重开；且该闭环全部由 AXPress 驱动，不覆盖预览面板成为 key window 的真人路径，需按 T-055 以真人驱动重新建立。 **2026-08-03 追加（P8）**：真人驱动的闭环证据改由 **T-062 在最终代码上重取**，`a645769` 上的 T-055 结果不再计入；且必须包含 ChatGPT 二次替换回归项通过。缺 T-062 即 C4 不得判定达成。
- **C5 — 真实验收完整：** T-039 通过；TextEdit 与 Chrome/ChatGPT 完整闭环、VS Code 后备闭环、性能/显示/输入/隐私证据均可复现。 ~~已达成（2026-07-28）~~ ~~已回退为未达成~~ **已于 2026-07-30 重新达成**：T-040 至 T-046 全部完成，含 P6 的真实环境复核与定向审计，详见 `evidence/T-039-acceptance-package.md` 第十节。原记录：121 tests 全绿，build/structure/sdd/secret/diff-check 五道门禁通过，7 项已知限制已如实披露，详见 `evidence/T-039-acceptance-package.md`。 **2026-07-31 再次回退为未达成**：Solar 对 `5070607` 的第三次 Implementation Gate REVIEW 判定 `CHANGES REQUESTED`，6 项 MUST 未闭合；且 Tasks Gate 因 P7 重开，下游 Implementation Gate 随之重开。**重新达成的条件（唯一，全部满足方可）**：① T-052 至 T-056 全部完成；② T-055 的真人复核全部通过——TextEdit 与 Chrome/ChatGPT 各连续五次「确认替换 → 恢复原文」成功，Undo 行为、范围保真、恢复后外部变化、三类关键失败场景均有真人记录；③ 五道门禁全部从分支内 `scripts/` 执行并通过（含 `project-structure-check.sh`）；④ T-057 重建的验收包逐项区分真人驱动与脚本驱动证据，并标注受 AXPress 局限影响的项；⑤ Solar 对 T-057 发布的新 SHA 给出 Implementation Gate `PASS`。 **2026-08-03 追加（P8）**：⑥ T-058 与 T-061 完成；⑦ T-058 的诊断数据取得后，ChatGPT 二次替换的修复任务经**新一轮 Tasks Gate** 定义并完成——不得在本次 PASS 后临时定义即开发；⑧ T-062 在最终代码上重跑**完整** T-055 并全部通过（此前 `a645769` 上的 (a)(b) 结果已失效，不再计入）。Google 搜索框选区兼容依 `BLOCKER` 移出 001，不作为 C5 条件。

## Plan Gate NIT 处置约束

| Finding | Tasks Gate 的强制落实 | 关闭条件 |
| --- | --- | --- |
| NIT-1 | T-023/T-024 明确 AXObserver source 挂载于 main run loop，callback 再跳入 actor，监控不是写入授权 | Fable 确认任务表述覆盖并在 Tasks Gate 关闭 |
| NIT-2 | T-036 明确 300ms 证据从 hot-key callback 起算，不包含 OS 投递延迟，且禁止增加按键监听 | Fable 确认测量边界可审计并在 Tasks Gate 关闭 |
| NIT-3 | T-013/T-014 明确测试并实现 `recoverable → previewing(recoveryUnavailable)`，仅允许复制原文或关闭 | Fable 确认状态、动作与禁止写入均被覆盖后关闭 |

## Tasks Gate 记录

- **第三次重开（2026-08-03，当前待审）**：T-055 真人复核执行中暴露三项缺陷
  （Google 搜索框预览期被判目标变化、ChatGPT 二次替换被判目标变化、ChatGPT 三次
  `readback` 写入失败），新增 P8（T-058 至 T-062）。其中 T-058 为纯诊断前置任务，
  T-059／T-060 的修复方案在 T-058 阶段数据取得前**不予定义**。用户已明确选择
  「严格守流程、快速推进」，故先提交任务定义，Tasks PASS 前不动生产代码。
  P7 的 T-052 至 T-054 已在上一次 Tasks PASS 后按序完成并推送
  （`3761281`、`247890d`、`a645769`）。
- **第三次重开第二版修订（2026-08-03，当前待审）**：Solar 对 `fa194a5` 判
  `CHANGES REQUESTED`，含一项 `BLOCKER`。已落实：原 T-059（Google 搜索框）移出
  001 并记入 `evidence/out-of-scope-observations.md` 观察 5；原 T-060 从任务列表
  移除，其修复须经新一轮 Tasks Gate 定义；T-058 补入 observer 回调只带 session ID
  与 target ID 的边界约束；T-061 更正错误引用的 AC-008 与 NFR-001，改为有界、
  单次 setter、超时 fail-closed；T-062 改为在最终代码上重跑完整 T-055；P8 已接入
  需求追踪表、C5 条件（追加 ⑥⑦⑧）与 T-057 出口（追加 ⑮⑯⑰）。
- **第三次重开第三版修订（2026-08-03，当前待审）**：Solar 对 `d154767` 判
  `CHANGES REQUESTED`，三项 MUST 加一项 SHOULD。已落实：新增 T-063（Probe/
  Evidence）与 T-064（Decision）形成「诊断 → 复现证据 → 根因决策 → 新 Tasks
  Gate」的可执行闭环，两者各有独立完成条件与 Evidence 出口；T-061 补入单调时钟
  deadline、有界退避、逐 UTF-16 code unit 比较、session／target 失效立即停止、
  禁止换用其他 setter、禁止把 setter 成功视为最终成功、超时安全后备、诊断不记
  内容或长度，以及两条必备失败优先测试；T-062 补入二次替换回归项与按尝试逐条
  列表要求，T-057 依赖改为 P8 全部完成并移除 T-055 单独前置，C3／C4 各补 P8
  达成条件；T-055 证据的历史结果已醒目标注失效并说明计数关系无法自洽。

- **第二次重开（2026-07-31，当前待审）**：因 P7（T-047 至 T-051）在已批准
  Tasks SHA `a8d0327` 之后新增并执行，构成 material change；Solar 对 `5070607`
  的第三次 Implementation Gate REVIEW 以 Finding 1（MUST）要求先重开 Tasks
  Gate。第一版修订（`7229940`）新增 T-052 至 T-056 并提交 T-047 至 T-051 追认，
  Solar 的 Tasks Gate REVIEW 判定 `CHANGES REQUESTED` 并给出四项修改与四项裁决；
  第二版修订即本次提交，已全部落实。Tasks PASS 前不得开工 T-052 至 T-057，也
  不得重新发起 Implementation Gate。
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
