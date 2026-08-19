# T-021 恢复算法失败优先测试（RED）

## 任务边界

- 任务：T-021 [Test] 编写重新验证、写入与恢复测试（按重开后的 Plan 算法重写）。
- Plan 基线：`0c9883f8385c731b0cc084d22519224eada926ea`（重开后的 Plan Gate
  第三版修订，Solar `PASS`）。
- Tasks 基线：`a8d032737659b0f347170e67a3b7c4f749cd3cfb`（重开后的 Tasks Gate，
  Solar `PASS`）。
- 本轮只编写测试，**不实现 T-022**，不处理原 Implementation REVIEW 的
  Finding 1、2、4、5、6。
- 原 `evidence/T-021-authoritative-write-recovery-red.md` 对应作废前的算法，
  不作为本任务证据；本文件为重写后的 T-021 证据。

## 测试文件

- 新增：`Tests/SystemInteractionFoundationTests/AXRecoveryAlgorithmTests.swift`
  （28 个测试，已登记进 `SystemInteractionFoundation.xcodeproj/project.pbxproj`）
- 复用：`Tests/SystemInteractionFoundationTests/AXAuthoritativeWriteRecoveryTests.swift`
  承载第 1 组（共享前置检查 A1–A4 逐项失败）与第 3 组（replacement B1–B2）的
  既有断言；这两组在批准算法中语义未变，故不重复编写。新文件另外补充
  "A1–A4 任一失败时 fallback 也不得执行"的交叉断言。

## 十组要求与测试映射

- **第 1 组 A1–A4 逐项失败**：`AXAuthoritativeWriteRecoveryTests` 的
  `testStoppedTargetApplicationFailsClosedBeforeSetter`、
  `testExternalApplicationChangeFailsClosedBeforeSetter` 等既有用例；
  交叉断言见新文件 `testSharedPrecheckFailureAlsoBlocksFallback`。
- **第 2 组 路径化 settable 检查**：
  `testWholeFieldRecoveryRejectsUnsettableValueAttribute`（断言
  `settableQueriedModes == [.wholeField]`）、
  `testSelectedRecoveryR1UsesSelectedSetterOnly`（断言查询的是
  `.selectedText`）、
  `testUnsettableSelectedAttributeDoesNotBlockR2Fallback`。
- **第 3 组 replacement B1–B2**：`AXAuthoritativeWriteRecoveryTests` 的
  `testSelectedReplacementRunsAllAuthoritativeChecksBeforeOneSetter`、
  `testWholeFieldReplacementUsesOnlyWholeFieldSetter` 等既有用例。
- **第 4 组 recovery 入口分支**：
  `testClipboardInputRecoveryIsRejectedWithoutAnySetter`。
- **第 5 组 whole-field recovery W1–W4**：
  `testWholeFieldRecoverySucceedsWithExactlyOneValueSetter`、
  `testWholeFieldRecoveryNeverReadsSelectedRange`（断言
  `selectedRangeReadCount == 0`）、
  `testWholeFieldRecoveryRejectsChangedValueWithoutSetter`、
  `testWholeFieldRecoveryRejectsUnsettableValueAttribute`、
  `testWholeFieldRecoveryRejectsMismatchedReadback`。
- **第 6 组 C1–C4 与 R1／R2／R3**：
  `testSelectedRecoveryR1UsesSelectedSetterOnly`、
  `testSelectedRecoveryR2CollapsedCaretEntersConstrainedFallback`、
  `testSelectedRecoveryR2AcceptsCaretAtEitherBoundary`、
  `testSelectedRecoveryR2MissingRangeCapabilityEntersFallback`、
  `testSelectedRecoveryR3ErrorsFailClosedWithoutFallback`（覆盖
  `invalidTarget`、`axTimedOut`、`axCannotComplete`、
  `accessibilityPermissionRequired`、`secureInputActive` 五类）、
  `testSelectedRecoveryRejectsNonZeroLengthRangeMismatch`、
  `testSelectedRecoveryRejectsCaretOutsideResultRange`。
