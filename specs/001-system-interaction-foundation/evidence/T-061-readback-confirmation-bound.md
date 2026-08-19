# T-061 回读确认改为有界、单次 setter、超时 fail-closed

## 任务边界与顺序决策

- 覆盖：FR-008、FR-010、FR-013、NFR-006、NFR-007。
- 执行日期：2026-08-04。父提交 `661bb763cc5d42385db7ba1fd9584fe9c1d5568f`（T-058 已获
  Solar `PASS`）。
- **执行顺序变更（用户裁决，2026-08-04）**：Solar 的下一步指示是「只执行 T-063」，
  但 T-063 要采的「二次替换」场景在当前代码上**不可达**——第一次替换本身系统性
  失败在回读。用户据此裁决先做 T-061。
  该调整**不需要修改 tasks.md、不需要重开 Tasks Gate**：T-061 在已批准的任务清单里
  的前置就是「Depends on: Tasks PASS」，不依赖 T-063 或 T-064。被调整的只是口头
  执行顺序。T-062 的前置仍要求 T-063、T-064 与新一轮 Tasks `PASS`，未被触碰。

## 触发本任务的实测证据

T-058 的埋点在真机上（macOS 26.5.2 / 25F84，Chrome 150.0.7871.187，应用
`661bb76`，cdhash `d7fc0e82`）抓到：

```text
11:26:23  replacement-stage=readback failure=writeFailed focus-is-self=na
11:26:41  replacement-stage=readback failure=writeFailed focus-is-self=na
11:28:57  replacement-stage=readback failure=writeFailed focus-is-self=na
11:32:13  replacement-stage=readback failure=writeFailed focus-is-self=na
```

同一时段 `completed` 记录 **0 条**：ChatGPT 页面里第一次替换从未成功。面板文案为
「未能安全替换原文，结果仍可复制。」这与 T-055 记录的 3 条同类失败是同一缺陷。

已知机理（T-037 已记录）：Chromium 在渲染进程异步应用辅助功能写入，setter 立刻
返回成功，紧接着的回读拿到的仍是写入前的值。

## 旧实现的四处问题

```swift
for attempt in 0 ..< 5 {
    if attempt > 0 { usleep(100_000) }
    if writeReadbackMatches(...) { return true }
}
return false
```

1. 预算是「5 次 × 固定 100ms」，**没有单调时钟 deadline**，总时长只是次数的副产品。
2. 退避固定，不是有界退避；上界从未被声明或断言。
3. 目标在回读期间失效时**不会提前停止**，会把剩余次数全部耗光。
4. 比较用 `writeReadbackMatches` 内的 Swift `String ==`，那是**规范等价**比较，不是
   UTF-16 逐码元比较。目标若把文字重新规范化，旧实现会把它当成写入成功。

第 4 点此前没人发现，是本任务写测试时暴露的。

## 九项条件的落实

### (1) 单调时钟 deadline

```swift
let deadline = clock.now() &+ readbackBudget.totalBudgetNanoseconds
```

`clock` 是注入的 `MonotonicClockReading`（生产实现 `SystemMonotonicClock` 用
`DispatchTime.now().uptimeNanoseconds`）。墙钟调整在这个抽象里**没有表示**，因此
无法影响预算。`MonotonicClockReading` 因此加上 `Sendable`（网关是 actor），两处
既有测试替身随之标注 `@unchecked Sendable`。

### (2) 有界退避，次数与总时长均有明确上界

```swift
static let `default` = ReadbackBudget(
    maximumAttempts: 8,
    totalBudgetNanoseconds: 1_200_000_000,   // 1200ms
    initialBackoffNanoseconds: 50_000_000,   //   50ms
    maximumBackoffNanoseconds: 250_000_000   //  250ms
)
```

