# T-067 三条 recovery 路径的回读覆盖

## 结论

**覆盖已落地并转绿。** 为 whole-field W4、selected R1、selected R2 fallback
各补 (a)(b)(c)(d) 四项失败优先断言，共 12 项。全套 **268 tests / 0 failures / 0 skipped**。

本任务不改生产行为：三条路径在 `5f5f4cf` 起已调用共享 helper
`AccessibilityGateway.confirmWrittenText`。T-067 把 FR-012／AC-013 的回读条件
写成可独立失败的测试，而不是再实现一套循环。

## 共享 helper 的全部调用点

| 调用点 | 路径 | 写入属性 | 回读 mode | 覆盖的需求 |
| --- | --- | --- | --- | --- |
| `replaceAfterAuthoritativeValidation` | replacement | 捕获 mode 对应的单一 setter | 同一 mode | FR-008, FR-010（T-061） |
| `restoreWholeField`（W4） | whole-field recovery | `kAXValueAttribute` | `.wholeField` | FR-012, AC-013 |
| `restoreViaSelectedSetter`（R1） | selected recovery | `kAXSelectedTextAttribute` | `recovery.captureMode`（选区） | FR-012, AC-013 |
| `restoreViaSelectedRangeFallback`（R2） | selected fallback | `kAXValueAttribute`（只替换结果范围） | `.wholeField` | FR-012, AC-013 |

没有第五个调用点。helper 没有在本任务中扩大行为面：比较单位、次数上界、累计等待上界、
逐操作 deadline、取消与目标失效中止，均沿用 T-061／T-065／T-066 已固定的语义。

## 十二条覆盖（按路径独立记录）

### W4

- (a) `testWholeFieldRecoveryDelayedReadbackConfirmsWithSingleSetter`：第二次等待后落地，setter=1，回读=3。
- (b) `testWholeFieldRecoveryUnconfirmedReadbackDoesNotWriteAgain`：从不落地，`.recoveryTargetChanged`，setter 仍为 1。
- (c) `testWholeFieldRecoveryTargetLossAbortsReadbackWithoutSpendingBudget`：第一次等待后元素身份失效，回读停在 1，剩余预算未消耗。
- (d) `testWholeFieldRecoveryReadbackNeverUsesSelectedSetterOrRange`：选区 setter／range／selectedText 读取均为 0。

### R1

- (a) `testSelectedR1RecoveryDelayedReadbackConfirmsWithSingleSetter`
- (b) `testSelectedR1RecoveryUnconfirmedReadbackDoesNotWriteAgain`
- (c) `testSelectedR1RecoveryTargetLossAbortsReadbackWithoutSpendingBudget`
- (d) `testSelectedR1RecoveryReadbackNeverUsesWholeFieldSetter`：whole-field setter=0，selected setter=1。

### R2

- (a) `testSelectedR2RecoveryDelayedReadbackConfirmsWithSingleSetter`
- (b) `testSelectedR2RecoveryUnconfirmedReadbackDoesNotWriteAgain`
- (c) `testSelectedR2RecoveryTargetLossAbortsReadbackWithoutSpendingBudget`
- (d) `testSelectedR2RecoveryReadbackNeverUsesSelectedSetter`：selected setter=0，whole-field setter=1。

三条路径的 (a)(b)(c) 期望相同（单次 setter、deadline fail-closed、失效立即停），
(d) 按实际写入属性分别断言，不以一条顶替另一条。

## 与 T-061 的关系

`tasks.md` 中 T-061 的 Covers 已按 Finding 3 选项二列入 FR-012／AC-013。
T-061 原测试只覆盖 replacement。本任务补上 recovery 三条路径后，该项纳入才有测试承载。
T-061 完成条件仍要求 T-065、T-066、T-067、T-068 全部完成。

## 未做

- 没有改 `confirmWrittenText` 或任何 setter。
- 没有开始 T-069 或其后的 P9 任务。
- 没有给 AX 调用加 timeout，没有把 loop elapsed 写成硬上界。
