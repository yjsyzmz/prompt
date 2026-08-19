# T-066 严格 deadline：不得在 `now >= deadline` 时开始新回读

## 结论

**已修复并转绿。** 失败优先测试先把错误行为写成 RED，再以最小循环改动转绿。
全套 **256 tests / 0 failures / 0 skipped**（含三项逐操作跨线测试）。

本任务只收紧「何时允许开始下一轮 A1／A3／A4 与 AX readback」，不改变 setter 次数、
比较单位、取消语义或恢复路径。

## 两层边界（按 Tasks Gate MUST 2）

### 层次一 —— 硬保证（测试断言）

1. **最大尝试次数有上界。** `testTheAttemptCeilingStopsTheLoopIndependentlyOfTheTimeBudget`
   把时间预算抬到 60s、次数上限压到 3：AX 回读与 A1／A3／A4 检查均为恰好 3，休眠 2 次，
   累计等待远小于时间预算。
2. **累计等待预算有上界。** 既有 `testBackoffAndTotalWaitStayInsideTheDeclaredBounds`
   仍成立：各次休眠之和 ≤ `totalBudgetNanoseconds`，单次 ≤ 退避封顶。
3. **`now >= deadline` 之后不得开始新的 A1／A3／A4 或 AX readback。**
   `testTheDeadlineStopsTheLoopIndependentlyOfTheAttemptCeiling` 把次数上限抬到 100、
   总预算压到 300ms、每次退避 100ms。三次等待后时钟落在 deadline 上；第四轮必须被拒绝。
   回读次数与 validity 检查次数均为 3，不是旧实现的 4。

### 层次二 —— 残余风险（只记录，不作上界断言）

单次已经开始的 AX 调用不可中断，可能越过 deadline。本任务**不**给整个 loop 的
elapsed 设硬上界，也没有增加 AX 调用级 timeout。测试用注入时钟只在 `sleep` 时推进，
因此测到的「累计等待」等于各次休眠之和（本用例为恰好 300ms），**不是**真实 AX
查询耗时。真实环境的 loop elapsed 可能大于 300ms；该差异是已知残余风险。

上一版「整个 loop 的 elapsed 以单调时钟测量且有界」已按 REVIEW 作废。

## RED → GREEN

基线（T-065 第四轮 PASS `8d6cf42`）：252 tests。

本任务新增 1 项次数上界测试，并把 deadline 测试的错误期望从 4 次回读改为 3 次。

### RED

暂时去掉循环顶部的 `now >= deadline` 拒绝后：

```text
Executed 253 tests, with 2 failures (0 unexpected)

Failing tests:
	ReadbackConfirmationBoundTests.testTheDeadlineStopsTheLoopIndependentlyOfTheAttemptCeiling()
	ReadbackConfirmationBoundTests.testTheDeadlineStopsTheLoopIndependentlyOfTheAttemptCeiling()
```

两处失败来自同一用例的 arm64 与 x86_64。未改 deadline 检查时，三次 100ms 等待之后
仍会执行第 4 次 A1／A3／A4 与 AX 回读——正是 Finding 2 指出的错误行为。次数上界
测试在 RED 阶段已经通过，证明 ① 原先就成立，本任务没有把它和 ③ 绑死。

### GREEN

恢复「进入 A1／A3／A4 之前先看 deadline」之后，连续两次：

```text
Executed 253 tests, with 0 failures (0 unexpected)
```

门禁：`build.sh`、`project-structure-check.sh`、`sdd-check.sh`、`secret-scan.sh`、
`git diff --check` 全部通过。

## 生产改动

`AccessibilityGateway.confirmWrittenText` 在每轮 `readbackTargetStillValid` 与
`writeReadbackMatches` **之前**读取单调时钟；`now >= deadline` 立即 `.unconfirmed`，
不再消费回读次数。新增 `readbackValidityCheckCount()`，让测试能把 A1／A3／A4 与
AX 回读分开计数。

既有「失败后再看时钟」的检查仍保留，用于退避睡眠本身不超过剩余预算。

`ReadbackBudget` 注释去掉「最多八次回读」的过时表述，改为如实写出 T-066 口径与
AX 不可中断的残余风险。

## 未做

- 没有给 AX 调用加 timeout。
- 没有断言整个 loop 的 wall/monotonic elapsed 硬上界。
- 没有开始 T-067 或任何后续 P9 任务。

## Finding 1（Solar 对 `e22a4fa` 的 MUST，2026-08-19）

上一版只在整组有效性检查之前采样一次时钟。A3 在检查内部跨过 deadline 后，
A4 与 AX 文本回读仍会启动。那不是「单次已开始的 AX 调用越时」：A3 已经返回，
A4 和文本回读是随后新启动的操作。

### RED

在宿主的 A1／A3／A4 调用内把假时钟推进到 deadline。三项失败优先测试、6 个失败：

```text
Executed 3 tests, with 6 failures (0 unexpected)

A1 内跨线：windowIdentityCheckCount 2≠1，elementIdentityCheckCount 2≠1，readbackAttemptCount 1≠0
A3 内跨线：elementIdentityCheckCount 2≠1，readbackAttemptCount 1≠0
A4 内跨线：readbackAttemptCount 1≠0
```

与 Solar 定向探针一致（A3 路径：`elementCheckCount = 2` 期望 1，`readbackAttemptCount = 1` 期望 0）。

### GREEN

`confirmWrittenText` 在每个 A1、A3、A4 之前以及 `writeReadbackMatches` 之前分别读取
单调时钟；`now >= deadline` 返回 `.unconfirmed`，不再启动后续 AX 操作。
已开始的那一次调用仍会跑完，记为残余风险。

三项跨线测试转绿。全套：

```text
Executed 256 tests, with 0 failures (0 unexpected)
```