- **回读次数上界：8 次**（含第一次）。
- **总等待时长上界：1200ms**。
- 退避倍增并封顶：50 → 100 → 200 → 250 → 250 …
- 每次休眠取 `min(backoff, deadline - now)`，因此**永不越过 deadline**。

两个上界的交互是明确的：七次退避理论上累加为
50+100+200+250+250+250+250 = **1350ms**，超过 1200ms 的 deadline，因此**时间上界
先生效**，最后一次休眠被裁剪。实测休眠序列为
`[50, 100, 200, 250, 250, 250, 100]`ms，合计恰好 1200ms，回读 8 次。

旧实现的等价预算是 5 次 / 400ms；新预算把最坏等待放宽到 1200ms，代价是确认失败
时用户多等约 0.8 秒。NFR-001 的 300ms 只约束确认前的预览呈现，**不包含确认之后的
回读**（依 Solar Tasks Gate REVIEW 的更正），因此这里不存在需要协商的时间上限。

### (3) 逐 UTF-16 码元比较

```swift
private func readbackTextMatches(_ candidate: String, _ expected: String) -> Bool {
    (candidate as NSString).isEqual(to: expected)
}
```

替换了 `writeReadbackMatches` 内全部三处 `==`（选区值、整段值、整段内的候选子串）。
不使用规范化比较、前缀比较或长度比较。比较单位与 FR-012 的范围单位一致。

### (4)(5)(6) 写入约束

- setter 仍在 `confirmWrittenText` **之前**调用，且只调用一次；重试只重复回读——
  `confirmWrittenText` 内部不含任何写入调用。
- 不存在替代 setter：选区路径失败时不会改用 `kAXValue`。测试
  `testSelectedModeNeverFallsBackToTheWholeFieldSetter` 断言
  `wholeFieldSetterAttemptCount == 0`。
- setter 返回成功不构成成功：唯一成功判据是 `ReadbackOutcome.confirmed`。

### (7) 中途失效立即停止

```swift
guard readbackTargetStillValid(targetHandle: targetHandle, pid: pid) else {
    return .aborted
}
```

在**每次回读之前**求值，复用写入路径已经信任的 A1／A3／A4 三项检查（应用仍在运行、
窗口身份一致、元素身份一致）。会话结束或面板关闭会释放捕获引用，届时窗口与元素
都无从匹配，因此同样落入这一分支——不需要另加一个「引用是否还在」的判据。

**一处实测更正**：最初的实现额外加了 `targetReferences[handle] != nil` 前置。这让
11 个既有测试转红，因为使用注入式 `authoritativeTarget` 假件的测试其
`retainedTargetReference()` 返回 nil，`targetReferences` 里根本没有条目。该前置被
移除；判据收敛为与写入路径完全一致的 A1／A3／A4。

A2（外部前台应用）**刻意不在回读期间复查**：真人用鼠标点「确认替换」时预览面板
合法地持有键盘焦点，复查 A2 会把每一次真人驱动的确认都判成失效。

### (8) fail-closed 与安全后备

`unconfirmed` 与 `aborted` 都返回 `.writeFailed`，映射为「未能安全替换原文，结果仍
可复制。」+ `[.copyResult]`，`isFailClosed == true`：保留结果可复制、不声称已写入、
不提供自动重写。测试 `testUnconfirmedWriteOffersACopyableResultAndClaimsNoWrite`
断言 `safeNextActions` 不含 `.retry`。

### (9) 隐私

回读诊断仍只记阶段与失败分类。新增阶段取值 `readbackAborted` 只有 rawValue，无内容、
无长度、无数字。测试 `testReadbackDiagnosticsCarryNoContentOrDigits` 对两种失败路径
的全部记录做反射与字符串断言。

## 为什么新增 `readbackAborted` 阶段

任务条件 (8) 只要求两种情形都 fail-closed，未要求区分。但若两者都记成 `readback`，
就会重演 T-058 修掉的那类盲区：「预算耗尽」与「目标中途失效」是不同的现实事件，
需要不同的后续动作，而日志无法分辨。该取值是内容无关的，代价只有一个枚举成员，
因此予以新增并在此说明理由。`DomainFailure` 未新增取值，T-054 的完全映射不受影响。

