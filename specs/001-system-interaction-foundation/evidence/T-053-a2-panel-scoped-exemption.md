# T-053 A2 豁免收窄为当前会话预览面板的对象身份

## 任务边界

- 来源：Solar 对 `5070607` 的第三次 Implementation Gate REVIEW，Finding 3（MUST）。
- Tasks Gate 裁决：**以当前会话 `NSPanel` 的 AppKit 对象身份判定面板，不得使用
  整个进程豁免**；并追加即时授权边界——只能在 `MainActor` 上、于确认替换或恢复
  动作发生的那一刻求值，不得缓存为可跨动作／跨 target／跨 session 复用的布尔。
- 覆盖：FR-007、FR-008、NFR-002、AC-005。
- 执行日期：2026-08-03。依赖顺序上紧随 T-052，未并行其他任务。

## 违规事实

`frontmostApplicationIsAcceptable(pid:)` 此前写作：

```swift
return focusedPID == pid
    || focusedPID == ProcessInfo.processInfo.processIdentifier
```

`plan.md:197` 批准的是「除工具自身 **non-activating panel** 外，没有其他应用成为
用户的新外部目标」。实现把豁免范围从「那一个面板」放大到「本进程的任何窗口」，
超出批准范围。

## 一个影响设计的实测事实

预览面板是**全应用单实例、跨会话复用**的：`PreviewPanelController.init()` 创建一次
`KeyableNonactivatingPanel`（`PreviewContentView.swift`），此后所有会话都是同一个
对象反复 `orderFrontRegardless` / `orderOut`，`AppLifecycleController` 以
`private let presenter` 持有它。

因此**单靠对象身份 `===` 不足以满足「会话替换使授权立即失效」**：面板对象在会话
切换后仍是同一个，`===` 恒成立。使授权按会话失效的机制必须是「每次动作重新求值」
而不是「比较对象是否还是同一个」。这一点决定了下面的设计。

## 实施

### 类型

`DomainContracts.swift` 新增：

```swift
struct PanelFocusAuthorization: Sendable, Equatable {
    let currentSessionPanelIsKey: Bool
    static let notOwned = PanelFocusAuthorization(currentSessionPanelIsKey: false)
}

@MainActor
protocol PreviewPanelFocusOwnership: AnyObject {
    func currentSessionPanelIsKey() -> Bool
}
```

`PanelFocusAuthorization` 是**单次动作的值**，不是可存储的授权。

### A2 判定

`AccessibilityGateway` 的 A2 收敛为单一实现，并返回结构化结果，使聚焦应用只被
读取一次：

```swift
private enum FrontmostApplicationCheck {
    case acceptable
    case rejected(focusedApplicationIsSelf: Bool)
}
```

判定顺序：聚焦应用等于目标 → 放行；否则若聚焦应用是本进程**且**当次
`panelFocus.currentSessionPanelIsKey` 为真 → 放行；其余一律拒绝。
`validate` 与 `sharedPrechecks` 共用它，`panelFocus` 由两个入口
`replaceAfterAuthoritativeValidation` 与 `restoreAfterAuthoritativeValidation`
以参数传入，**生产侧刻意不设默认值**——遗漏该参数是编译错误，而不是静默退化。

### 即时求值

`GatewaySessionTextTarget`（`@MainActor`）在**每次** `replace` 与 `restore` 内部
调用 `currentPanelFocusAuthorization()`，该方法现场询问
`PreviewPanelFocusOwnership` 并把结果作为单次参数传给 gateway；结果不写入任何
属性。持有的是**答案的来源**（`weak var panelFocusOwnership`），不是答案。

`PreviewPanelController` 实现该协议：

```swift
func currentSessionPanelIsKey() -> Bool {
    NSApp.keyWindow === panel
}
```

面板被 `orderOut`（关闭）或被本进程其他窗口取代时，`NSApp.keyWindow` 不再是它，
授权自然为假；面板若被重建，比较的是 presenter 当前持有的那一个。

装配处（`AppLifecycleController` 的指定 init）以
`presenter as? any PreviewPanelFocusOwnership` 注入：只有能回答「我的面板此刻是否
为 key」的 presenter 才可能取得豁免，其他（包括全部测试替身）一律无豁免。

## 失败优先证据（RED）

新增五条测试。第一轮 RED 由编译器逐项点名缺失的 API：

```text
cannot find 'PanelFocusAuthorization' in scope
extra argument 'panelFocus' in call
```

行为层面的 RED 由两条测试提供，它们在旧实现下必然通过错误路径：

- `testFocusOnThisProcessWithoutPanelKeyIsRejected`：聚焦应用是本进程但面板不是
  key 时必须停在 `.frontmostApplication`／`.invalidTarget`，且
  `setterAttemptCount == 0`。旧实现会放行并完成写入。
- `testPanelFocusLostBetweenActionsRevokesTheExemption`：替换成功后把焦点移到
  本进程但面板非 key，恢复必须被拒且字段内容不变。旧实现会恢复成功。

即时求值由 `testPanelFocusIsReevaluatedForEveryAction` 覆盖：询问次数必须
0 → 1（确认）→ 2（恢复）。若把答案缓存下来，第二次不会再问，计数停在 1。

另有 `testPanelKeyDoesNotExemptADifferentExternalApplication` 确认面板持有焦点
**不会**帮助另一个外部应用通过 A2。

## 过程中发现并修正的一处实现缺陷

首版实现为了给诊断填 `focusedApplicationIsSelf`，在拒绝分支里第二次调用了
`currentExternalPID()`。`AXAuthoritativeWriteRecoveryTests.testExternalApplicationChangeFailsClosedBeforeSetter`
断言权威调用序列，立刻捕获到多出的一次 `externalApplication` 调用。

这不只是多一次 AX 往返：两次读取可能得到不同答案，诊断记录的「聚焦应用是否为
本进程」就会与判定所依据的那次读取不一致。已改为由
`FrontmostApplicationCheck` 一次读取同时给出判定与该事实。

## 结果（GREEN）

**210 tests / 0 failures**，`TEST SUCCEEDED`。

## 测试便捷入口的说明

既有写入与恢复套件共 55 处直接调用两个 gateway 入口，其验证对象是
A3／A4／B1、R1–R3 与 fallback 六项门禁，前提均为「真人点了面板按钮」。为避免在
55 处重复同一常量，测试目标内提供了带该前提的便捷重载（见
`SyntheticAXHostFixtures.swift` 末尾），**生产 API 仍不提供默认值**。需要验证豁免
边界本身的用例必须显式传参。
