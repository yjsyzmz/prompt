---
feature: "001-system-interaction-foundation"
stage: research
status: approved
spec_version: "501e34584e3ca06a922038d153a96e3b93aa65ab"
researched_on: "2026-07-20"
---

# 系统交互基础——技术研究

## 研究范围与方法

本研究只为已通过 Spec Gate 的 `001-system-interaction-foundation` 选择可实施的 macOS 技术路线。研究不改变产品范围，不包含 AI、提示词库、账号、同步、持久化、最终视觉系统、永久快捷键或公开分发实现。

证据优先级如下：

1. Apple Developer Documentation 与当前 Apple SDK 公开头文件；
2. 仓库宪法、已批准产品设计与 Spec；
3. 可通过后续本地能力探针验证的假设。

当前开发机只有 Command Line Tools，`xcodebuild` 无法使用；完整 Xcode 是进入 Tasks/Implementation 前的环境前提，不阻碍本轮 Plan Gate。

## RQ-001 — 原生应用采用哪种界面与系统集成架构

- **Context：** 本功能需要稳定控制全局快捷键、跨应用 Accessibility、焦点、窗口层级和多显示器位置，同时仍需快速迭代悬浮预览内容。
- **Options considered：**
  1. AppKit 管理应用生命周期与系统交互，SwiftUI 只承载预览内容；
  2. 全部使用 AppKit；
  3. Electron/Tauri 工作台加 Swift 原生桥接或 helper。
