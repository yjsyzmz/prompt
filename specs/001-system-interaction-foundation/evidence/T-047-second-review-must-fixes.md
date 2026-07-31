# T-047 第二轮 Implementation Gate REVIEW 三项 MUST 的修复

## 任务边界

- 来源：Solar 对 `9bb221e` 的第二轮 Implementation Gate REVIEW，`CHANGES
  REQUESTED`，三项 MUST。
- 本文件记录三项修复各自的失败优先证据、最小实现与实测结果。
- 顺序：MUST 2 → MUST 3 → MUST 1。前两项是呈现层的正确性缺陷，修好之后
  MUST 1 的分级诊断才能在正确的失败分类之上采集数据。

## 记录更正：起点状态

上一次会话中曾报告 MUST 2 与 MUST 3 已完成并推送为 `6cf9633` 与 `3f8a21d`，
并称 193 tests 全绿。**该报告不成立。** 本轮开工前核对真实仓库状态：

- `git log` 头部为 `9bb221e`，`origin/feature/001-system-interaction-foundation`
  同为 `9bb221e`；上述两个 commit 不存在。
- 工作区仅有两处未提交痕迹：`SessionIntegration.swift` 的 `replace` 已改为返回
  `Result`，以及一个未注册进 `project.pbxproj` 的测试文件。
- 而 `InteractionSessionCoordinator.swift` 的协议仍声明返回 `Bool`，
  `PreviewCapability` 无 `replacementRejected`，`PreviewStatus` 无
  `targetNotWritable`，`PreviewUserAction` 无 `retryCopy`。该状态**无法编译**。
- 干净基线 `9bb221e` 的真实测试数为 **172 tests / 0 failures**，不是 193。

处置：把未提交改动恢复到 `9bb221e`，在干净基线上重跑五道门禁确认全绿，再从零
重做三项 MUST。

## MUST 2 — 保留并正确呈现 replacement 的具体失败（`d505e32`）

### 失败优先证据

新建 `Tests/SystemInteractionFoundationTests/ReplacementFailureMappingTests.swift`
（8 个用例）。在 `9bb221e` 的实现上运行：**180 tests / 6 failures**。

六条失败集中在同一个问题：窗口切换（A3）、元素失效（A4）、应用退出（A1）、
焦点换应用（A2）、外部改内容（B1）这五种**从未调用过 setter** 的拒绝，面板
一律显示

```text
未能安全替换原文，结果仍可复制。
```

同一批断言实测 `host.setterAttemptCount == 0`，证明确实没有发生任何写入。

### 最小实现

- `PreviewCapability` 增加 `replacementRejected(DomainFailure)`。
- `SessionTextTargetAccessing.replace` 由 `Bool` 改为
  `Result<Void, DomainFailure>`；`GatewaySessionTextTarget` 透传具体失败。
- `InteractionSessionCoordinator.confirmReplacement` 只把 `.writeFailed`
  路由到 `.previewing(.writeFailed)`，其余失败进入
  `.previewing(.replacementRejected(failure))`。
- `AppLifecycleController.replacementRejectionStatus(for:)` 把拒绝映射为
  `secureInput` / `permissionRequired` / `targetNotWritable` / `staleTarget`。
- `PreviewStatus` 增加 `targetNotWritable`，文案
  「当前输入位置已不可写入，未做任何修改，结果仍可复制。」

### 为什么只有 `.writeFailed` 保留写入失败语义

`AccessibilityGateway` 中 setter 失败与 readback 失败**都**返回
`.writeFailed`（`AccessibilityGateway.swift` 的 setter 与
`writtenTextConfirmed` 两处），这两条是唯一真正触碰过目标的路径。
`DomainFailure` 中不存在 `readbackMismatch` 这个 case。

### 连带更正的既有断言

`EndToEndIntegrationTests.testStaleTargetEventDisablesConfirmAndValidationBlocksWrite`
原本断言竞态 confirm 后面板显示 `writeFailed`——**这条断言断言的就是错误行为**。
已改为期望 `staleTarget` 并在测试内写明原因。`PreviewStateActionTests` 的两张
穷举矩阵补入 `targetNotWritable`。

### 结果

199 tests 全绿（含后续两项 MUST）；MUST 2 提交时为 180 tests / 0 failures。

## MUST 3 — 剪贴板重试必须重试原始那次复制（`8f72296`）

### 失败优先证据

新建 `Tests/SystemInteractionFoundationTests/ClipboardRetrySemanticsTests.swift`
（4 个用例）。运行：**184 tests / 5 failures**，核心失败为

