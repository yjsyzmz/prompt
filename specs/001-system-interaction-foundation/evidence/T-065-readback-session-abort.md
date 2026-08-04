# T-065 会话／面板关闭中止回读：判定须重开 Plan Gate

## 结论（先说结果）

**T-065 的输出是「须重开 Plan Gate」，本任务不实施修复。**

真实 RED 已取得并记录在下面。使该 RED 转绿的**任何可行路径都会改变已批准 Plan
`0c9883f` 的数据流、状态机或写入隔离方式**，因此按 T-065 自身的约束——「若修复会改变
已批准的数据流、状态机或写入隔离方式，必须先重开 Plan Gate 再动实现」——本任务在此
停止，不在任务内自行变更架构。

## 任务边界

- 来源：Solar 对 `ad5c9df` 的 REVIEW Finding 1（MUST）；Tasks Gate 第四次重开第二版
  修订 `1e66ad1` 已 `PASS`，授权范围是「只执行 T-065」。
- 覆盖：FR-008、FR-010、FR-013、NFR-002、NFR-007。
- 执行日期：2026-08-04。父提交 `1e66ad1912611197442a2fed58e3666658f2de4c`。
- P9 唯一顺序中本任务位列第一；T-066、T-067、T-069、T-070 在本任务最终通过前不得开工。

## 一、被指出的缺口

T-061 条件 (7) 要求：回读期间若 session 或 target 失效（**含面板关闭**、目标应用退出、
窗口／元素身份变化），必须**立即停止**回读。

`5f5f4cf` 交付的 `testTargetInvalidationDuringReadbackStopsImmediately` 只在 fake
sleeper 回调里直接令合成 AX 元素失效。它证明的是 **A3／A4 外部变化能在下一轮被看到**，
**没有**证明 session／panel-close 中止。两者不是同一件事：前者由目标侧变化驱动，后者
由**本应用自己的会话生命周期**驱动，而后者的处理全部发生在 `MainActor` 上。

## 二、生产调用链的事实

确认替换的完整链路：

```text
用户点击「确认替换」                          （MainActor）
  → AppLifecycleController.handle(.confirmReplacement)
  → InteractionSessionCoordinator.confirmReplacement()   同步
  → GatewaySessionTextTarget.replace(_:)                  同步
  → performBlocking { … }
        Task.detached { await gateway.replaceAfterAuthoritativeValidation(…) }
        semaphore.wait()          ← MainActor 线程在此停住
  → AccessibilityGateway.confirmWrittenText(…)            actor 内
        每轮之间 sleeper.sleep(nanoseconds:) → nanosleep   同步阻塞
```

关键事实：`semaphore.wait()` 期间 **`MainActor` 线程被占住**。而会话生命周期的三个中止
入口——面板关闭／取消、`coordinator.close()`、新会话抢占——**全部只能在 `MainActor` 上
被处理**。因此在回读窗口内：

- 用户的点击无法被处理（主线程停住，AppKit 事件循环停转）；
- `finishSession()` 触发的 `releaseTarget` 也只能排在被同步休眠占住的 actor 之后；
- 任何「在 `MainActor` 上置一个取消标志」的方案都不成立——没有代码能在 `MainActor`
  上运行。

## 三、失败优先测试（经生产 bridge，非替身驱动）

新增 `Tests/SystemInteractionFoundationTests/ReadbackSessionAbortTests.swift`。装配中
**只有时钟与休眠是替身**，`InteractionSessionCoordinator`、`GatewaySessionTextTarget`
及其 `DispatchSemaphore` 桥、`AccessibilityGateway` 全部是生产对象。

三个触发各一项测试：

- `testClosingThePanelDuringReadbackStopsItWithoutWaitingForTheDeadline` ——
  `controller.handle(.close)`
- `testCoordinatorCloseDuringReadbackStopsItWithoutWaitingForTheDeadline` ——
  `controller.stop()`（内部 `coordinator.close()`）
- `testNewSessionPreemptionDuringReadbackStopsTheOldReadback` —— 回读进行中再按快捷键

中止请求从**回读循环所在的 detached task** 发起，投递到 `MainActor`：

```swift
nonisolated func requestOnMainActor(
    _ action: @escaping @Sendable @MainActor (AppLifecycleController) -> Void
) {
    Task { @MainActor [controller] in action(controller) }
}
```

这正是真实情形的形状：中止请求只能排队等 `MainActor`，测试要断言的就是**排队的中止
请求能否及时生效**。

每项断言四件事：① 剩余回读次数不再被消耗；② 中止后不再继续等待（无需等到 deadline）；
③ 不追加任何写入（setter 仍为 1）；④ 未确认的结果不得进入 `recoverable`。

## 四、真实 RED

在加入 skip 开关**之前**运行 `bash scripts/unit-tests.sh`：

