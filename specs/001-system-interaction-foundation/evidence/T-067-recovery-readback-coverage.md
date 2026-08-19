# T-067 三条 recovery 路径的回读覆盖

## 结论

**覆盖已落地并转绿。** Solar 对 `0abf88c` 的 Finding 1／4 已关闭；对 `d004520c` 的 Finding 2 计数过宽已收紧。
全套 **272 tests / 0 failures / 0 skipped**。

本任务原先只把 (a)(b)(c)(d) 写成 gateway 级测试。复核证明两处不够：
R1 仍继承 replacement 的 whole-field substring fallback；(c) 只覆盖元素失效，
没有经过生产 `recoverOriginal` / `recoverWork` 的会话取消。

## 共享 helper 的全部调用点

| 调用点 | 路径 | 写入属性 | 回读确认策略 | 覆盖的需求 |
| --- | --- | --- | --- | --- |
| `replaceAfterAuthoritativeValidation` | replacement | 捕获 mode 对应的单一 setter | 同一 mode；selected 允许 whole-field substring fallback | FR-008, FR-010（T-061） |
| `restoreWholeField`（W4） | whole-field recovery | `kAXValueAttribute` | `.wholeField` | FR-012, AC-013 |
| `restoreViaSelectedSetter`（R1） | selected recovery | `kAXSelectedTextAttribute` | **仅 selected range + selected text**（`selectedConfirmation: .selectedAttributesOnly`） | FR-012, AC-013 |
| `restoreViaSelectedRangeFallback`（R2） | selected fallback | `kAXValueAttribute`（只替换结果范围） | `.wholeField` | FR-012, AC-013 |

没有第五个调用点。`confirmWrittenText` 增加了显式策略参数，默认保持
replacement 行为；只有 R1 改为 selected-attribute-only。W4／R2 仍只回读
`kAXValue`。没有改 replacement 的 selected fallback。

## 十二条路径覆盖（按路径独立记录）

### W4

- (a) `testWholeFieldRecoveryDelayedReadbackConfirmsWithSingleSetter`：第二次等待后落地，setter=1，回读=3。
- (b) `testWholeFieldRecoveryUnconfirmedReadbackDoesNotWriteAgain`：从不落地，`.recoveryTargetChanged`，setter 仍为 1；回读 7 次，累计 sleep 恰好 1200ms（Finding 4）。
- (c) `testWholeFieldRecoveryTargetLossAbortsReadbackWithoutSpendingBudget`：第一次等待后元素身份失效，回读停在 1。**保留。**
- (d) `testWholeFieldRecoveryReadbackNeverUsesSelectedSetterOrRange`：选区 setter／range／selectedText 读取均为 0。

### R1

- (a) `testSelectedR1RecoveryDelayedReadbackConfirmsWithSingleSetter`
- (b) `testSelectedR1RecoveryUnconfirmedReadbackDoesNotWriteAgain`：同 W4，deadline 耗尽断言。
- (c) `testSelectedR1RecoveryTargetLossAbortsReadbackWithoutSpendingBudget`：**保留。**
- (d) `testSelectedR1RecoveryReadbackNeverUsesWholeFieldSetter`：whole-field setter=0，selected setter=1，**`fullValueReadCount == 0`**。

### R2

- (a) `testSelectedR2RecoveryDelayedReadbackConfirmsWithSingleSetter`
- (b) `testSelectedR2RecoveryUnconfirmedReadbackDoesNotWriteAgain`：同 W4，deadline 耗尽断言。
- (c) `testSelectedR2RecoveryTargetLossAbortsReadbackWithoutSpendingBudget`：**保留。**
- (d) `testSelectedR2RecoveryReadbackNeverUsesSelectedSetter`：selected setter=0，whole-field setter=1。

## Finding 1 MUST（`0abf88c` REVIEW）

失败优先：`testSelectedR1RecoveryDoesNotConfirmViaWholeFieldSubstringFallback`。