## 测试（先失败，后实现）

新增 `Tests/SystemInteractionFoundationTests/ReadbackConfirmationBoundTests.swift`
共 10 项。

### 第一轮 RED（断言级）

在实现新循环之前：

```text
Executed 242 tests, with 8 failures (0 unexpected)

testUnconfirmedUntilDeadlineFailsClosedWithoutAnotherWrite:
  XCTAssertEqual failed: ("5") is not equal to ("8")
testTargetInvalidationDuringReadbackStopsImmediately:
  XCTAssertEqual failed: ("5") is not equal to ("1")
  XCTAssertEqual failed: ("readback") is not equal to ("readbackAborted")
testTheDeadlineStopsTheLoopIndependentlyOfTheAttemptCeiling:
  XCTAssertEqual failed: ("5") is not equal to ("4")
testBackoffAndTotalWaitStayInsideTheDeclaredBounds:
  XCTAssertEqual failed: ("0") is not equal to ("7")
testDelayedApplicationIsConfirmedWithASingleSetter: failed
```

### 第二轮 RED（(3) 的判据真的会咬）

实现新循环后、把比较改为 UTF-16 之前，**只剩一项失败**：

```text
Executed 242 tests, with 1 failure (0 unexpected)
Failing tests:
  ReadbackConfirmationBoundTests.testCanonicallyEquivalentTextIsNotAcceptedAsConfirmation()
```

这一步是刻意分两次跑的。第一轮 RED 时该测试是**空过**的——旧循环不经过注入的
sleeper，分解形式的文字压根没被写进夹具。只有在新循环生效后，它才真正区分
「Swift `==`」与「UTF-16 逐码元」：前者判为确认成功，测试失败；后者拒绝，测试通过。
若只跑一轮，这条断言会以假通过的形式混过去。

### 用例清单

任务明文要求的三条：

- `testDelayedApplicationIsConfirmedWithASingleSetter` —— (a)：第 2 次等待后渲染
  进程才应用写入；须报成功、setter 仅 1 次、回读恰好 3 次
- `testUnconfirmedUntilDeadlineFailsClosedWithoutAnotherWrite` —— (b)：预算耗尽，
  fail-closed、文本未变、setter 仍为 1 次、回读用尽 8 次
- `testTargetInvalidationDuringReadbackStopsImmediately` —— (c)：第 1 次等待中令
  元素身份失效；回读次数为 1（远小于 8）、休眠次数为 1、阶段为 `readbackAborted`、
  setter 未追加

其余：

- `testBackoffAndTotalWaitStayInsideTheDeclaredBounds` —— 休眠次数 = 次数上界 − 1、
  单次不超过封顶、合计不超过总预算、首次等于声明的初始退避
- `testTheDeadlineStopsTheLoopIndependentlyOfTheAttemptCeiling` —— 把次数上界抬到
  100、总预算压到 300ms，循环须在第 4 次回读后停止，证明是**时间**上界在起作用
- `testCanonicallyEquivalentTextIsNotAcceptedAsConfirmation` —— 见上
- `testSelectedModeNeverFallsBackToTheWholeFieldSetter` —— (5)
- `testSetterSuccessAloneIsNeverReportedAsSuccess` —— (6)
- `testUnconfirmedWriteOffersACopyableResultAndClaimsNoWrite` —— (8)
- `testReadbackDiagnosticsCarryNoContentOrDigits` —— (9)

时间通过注入的 `MonotonicSleeping` 假件推进，测试不消耗真实等待。

## 改动清单

