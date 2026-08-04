# T-065 会话／面板关闭立即中止回读

## 结论

**已修复并转绿。** 三项经生产 bridge 的测试从真实 RED 变为 GREEN，全套 246 项、
**0 skipped**、0 failures。

修复是**回到已批准 Plan**，不是变更架构：`plan.md` 早已规定 `TextTargetAccessing`
的写入与恢复是 `async`、会话结束时取消异步任务、异步结果返回时按 session ID 去重。
真正偏离 Plan 的是被移除的同步协议与 `DispatchSemaphore` 桥。

## 一、Owner 上一轮判断错误的更正

`005ca4c` 的证据结论是「任何可行修复都触及已批准 Plan，因此必须重开 Plan Gate」。
**该结论错误，已由本文件取代。** Solar 对 `005ca4c` 的 REVIEW Finding 1 指出并给出
行号，Owner 逐条核对 `plan.md` 后确认引用准确：

- 第 130–135 行：`TextTargetAccessing.replace / restore / release` **全部是 `async`**；
- 第 52 行：UI 与 Coordinator 在 `MainActor`，AX 引用由 `AccessibilityGateway`
  actor 串行拥有；
- 第 55 行：「所有异步结果返回时必须再次匹配当前 session ID，旧结果直接丢弃并清理」；
- 组件表：`InteractionSessionCoordinator` 的职责明确含「异步结果去重」；
- 第 158 行：`applying` 状态已在批准的状态机内；
- 第 387 行：「会话结束时取消异步任务、停止观察、释放 target handle」。

**错误原因是可指认的**：Owner 从实现代码与 T-065 的约束文本推理，**没有先读
`plan.md` 的接口章节**就下了「须重开 Plan Gate」的结论。这与本项目反复纠正的
「先查证再断言」是同一类错误，只是这次发生在 Owner 自己身上。

## 二、修复内容

### 1. 恢复 `plan.md` 批准的 `async` 契约

```swift
@MainActor
protocol SessionTextTargetAccessing: AnyObject {
    func replace(_ content: SessionContent) async -> Result<Void, DomainFailure>
    func validateForRecovery(_ content: SessionContent) async -> Bool
    func restore(_ content: SessionContent) async -> Bool
}
```

`GatewaySessionTextTarget` 内的 `performBlocking`／`DispatchSemaphore`／`ResultBox`
**已整体删除**，改为直接 `await gateway.…`。协议留在 `MainActor`（`plan.md` 第 52 行），
真正的挂起发生在 `await` gateway 那一刻——那一刻 `MainActor` 被释放。

### 2. 协调器保存并取消在途任务

```swift
private(set) var applyWork: Task<Void, Never>?
private(set) var recoverWork: Task<Void, Never>?

private func cancelInFlightWork() {
    applyWork?.cancel();  applyWork = nil
    recoverWork?.cancel(); recoverWork = nil
}
```

`endSession()` 与 `replaceCurrentSession()` 都调用它，覆盖取消、关闭与新会话抢占三条
路径（`plan.md` 第 387 行）。

### 3. 结果回到 `MainActor` 后按 session ID 与状态 fail-closed

```swift
private func applyCompleted(
    _ outcome: Result<Void, DomainFailure>,
    for sessionID: InteractionSessionID
) {
    guard !Task.isCancelled, sessionID == currentSessionID, state == .applying else {
        return
    }
    …
}
```

`sessionID` 在**启动时捕获**，回来时与 `currentSessionID` 比对。被取消或已离开
`applying` 的结果一律丢弃，**不得进入 `recoverable`**（`plan.md` 第 55 行）。
`recoveryCompleted` 同构。

### 4. 取消传播进回读循环

```swift
if Task.isCancelled {
    return .aborted
}
```

置于每轮回读之前。取消能生效的前提正是 `MainActor` 不再被占住——否则取消请求根本
排不到执行。这一行与第 1 项是同一个修复的两半，缺任一半都无效（见第四节负向对照）。

## 三、确定性握手（Finding 3）

上一版测试用 `Task.yield()` 猜调度，Solar 判定失败或通过都无法归因。现改为显式握手，
逐步证明四件事：

```swift
controller.handle(.confirmReplacement)
let inFlight = controller.applyWork      // 取消会清空句柄，先抓住在途任务
await waitFor(sleepEntered)              // (a) 第一轮 sleep 已进入回读循环
abort(controller)                        // (b) 中止在 MainActor 上实际执行完毕
abortCompleted.signal()                  // (c) 才放行后续回读
await inFlight?.value                    // (d) 等生产任务真正结束
```

- `sleepEntered` 由 sleeper 替身在第一轮 sleep 内 `signal()`，随后 `wait()` 在
  `abortCompleted` 上把回读**卡住**，因此 (b) 与 (c) 的先后是被强制的，不是碰巧。
- `waitFor` 用 `withCheckedContinuation` + 全局队列桥接信号量，**不占用
  `MainActor`**。
