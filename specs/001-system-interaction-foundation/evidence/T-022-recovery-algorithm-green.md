# T-022 恢复算法实现（GREEN）

## 任务边界

- 任务：T-022 [Implementation] 实现权威验证、替换与恢复（按重开后的 Plan 算法重写）。
- Plan 基线：`0c9883f8385c731b0cc084d22519224eada926ea`（Solar `PASS`）。
- Tasks 基线：`a8d032737659b0f347170e67a3b7c4f749cd3cfb`（Solar `PASS`）。
- 驱动测试：`evidence/T-021-recovery-algorithm-red.md`（修正夹具后 149 tests、
  15 failures 的稳定 RED）。
- 本轮只实现使 T-021 转绿所需的最小代码，未处理原 Implementation REVIEW 的
  Finding 1、2、4、5、6。
- 原 `evidence/T-022-authoritative-write-recovery-green.md` 对应作废前的算法，
  不作为本任务证据。

## 实现内容（`Sources/SystemInteractionFoundation/AccessibilityGateway.swift`）

按 tasks.md 的七条约束逐项落实：

1. **共享前置检查下沉为 `sharedPrechecks(targetHandle:pid:)`**（A1–A4）：
   应用与 PID、外部目标、窗口身份、元素身份、元素可编辑性与 secure subrole、
   全局 Secure Event Input。该函数**不含** settable 检查。
2. **settable 检查路径化**：replacement 沿用 `validate` 内对捕获模式对应属性的
   检查；whole-field recovery 检查 `.wholeField`；selected recovery R1 检查
   `recovery.captureMode`（即 `kAXSelectedTextAttribute`）；fallback 由门禁 1
   检查 `.wholeField`。`kAXSelectedTextAttribute` 不可写不再阻断 fallback。
3. **replacement 保持严格单 setter**：`replaceAfterAuthoritativeValidation`
   逻辑未变，`validate` 简化为只服务 replacement（移除 `isRecovery` 分支）。
4. **recovery 入口按 capture mode 分支**：
   `restoreAfterAuthoritativeValidation` 先 `switch recovery.captureMode`，
   `clipboardInput` 立即 `recoveryTargetChanged`；`wholeField` 进入
   `restoreWholeField`；`selectedText` 进入 `restoreSelected`。
5. **新增 `restoreWholeField`（W1–W4）**：读全文并要求等于 expected transformed
   text → 检查 `kAXValueAttribute` 可设置 → 一次 `setText(.wholeField)` →
   回读确认。该函数不调用 `currentSelectedRange`，也不使用
   `kAXSelectedTextAttribute`。
6. **新增 `restoreSelected`（C1–C4 与 R1／R2／R3）**：
   - C1 计算 expected result range = 捕获 location + expected transformed text
     的 UTF-16 长度；
   - C2 分类：`currentRange == expectedResultRange` → R1；
     零长度且 location 落在 `[location, location + length]` → R2 情形 1；
     `.failure(.unsupportedTarget)` → R2 情形 2；
     其他 failure（invalid、权限、secure、timeout、cannotComplete）→ 原样返回
     （R3）；非零长度不匹配或零长度落在范围外 → `recoveryTargetChanged`；
   - R1 走 `restoreViaSelectedSetter`：内容比较 → 路径化 settable → 一次
     selected setter → 回读确认；
   - R2 走 `restoreViaSelectedRangeFallback`。
7. **`restoreCollapsedSelection` 已删除**，由 `restoreViaSelectedRangeFallback`
   取代，逐项实现六项门禁：① `kAXValueAttribute` 可设置；② **在门禁 1 之后、
   setter 之前**读取基值（函数内只读一次，不复用早前读取）；③ location ≥ 0、
   length ≥ 0 且 location + length ≤ 基值 UTF-16 长度；④ 基值该范围内文本等于
   expected transformed text；⑤ 写入值由基值仅替换该范围构成；⑥ 一次
   `setText(.wholeField)` 后回读确认。任一失败返回 `recoveryTargetChanged`，
   不改回 selected setter、不第二次写入。
8. **不依赖 AXObserver 授权**：恢复路径不读取任何监控状态。
9. **未引入额外写入策略**：无清空、无模拟全选、无模拟粘贴、无分段写入；
   TOCTOU 残余风险按 Plan 记录接受。

同时删除了随旧算法作废的死代码：`recoveryTextFromFullValue`，以及 `validate`／
`currentText` 中仅服务旧 recovery 语义的 `isRecovery` 分支。

## GREEN 结果

命令：`./scripts/unit-tests.sh`，连续两次运行结果一致：

```text
Executed 149 tests, with 0 failures (0 unexpected)
```

- T-021 的 7 个 RED 测试（15 个断言失败）全部转绿。
- 既有 121 个测试保持绿色，其中 `AXAuthoritativeWriteRecoveryTests` 的三项
  恢复相关用例（静默 setter 失败、成功替换后恢复、恢复前结果变化）在新算法下
  仍通过——它们对应 R1 路径，语义未变。

### RED→GREEN 对照

- `testWholeFieldRecoveryRejectsUnsettableValueAttribute` → W2 返回
  `recoveryTargetChanged`，且 `settableQueriedModes == [.wholeField]`。
- `testSelectedRecoveryR2MissingRangeCapabilityEntersFallback` → `.unsupportedTarget`
  归入 R2 情形 2，fallback 执行一次 whole-field setter。
- `testSelectedRecoveryR3ErrorsFailClosedWithoutFallback` → 五类安全性错误原样
  返回，setter 计数为 0。
- `testSelectedRecoveryRejectsNonZeroLengthRangeMismatch` /
  `testSelectedRecoveryRejectsCaretOutsideResultRange` → C2 两类排除项零 setter
  拒绝。
- `testUnsettableSelectedAttributeDoesNotBlockR2Fallback` → settable 路径化后
  fallback 不再被阻断。
- `testFallbackPrecondition1RejectsUnsettableValueAttribute` → 门禁 1 返回
  `recoveryTargetChanged`。

## 其他门禁

- `./scripts/build.sh` → `BUILD SUCCEEDED`
- `./scripts/project-structure-check.sh` → passed
- `./scripts/sdd-check.sh` → passed
- `./scripts/secret-scan.sh` → 无命中
- `git diff --check` → 无输出

## 未闭合项（如实记录）

- 本任务只闭合合成测试层面的算法正确性。C3、C4、C5 仍为未达成，需 P6 的
  T-040 至 T-046 完成：T-040 自动化下游复核，T-041／T-042 真实环境的
  selected／whole-field 恢复复核，T-043 状态与访问计数，T-044 UTF-16 夹具，
  T-045 定向隐私审计，T-046 汇总。
- R2 无法区分"应用塌陷"与"用户把光标移入结果范围"的残余行为，以及 AX
  whole-field setter 的 TOCTOU 残余风险，均按 Plan 保留并将在 P6 新证据中
  继续披露。
- 原 Implementation REVIEW 的 Finding 1、2、4、5、6 尚未处理。

## 结论

T-022 已按批准算法完成最小实现：149 tests、0 failures，连续两次一致；
build、project-structure、sdd-check、secret-scan、`git diff --check` 全部通过。