- `Sources/SystemInteractionFoundation/SystemInteractionAdapters.swift`：
  `MonotonicClockReading` 加 `Sendable`；新增 `MonotonicSleeping` 与
  `SystemMonotonicSleeper`（用 `nanosleep` 并在 `EINTR` 时补足剩余时间，避免被信号
  打断后静默缩短预算）
- `Sources/SystemInteractionFoundation/DomainContracts.swift`：新增 `ReadbackBudget`、
  `ReadbackOutcome`、`ReplacementStage.readbackAborted`
- `Sources/SystemInteractionFoundation/AccessibilityGateway.swift`：注入 clock／
  sleeper／budget；`writtenTextConfirmed` 改为 `confirmWrittenText`；新增
  `readbackTargetStillValid`、`readbackTextMatches`、`readbackAttemptCount()`；
  四处调用点改为按 `ReadbackOutcome` 分派
- `Tests/.../ReadbackConfirmationBoundTests.swift`：新增
- `Tests/.../AXAuthoritativeWriteRecoveryTests.swift`：调用序列断言补入回读前的
  A1／A3／A4 三项（该测试固定的是旧行为，须随之更新）
- `Tests/.../HotKeySecureInputProbeTests.swift`、`PresentationLatencyInstrumentationTests.swift`：
  时钟替身补 `@unchecked Sendable`
- `SystemInteractionFoundation.xcodeproj/project.pbxproj`：注册新测试文件

## 门禁

全部从**分支内** `scripts/` 执行（工作目录 `.worktrees/fable`）：

- `build.sh` → `BUILD SUCCEEDED`
- `unit-tests.sh` → `Executed 242 tests, with 0 failures`（连续两次，计数一致）
- `project-structure-check.sh` → passed
- `sdd-check.sh` → exit 0
- `secret-scan.sh` → 无命中
- `git diff --check` → 无输出

## 已知限制（如实披露）

1. **回读期间会阻塞 actor。** 循环是同步的，最坏情况占用 `AccessibilityGateway`
   约 1200ms。这是刻意的：改成 `await Task.sleep` 会在写入序列中引入挂起点，使
   actor 可重入，从而扩大 Plan 已披露的 TOCTOU 窗口。代价是同一时刻不会有第二个
   会话进入网关——当前设计本就只允许一个活动会话。
2. **失效检测的粒度是「两次回读之间」。** 最坏情况下目标失效后最多再等一个退避
   周期（≤250ms）才被发现。要做到真正即时需要在等待中被打断的机制，超出本任务
   范围。
3. **1200ms 是依据本机四次真机失败选的，不是统计意义上的定量结论。** 该值是否
   足以覆盖 ChatGPT 的实际延迟，须由真机复验确认；若仍不足，应以新证据调整预算
   而不是放弃回读确认。
4. **本任务不解决「二次替换被判目标变化」。** 那是 T-063 采集、T-064 判定的对象，
   与本任务修的回读确认是两个不同问题（T-058 的埋点已把两者分开）。
5. **真机复验未能触达本任务修改的代码路径。** 2026-08-04 14:27 在 `5f5f4cf`
   （cdhash `26aef136`）上由真人在 ChatGPT 页面复验两次，两次都失败，但日志是：

   ```text
   14:27:16  stale-target-reason=focusedApplicationChanged focus-is-self=false
   14:27:30  stale-target-reason=focusedApplicationChanged focus-is-self=false
   ```

   `replacement-stage` 记录 **0 条**——替换从未被请求，拒绝发生在监听器路径，
   **回读循环根本没有执行**。因此：
   - T-061 目前**只有自动化证据**，没有真机证据。不得声称回读修复已在真实环境验证。
   - 1200ms 预算是否足够仍是未验证的假设（限制 3 依然成立）。
   - 这次失败属于 T-063／T-064 的对象（监听器路径 A2 拒绝），与本任务修的回读确认
     是两个不同缺陷——T-058 的埋点正是让这两者可以被分开的原因。
   - 本任务的真机证据须等到 ChatGPT 场景能走到 setter 之后才能取得，届时补入本节。

