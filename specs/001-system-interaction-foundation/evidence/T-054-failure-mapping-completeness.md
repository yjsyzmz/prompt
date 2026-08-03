# T-054 替换失败按实际原因分流，并为不可达取值提供证明

## 任务边界

- 来源：Solar 对 `5070607` 的第三次 Implementation Gate REVIEW，Finding 4（MUST）；
  分组边界与追加约束由后续两轮 Tasks Gate REVIEW 逐项固化。
- 覆盖：FR-008、NFR-007、AC-008。
- 执行日期：2026-08-03。依赖顺序上紧随 T-053，未并行其他任务。

## 违规事实

`AppLifecycleController.replacementRejectionStatus(for:)` 此前只显式映射四类失败，
其余全部落入 `default → .staleTarget`。后果是把「内容变了」「目标暂时读不到」
「未知失败」都说成「原输入位置已经变化」——原因不同、用户该做的事也不同，却给同
一句话。而且 `default` 会静默吞掉将来新增的 `DomainFailure`。

## 实施

### 映射搬家并变为全量

映射从 `AppLifecycleController` 的私有方法搬到
`PreviewPresentationMapper.status(forReplacementRejection:)`，`switch` **不带
`default`**；`DomainFailure` 增加 `CaseIterable`。两者合起来的效果是：新增一个
`DomainFailure` 会同时导致编译失败与映射表测试失败，无法被悄悄吞掉。
`AppLifecycleController` 保留同名方法但只做转发，因此全仓只有一份定义。

### 裁决的七组归属

| DomainFailure | PreviewStatus |
| --- | --- |
| `invalidTarget`、`recoveryTargetChanged` | `staleTarget` |
| `sourceChanged` | `sourceOrSelectionChanged`（新增） |
| `secureInputActive` | `secureInput` |
| `accessibilityPermissionRequired` | `permissionRequired` |
| `attributeNotSettable`、`unsupportedTarget` | `targetNotWritable` |
| `axTimedOut`、`axCannotComplete` | `targetTemporarilyUnavailable`（新增） |
| `writeFailed` | `writeFailed` |
| `hotKeyConflict`、`emptySource`、`pasteboardReadFailed`、`pasteboardWriteFailed`、`panelPlacementFallback`、`unknown` | `unspecifiedFailure`（新增） |

新增三个状态的理由与文案：

- `sourceOrSelectionChanged`——「原文或选区已经变化，未做任何修改，请重新选取。」
  与 `staleTarget` 的「原输入位置已经变化」区分开：一个是内容变了，一个是位置没了，
  用户的下一步不同。
- `targetTemporarilyUnavailable`——「目标暂时无法访问，未做任何修改，可以重试。」
  同时提供重试、复制结果、关闭三个动作，因为重试在这一类里是有意义的。
- `unspecifiedFailure`——「本次操作未能完成，未做任何修改，结果仍可复制。」
  fail-closed：既不声称目标已变化，也不声称发生过写入，仍保留复制结果这一出口。

**只有 `.writeFailed` 可以呈现为写入失败**，由一条遍历全部取值的测试守住。

## 失败优先证据（RED）

第一轮 RED 由编译器逐项点名缺失的生产 API：

```text
type 'PreviewStatus' has no member 'sourceOrSelectionChanged'
type 'PreviewStatus' has no member 'targetTemporarilyUnavailable'
type 'PreviewStatus' has no member 'unspecifiedFailure'
type 'DomainFailure' has no member 'allCases'
```

补齐 API 后第二轮跑出 **218 tests / 7 failures**，全部是旧分组的实测证据：

- `PreviewStateActionTests` 的文案与按钮两张穷举矩阵各缺三项（6 条失败）——这两张
  矩阵的存在本身就是在强制「新增状态必须显式登记」。
- `testExternalContentEditBeforeWriteIsNotPresentedAsWriteFailure`（我在 MUST 2
  阶段写的）断言 B1 → `staleTarget`。**该断言编码的正是被本次裁决否定的旧分组**，
  已更正为 `sourceOrSelectionChanged` 并写明两者下一步的差别。

## 真实路由与 setter 次数

`testRealRoutingForEveryReachableFailureClass` 用十二条场景贯穿
`AccessibilityGateway → InteractionSessionCoordinator → PreviewPresentationMapper`，
每条都从合成宿主注入真实失败、经协调器确认、再读面板实际文案，并断言
`setterAttemptCount == 0`：

| 场景 | 注入 | 期望状态 |
| --- | --- | --- |
| A1 应用退出 | `terminateApplication()` | `staleTarget` |
| A2 切到其他应用 | `moveFocusToDifferentApplication()` | `staleTarget` |
| A3 窗口变化 | `switchWindow()` | `staleTarget` |
| A4 元素变化 | `invalidateElement()` | `staleTarget` |
| B1 内容变化 | `editSegmentExternally(_:)` | `sourceOrSelectionChanged` |
| 安全输入 | `activateGlobalSecureInput()` | `secureInput` |
| 元素转只读 | `makeReadOnly()` | `targetNotWritable` |
| 属性不可写 | `blockReplacementAttribute()` | `targetNotWritable` |
| AX 超时 | `failNextContentReads(1, with: .axTimedOut)` | `targetTemporarilyUnavailable` |
| AX 无法完成 | `failNextContentReads(1, with: .axCannotComplete)` | `targetTemporarilyUnavailable` |
| 权限缺失 | `failNextContentReads(1, with: .accessibilityPermissionRequired)` | `permissionRequired` |
| 未知失败 | `failNextContentReads(1, with: .unknown)` | `unspecifiedFailure` |

`testWriteFailureIsTheOnlyClassThatReachesTheSetter` 反向断言
`setterAttemptCount > 0`。这样「未发生写入」在每一类上都是**实测**而非推断。

为让后四类在替换路径上可达，合成宿主的 `failNextContentReads` 增加
`with failure:` 参数（此前固定产出 `axCannotComplete`）。

## 不可达取值的证明

`testFailuresJudgedUnreachableAreNeverProducedByTheReplacementPath` 用十四种注入
（含空注入与静默丢弃写入）各跑一次 `replaceAfterAuthoritativeValidation`，断言
`emptySource`、`pasteboardReadFailed`、`pasteboardWriteFailed`、
`panelPlacementFallback`、`hotKeyConflict` 从不出现。

这条测试的边界要如实说明：它证明的是「在这十四种可注入条件下不出现」，不是数学
意义上的不可达。真正的保障来自两处叠加——这五个取值在替换路径的代码里没有产生
点，且它们仍被映射到 fail-closed 的 `unspecifiedFailure`，即便将来意外出现也不会
误称目标变化或已写入。

## 结果（GREEN）

**218 tests / 0 failures**，`TEST SUCCEEDED`。