- **Evidence gathered：** 宪法 Article IV 要求首版优先原生 macOS 可靠性；Apple 将 `NSPanel` 定义为辅助窗口并提供浮动、按需成为 key window 和非激活 panel 能力；SwiftUI 可以通过 `NSHostingView` 嵌入 AppKit。参考：[NSPanel](https://developer.apple.com/documentation/appkit/nspanel)、[nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)。
- **Decision：** 采用 Swift 6、AppKit 核心加 SwiftUI 内容视图。AppKit 负责 `NSApplication` 生命周期、`NSPanel`、快捷键、Accessibility、屏幕坐标与焦点；SwiftUI 只负责状态驱动的预览内容和按钮。首版不引入第三方运行时依赖。
- **Consequences：** 获得最直接的系统控制与可测试的业务边界，但团队需要维护少量 AppKit/SwiftUI 桥接。跨平台复用不作为 001 的目标。
- **Follow-up：** Tasks Gate 需要把系统适配层与纯状态逻辑分开，并让生产代码晚于对应测试任务。

## RQ-002 — 跨应用文字读取和写入使用什么 API

- **Context：** TextEdit、Chrome/ChatGPT 与 VS Code 来自不同 UI 技术栈，必须通过系统级可访问性接口进行能力探测，且不能模拟清空后粘贴等高风险操作。
- **Options considered：**
  1. `AXUIElement` 读取并设置文本相关属性；
  2. 合成键盘事件执行复制、全选和粘贴；
  3. 针对每个应用实现 AppleScript、浏览器扩展或专用插件。
- **Evidence gathered：** Apple 的 `AXUIElement` 客户端 API 可以查询元素、判断属性是否可设置、读取参数化属性并设置属性；文本元素提供 `kAXSelectedTextAttribute`、`kAXSelectedTextRangeAttribute`、`kAXValueAttribute`，`kAXBoundsForRangeParameterizedAttribute` 可以返回文字范围的屏幕边界。API 还定义 `kAXErrorInvalidUIElement`、`kAXErrorCannotComplete` 与 `kAXErrorAPIDisabled` 等失败。参考：[AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement)、[Attributes](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/attributes)、[Parameterized Attributes](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/parameterized_attributes)。
- **Decision：** 直接能力只使用 `AXUIElement`。非空选区读取/写入 `kAXSelectedTextAttribute`；没有非空选区时读取/写入 `kAXValueAttribute`。每次写入前用保存的目标句柄、PID、窗口、范围与当前文字重新验证，并先调用 `AXUIElementIsAttributeSettable`。不使用合成按键作为直接写入后备。
- **Consequences：** 行为符合“只修改原目标”的安全要求，但 Electron 或自绘控件可能不完整实现 AX 属性；这些目标必须降级到显式剪贴板流程。
- **Follow-up：** 在 TextEdit、Chrome/ChatGPT 和 VS Code 上分别记录实际属性支持、错误和结果；不能从单一应用外推普遍兼容性。

## RQ-003 — 如何处理 Accessibility 权限与 App Sandbox

- **Context：** 跨应用 AX 客户端需要用户授权；分发模式不能与核心能力冲突。
- **Options considered：**
  1. 关闭 App Sandbox，使用 Accessibility 授权；
  2. 保持 App Sandbox 并寻找 entitlement；
  3. 把 Accessibility 放入独立 helper。
- **Evidence gathered：** `AXIsProcessTrustedWithOptions` 返回进程是否为可信 Accessibility 客户端，并可用 `kAXTrustedCheckOptionPrompt` 异步提示用户。Apple 的 App Sandbox 文档明确列出“assistive apps 使用 Accessibility API”为 sandbox 不兼容活动；Mac App Store 分发要求 App Sandbox。Apple 同时支持 Mac App 在商店外使用 Developer ID、Hardened Runtime 与 notarization。参考：[AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)、[App Sandbox 限制](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)、[Preparing for distribution](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)、[Distribution](https://developer.apple.com/documentation/technologyoverviews/distribution)。
- **Decision：** 001 的应用 target 关闭 App Sandbox，不设计绕过方案；保留 Hardened Runtime 配置能力。开发阶段使用本地签名运行，正式公开分发留给后续独立范围，并采用 Developer ID 与 notarization，而不是 Mac App Store。Apple 没有在上述 API 文档中承诺 Accessibility 设置页深链长期稳定，因此“打开设置”由独立适配器实现：优先尝试当前 macOS 14+ 的 Accessibility 设置 URL，失败时打开通用 Privacy & Security 并展示人工导航说明；系统 prompt 仍只通过官方 `AXIsProcessTrustedWithOptions` 触发。
- **Consequences：** 核心能力可行，但未来公开分发需要 Apple Developer Program。应用必须把权限用途、打开设置和重新检测做成显式用户流程；不能声称安装即获得授权。
- **Follow-up：** 进入实现前安装完整 Xcode；公开发布前单独规划签名、公证、下载和更新体验。

## RQ-004 — 全局快捷键与安全输入如何实现

- **Context：** 快捷键必须在应用运行时全局可用、可报告冲突；密码框或系统 Secure Event Input 开启时必须在读取内容前拒绝。
- **Options considered：**
  1. 使用系统 SDK 的 `RegisterEventHotKey` 和 `IsSecureEventInputEnabled`；
  2. 使用 `CGEventTap` 监控按键；
  3. 引入第三方快捷键库。
- **Evidence gathered：** 当前本机 macOS SDK 公开头文件 `CarbonEvents.h` 仍声明 64 位可用的 `RegisterEventHotKey`、exclusive 注册与 `eventHotKeyExistsErr`；`CarbonEventsCore.h` 声明 `IsSecureEventInputEnabled`，并说明其返回任意进程是否启用了 Secure Event Input；`AXRoleConstants.h` 声明 `kAXSecureTextFieldSubrole`。这些符号存在于当前 SDK 的 `Carbon.tbd`/`HIToolbox.tbd`。使用 `CGEventTap` 会增加按键监控权限和事件处理风险。
- **Decision：** 在 `@MainActor` 上用一个很薄的 HIToolbox 适配器注册 exclusive 临时快捷键，保存 `EventHotKeyRef` 并在停用时注销。注册错误映射为可理解的冲突状态。读取前先检查全局 `IsSecureEventInputEnabled`，再检查焦点元素 `kAXSecureTextFieldSubrole`；任一为真都拒绝，不读取任何文本。首版不引入快捷键依赖。
- **Consequences：** 方案依赖一个历史较久但仍公开存在的系统接口，需要封装以便未来替换；全局 Secure Event Input 可能带来安全优先的误拒绝。操作系统也可能在回调到达本应用前抑制第三方 global hot key；这一点不能仅靠头文件证明。
- **Follow-up：** 实现阶段首先构建快捷键注册与 Secure Event Input 能力探针。若目标 SDK 正式标记接口不可用，或安全输入使快捷键完全无法产生任何可见状态，必须返回 Plan/Spec Gate 记录平台边界，不能静默换成事件监听或宣称 AC-004 已满足。

## RQ-005 — 如何在不错误写入的前提下保存和重新验证目标

- **Context：** 用户与悬浮窗交互后，原应用、窗口、元素、选区或内容都可能变化；自身 panel 交互又不能被误判为外部切换。
- **Options considered：**
  1. 只保存文字并在确认时写回当前焦点；
  2. 保存 AX 引用和目标指纹，在写入前重新查询；
  3. 捕获后锁定或持续控制目标应用。
- **Evidence gathered：** `AXUIElement` 引用可以比较并查询所属 PID；`AXObserver` 可接收 Accessibility 通知；`NSWorkspace` 提供应用激活变化。AX 错误明确包含元素失效和目标应用无法及时响应。
- **Decision：** `AccessibilityGateway` 内部保存不跨 actor 暴露的 AX 应用、窗口、元素引用；业务层只持有随机 `TargetHandle` 和不可变 `TargetSnapshot`。指纹包含 PID、窗口/元素身份、捕获模式、范围和原文。`NSWorkspace` 与 `AXObserver` 负责提前使按钮失效；每次确认/恢复仍执行权威重新验证。自身 non-activating panel 事件不算外部切换，任何其他应用、窗口或元素变化都使直接写入失效。
- **Consequences：** 不能依赖通知作为唯一安全保证；观察器缺失时按钮可能直到确认时才更新，但最终写入仍被阻止。所有 AX 调用需要有限超时和领域错误映射。
- **Follow-up：** 使用合成宿主验证同应用换输入框、切窗口、切应用、内容变化和 AX 元素失效。

## RQ-006 — 悬浮预览如何保持目标焦点并安全定位

- **Context：** 预览需要出现在输入位置附近、支持按钮、跨 Space/全屏显示，又不能在出现时抢走原输入目标。
- **Options considered：**
  1. `NSPanel` + `.nonactivatingPanel` + SwiftUI `NSHostingView`；
  2. 普通 `NSWindow` 或 SwiftUI `WindowGroup`；
  3. `NSPopover` 锚定目标。
- **Evidence gathered：** Apple 将 `.nonactivatingPanel` 定义为不会激活所属应用的 panel；`NSPanel` 提供浮动和按需成为 key window 的行为。`kAXBoundsForRangeParameterizedAttribute` 返回文字范围的屏幕像素矩形。参考：[nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)、[isFloatingPanel](https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel)、[bounds for range](https://developer.apple.com/documentation/applicationservices/carbon_accessibility/parameterized_attributes)。
- **Decision：** 使用 `NSPanel`，配置 `.nonactivatingPanel`、floating level、`hidesOnDeactivate = false`、`becomesKeyOnlyIfNeeded = true`、`.canJoinAllSpaces` 与 `.fullScreenAuxiliary`。内容由 `NSHostingView` 承载。位置按范围边界、元素边界、窗口、活跃显示器逐级降级，并在所选屏幕 frame/visibleFrame 内留安全边距夹紧。AX 顶部原点坐标与 AppKit 底部原点坐标只由 `ScreenGeometryConverter` 转换。
- **Consequences：** panel 控制保持原生且可覆盖全屏环境，但多显示器坐标转换必须单独测试。最终视觉尺寸和样式仍不在 001 决策范围内。
- **Follow-up：** 对单/多显示器、负坐标布局、屏幕边缘、全屏与非默认缩放建立纯几何测试及人工证据。

## RQ-007 — 剪贴板后备怎样满足显式操作与隐私要求

- **Context：** 权限缺失或 AX 不支持时必须有后备路径，但应用不得自动检查或修改剪贴板。
- **Options considered：**
  1. 用户点击后单次读写 `NSPasteboard.general`；
  2. 后台观察 `changeCount` 并自动读取；
  3. 模拟 Command-C/Command-V。
- **Evidence gathered：** `NSPasteboard` 是应用访问系统 pasteboard server 的唯一接口；general pasteboard 默认参与 Universal Clipboard，`prepareForNewContents(with: .currentHostOnly)` 可以把新内容限制在当前设备。参考：[NSPasteboard](https://developer.apple.com/documentation/appkit/nspasteboard)、[currentHostOnly](https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions/currenthostonly)。
- **Decision：** 只在“使用剪贴板内容”“复制结果”“复制原文”按钮处理过程中访问 general pasteboard。应用写入前调用 `.currentHostOnly`，只写 `.string`。不观察 `changeCount`，不读取预览元数据，不模拟复制/粘贴。剪贴板输入产生只读后备会话，直接替换永远不可用。
- **Consequences：** 符合最小访问与本机隐私原则，但应用写入的结果不会通过 Universal Clipboard 自动同步到其他 Apple 设备。
- **Follow-up：** 单元测试精确断言每个用户操作的剪贴板读写次数；人工测试未来系统可能出现的 pasteboard 隐私提示。

## RQ-008 — 最低系统、工具链与处理并发的基线是什么

- **Context：** 需要控制测试矩阵并使用现代 Swift 并发隔离，同时覆盖足够多的真实用户。
- **Options considered：** macOS 13、14 或只支持当前最新版；Swift 5 language mode 或 Swift 6 language mode。
- **Evidence gathered：** Apple 当前稳定 Xcode 仍支持把 macOS 12 及以后作为 deployment target，所需 AX/AppKit/HIToolbox API 远早于 macOS 14 可用。参考：[Xcode Support](https://developer.apple.com/support/xcode/)。
- **Decision：** deployment target 为 macOS 14.0，同时构建 `arm64` 与 `x86_64`。使用最新稳定 Xcode、Swift 6 language mode。AppKit、快捷键和 panel 位于 `@MainActor`；`AccessibilityGateway` 作为 actor 串行拥有原始 AX 引用并只返回值类型，避免并发写入和不可控共享。
- **Consequences：** 放弃更旧系统以缩小兼容矩阵；Swift 6 会更早暴露并发隔离问题。开发机必须安装完整 Xcode，CI 需要使用支持 deployment target 14 的稳定 runner。
- **Follow-up：** Tasks Gate 前记录实际 Xcode/Swift 版本，并在首次工程提交中锁定 deployment target 和 language mode。

## RQ-009 — 哪些验证可以自动化，哪些必须形成手工兼容性证据

- **Context：** GitHub CI 无法可靠授予跨应用 Accessibility/TCC 权限，也无法代表真实的 Chrome、VS Code、多显示器与全屏环境。
- **Options considered：**
  1. 全部依赖 UI 自动化；
  2. 只做人工测试；
  3. 纯逻辑/合成宿主自动化，加真实应用人工矩阵。
- **Evidence gathered：** 宪法 Article V 要求可自动化行为提供测试，无法自动化的系统交互必须记录人工兼容性结果；Spec NFR-001 至 NFR-006 已规定性能、零修改、应用和显示环境证据。
- **Decision：** CI 运行纯单元测试和无需 TCC 的构建检查；本地合成宿主验证 AX 文本控件；真实 TextEdit、Chrome/ChatGPT、VS Code、权限、安全输入、显示和 Undo 使用结构化人工记录。长文本初始基准为 10,000 个字符，只声明为已验证范围。
- **Consequences：** 自动化不能单独证明系统兼容性；Implementation Gate 必须同时提交机器可重复检查和人工结果。测试记录只含环境、合成样本标签、耗时与结果，不含用户内容。
- **Follow-up：** Tasks Gate 为每个 FR/NFR/AC 指定自动化或人工证据，不允许用“以后测试”替代任务。

## 研究结论

建议的 Plan 基线是：原生、无第三方运行时依赖、AppKit 系统核心加 SwiftUI 内容；macOS 14+；关闭 App Sandbox；AXUIElement 直接能力加显式本机剪贴板后备；单一内存会话与写入前强制重新验证；自动化逻辑测试、合成 AX 宿主和真实应用人工矩阵并存。

没有需要扩大产品范围或修改已批准 Spec 的研究结论。主要外部前提是安装完整 Xcode；主要残余风险是第三方应用 AX 支持差异、Secure Event Input 对快捷键投递的实际影响、System Settings 深链稳定性、non-activating panel 在第三方全屏 Space 中的表现、历史 HIToolbox 快捷键接口的长期演进，以及未来公开分发需要 Developer ID。