```text
Executed 245 tests, with 6 failures (0 unexpected)

Failing tests:
  ReadbackSessionAbortTests.testClosingThePanelDuringReadbackStopsItWithoutWaitingForTheDeadline()
  ReadbackSessionAbortTests.testCoordinatorCloseDuringReadbackStopsItWithoutWaitingForTheDeadline()
  ReadbackSessionAbortTests.testNewSessionPreemptionDuringReadbackStopsTheOldReadback()

ReadbackSessionAbortTests.swift:186: XCTAssertLessThan failed: ("8") is not less than ("8")
  - 中止请求到达后，剩余回读次数必须不再被消耗
ReadbackSessionAbortTests.swift:191: XCTAssertLessThan failed: ("7") is not less than ("7")
  - 无需等到 deadline：中止后不得继续等待
```

三个触发的结果完全一致：**8 次回读全部消耗、7 次等待全部走完**，中止请求无一生效。

值得单独指出的是断言 ③ 与 ④ **通过了**：setter 仍只调用一次，未确认的结果也没有进入
`recoverable`。所以这次失败的性质是精确的——**不是「中止后做错了事」，而是「中止压根
没有及时发生」**，与 Finding 1 的判断一字不差。

## 五、修复路径穷举与判定

要让排队的中止请求在回读期间生效，`MainActor` 必须在回读期间是空闲的。可行路径只有
以下四条，逐条判定：

1. **把确认路径改为端到端异步**（去掉 `performBlocking`）——须改动
   `SessionTextTargetAccessing` 的**同步契约**与协调器的同步状态转移。
   → 触及已批准的**数据流与状态机**。
2. **`replace()` 提前返回，确认结果稍后投递**——须新增「确认中」状态并改变结果如何
   到达状态机。
   → 触及已批准的**数据流与状态机**。
3. **阻塞期间抽运 run loop**——使 `MainActor` 在一次写入进行中变为可重入，新会话可能
   在写入中途启动。
   → 触及已批准的**写入隔离方式**，且降低安全性。
4. **在 `MainActor` 上轮询取消标志**——不成立：`MainActor` 被占住，没有任何代码能置位。
   → 技术上不可行。

**四条中三条触及已批准 Plan，第四条不可行。因此不存在「不改架构即可修复」的路径。**

依 T-065 的明文约束，本任务到此停止，输出「须重开 Plan Gate」及上述依据。同时**不得**
把「阻塞 actor／MainActor」记作可接受的已知限制——Solar 已判定这不是限制而是待修缺陷，
本文件不做此登记。

## 六、关于把红色测试留在仓库里的处理（须审）

红色测试直接入库会让 `unit-tests.sh` 长期失败，而任何 HANDOFF 都要求该门禁全绿。三个
选项：① 就地留红；② 不入库，只在证据里贴 RED 输出；③ 入库但显式跳过。

**选择 ③**，理由：① 会阻塞后续所有 HANDOFF；② 会让这三项断言在下一轮无迹可寻。实现
方式是**单一开关**，不存在逐个测试悄悄跳过的空间：

```swift
/// 置为 `false` 即可重新启用全部三项。修复须先取得 Plan Gate 批准，届时由修复
/// 提交把它改掉——这是本文件唯一的开关。
private static let planGateStillPending = true

try XCTSkipIf(Self.planGateStillPending, Self.pendingPlanGate)
```

skip 消息内含任务号、原因（须先重开 Plan Gate）与本证据文件路径。加入开关后：

```text
Executed 245 tests, with 3 tests skipped and 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

**这一处理是 Owner 的决定，请 Reviewer 在本轮明确裁决。** 若认为红色测试必须留红、
或必须改用其他方式标记，我按裁决改。

## 七、改动清单

- `Tests/SystemInteractionFoundationTests/ReadbackSessionAbortTests.swift`：新增
- `SystemInteractionFoundation.xcodeproj/project.pbxproj`：注册新测试文件
- **生产代码零改动**：`Sources/` 下未修改任何文件

## 八、门禁

全部从**分支内** `scripts/` 执行（工作目录 `.worktrees/fable`）：

- `build.sh` → `BUILD SUCCEEDED`
- `unit-tests.sh` → `Executed 245 tests, with 3 tests skipped and 0 failures`（连续两次）
- `project-structure-check.sh` → passed
- `sdd-check.sh` → exit 0
- `secret-scan.sh` → 无命中
- `git diff --check` → 无输出

## 九、已知限制与残余风险

1. **缺口未修，只被证明。** 回读期间的会话／面板关闭中止仍不成立；在 Plan Gate 批准
   修复之前，最坏情况下 `MainActor` 会被占住约 1200ms，期间用户的取消与关闭无法被处理。
   **此项不作为可接受限制登记**，它是待修缺陷。
2. **三项测试当前被跳过。** 它们不提供任何回归保护，直到 Plan Gate 批准的修复把开关
   置为 `false`。
3. **本任务未判断修复方案。** 第五节只穷举了路径并判定其是否触及已批准 Plan，**没有
   选定**任何一条，也没有设计接口。方案选择属重开后的 Plan Gate。
