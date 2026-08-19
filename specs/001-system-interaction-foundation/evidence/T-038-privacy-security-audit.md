# T-038 隐私与安全审计证据

## 任务边界

- 任务：T-038 [Audit] 执行隐私与安全审计。
- 依赖：T-035、T-037。
- 覆盖：FR-003、FR-013、NFR-006、AC-004、AC-008、AC-014。
- 要求：检查文件、配置、日志、崩溃自定义字段、截图、测试结果和遥测均无
  真实内容；复核安全输入零读取/转换/展示/复制/写入，正常路径剪贴板访问
  次数和会话结束后的敏感引用释放。

## 审计环境

- 审计对象：代码状态 `7a982d4`（分支 `feature/001-system-interaction-foundation`）
- 审计方式：仓库静态检查 + 既有自动化测试复核
- 审计日期：2026-07-28

## 一、仓库文件与配置无真实内容

- 仓库跟踪文件中唯一的文字夹具标记为 `SYNTHETIC-001`；
  证据目录 38 个文件中出现该标记 27 处，其余中文均为面板文案引用与说明。
- 命中疑似敏感文件名模式的跟踪文件仅两个，均无凭据：
  - `.ci/xcode.env`：只含 5 个构建变量名（工程、scheme、三个 target 名）。
  - `scripts/secret-scan.sh`：扫描脚本自身。
- `.gitignore` 覆盖本地 worktree（`.worktrees/`）、`DerivedData/`、
  `xcuserdata/`、`.env*`、`*.pem`、`*.p12`、`*.mobileprovision`、
  `build/`、`.cache/`。`git ls-files | grep worktrees` 为 0，
  确认 Agent 工作树未被提交。
- 仓库内唯一出现本机绝对路径的位置是 `AGENTS.md:156` 的 Fable 唤醒消息
  模板，属于协作协议正文，不含内容或凭据。
- 无截图文件被提交（证据均为文本）。测试结果（`.xcresult`）位于
  `DerivedData/`，已被忽略，不进入仓库。

## 二、日志、崩溃字段与遥测

- 全仓库生产代码中日志调用只有一处：
  `Sources/SystemInteractionFoundation/SystemInteractionAdapters.swift:246`
  的 `OSLogPresentationLatencyRecorder`。输出格式为
  `presentation-latency-ms=<数值>`，只含一个毫秒浮点数，不含任何被捕获
  的文字。
- 无 `print`、`NSLog`、`debugPrint`、`dump` 调用。
- 无崩溃上报、无自定义崩溃字段、无遥测或分析代码：
  对 `crash`、`telemetry`、`analytics`、`uncaughtException`、
  `NSSetUncaught` 的检索结果为空。
- 无网络能力：对 `URLSession`、`URLRequest`、`Network` 的检索结果为空，
  与 001 "不接入网络"的范围约束一致。

## 三、敏感值不可持久化（FR-013、AC-014）

- `SourceText` 与 `TransformedText` 仅声明 `Equatable, Sendable`
  （`DomainContracts.swift:3`、`:11`），未声明 `Codable`/`Encodable`/
  `Decodable`；全仓库无这三个协议的任何声明，敏感文字无法被序列化落盘。
- `DomainFailure`（`DomainContracts.swift:33-45`）的 13 个 case 全部为
  无关联值的枚举成员（`hotKeyConflict`、`secureInputActive`、
  `unsupportedTarget`、`writeFailed` 等），错误类型在结构上不可能携带
  用户内容。
- 界面文案由 `PreviewPresentationMapper` 的固定字符串生成，不拼接原始
  错误码或内容（由 T-027 测试断言）。

## 四、安全输入零处理（FR-003、AC-004）

- 门禁位置：`AppLifecycleController.beginDirectInteraction()` 的
  `guard secureInput.performIfContentReadAllowed({}) == .allowed`
  （`AppLifecycleController.swift:185`），位于会话创建、权限流程与任何
  捕获调用之前。安全输入开启时直接 `present(.secureInput)` 返回。
- `SecureInputGuard.performIfContentReadAllowed`
  （`SystemInteractionAdapters.swift:202-210`）在 `isSecureEventInputEnabled()`
  为真时立即返回 `.blocked`，闭包不被执行，因此不发生读取、不构造
  `SourceText`、不调用转换器、不呈现内容、不访问剪贴板、不写入目标。
- 该行为由 T-005、T-011、T-019 的自动化测试断言（安全输入路径内容读取
  计数为 0、不创建任何内容值），并由 T-007 在真实 Secure Event Input
  环境探针确认回调到达后于任何内容读取前返回 `blocked`，
  T-035 第 9 项在真实密码框中确认面板显示正确说明。
- 门禁之前唯一执行的语句是单调时钟采样（T-036 仪器），只产生时间戳，
  不接触内容。

## 五、剪贴板访问边界（NFR-006、AC-008）

- 生产代码中的剪贴板入口共三个，全部以 `AfterExplicitAction` 命名并只由
  用户点击驱动：
  - `ClipboardPolicy.readFromClipboardAfterExplicitAction`
    （`ClipboardPolicy.swift:31`）——仅"使用剪贴板"按钮触发
    （`AppLifecycleController.swift:206-207`）。
  - `ClipboardPolicy.copyResultAfterExplicitAction`
    （`ClipboardPolicy.swift:35`）——仅"复制结果"按钮触发
    （`AppLifecycleController.swift:203`）。
  - `copyOriginal` 路径（`InteractionSessionCoordinator.swift:190-198`）
    ——仅"复制原文"按钮触发（`AppLifecycleController.swift:209-210`）。
- 无后台轮询、无自动读取、无以模拟粘贴替代 AX 写入的路径。
- 写入统一使用 `PasteboardWritePrivacy.currentHostOnly`，不参与跨设备
  通用剪贴板同步。
- 精确访问计数由 T-017 spy 测试断言：取消、普通预览、安全输入路径读写
  次数均为 0；三个显式动作各发生一次预期访问。T-034 的 VS Code 后备
  路径在真实环境复核了"读取失败时不访问剪贴板"。

## 六、会话结束后的敏感引用释放（FR-013）

- `AppLifecycleController.finishSession()`（`:428` 起）在会话结束时
  将 `lastTransformed` 与 `pendingAnchorRect` 置 `nil`，
  调用 `textTarget.endSession()`、`targetMonitor.stopMonitoring()`
  与 `dismissPresentation()`，并清空 `activeSessionID`／`activeTargetHandle`
  （`:436`），随后在 `cleanupWork` 中 `await gateway.deactivateMonitoring`
  与 `gateway.releaseTarget(targetHandle)`（`:439`）释放 actor 内持有的
  原始 AX 引用。
- 原始 AX 引用只存在于 `AccessibilityGateway` actor 内部，领域层仅持有
  不可持久化的 `TargetHandle`，由 T-020 设计约束与 T-014 会话清理测试
  覆盖；T-030 的端到端测试断言会话结束后过期 monitor 回调被忽略且不再
  呈现状态。

## 结论

六个审计维度全部通过：仓库文件、配置、日志、崩溃字段、测试产物与遥测均
不含真实用户内容或凭据；敏感值在类型层面不可序列化，错误类型不可能携带
内容；安全输入在任何内容读取前 fail-closed，零读取／转换／展示／复制／
写入；剪贴板仅有三个用户显式驱动的入口且均为 `currentHostOnly`；会话
结束时敏感引用与 AX 句柄均被释放。FR-003、FR-013、NFR-006、AC-004、
AC-008、AC-014 达成，未发现需要返回上游 Gate 的问题。
