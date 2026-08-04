# T-058 目标变化监听器路径的不含内容分级诊断

## 任务边界

- 来源：Solar 对 `3e3bcc9` 的 Tasks Gate `PASS`；用户明确要求「只执行 T-058，完成后停止」。
- 覆盖：FR-013、NFR-006、NFR-007。
- 执行日期：2026-08-03。父提交 `3e3bcc96a1c9a35e2e8c663cbb96e992051181fc`。
- 本任务**只做诊断**。ChatGPT 二次替换的修复方案不在本任务内，须由 T-063 采集、
  T-064 判定后经新一轮 Tasks Gate 定义。

## 要归因的事实

T-055 的真人复核留下一个无法解释的组合：**22 条阶段记录里 A1–A4 拒绝为零条**，
而用户看到的文案正是「原输入位置已经变化，不能安全替代」。

原因在代码里是明确的。`AppLifecycleController.targetDidBecomeStale` 此前是：

```swift
fileprivate func targetDidBecomeStale(_ envelope: AXMonitorCallbackEnvelope) {
    guard
        envelope.sessionID == coordinator.currentSessionID,
        envelope.targetHandle == activeTargetHandle,
        coordinator.state == .previewing(.ready)
    else {
        return
    }
    present(.staleTarget)
}
```

这条路径**根本没有请求过替换**。`ReplacementStage` 描述的是
`replaceAfterAuthoritativeValidation` 内部的十三个位置，监听器拒绝发生在它之前，
所以再多的阶段埋点也照不到这里——阶段记录为零不是埋点漏了，是这次拒绝压根不
经过阶段序列。这也是 Google 搜索框（已移出 001，见 `out-of-scope-observations.md`
观察 5）与 ChatGPT 二次替换两个现象此前都无法归因的共同原因。

## 设计与两条硬约束

### 约束一：observer 回调载荷不得改动

`AXMonitorCallbackEnvelope` 保持原样，仍只有两个字段：

```swift
struct AXMonitorCallbackEnvelope: Equatable, Sendable {
    let sessionID: InteractionSessionID
    let targetHandle: TargetHandle
}
```

`git diff` 对 `ExternalTargetMonitor.swift` 无任何改动，可直接核验。判定依据不是
由 `AXObserver` 回调带过来的，而是在接收侧（控制器）于拒绝发生的那一刻重新求值。

### 约束二：不得改变监听器的判定行为

`present(.staleTarget)` 仍在同一个 `guard` 之后**同步、无条件**执行；诊断在它
之后发起，因此既不能延后拒绝，也不能改变拒绝与否。三项 guard 条件一字未动。

### 判定依据的取值

新增 `StaleTargetReason`（`DomainContracts.swift`），六个取值：

- `applicationTerminated` —— A1：目标应用已退出
- `focusedApplicationChanged` —— A2：键盘焦点既不在目标应用、也不在本会话面板
- `windowIdentityChanged` —— A3：窗口身份与捕获时不一致
- `elementIdentityChanged` —— A4：元素身份与捕获时不一致
- `identityIntact` —— 回调触发了，但三项身份全部仍然匹配
- `identityUnknown` —— 该 handle 没有保留引用，无从比较

`identityIntact` 是本任务的关键取值。它把「目标真的变了」与「拒绝无法用任何身份
变化解释」分成两件事——后者才是 ChatGPT 二次替换现象的形状。如果只提供三种「变化」
取值，实现就必须在无法解释时挑一个最像的报出来，T-064 的根因判断就会建立在猜测上。
`identityUnknown` 同理：宁可报「无从比较」，不得填补。

### 隐私边界（沿用 T-052 裁决）

```swift
struct StaleTargetDiagnosticReport: Equatable, Sendable {
    let reason: StaleTargetReason
    let focusedApplicationIsSelf: Bool?
}
```

结构上没有 `String`、没有任何数值成员，因此内容与任何由内容派生的度量（含长度）
都无法经由该类型进入日志。`focusedApplicationIsSelf` 只在 A2 取值时给出，语义只有
「焦点是不是本进程」，不携带任何其他身份。

日志适配器 `OSLogStaleTargetDiagnosticsRecorder` 单独用 `stale-target-reason`
category，插值只有 `reason.rawValue` 与一个 `Bool`：

```text
stale-target-reason=<reason> focus-is-self=<true|false|na>
```

### 判定放在哪里