- **第 7 组 R2 不推断来源**：
  `testSelectedRecoveryR2DoesNotInferCaretProvenance`、
  `testSelectedRecoveryR2WithEditedRangeIsBlockedByPrecondition4`。
- **第 8 组 六项门禁与 setter 计数**：
  `testFallbackPrecondition1RejectsUnsettableValueAttribute`、
  `testFallbackPrecondition2RejectsUnreadableFullValue`、
  `testFallbackPrecondition2UsesFreshlyValidatedBaseValue`（在门禁通过后改写
  目标全文，断言写入值派生自紧邻读取的基值且不含旧值片段）、
  `testFallbackPrecondition3RejectsOutOfBoundsResultRange`、
  `testFallbackPrecondition3RejectsNegativeLocation`、
  `testFallbackPrecondition4RejectsRangeContentMismatch`（使用等长但内容不同的
  文本，确保拦截依据是内容而非长度）、
  `testFallbackPrecondition5KeepsEveryCodeUnitOutsideTheRange`、
  `testFallbackPrecondition6RejectsMismatchedReadback`、
  `testFallbackSetterFailureDoesNotRetryAnotherSetter`。
- **第 9 组 UTF-16 夹具**：
  `testFallbackHandlesEmojiCombiningMarksAndSurrogatePairs`，夹具含 😀 与 𝄞
  （代理对）、`e` + U+0301（组合字符序列），前后缀也含代理对与组合字符。
- **第 10 组 失败后保留原文**：
  `testEveryRecoveryFailureLeavesTargetContentUntouched`，对不可写、全文不可读、
  Secure Input 与 R3 四条失败路径断言目标内容完全未变。

## 夹具修正与 RED 基线勘误（2026-07-28，T-022 期间发现）

本文件初版记录的 RED 为「149 tests、27 failures、12 个测试」。在 T-022 实现
期间发现其中部分失败源于**测试夹具自身的错误**，而非缺失的实现：
`capturedLocation` 被硬编码为 6，与夹具前缀 `SYNTHETIC-001 前缀：` 的 UTF-16
长度不一致，导致 expected result range 落在错误位置，门禁 4 的内容比较必然
失败。该错误已修正为 `capturedLocation = (prefix as NSString).length`。

修正夹具后，对**未修改的旧实现**重新验证 RED（`git stash` 暂存源码改动后
运行）：

```text
Executed 149 tests, with 15 failures (0 unexpected)
```

真实的 RED 覆盖 7 个测试，逐项对应缺失的批准算法：

1. `testWholeFieldRecoveryRejectsUnsettableValueAttribute` — recovery 路径的
   settable 失败必须返回 `recoveryTargetChanged`，旧实现返回
   `attributeNotSettable`。
2. `testSelectedRecoveryR2MissingRangeCapabilityEntersFallback` — range 能力
   缺失时必须进入受约束 fallback，旧实现不会。
3. `testSelectedRecoveryR3ErrorsFailClosedWithoutFallback` — 五类安全性错误
   必须原样呈现，旧实现一律归并为 `recoveryTargetChanged`。
4. `testSelectedRecoveryRejectsNonZeroLengthRangeMismatch` — 非零长度不匹配
   必须零 setter 拒绝。
5. `testSelectedRecoveryRejectsCaretOutsideResultRange` — 结果范围之外的
   插入点必须零 setter 拒绝（旧实现无此排除项）。
6. `testUnsettableSelectedAttributeDoesNotBlockR2Fallback` — settable 检查
   未路径化，旧实现会因 `kAXSelectedTextAttribute` 不可写阻断 fallback。
7. `testFallbackPrecondition1RejectsUnsettableValueAttribute` — fallback 门禁 1
   的失败状态映射。