夹具：selected setter 报告成功但不落地；selected text 仍是 transformed；
whole value 在原范围上的 substring 恰好等于 original。修复前 recovery 会
`success` 且 `fullValueReadCount > 0`。修复后：`.recoveryTargetChanged`，
selected setter=1，whole-field setter=0，**recovery 全程 `fullValueReadCount == 0`**。

生产改动：`writeReadbackMatches` 在 selected 路径上按
`SelectedReadbackConfirmation` 分支。R1 传入 `.selectedAttributesOnly`；
replacement 默认 `.allowWholeFieldSubstringFallback`。

## Finding 2 MUST（`0abf88c` REVIEW）

现有三条 (c) 只在 sleeper 回调里设 `elementIdentityMatches = false`。
Solar 把 `Task.isCancelled` 改成永不成立后，这三条仍绿。

新增三条**生产 bridge** 测试，模板与 `ReadbackSessionAbortTests` 的
`AbortEnvironment` 相同（`sleepEntered` / `abortCompleted` 握手，不占
`MainActor`），走 `restoreOriginal` + `recoverWork`：

| 路径 | 测试 | 触发 |
| --- | --- | --- |
| W4 | `testWholeFieldRecoveryReadbackStopsWhenPanelCloses` | 面板关闭 |
| R1 | `testSelectedR1RecoveryReadbackStopsWhenCoordinatorStops` | `controller.stop()` |
| R2 | `testSelectedR2RecoveryReadbackStopsWhenNewSessionPreempts` | 新会话抢占 |

逐路径断言（`d004520c` REVIEW 收紧后）：启动 recovery **之前**记录
`readbackAttemptCount` 与 sleep 次数基线；中止并等待 `recoverWork` 结束后，
recovery 增量**恰好**为 1 次 readback、1 次 sleep。不再使用「少于最大值」。
恢复 setter 恰好一次；第一轮 sleep 里把原文补上后，旧结果仍不得写回
recoverable 或新会话。原三条 target-loss 测试全部保留。

负向变异（临时把 `confirmWrittenText` 的 `Task.isCancelled` 改为永不成立，
跑完即还原，未提交）：三条测试全部失败，**3 tests / 4 failures**。

| 路径 | 期望增量 | 忽略取消后的实际增量 |
| --- | --- | --- |
| W4 panel-close | readback=1, sleep=1 | readback=2（sleep 仍为 1：下一轮立刻确认成功） |
| R1 coordinator-stop | readback=1, sleep=1 | readback=7, sleep=7（R1 无 whole-field fallback，耗到 deadline） |
| R2 new-session | readback=1, sleep=1 | readback=2（下一轮立刻确认成功） |

W4／R2 在宽松的 `< maximumAttempts` 下会假通过，因为补上原文后第二次回读
即成功，总次数仍小于 8。精确增量把这条路堵住了。生产代码已还原。

## Finding 4 SHOULD

(b) 现断言默认预算下恰好 7 次回读、累计 sleep 恰好 1200ms。时间上界先于
8 次次数上界生效，与 `ReadbackBudget.default` 注释一致。

## 与 T-061 的关系

`tasks.md` 中 T-061 的 Covers 已按 Finding 3 选项二列入 FR-012／AC-013。
T-061 原测试只覆盖 replacement。本任务补上 recovery 三条路径后，该项纳入才有测试承载。
T-061 完成条件仍要求 T-065、T-066、T-067、T-068 全部完成。

## 门禁（`.worktrees/fable` 分支内 `scripts/`）

- `unit-tests.sh` → **272 tests / 0 failures / 0 skipped**
- `build.sh` → `BUILD SUCCEEDED`
- `project-structure-check.sh` → passed
- `sdd-check.sh` → exit 0
- `secret-scan.sh` → 无命中
- `git diff --check` → 无输出

## 未做

- 没有开始 T-069 或其后的 P9 任务。
- 没有给 AX 调用加 timeout，没有把 loop elapsed 写成硬上界。
- 没有改 replacement 的 selected→whole-field substring fallback。