```text
retry must attempt the copy again: ("1") is not equal to ("2")
```

在结果复制与原文复制两条路径上均复现。

### 根因

`AppLifecycleController.handle(_:)` 中 `.clipboardWriteFailed` 面板的「重试」
按钮指向 `.retry`，而 `.retry` 执行的是 `beginDirectInteraction()`——重新捕获
目标。在恢复被拒后想复制原文却失败的场景下，这一按就把用户唯一还能拿回的
原文丢掉了。

### 最小实现

- `PreviewUserAction` 增加 `retryCopy`，`clipboardWriteFailed` 面板改用它。
- 控制器记录 `pendingCopyRetry`（`.result` 或 `.original`），`.retryCopy`
  重放对应的那次复制；成功后清除并回到原面板状态。
- `finishSession()` 清除 `pendingCopyRetry`。

### 连带更正的既有断言

`FailureRecoveryGuidanceTests` 中对 `.retry` 按钮的断言与
`PreviewStateActionTests` 的按钮矩阵改为 `.retryCopy`。

## MUST 1 — 不含内容的分级诊断（`f1bda7a`、`2792b1d`）

### 失败优先证据

新建 `Tests/SystemInteractionFoundationTests/ReplacementStageDiagnosticsTests.swift`
（14 个用例）。该能力此前完全不存在，因此 RED 表现为编译器逐项点名缺失的
生产 API：

```text
cannot find type 'ReplacementStage' in scope
cannot find type 'ReplacementStageReport' in scope
cannot find type 'ReplacementDiagnosticsRecording' in scope
extra argument 'diagnostics' in call
value of type 'SyntheticAXTextHost' has no member 'acceptSetterWithoutApplying'
value of type 'SyntheticAXTextHost' has no member 'makeReadOnly'
value of type 'SyntheticAXTextHost' has no member 'blockReplacementAttribute'
value of type 'SyntheticAXTextHost' has no member 'activateGlobalSecureInput'
value of type 'SyntheticAXTextHost' has no member 'failNextContentReads'
```

### 最小实现

`ReplacementStage` 覆盖 11 个拒绝点加成功态：`unsupportedMode`、
`applicationRunning`（A1）、`frontmostApplication`（A2）、`windowIdentity`（A3）、
`elementIdentity`（A4）、`elementCapability`、`globalSecureInput`、
`contentRead`、`contentComparison`（B1）、`attributeSettable`、`setter`、
`readback`、`completed`。

两个设计决定：

1. **`ReplacementStageReport` 在类型上不含任何 `String` 字段**，只有阶段标识、
   `DomainFailure?` 和两个 UTF-16 长度。隐私不依赖"记得别打印内容"，而是类型
   里没有内容可打印（FR-013、NFR-006）。有一条测试对所有实际产生的报告执行
   `String(describing:)` 并断言不含合成标记与夹具文字。
2. **记录是同步的。** 若改为 `async`，A4 与 setter 之间会多出一个 suspension
   point，把 `plan.md` 已披露的 TOCTOU 窗口人为拉宽。代价是记录方须自行保证
   线程安全：生产侧用 `os_log`，测试侧用 `NSLock`。

合成宿主新增 5 个钩子，用于到达此前在替换路径上不可达的阶段：静默丢弃写入
（→ readback）、捕获后转只读（→ elementCapability）、可编辑但属性不可写
（→ attributeSettable）、全局安全输入激活（→ globalSecureInput）、内容读取
失败（→ contentRead）。

生产装配：`AppLifecycleController.makeReplacementDiagnostics()` 返回
`OSLogReplacementDiagnosticsRecorder`，由 `convenience init()` 注入。
`ProductionTargetMonitorAssemblyTests` 增加一条断言，确认真实装配确实挂上了
记录器——否则分类只存在于测试里，真实环境跑多少次都拿不到数据。

### 真实环境稳定性数据

见 `evidence/T-037-chatgpt-multiline-followup.md` 第二轮：40 次触发，37 次进入
替换路径且全部 `completed`，`failure != none` 的记录数为 0；3 次失败发生在捕获
阶段，经延长粘贴沉降间隔后消失。同时撤回了该文件此前"失败发生在 A1–A4 之一"
的归因——本轮 A1–A4 拒绝记录为 0，原结论无证据支撑。

## 验证

- 199 tests / 0 failures
- `./scripts/build.sh` → `BUILD SUCCEEDED`
- `./scripts/sdd-check.sh` → passed
- `./scripts/secret-scan.sh` → 无命中
- `git diff --check` → 无输出