6. **补充观测（2026-08-04 14:30，同一 SHA）：回读循环执行了，预算被完整耗尽，
   且扩大预算已被证据排除。**

   ```text
   14:30:01  replacement-stage=readback failure=writeFailed focus-is-self=na
   14:30:16  replacement-stage=readback failure=writeFailed focus-is-self=na
   14:30:42  replacement-stage=readback failure=writeFailed focus-is-self=na
   ```

   三次均为 `readback`，**无一条 `readbackAborted`**——目标全程有效，不是中途失效，
   而是 8 次回读 / 1200ms 用尽仍未确认。这一区分由本任务新增的 `readbackAborted`
   取值提供，旧实现无法分辨。

   真人随后在**不点任何按钮**的情况下观察 ChatGPT 输入框：三次失败之后，等待数秒，
   `【系统交互验证】` 前缀**始终没有出现**。因此：

   - setter 报告成功但写入**从未落地**，不是「落地得比 1200ms 更晚」。
   - **扩大回读预算不能解决这个现象**，予以排除。这不是一个可以靠调数字修好的缺陷。
   - 本任务的 fail-closed 行为在此情形下是**正确的**：不声称已写入、保留结果可复制、
     不自动重写。用户看到的结果是诚实的，尽管产品目标未达成。

   **本次改动不是原因。** 同一现象在 T-061 之前的 `661bb76` 上就已出现
   （11:26:23、11:26:41、11:28:57、11:32:13 四条同类记录），当时的比较还是 Swift
   `String ==`。因此把比较改为 UTF-16 逐码元与本现象无关。

   **该现象超出 T-061 的范围**，须单独判定：它触及已批准的 C5「Chrome/ChatGPT 完整
   闭环」，因此不得由本任务顺手处理，也不得靠推断结案。

7. **真机证据已取得（2026-08-04 14:34，同一 SHA，TextEdit 对照）。**

   ```text
   14:34:42  replacement-stage=completed failure=none focus-is-self=na
   14:34:47  replacement-stage=completed failure=none focus-is-self=na
   ```

   真人在 TextEdit 中以鼠标拖选后确认替换，**两次均成功**，写入被回读确认。因此：

   - **有界回读在真实应用上端到端可用**，1200ms／8 次的预算对 TextEdit 充足。
     限制 5「只有自动化证据」由此撤回；限制 3 的「预算是否足够」对 TextEdit 已获
     真机确认，对 ChatGPT 则不适用——那里写入根本不落地，任何预算都不改变结果。
   - **可保留的结论，逐字如下**：失败可在 ChatGPT 复现；TextEdit 对照未复现；扩大
     readback budget 不能使这三次写入落地；**根因未知**。

     **依 Solar 对 `ad5c9df` 的 REVIEW Finding 4 更正（2026-08-04）**：本节原写有
     「写入路径本身完好」「定性为目标特定，而不是本项目写入实现的缺陷」，该定性
     **超出现有证据，已删除**。TextEdit 两次成功只能证明共享写入路径在 TextEdit
     可用；ChatGPT 特有的 capture mode、属性选择、range 语义或适配逻辑仍可能是本项目
     的实现缺陷。T-064 以及新增的决策任务**不得继承**被删除的那条推断。

8. **附带观测：`identityIntact` 首次在真实环境出现。**

   ```text
   14:32:12  stale-target-reason=identityIntact focus-is-self=na
   ```

   这条记录来自 14:32 前后切换应用的过渡时段，**不作为干净样本**（环境未固定，
   须由 T-063 在固定环境下重取）。但它验证了 T-058 保留该取值的理由：确实存在
   「监听器判定目标变化，而三项身份全部匹配」的真实拒绝。若当初只提供三种「变化」
   取值，这一次拒绝就会被迫记成某种变化，T-064 的根因判断将建立在错误分类上。