其余新增测试在旧实现下即已通过（塌陷插入点在部分条件下恰好走到旧的
whole-field 恢复分支、门禁 2／3／4 的越界与内容检查、UTF-16 夹具、失败后
保留原文等），它们作为 T-022 的回归保护保留。

**本次勘误不改变结论**：修正后的测试在旧实现下仍稳定 RED（15 failures，
全部位于新测试文件），失败原因全部指向缺失的批准算法。

## RED 结果（初版记录，含上述夹具错误）

命令：`./scripts/unit-tests.sh`

连续两次运行结果一致：

```text
Executed 149 tests, with 27 failures (0 unexpected)
```

- 测试总数由 121 增至 149（新增 28 个）。
- **全部失败均来自 `AXRecoveryAlgorithmTests.swift`**：过滤该文件后的
  错误行数为 0，既有 121 个测试保持绿色。
- 27 个断言失败对应 12 个尚未实现的行为，逐项指向缺失的 T-022 算法：
  1. `testWholeFieldRecoveryRejectsUnsettableValueAttribute` — 当前返回
     `attributeNotSettable`，批准算法要求 recovery 路径返回
     `recoveryTargetChanged`。
  2. `testSelectedRecoveryR2CollapsedCaretEntersConstrainedFallback`
  3. `testSelectedRecoveryR2AcceptsCaretAtEitherBoundary`
  4. `testSelectedRecoveryR2MissingRangeCapabilityEntersFallback`
  5. `testSelectedRecoveryR2DoesNotInferCaretProvenance`
     —— 2 至 5 项：当前实现虽会把 `requiresWholeFieldRestoration` 置为 true，
     但随后的通用 `validate` 因同一状态直接返回，fallback 从未真正执行
     （与 Plan Gate REVIEW 的 Residual risks 第二条一致）。
  6. `testSelectedRecoveryR3ErrorsFailClosedWithoutFallback` — 当前把所有
     range 读取失败一律归并为 `recoveryTargetChanged`，未按 R2／R3 分类，
     安全性错误未被单独呈现。
  7. `testUnsettableSelectedAttributeDoesNotBlockR2Fallback` — 当前 settable
     检查未路径化，`kAXSelectedTextAttribute` 不可写会阻断 fallback。
  8. `testFallbackPrecondition1RejectsUnsettableValueAttribute`
  9. `testFallbackPrecondition2UsesFreshlyValidatedBaseValue` — 当前未要求
     基值紧邻 setter 获取并校验。
  10. `testFallbackPrecondition5KeepsEveryCodeUnitOutsideTheRange`
  11. `testFallbackPrecondition6RejectsMismatchedReadback`
  12. `testFallbackSetterFailureDoesNotRetryAnotherSetter`

- 已通过的新测试（当前实现恰好符合批准算法的部分）：clipboardInput 拒绝、
  whole-field 成功路径与内容变化拒绝、whole-field 不读 selected range、
  R1 selected setter、C2 两类排除项、门禁 2 全文不可读、门禁 3 越界与负
  location、门禁 4 内容不符、UTF-16 夹具、失败后保留原文。这些用例同样纳入
  T-022 的回归保护。

## 其他门禁

- `./scripts/build.sh` → `BUILD SUCCEEDED`（生产构建保持绿色，本轮未改动源码）
- `./scripts/project-structure-check.sh` → passed
- `./scripts/sdd-check.sh` → passed
- `./scripts/secret-scan.sh` → 无命中
- `git diff --check` → 无输出

## 隐私与夹具约束

- 全部夹具文字以 `SYNTHETIC-001` 标记，无真实用户内容、无类似凭据字符串。
- 测试替身只在内存中持有字符串，不写入磁盘、日志或测试产物。

## 结论

T-021 已按批准算法建立稳定 RED：149 tests、27 failures，连续两次一致，
失败全部集中在新测试文件且逐项指向缺失的 T-022 算法，既有 121 个测试与
生产构建保持绿色。可进入 T-022 实现。