身份检查（`targetApplicationIsRunning` / `frontmostApplicationCheck` /
`windowMatches` / `elementMatches`）是 actor 隔离的私有实现，所以在
`AccessibilityGateway` 上新增一个**纯查询**：

```swift
func staleTargetAssessment(
    for targetHandle: TargetHandle,
    panelFocus: PanelFocusAuthorization
) -> StaleTargetDiagnosticReport
```

它不记录、不写入、不改任何 actor 状态，顺序与写入路径 A1→A2→A3→A4 完全一致，
比较用的 pid 也是与目标一同捕获的那一个——即 A1、A2 用的同一个 pid。**记录动作在
控制器侧**：网关只回答事实，控制器决定记什么。

A2 的面板豁免沿用 T-053：`panelFocus` 在 `MainActor` 上、于拒绝发生的那一刻从
`presenter as? PreviewPanelFocusOwnership` 求值，且**先于 `present(.staleTarget)`**
读取，读完即用、不缓存。面板是跨会话复用的单实例，缓存的 `true` 会把授权带给一个
并未获得授权的后续会话。

## 测试（先失败，后实现）

新增 `Tests/SystemInteractionFoundationTests/StaleTargetDiagnosticsTests.swift`，
14 项，全部通过生产装配路径驱动：真按快捷键 → 权限流 → 捕获 → 就绪预览，然后
`await gateway.receive(envelope)`，由网关转交给控制器自己的
`MonitorInvalidationBridge`。没有测试专用后门，也没有用 AXPress 代替真实路径。

### RED 记录（真实失败，非编译失败）

在控制器接线之前运行 `bash scripts/unit-tests.sh`：

```text
Executed 232 tests, with 14 failures (0 unexpected)

StaleTargetDiagnosticsTests.swift:25: error: XCTAssertEqual failed:
  ("nil") is not equal to ("Optional(StaleTargetReason.windowIdentityChanged)")
StaleTargetDiagnosticsTests.swift:84: error: XCTAssertEqual failed:
  ("0") is not equal to ("3")
```

失败是断言级的：类型与网关查询已存在、测试可编译，缺的正是控制器侧的记录动作。
其余 218 项全部保持通过，说明 RED 精确地圈在待实现的行为上。

### 用例清单

三种依据彼此可分：

- `testWindowChangeIsClassifiedAsWindowIdentity`
- `testElementInvalidationIsClassifiedAsElementIdentity`
- `testExternalFocusChangeIsClassifiedAsFocusedApplication`
- `testTerminatedApplicationIsClassifiedAsItsOwnReason`
- `testTheThreeMonitorReasonsAreAllDistinct` —— 三种依据在文案上完全相同，
  只有原因分类能把它们分开；断言 `Set(reasons).count == 3`

无法归因的情形如实报告：

- `testSecondSessionRefusalWithIntactIdentityIsReportedAsIntact` ——
  **ChatGPT 二次替换场景的观测覆盖**。同一输入框完成一轮「确认替换 → 恢复原文」
  后再次触发，面板刚就绪即收到监听器回调；三项身份全部匹配时必须报
  `identityIntact`，不得含糊报成某种变化
- `testSessionPanelHoldingFocusIsNotReportedAsAFocusChange` —— 面板持有键盘焦点
  （真人鼠标点按钮的常态）不得被记成「焦点应用变化」，否则 T-063 的每一条记录
  都会被这条噪声污染
- `testFocusOnThisProcessWithoutPanelKeyReportsFocusOwnership` —— 焦点在本进程但
  面板未持有时仍报 A2，并记下 `focusedApplicationIsSelf=true`

行为未变：

- `testTheRefusalItselfIsUnchanged` —— 呈现次数恰好 +1，文案与
  `PreviewPresentationMapper().viewState(for: .staleTarget).message` 逐字相等，
  setter 调用次数为 0
- `testExactlyOneReportPerRefusal` —— 一次拒绝一条记录
- `testCallbackAfterSessionEndProducesNoReport` —— 会话结束后的回调此前被忽略，
  加埋点后同样不得产生记录（被忽略的回调不是一次拒绝）

隐私：

- `testReportHasNoNumericContentMeasureField` —— 反射遍历成员，任一类型名含 `Int`
  即失败
- `testNoReportEverCarriesContentOrDigits` —— 五种情形下所有记录的字符串化结果
  既不含 `SYNTHETIC-001` 标记、不含「文字」，也不含任何十进制数字

生产装配：

- `testProductionAssemblyAttachesStaleTargetDiagnostics` ——
  `AppLifecycleController.makeStaleTargetDiagnostics()` 必须真的挂上，否则真实
  环境跑多少次都拿不到原因分类

