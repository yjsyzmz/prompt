# T-045 定向隐私与安全审计（恢复实现变更）

## 任务边界

- 任务：T-045 [Audit] 定向隐私与安全审计。
- 范围限定：只针对本轮恢复实现变更执行，**不重跑与恢复无关的审计步骤**
  （完整六维审计见 `evidence/T-038-privacy-security-audit.md`）。
- 完成条件：逐项列出被审计的新增／修改代码位置与结论。
- 覆盖：FR-013、NFR-006、AC-014。
- 审计对象代码状态：`e0798bc`
- 审计日期：2026-07-30

## 被审计的变更清单

本轮进入仓库的生产代码变更（Plan 第三版批准的恢复算法 + 五项 Finding 修复）：

1. `b20446d` — 恢复算法重写：`sharedPrechecks`、`restoreWholeField`、
   `restoreSelected`、`restoreViaSelectedSetter`、`restoreViaSelectedRangeFallback`；
   删除 `restoreCollapsedSelection` 与 `recoveryTextFromFullValue`
2. `abe4389` — 预览内容披露（`PreviewViewState.sourceText`／`resultText`）、
   `AXMonitoringTarget` 与生产组合监控装配
3. `e22c7b8` — `releaseStaleCapture`／`clearActiveTargetState`、
   `retainedTargetCount`／`hasActiveMonitoring`、安全输入结束旧会话
4. `e724ba3` — 剪贴板写入结果上报、`clipboardReadFailed`／`clipboardWriteFailed`
   状态、设置回退指引、`retryRegistration`
5. `1ce9d01` — 按钮与内容区域的 `accessibilityLabel`

## 审计项一：内容日志

全仓库生产代码中 `Logger` / `os_log` / `print` / `NSLog` / `debugPrint` /
`dump` 的调用点检索结果**只有一处**：

```text
Sources/SystemInteractionFoundation/SystemInteractionAdapters.swift:246
    private let log = Logger(...)   // OSLogPresentationLatencyRecorder
```

即 T-036 的延迟仪器，输出格式为 `presentation-latency-ms=<数值>`，只含一个
毫秒浮点数。**本轮恢复实现未新增任何日志调用。**

定位 Finding 5 期间曾临时加入 `write-diagnostics` 埋点（记录长度、错误码与
布尔标志，不含内容），采集完成后已全部回退。残留检索：

```text
grep "TEMPORARY DIAGNOSTIC|write-diagnostics|bridge.replace|diagnostics.info"
Sources/ Tests/  → 无命中
```

## 审计项二：持久化与敏感附件

检索 `Codable` / `Encodable` / `Decodable` / `UserDefaults` /
`NSKeyedArchiver` / `.write(to:)` / `FileManager` → **无命中**。

- 新增的 `PreviewViewState.sourceText` 与 `resultText` 是 `String?` 字段，
  只用于视图渲染，不参与序列化（`PreviewViewState` 未声明任何编解码协议）。
- 恢复路径新增的基值（`AccessibilityGateway.swift:535` 的 `baseValue`、
  `:540` 的 `base`）是函数内局部变量，作用域随 fallback 返回即结束，
  不写入任何字段、不落盘。
- 无崩溃自定义字段、无遥测、无网络 API（与 T-038 结论一致）。

## 审计项三：`AXMonitoringTarget` 不携带文本

Finding 2 为把捕获元素交给主 actor 的 observer scheduler 新增了该类型
（`AccessibilityGateway.swift:87-95`）：

```swift
final class AXMonitoringTarget: @unchecked Sendable {
    let element: AXUIElement
    let pid: Int32
}
```

只有元素引用与 pid 两个成员，**不含任何文本**。它是本轮唯一新增的"跨 actor
边界传递"类型，审计确认未借此泄出内容。

## 审计项四：会话结束时的引用释放

恢复相关的内容引用为 `lastSource`（新增，Finding 1 需要展示原文）与
`lastTransformed`，另有 `activeMonitoringTarget`（新增，Finding 2）。
释放点覆盖两条路径：

- `finishSession()`（`AppLifecycleController.swift:456-459`）：
  `activeMonitoringTarget = nil`、`lastSource = nil`、`lastTransformed = nil`，
  随后 `textTarget.endSession()`、`stopMonitoring()`、`dismissPresentation()`，
  并在 `cleanupWork` 中 `deactivateMonitoring` + `releaseTarget`。
- `clearActiveTargetState(for:)`（`:569-571`，Finding 4 新增）：
  竞态路径下同样清空这三个字段，覆盖 `finishSession` 到不了的过期捕获场景。

新增字段没有绕过既有清理路径。`retainedTargetCount()` 与
`hasActiveMonitoring()` 为资源计数查询，只返回整数与布尔，不暴露内容，
其正确性由 `SessionLifecycleRaceTests` 断言。

## 审计项五：剪贴板边界未被扩大

Finding 6 让 `ClipboardPolicy.copyResultAfterExplicitAction` 与
`copyOriginalAfterExplicitAction` 返回写入结果，并让
`InteractionSessionCoordinator.copyOriginal()` 上报成功与否——**只改变返回值，
未新增任何访问点**。

修复过程中曾一度让 `copyOriginal` 同时经过 `clipboard` 与 `coordinator` 两条
路径，导致剪贴板被写两次，已被既有访问计数断言拦下并收敛为单一路径
（见 `e724ba3` 提交说明）。当前三个入口仍与 T-038 记录一致，且均为
`currentHostOnly`。

T-043 的真实环境复核补充了行为侧证据：恢复成功与恢复失败两条路径执行前后
剪贴板指纹完全一致。

## 结论

本轮恢复实现变更未引入内容日志、未引入任何持久化或序列化能力、未新增遥测或
敏感附件；跨 actor 新类型只携带元素引用与 pid；恢复路径的基值为局部变量，
内容引用与监控目标在正常结束与竞态两条路径上均被清空；剪贴板访问点数量与
隐私选项未变。FR-013、NFR-006、AC-014 在本轮变更范围内保持成立。
未发现需要返回上游 Gate 的问题。
