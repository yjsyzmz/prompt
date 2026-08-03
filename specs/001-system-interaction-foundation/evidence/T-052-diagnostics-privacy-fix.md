# T-052 从分级诊断中完全删除用户文字长度字段

## 任务边界

- 来源：Solar 对 `5070607` 的第三次 Implementation Gate REVIEW，Finding 2（MUST）。
- Tasks Gate 裁决（`2ec3cd8` 上 PASS）：**完全删除长度字段，不允许等级化表示。**
- 覆盖：FR-013、NFR-006。
- 执行日期：2026-07-31。本任务是 Tasks PASS 后 P7 的第一项，按依赖顺序执行，
  未并行其他任务。

## 违规事实

- `SystemInteractionAdapters.swift` 把 `expectedLength` 与 `observedLength` 以
  `privacy: .public` 写入 `os_log`。
- `DomainContracts.swift` 的 `ReplacementStageReport` 以这两个长度为字段。

长度是用户文字的可观测元数据。已批准 Plan 未授权以「风险披露」豁免
FR-013／NFR-006 的明文边界，因此这不是可接受的残余风险，而是违规。

## 失败优先证据（RED）

新增两条测试：

- `testStageReportHasNoNumericContentMeasureField`：对实际产生的每条报告做
  `Mirror` 反射，断言没有任何字段的类型名包含 `Int`。
- `testStageReportDescriptionContainsNoDigits`：断言报告的
  `String(describing:)` 不含任何十进制数字。

在删除前运行：**205 tests / 3 failures**，失败信息逐项点名违规字段：

```text
testStageReportHasNoNumericContentMeasureField : XCTAssertFalse failed -
  FR-013: a stage report may not carry a numeric measure of user text;
  found expectedLength of type Int
testStageReportHasNoNumericContentMeasureField : XCTAssertFalse failed -
  FR-013: a stage report may not carry a numeric measure of user text;
  found observedLength of type Optional<Int>
testStageReportDescriptionContainsNoDigits : XCTAssertNil failed:
  "196[utf8]..<197[utf8]" - FR-013: diagnostics must not expose any digit
  derived from content
```

第三条失败的 `196[utf8]..<197[utf8]` 是 `Range` 的描述，指向被判定含数字的位置，
证明断言确实作用在真实输出上而非空集。

## 实施

- `ReplacementStageReport` 删除 `expectedLength` 与 `observedLength`，现存字段
  仅为 `stage`、`failure`，以及 A2 独有的 `focusedApplicationIsSelf`。**该结构
  现在既无 `String` 也无数值成员**，隐私边界由类型保证而非由调用纪律保证。
- `AccessibilityGateway` 删除 `expectedLength`／`writtenLength` 的计算与全部
  传参；`validate` 的 `reject` 辅助函数不再接受 `observedLength`。
- `OSLogReplacementDiagnosticsRecorder` 的输出格式变为：

  ```text
  replacement-stage=<stage> failure=<failure> focus-is-self=<true|false|na>
  ```

- 依赖长度的既有断言同步删除：`testExternalContentEditIsReportedAsTheComparisonStage`
  原先断言 `observedLength == replacement.utf16.count`，该断言已移除，阶段与
  失败分类的断言保留。

注意：`AccessibilityGateway` 中另有一处名为 `expectedLength` 的**局部变量**，
用于计算 `AXTextRange` 的 `length`，属恢复算法的范围数学，与诊断无关，未改动。

## 结果（GREEN）

**205 tests / 0 failures**，`TEST SUCCEEDED`。

## 同步更正的记述

- `evidence/T-037-chatgpt-multiline-followup.md`：删除「两个 UTF-16 长度」的
  描述；日志样例改为删除后的实际格式，并加注说明原样例含长度字段、已被判定违规。
- `evidence/T-047-second-review-must-fixes.md`：删除「两个 UTF-16 长度」。
- `evidence/T-039-acceptance-package.md`：已知限制第 12 项改写为「长度字段已删除」，
  撤回原先以「风险披露」保留长度的表述；结论段同步更正。

## 接受的代价

B1 阶段（内容比较）不再输出 expected 与 observed 的可比信息。内容不一致时诊断
只能报告 `contentComparison` + `sourceChanged`，无法给出量级差异。此前那 40 次
采集中 `expected-utf16=55 observed-utf16=64` 这类信息，今后不再可得。

这一代价是明确接受的：隐私边界优先于定位便利。若后续确需量级信息，须先在 Plan
层取得授权，不得在 Implementation 阶段自行恢复。