- 第 (b) 步能被执行本身就是被测行为：若 `MainActor` 仍被 semaphore 占住，这一行根本
  轮不到运行。

## 四、真实 RED → GREEN

### RED（`005ca4c`，旧同步桥）

```text
Executed 245 tests, with 6 failures (0 unexpected)
  8 次回读全部消耗（断言要求 < 8）
  7 次等待全部走完（断言要求 < 7）
```

三个触发结果一致；`setter == 1` 与「未进入 recoverable」两条断言当时**通过**，说明
缺口性质是「中止没有及时发生」，而不是「中止后做错事」。

### GREEN（本次）

```text
Executed 246 tests, with 0 failures (0 unexpected)   ← 0 skipped
```

三项测试实测 `readbackAttemptCount == 1`、`sleptDurations.count == 1`：中止在第一轮
等待后立即生效，剩余预算未被消耗。

### 负向对照（证明 GREEN 归因于取消机制，而非调度运气）

把回读循环里的取消检查临时改为永不成立（`if Task.isCancelled, false`），其余不动：

```text
Executed 246 tests, with 6 failures (0 unexpected)

ReadbackSessionAbortTests.swift:24: XCTAssertLessThan failed: ("8") is not less than ("8")
ReadbackSessionAbortTests.swift:24: XCTAssertLessThan failed: ("7") is not less than ("7")
ReadbackSessionAbortTests.swift:33: 同上
ReadbackSessionAbortTests.swift:42: 同上
```

**恰好这三项失败，其余 243 项不受影响。** 恢复该行后重新全绿。这条对照是本次
GREEN 可归因性的直接证据。

### 新增第四项测试

`testCancelledWriteNeverReachesRecoverableEvenIfItLaterSucceeds`：让写入在回读中途
真正落地，同时结束会话。断言旧 session 的成功结果**不得**进入 `recoverable`——这是
`plan.md` 第 55 行去重规则的直接断言，也是 Solar 列出的残余风险之一。

## 五、`skip` 处理的最终状态

`005ca4c` 曾以单一开关 `planGateStillPending` + `XCTSkipIf` 入库三项红色测试。依
Solar 裁决——「只可作为缺口证明提交中的临时标记，不接受其作为 T-065 完成态」——该
开关与全部 skip 已**整体删除**。本次交付 **0 skipped**，测试计数 246。

## 六、改动清单

生产代码：

- `Sources/.../InteractionSessionCoordinator.swift`：协议改 `async` 并加 `@MainActor`；
  `confirmReplacement`／`recoverOriginal` 改为启动可取消任务；新增 `applyWork`、
  `recoverWork`、`applyCompleted`、`recoveryCompleted`、`cancelInFlightWork`
- `Sources/.../SessionIntegration.swift`：删除 `performBlocking`、`DispatchSemaphore`
  与 `ResultBox`，三个方法改为 `async`
- `Sources/.../AccessibilityGateway.swift`：回读循环每轮前检查 `Task.isCancelled`
- `Sources/.../AppLifecycleController.swift`：暴露 `applyWork`／`recoverWork` 直通句柄

测试：

- `Tests/.../ReadbackSessionAbortTests.swift`：重写为确定性握手，删除 skip 开关，
  新增第四项测试
- 九个既有测试文件共插入 35 处 `await …applyWork?.value` / `await …recoverWork?.value`，
  四处测试签名补 `async`；**未改动任何断言、期望值、注释或测试名**（已用 diff 过滤
  逐行核对）
- `Tests/.../ProductionTargetMonitorAssemblyTests.swift`：四处调用点补 `await`

## 七、门禁

全部从**分支内** `scripts/` 执行（工作目录 `.worktrees/fable`）：

- `build.sh` → `BUILD SUCCEEDED`
- `unit-tests.sh` → `Executed 246 tests, with 0 failures`，**0 skipped**（连续两次）
- `project-structure-check.sh` → passed
- `sdd-check.sh` → exit 0
- `secret-scan.sh` → 无命中
- `git diff --check` → 无输出

## 八、已知限制与残余风险（如实披露）

1. **单次已经开始的 AX 调用不可中断。** 取消只在两次回读之间的检查点生效，最坏情况
   下要等当前那一次 AX 查询自行返回。**本任务不声称能原子或即时中断单次系统调用**，
   这一项按 Solar 要求留给 T-066 的口径记录。
2. **`ProductionTargetMonitorAssemblyTests.testElementLevelChangeDeliversEnvelopeToGateway`
   在本次改动过程中出现过一次失败、复跑通过。** 该测试用
   `await Task.yield()` + `settle()` 同步，属 Finding 3 批评的同一类非确定性写法；本次
   未改它（不在 T-065 授权范围）。**如实登记为已观察到的间歇性**，建议由 Reviewer
   裁决是否单独立项，不建议在 T-065 内顺手改。
3. **本任务只解决「中止能否及时发生」。** 回读预算的严格 deadline 属 T-066，三条
   recovery 路径的覆盖属 T-067，均未开工。