## 改动清单

- `Sources/SystemInteractionFoundation/DomainContracts.swift`：新增
  `StaleTargetReason`、`StaleTargetDiagnosticReport`、
  `StaleTargetDiagnosticsRecording`
- `Sources/SystemInteractionFoundation/AccessibilityGateway.swift`：新增纯查询
  `staleTargetAssessment(for:panelFocus:)`
- `Sources/SystemInteractionFoundation/AppLifecycleController.swift`：新增
  `staleTargetDiagnostics` 依赖与 `makeStaleTargetDiagnostics()` 工厂、
  `staleTargetDiagnosticsWork`、`currentPanelFocusAuthorization()`；
  `targetDidBecomeStale` 在原有 `present(.staleTarget)` 之后发起归因
- `Sources/SystemInteractionFoundation/SystemInteractionAdapters.swift`：新增
  `OSLogStaleTargetDiagnosticsRecorder`
- `Tests/SystemInteractionFoundationTests/StaleTargetDiagnosticsTests.swift`：新增
- `SystemInteractionFoundation.xcodeproj/project.pbxproj`：注册新测试文件
- `Sources/SystemInteractionFoundation/ExternalTargetMonitor.swift`：**无改动**
  （observer 边界）

## 门禁

全部从**分支内** `scripts/` 执行（`bash scripts/<name>.sh`，工作目录
`.worktrees/fable`），未使用主 worktree 的脚本：

- `build.sh` → `BUILD SUCCEEDED`
- `unit-tests.sh` → `Executed 232 tests, with 0 failures`（连续两次，计数一致）
- `project-structure-check.sh` → passed
- `sdd-check.sh` → exit 0
- `secret-scan.sh` → 无命中
- `git diff --check` → 无输出

## 已知限制（如实披露）

1. **归因发生在呈现之后。** 为了不改变监听器行为，身份重新求值在
   `present(.staleTarget)` 之后异步进行，存在一个极短的时间窗：若身份在这个窗口
   内才发生变化，记录会把它算进本次拒绝。这会让 `identityIntact` 偏少而不是偏多，
   因此不会把「无法解释的拒绝」错报成「身份已变」之外的方向；T-063 逐次采集时须
   注意这一偏向。
2. **诊断不能区分「哪一个 observer 通知触发了本次回调」。** Plan 的边界不允许回调
   携带通知类型，因此 `identityIntact` 只说明身份未变，不能说明是
   `kAXValueChanged`（很可能由本工具自己的写入引发）还是别的通知。这正是 T-063
   需要真人逐次采集、T-064 才能判定根因的原因。
3. **日志格式未经 `log stream` 实测确认。** 本任务的隐私保证来自类型结构（无
   `String`、无数值成员）与适配器插值的静态可读性，以及两项反射／字符串断言。
   真机 `log stream` 的实测确认是 T-057 出口 ⑧ 的内容，不在本任务范围。
4. **本任务不修任何缺陷。** ChatGPT 二次替换仍会被拒绝；本任务只让每一次拒绝可以
   被归因。修复须经 T-063 采集、T-064 判定、并取得新一轮 Tasks Gate `PASS`。

## 审核结论与延期记录

Solar 于 2026-08-03 对 `661bb76` 给出 T-058 `PASS`：独立验证 232 tests / 0 failures，
构建、本地门禁与 GitHub Checks 全绿，无 `BLOCKER`、无 `MUST`。

一项非阻塞 `SHOULD` 予以**延期至 T-057**，理由如下（依 Review 契约，延期须记录理由）：

- finding：`testProductionAssemblyAttachesStaleTargetDiagnostics` 实际是手动把
  `makeStaleTargetDiagnostics()` 注入成员初始化器，只证明工厂返回非 nil，并未证明
  `convenience init()`（真正的生产装配入口）用了它。
- 接受该判断。同一弱点在既有的
  `testProductionAssemblyAttachesReplacementDiagnostics` 上同样存在，因此这是一处
  应统一补强的装配断言，不是 T-058 引入的新缺口。
- 延期理由：补强需要为 `convenience init()` 提供可观测的装配断言，会触及两条诊断
  路径的装配测试；T-057 的出口本就要求逐项重建验收包并重跑全部门禁，在那里一次
  改到位比在 P8 中途插入更小、更不易遗漏。T-057 出口 ⑮ 已要求 T-058 证据归档，
  本节即该记录。
