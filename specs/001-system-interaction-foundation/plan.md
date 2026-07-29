---
feature: "001-system-interaction-foundation"
stage: plan
status: revision-pending-review
spec_version: "501e34584e3ca06a922038d153a96e3b93aa65ab"
owner: "Fable (Comate), from T-028"
reviewer: "Solar, from T-028"
---

# 系统交互基础——技术计划

## Technical context

本计划实现一个不接入模型的 macOS 系统能力验证应用。应用在已经运行时由临时全局快捷键触发，通过 Accessibility 读取当前选区或输入框全文，本地生成确定性结果，在 non-activating 悬浮 panel 中预览，并只在用户明确确认且目标重新验证通过后替换原文。失败时提供可理解状态和显式剪贴板后备。

技术基线：

- 平台：macOS 14.0 及以上，`arm64` 与 `x86_64`；
- 语言：Swift 6 language mode；
- UI：AppKit 应用生命周期和 `NSPanel`，SwiftUI 预览内容；
- 系统接口：ApplicationServices `AXUIElement`、HIToolbox hot key/Secure Event Input、AppKit `NSWorkspace`/`NSScreen`/`NSPasteboard`；
- 并发：AppKit 与快捷键在 `@MainActor`，AX 引用由 `AccessibilityGateway` actor 串行拥有；
- 依赖：不引入第三方运行时包；
- 权限：关闭 App Sandbox，运行时显式请求 Accessibility；
- 数据：真实用户内容只存在于当前内存会话；
- 网络：001 不申请或使用网络能力；
- 工具：进入实现前安装最新稳定完整 Xcode；当前 Command Line Tools 只能验证脚本和文档。

产品名与最终功能名尚未确定。工程显示名必须集中配置为可替换值，不能把临时名称写进领域接口或测试语义。

## Constitution Check

| 宪法条款 | 计划符合方式 | 升级条件 |
| --- | --- | --- |
| Article I — Specifications are authoritative | 所有组件和测试均追溯到已批准的 FR/NFR/AC；Plan 不增加模型、持久化或最终 UI 行为 | 任何行为变化先回到 Spec Gate |
| Article II — Preserve user control and text | preview-before-write；确认/恢复前强制重新验证；安全输入双重拒绝；原文会话内可恢复；始终保留显式剪贴板后备 | 出现无法证明原子或安全的直接写入时禁用该目标的直接能力 |
| Article III — Privacy and credential safety | 内容不进入文件、配置、日志、分析、截图或网络；剪贴板只在按钮事件中访问并限制当前设备 | 任何持久化、同步、遥测或网络需求必须另开 Spec |
| Article IV — Native macOS reliability first | AppKit、AXUIElement、HIToolbox 与 NSPasteboard 原生实现；无跨平台壳与第三方运行时依赖 | 原生 API 不可行时重新进入 Plan Gate，不私自增加 helper/扩展 |
| Article V — Testable requirements and evidence | 纯逻辑单元测试、合成 AX 宿主、本地真实应用人工矩阵和性能证据共同覆盖 | Tasks Gate 必须把每个 FR/NFR/AC 映射到具体证据 |
| Article VI — Independent review | Solar 只编写；Fable 针对准确 SHA 独立审核研究、计划、检查和宪法一致性 | HANDOFF 后任何推送使审核失效 |
| Article VII — Minimal scope | 只实现 001 的能力探针；不做 AI、提示词库、账号、同步、社区、更新器或最终设置 | 新子系统必须单独 Spec |
| Article VIII — Failure must be understandable and recoverable | 领域错误映射到有限用户状态；无静默失败；目标失效或写入失败保留复制/恢复路径 | 未分类失败不得直接显示原始系统码或继续写入 |

Plan Gate 不需要修改宪法，也没有需要用户豁免的条款。

## Architecture and component boundaries

### 进程与线程模型

001 使用单一 macOS 应用进程，不创建 XPC service、登录项、浏览器扩展或 helper。

- `@MainActor`：应用生命周期、hot key 回调、Secure Event Input 全局检查、`InteractionSessionCoordinator`、panel 与 SwiftUI 状态；
- `AccessibilityGateway` actor：串行拥有所有原始 `AXUIElement`/`AXObserver` 引用并执行 AX 调用；
- 值类型边界：actor 只向主 actor 返回 `CaptureResult`、`TargetSnapshot`、`TargetValidity` 和领域错误；原始 AX 引用不暴露给 UI；
- 会话隔离：每次触发生成 UUID；所有异步结果返回时必须再次匹配当前 session ID，旧结果直接丢弃并清理。

### 组件

| 组件 | 单一职责 | 不负责 |
| --- | --- | --- |
| `AppLifecycleController` | 启动/退出、组装依赖、展示必要状态 | 文本读取和业务状态转换 |
| `GlobalHotKeyRegistrar` | 注册/注销临时 exclusive hot key、映射冲突 | 创建会话或读取文字 |
| `AccessibilityPermissionClient` | 检查信任状态、触发系统提示、打开设置、重新检测 | 绕过权限或读取目标 |
| `SecureInputGuard` | 检查全局 Secure Event Input 与目标 secure subrole | 记录密码元素或内容 |
| `AccessibilityGateway` | 捕获、观察、重新验证、直接替换、恢复 | UI、日志或持久化 |
| `ExternalTargetMonitor` | 组合 `NSWorkspace` 与 AX 通知，提前报告目标过期 | 作为最终写入授权依据 |
| `InteractionSessionCoordinator` | 唯一会话、状态机、异步结果去重、动作路由和清理 | 直接调用 C API 或绘制 panel |
| `DeterministicTransformer` | 生成固定验证标记加原文 | 模型、网络或模板系统 |
| `PreviewPanelController` | `NSPanel` 生命周期、位置、可见性和 SwiftUI bridge | 判断目标是否可写 |
| `ScreenGeometryConverter` | AX/AppKit 坐标转换、选屏与边界夹紧 | 读取用户内容 |
| `PasteboardClient` | 响应显式按钮执行单次本机剪贴板读写 | 后台观察或自动读取 |
| `CapabilityProbeClock` | 单调计时和不含内容的性能样本 | 遥测上传或持久化用户内容 |

### 依赖方向

`InteractionSessionCoordinator` 只依赖协议，不依赖具体系统类。系统适配器实现协议并通过应用组装注入。SwiftUI 只订阅不可变 `PreviewViewState` 并发送用户意图；SwiftUI view 不直接接触 AX、剪贴板或窗口对象。

依赖方向为：

```text
System adapters → domain protocols ← InteractionSessionCoordinator → PreviewViewState → SwiftUI
```

任何面向未来 AI、提示词库或账号的抽象都禁止出现在 001 组件中。

## Interfaces and data flow

### 核心值类型

```text
InteractionSessionID = UUID
TargetHandle = UUID（只在 AccessibilityGateway 内映射到 AX 引用）

CaptureMode
  - selectedText(range)
  - wholeField
  - clipboardInput

TargetSnapshot
  - sessionID
  - targetHandle（clipboardInput 时为空）
  - pid / bundleIdentifier（只用于身份和证据，不含内容）
  - captureMode
  - sourceText（敏感，仅内存）
  - transformedText（敏感，仅内存）
  - anchorRect（可空）

RecoverySnapshot
  - targetHandle
  - captureMode
  - originalText（敏感，仅内存）
  - expectedTransformedText（敏感，仅内存）
```

不定义序列化协议，敏感结构不采用 `Codable`，也不能放入 `UserDefaults`、文件、通知 payload、崩溃附件或日志插值。

### 领域协议

```text
GlobalHotKeyRegistering
  registerTemporaryShortcut() -> HotKeyRegistrationResult
  unregister()

AccessibilityPermissionChecking
  currentStatus() -> PermissionStatus
  promptIfNeeded()
  openAccessibilitySettings() -> OpenSettingsResult

TextTargetAccessing
  capture(sessionID) async -> CaptureResult
  monitor(targetHandle, sessionID) async -> TargetEvent stream
  validateForReplacement(targetHandle, snapshot) async -> TargetValidity
  replace(targetHandle, snapshot) async -> WriteResult
  validateForRecovery(targetHandle, recovery) async -> TargetValidity
  restore(targetHandle, recovery) async -> WriteResult
  release(targetHandle) async

PasteboardAccessing
  readStringAfterExplicitAction() -> PasteboardReadResult
  writeLocalStringAfterExplicitAction(text) -> PasteboardWriteResult

PreviewPresenting
  show(state, anchorRect)
  update(state)
  dismiss()
```

方法名中的 explicit action 是设计约束；实现必须从明确用户动作路径调用，不能用于启动、快捷键按下或后台观察。

### 会话状态机

允许的主状态只有：

```text
idle
→ checkingPermission
→ capturingTarget
→ previewing
→ applying
→ recoverable
→ ended
```

失败通过 `previewing` 的 capability state 表达，不创建绕过写入的新状态：

- `ready`：确认、复制、取消可用；
- `permissionRequired`：打开设置、重新检测、剪贴板输入可用；
- `secureInput`：不含内容的说明和关闭可用；
- `emptyOrUnsupported`：重试、剪贴板输入、关闭可用；
- `staleTarget`：复制结果、取消可用；
- `writeFailed`：复制结果、取消可用；
- `recoveryUnavailable`：复制原文、关闭可用。

只有 `ready` 可以转入 `applying`。只有成功的直接替换可以进入 `recoverable`。`clipboardInput` 从不启用直接替换或恢复。

### 正常捕获流程

1. hot key 回调在主 actor 创建新 session ID；若已有会话，先结束旧会话并释放 target handle；
2. panel 立即展示不含用户内容的 loading shell，使外部 AX 响应慢时仍能满足可见响应要求；
3. `SecureInputGuard` 检查全局 Secure Event Input；命中即显示 `secureInput`，不调用文字读取；
4. 权限客户端检查 Accessibility；缺失时显示 `permissionRequired`，不调用文字读取；
5. `AccessibilityGateway` 获取当前外部应用、窗口与焦点元素，读取 role/subrole/editable 状态；secure subrole 命中即中止；
6. 如果 selected range 长度大于 0，只读取 selected text；否则读取完整 value。空字符串无结果，纯空白是合法输入；
7. gateway 保存 AX 引用并返回随机 target handle、值类型快照与可选 anchor rect；
8. transformer 生成第一行 `【系统交互验证】`、一个换行和原文；
9. coordinator 只在 session ID 仍为当前值时发布 `ready` preview，否则立即释放旧 handle；
10. target monitor 开始监听外部应用、窗口、焦点、选区和值变化。

### 目标重新验证

外部监控用于尽快禁用按钮，但不是写入授权。replacement 与 recovery 使用
**两套明确区分的算法**，共享同一组目标有效性前置检查。

#### 共享前置检查（A1–A5，两条路径都必须先全部通过）

1. target 应用仍在运行，PID 与保存值一致；
2. 除工具自身 non-activating panel 外，没有其他应用成为用户的新外部目标；
3. AX 窗口和元素仍有效且身份一致；
4. 当前元素仍可编辑且不是 secure subrole，全局 Secure Event Input 未开启；
5. 目标属性仍可设置。

A1–A5 任一失败立即返回 `staleTarget` 或具体安全错误，零 setter。
AX 通知缺失、延迟或失败不能放宽该门禁。

#### AX 范围单位约定

AX 与 CFRange 的 `location` 与 `length` 一律为 **UTF-16 code unit**。
本计划中所有范围计算、长度比较、越界检查与子串替换都使用该单位，
不使用 Swift `Character`、字形簇或字节长度。
`expected result range` 定义为：`location` = 捕获时记录的 selected range
起始位置，`length` = expected transformed text 的 UTF-16 长度。
Emoji、组合字符与代理对必须按 UTF-16 长度参与上述计算。

#### replacement 重新验证（confirm 路径）

- B1：selected 模式下 selected range 与 selected text 都必须仍等于捕获值；
  whole-field 模式下完整 value 必须仍等于捕获值；
- B2：通过后只允许使用捕获模式对应的单一 setter（selected 模式写
  `kAXSelectedTextAttribute`，whole-field 模式写 `kAXValueAttribute`），
  执行恰好一次；
- B1 失败返回 `staleTarget`，零 setter；不得改用其他 setter 或范围。

#### recovery 重新验证（restore 路径）

- C1：先计算 expected result range（见范围单位约定）；
- C2：读取当前 selected range，并按结果分为三类：
  - **类别 R1 — 范围仍覆盖结果**：当前 selected range 等于 expected result
    range。走默认恢复，只使用捕获模式对应的同一 setter，写入一次原文。
  - **类别 R2 — 可接受的范围不匹配或能力缺失**，仅限以下两种情形：
    1. 成功读到 selected range，但它是**零长度插入点**，且位置落在
       expected result range 内（含两端）——即目标应用在写入后塌陷了选区；
    2. selected range 属性**不受支持、无值，或经能力探针确认无法可靠读取**。
    这两种情形可以进入下述六项 whole-field 前置条件。
  - **类别 R3 — 安全性或目标有效性错误**：`invalid element`／invalid UI
    element、权限错误、Secure Input、timeout、`cannotComplete`，以及任何
    非能力缺失的读取失败。**必须立即 fail-closed**，返回 `staleTarget` 或
    对应安全错误，零 setter，不得进入例外。
  - 用户主动移动或改变选区（读到非零长度且不等于 expected result range 的
    范围）不属于 R2，按 R1 的不匹配处理即 `recoveryTargetChanged`，零 setter。
- C3：R1 与 R2 都必须额外满足"当前位置内容等于 expected transformed text"
  （R1 比较选区内容，R2 由下述前置条件 4 比较范围内容）；不满足只允许复制原文。
- C4：任何 whole-field 前置条件失败、setter 失败或回读失败都返回
  `recoveryTargetChanged`，**不得再尝试 selected setter，也不得第二次写入**。

任何一步失败都不执行 setter；恢复失败时保留原文并只允许复制原文。

### 写入与恢复

**替换（confirm 路径）——本次修订未改动：**

- selected 模式只对 `kAXSelectedTextAttribute` 执行一次 setter；
- whole-field 模式只对 `kAXValueAttribute` 执行一次 setter；
- 禁止先清空、模拟全选、模拟粘贴或分段写入；
- setter 返回错误时不执行第二种直接写入策略，保留结果并显示 `writeFailed`；
- setter 成功后创建 `RecoverySnapshot` 并进入 `recoverable`。

**恢复（restore 路径）——本次修订新增 selected-range recovery fallback：**

- 默认规则（类别 R1）不变：恢复沿用捕获时的同一 setter，selected 模式写
  `kAXSelectedTextAttribute`，whole-field 模式写 `kAXValueAttribute`；
- 恢复前要求目标内容仍等于 expected transformed text；不相等时只允许复制原文；
- **selected-range recovery fallback**（原稿称"塌陷选区例外"，因同时覆盖
  范围能力缺失，改用此更准确的名称）：T-032 真实环境验证发现，TextEdit 在
  选区替换成功后会把选区塌陷为零长度插入点，`kAXSelectedTextRange` 不再等于
  结果范围；此时写 `kAXSelectedTextAttribute` 会把原文插入到错误位置或写入
  空选区，恢复必然失败。部分目标应用还可能完全不提供可靠的 selected range
  读取。原计划未预见这两种平台行为。
  因此在 selected 模式且**仅当**重新验证判定为类别 R2（零长度插入点落在
  expected result range 内，或 selected range 属性不受支持／无值／经能力探针
  确认不可可靠读取）时，恢复改为一次 `kAXValueAttribute` 写入，且必须满足
  全部前置条件：
  1. `kAXValueAttribute` 可写（`replacementAttributeIsSettable`）；
  2. 能读到目标全文；该全文即下述基值，必须在 A1–A5 与 C2 全部通过之后、
     **紧邻 setter 之前**获取，不得复用捕获阶段或验证早期读到的旧值；
  3. expected result range（`location` + expected transformed text 的
     UTF-16 长度）完全落在基值的 UTF-16 长度内，且 `location >= 0`；
  4. 基值中该范围内的现有文本按 UTF-16 逐 code unit **完全等于**
     expected transformed text；
  5. 写入内容仅由"基值 + 该范围替换回原文"构成，范围外的 UTF-16 code unit
     必须与基值完全一致；
  6. 写入后回读全文并确认等于预期恢复结果，否则 `recoveryTargetChanged`。
  任一条件不满足即 fail-closed，不写入、保留原文、只允许复制原文。
- 类别 R3（目标失效、权限、Secure Input、timeout、`cannotComplete` 等安全性
  或有效性错误）**不得**进入本 fallback，必须立即零 setter 拒绝。
- 该 fallback 只适用于恢复路径，不适用于替换路径；替换路径仍严格单 setter。
  它不得用于绕过任何重新验证步骤，也不得在写入失败后重试第二种策略或
  改回 selected setter。
- **TOCTOU 残余风险（如实记录）**：AX whole-field setter 不具备
  compare-and-swap 语义。前置条件 2 的紧邻基值校验、前置条件 4/5 的范围与
  范围外一致性检查、外部目标监控以及写后回读，只能**降低**基值读取与 setter
  之间被外部并发改写的概率，不能原子消除。写后回读用于**检测**结果不符并
  报告 `recoveryTargetChanged`，**不能撤销**已经发生的覆盖。因此本 fallback
  的安全性依赖上述多重门禁加真实环境证据，不宣称原子性。
- 实现入口见 `AccessibilityGateway` 的恢复路径；测试要求见 Test strategy 的
  `RecoveryTests` 条目。
- 新会话、取消、成功状态关闭或退出会释放 target handle 并清除 source/result/recovery 字符串引用。

### 剪贴板流程

1. 用户在外部应用手动复制原文；
2. 用户明确点击“使用剪贴板内容”；
3. `PasteboardClient` 单次读取 `.string`；失败或空字符串显示可恢复状态，纯空白合法；
4. 创建 `clipboardInput` 快照并生成预览，确认替换永远禁用；
5. 用户明确点击“复制结果”或“复制原文”时，调用 `prepareForNewContents(.currentHostOnly)` 后只写 `.string`；
6. 应用不观察 pasteboard、不自动重试、不保存剪贴板内容。

### 预览定位

`ScreenGeometryConverter` 按以下顺序选择 anchor：

1. `kAXBoundsForRangeParameterizedAttribute` 的选区/插入点边界；
2. AX 元素 position + size；
3. AX window position + size；
4. 当前外部目标所在屏幕中心附近；
5. 当前活跃显示器安全位置。

转换后选择与 anchor 相交面积最大的 `NSScreen`，将 panel 在该屏幕可用 frame 内保留固定安全边距；全屏 Space 使用包含目标窗口的屏幕 frame。panel 配置 `.nonactivatingPanel`、floating、`hidesOnDeactivate = false`、`becomesKeyOnlyIfNeeded = true`、`.canJoinAllSpaces` 和 `.fullScreenAuxiliary`。最终视觉尺寸不在本 Plan 中锁定，但必须完整可见并提供规格要求的操作。

## Privacy and security

### 内容生命周期

- 敏感内容：源文字、确定性结果、恢复原文和剪贴板文字；
- 允许位置：当前 `InteractionSessionCoordinator` 值对象和 gateway 的当前 target record；
- 禁止位置：文件、数据库、`UserDefaults`、普通配置、日志、通知 payload、分析、网络、截图、测试附件、错误描述和崩溃自定义字段；
- 清理：会话结束时取消异步任务、停止观察、释放 target handle，并把所有敏感字段置空/释放；Swift String 不提供安全擦除保证，因此不声称内存取证级清零，只保证应用不再持有引用和不做持久化；
- 并发：异步回调必须携带 session ID；旧 session 的内容不能重新进入 UI。

### 日志规则

允许记录：会话随机 ID 的短期不可逆摘要、状态名、领域错误类别、耗时、macOS/应用版本和合成测试样本标签。

禁止记录：任何文本、文本长度与内容组合、选区文字、完整 AX value、剪贴板内容、Accessibility 属性 dump、窗口标题或包含用户内容的元素描述。

即使日志框架支持 privacy redaction，也不能把敏感内容传给 logger。

### 权限与签名边界

- App Sandbox 明确关闭；不申请网络、文件、Apple Events、Input Monitoring 或其他非必要 entitlement；
- Accessibility 未授权时不调用内容读取/写入；
- 系统 prompt 与“打开设置”都必须由用户动作触发并提供用途说明；
- 开发构建使用稳定路径和本地签名，避免频繁更换身份导致 TCC 授权混乱；
- 未来对外构建启用 Hardened Runtime、Developer ID 签名和 notarization，但其流水线不属于 001；
- 安全输入拒绝优先于便利性，允许安全误拒绝，不允许疑似密码内容进入会话。

## Failure and recovery

| 领域失败 | 可观察状态 | 安全恢复动作 |
| --- | --- | --- |
| `hotKeyConflict` | 快捷键不可用说明 | 重新注册；001 不提供永久改键 UI |
| `accessibilityPermissionRequired` | 权限用途说明 | 打开设置、重新检测、剪贴板输入 |
| `secureInputActive` | 不含输入内容的安全说明 | 关闭并在普通输入框重试 |
| `emptySource` | 没有可处理文字 | 选择/输入文字后重试 |
| `unsupportedTarget` | 目标不可编辑或属性不支持 | 剪贴板输入或关闭 |
| `axTimedOut` / `axCannotComplete` | 目标应用未及时响应 | 保持原文、重试或剪贴板输入 |
| `invalidTarget` | 原目标已失效 | 禁用替换，复制结果或取消 |
| `sourceChanged` | 原文/选区已变化 | 禁用替换，复制结果或重新触发 |
| `attributeNotSettable` | 当前目标不可直接写入 | 复制结果 |
| `writeFailed` | 替换未确认成功 | 保留结果，复制结果；不尝试第二种 setter |
| `recoveryTargetChanged` | 无法安全直接恢复 | 保留并复制原文 |
| `pasteboardReadFailed` | 未获得剪贴板文字 | 用户重新复制后重试 |
| `pasteboardWriteFailed` | 未能复制 | 保留 preview，允许再次点击 |
| `panelPlacementFallback` | 使用安全后备位置 | 功能继续，不把定位失败当成内容失败 |

底层 `AXError`、`OSStatus` 和 pasteboard 返回值只能映射为上述领域错误；界面不显示原始错误码。未知错误采用 fail-closed：不写入、保留已有安全后备动作，并只记录不含内容的类别。

“打开 Accessibility 设置”先尝试集中封装的 macOS 14+ 设置 URL；打开失败时退回通用 Privacy & Security 页面并展示人工导航说明。深链失败不能被当作权限已授予，也不能阻止“重新检测”和剪贴板输入。

异常退出后应用内恢复信息不可用。目标应用自身 Undo 行为只作为 AC-017 兼容性证据，不替代正常会话内恢复。

## Test strategy

### 测试替身边界

以下协议必须可注入 fake/spy：hot key、权限、secure input、AX gateway、外部目标监控、pasteboard、panel、screen geometry 和 monotonic clock。测试不得依赖真实用户剪贴板或现实应用内容。

### Unit

- `InteractionSessionCoordinatorTests`：每个允许状态转换、非法转换拒绝、单会话、旧异步结果丢弃；
- `ConfirmationSafetyTests`：所有确认前路径 setter 调用数为 0；只有 `ready + valid` 触发一次 setter；
- `TargetValidationTests`：PID、窗口、元素、range、内容、settable、secure input 任一变化都阻断；
- `RecoveryTests`：只有 expected transformed text 仍存在时恢复，其他情况只允许复制原文；
  selected-range recovery fallback 必须逐项覆盖以下门禁与失败分支：
  - **类别判定**：R1（范围仍等于 expected result range）走 selected setter；
    R2 之情形 1（零长度插入点落在结果范围内）与情形 2（range 属性不受支持／
    无值／能力探针确认不可可靠读取）进入 fallback；读到非零长度且不等于结果
    范围（用户主动改选区）返回 `recoveryTargetChanged` 且零 setter；
  - **R3 零 setter**：`invalid element`、权限错误、Secure Input、timeout、
    `cannotComplete` 等安全性或有效性错误一律立即拒绝，不进入 fallback，
    selected 与 whole-field setter 计数均为 0；
  - **前置条件 1**：`kAXValueAttribute` 不可写时零 setter；
  - **前置条件 2**：全文读取失败时零 setter；且必须断言写入使用的基值是
    通过全部门禁后紧邻 setter 获取并验证的同一份值（不得复用旧值）；
  - **前置条件 3**：expected result range 越界（location 为负、
    location + UTF-16 长度超出基值长度）时零 setter；
  - **前置条件 4**：基值该范围内文本不等于 expected transformed text 时零 setter；
  - **前置条件 5**：fallback 成功时范围外的 UTF-16 code unit 与基值完全一致；
  - **前置条件 6**：写后回读不一致时返回 `recoveryTargetChanged`；
  - **setter 计数**：fallback 成功时 selected setter 为 0、whole-field setter
    恰好为 1；whole-field setter 本身失败时返回 `recoveryTargetChanged`，
    不重试其他 setter、不第二次写入；
  - **共享前置检查**：应用、PID、窗口、元素、可编辑性或 Secure Input 任一
    检查失败时 fallback 也不得执行；
  - **UTF-16 单位**：使用 Emoji、组合字符与代理对构造夹具，验证范围计算与
    替换按 UTF-16 code unit 进行，且结果范围外内容保持完全一致；
- `ClipboardPolicyTests`：启动/快捷键/preview 不访问 pasteboard；三个显式动作精确触发预期单次访问；写入使用 current-host-only；
- `DeterministicTransformerTests`：中文、英文、混合、纯空白、多行、Emoji/特殊字符和 10,000 字符合成输入逐字符一致；
- `ScreenGeometryConverterTests`：单屏、多屏、负坐标、边缘、全屏 frame 与缩放后的 clamp；
- `ErrorMappingTests`：已知/未知 AX 与 OSStatus 都 fail-closed，用户状态包含安全下一步；
- `PrivacyContractTests`：领域错误和可日志事件不接受敏感 String 字段，敏感会话类型不采用 `Codable`。

### Integration

本地测试 bundle 启动一个独立合成宿主应用，包含：普通单行输入、`NSTextView` 多行输入、非空选区、空输入、只读文本、安全文本框以及可销毁/切换的两个输入元素。测试只使用固定的 `SYNTHETIC-001` 系列样本。

在已授予测试构建 Accessibility 权限的开发机上验证：

- 选区读取和只替换选区；
- 无选区时全文读取和替换；
- secure field 在内容读取前拒绝；
- 切换窗口/元素和修改内容使目标失效；
- AX 元素销毁与目标应用退出；
- setter 错误映射和恢复；
- target observer 缺失时确认门禁仍有效。

CI 不依赖 TCC 权限，只执行可重复构建与纯单元测试；本地 AX integration 结果作为结构化证据提交。

### Manual compatibility

必须使用非敏感合成文字，在记录中注明 Mac 型号、CPU、macOS 版本、目标应用版本、全屏状态、显示器布局、显示缩放和步骤：

| 环境 | 最低证据 |
| --- | --- |
| TextEdit | 选区与全文的读取、预览、确认、替换、恢复、Undo |
| Chrome/ChatGPT | 全文与代表性多行输入的完整闭环、焦点切换阻断 |
| VS Code | 显式剪贴板输入与复制结果闭环；直接能力只记录实际结果 |
| 权限关闭 | 不读取、打开设置、重新检测、剪贴板路径 |
| 密码/安全输入 | 不读取、不展示、不复制、不记录 |
| 显示环境 | 单/多显示器、边缘、全屏、非默认缩放，panel 完整可见 |
| 输入形态 | 中文、英文、混合、纯空白、多行、Emoji/特殊字符、10,000 字符合成文本 |

### Performance

- 在 TextEdit 与 Chrome/ChatGPT 各连续触发 10 次；
- 计时起点为 hot key callback，终点为 loading/preview shell 或明确状态完成首帧；
- 使用 monotonic clock；至少 9 次小于等于 300ms；
- 记录设备、系统、应用版本、10 次耗时和测量方法，不记录输入内容；
- AX 捕获可在 shell 显示后异步完成，但最终内容必须属于同一 session ID。

安全输入人工验证必须单独记录 hot key 是否仍会投递。如果操作系统在回调前完全抑制快捷键，结果必须标为未满足 AC-004 并返回 Spec/Plan Gate；不能把“没有读取到内容”误记为可理解的拒绝状态。

### 需求证据原则

Tasks Gate 必须为 FR-001 至 FR-013、NFR-001 至 NFR-007、AC-001 至 AC-017 逐项指定至少一个 Unit、Integration 或 Manual 证据。系统行为不得只依赖人工目测；真实应用兼容性也不得只用 fake 宣称通过。

## Rollout and compatibility

001 是首次能力验证，没有数据库、文件格式、用户数据或迁移。回滚方式是停止当前构建并恢复到上一个已知版本；Accessibility 授权仍由用户在 System Settings 管理。

实现阶段采用以下阶段出口：

1. 完整 Xcode 已安装，工程能以 macOS 14 deployment target 和 Swift 6 构建；
2. App Sandbox 关闭且没有非必要 entitlement；
3. CI 的 build、unit-tests、sdd-check、secret-scan 全绿；
4. 合成 AX 宿主证据通过；
5. TextEdit 与 Chrome/ChatGPT 达到完整闭环最低标准；
6. VS Code 达到剪贴板后备最低标准；
7. 性能、显示、安全输入、失败恢复、隐私和 Undo 证据完成；
8. 所有已知限制在 PR 中记录，真实用户内容未进入产物。

如果 TextEdit 或 Chrome/ChatGPT 无法稳定达到完整闭环，001 不得以“部分完成”作为通过，也不得继续后续 AI/提示词库功能；必须返回 Plan 或 Spec Gate 修正基础能力。VS Code 直接能力失败可以接受，但剪贴板后备必须通过。

正式产品名、签名公证流水线、安装器、更新器、菜单栏形态、最终工作台和最终快捷键均留给后续已批准范围。

### 已知技术风险与提前验证顺序

1. **Secure Event Input 可能阻断 hot key 投递：** 首个系统探针验证；若无法显示拒绝状态，返回 Spec/Plan Gate。
2. **HIToolbox hot key 的长期演进：** 编译时确认目标 SDK 无不可用标记，运行时验证冲突错误；不得暗中改用按键监听。
3. **第三方 AX 支持差异：** 先验证 TextEdit，再验证 Chrome/ChatGPT，最后记录 VS Code 直接能力与后备。
4. **设置深链不是稳定公开契约：** 使用集中适配器和通用 Privacy & Security 回退说明。
5. **跨应用全屏 panel 行为：** 在 direct-write 代码前完成 non-activating、all-Spaces 和 full-screen auxiliary 探针。
6. **当前缺少完整 Xcode：** Tasks Gate 可以编写，但 Implementation Gate 的任何工程/构建任务开始前必须安装并记录稳定版本。
7. **公开分发成本与签名：** 001 只保证本地开发能力；Developer ID、notarization 与下载体验另行规划。
8. **选区塌陷或范围不可读导致恢复不可用（本次修订新增，待 Reviewer 审核）：**
   目标应用在写入后可能把选区塌陷为插入点，或完全不提供可靠的 selected range
   读取，使 selected setter 无法定位原范围。本修订提出 selected-range recovery
   fallback 应对这两种行为。该 fallback 扩大了恢复路径的写入面，风险由
   "类别 R2 限定 + 六项前置条件 + 紧邻基值校验 + 回读确认 + 范围外零改动"约束；
   但 AX whole-field setter 无 compare-and-swap 语义，基值读取与 setter 之间的
   TOCTOU 残余风险只能降低、不能消除，回读只能检测不能撤销。
   闭合本风险还需要新增单元测试与 TextEdit 选区路径的真实环境恢复证据。

## Plan Gate record

- 用户技术路线确认：AppKit 核心 + SwiftUI 内容、数据流、重新验证、隐私/恢复和测试策略均已逐段确认
- Review commit SHA 与 Reviewer verdict：以 PR #2 中结构化 `HANDOFF` 和 `REVIEW` 评论为权威记录；本文件不复制会随提交变化的结果
- 审核更新规则：任何 Plan Gate `HANDOFF` 后的新提交都会使旧审核请求失效，Owner 必须针对新的准确 SHA 重新发布 `HANDOFF`
- PR review reference：PR #2
- 后续授权：Tasks Gate 已获用户授权，仅允许编写 `tasks.md`；Implementation Gate 未获授权
- **2026-07-28 修订（Plan Gate 重开）：** Solar 在 Implementation Gate 审核
  `ebb697826cb5e67546ea01aabda1181cd9e15471` 时提出 MUST：提交 `d95228e` 引入的
  `restoreCollapsedSelection` 在 selected 模式恢复时改用 whole-field setter，
  违反本文件原"写入与恢复"章节的单 setter 约束，且该变更未在 P5 证据中披露。
  用户于 2026-07-28 批准**重开 Plan Gate 并保留该设计方向**，提交 Reviewer
  审核；Reviewer 尚未给出 Plan Gate `PASS`，本修订在获得 `PASS` 前不构成
  已批准设计。
  第一版修订（`1333438`）内容：新增"塌陷选区例外"及六项前置条件、补充
  `RecoveryTests` 覆盖要求、新增技术风险第 8 条。
  **第二版修订（本次，回应 Solar 对 `1333438` 的 Plan Gate REVIEW 三项 MUST）：**
  拆分共享前置检查（A1–A5）、replacement 算法（B1–B2）与 recovery 算法
  （C1–C4），并把 recovery 的范围读取结果分类为 R1／R2／R3——仅 R2
  （零长度插入点落在结果范围内，或 range 能力缺失）可进入 fallback，R3
  安全性与有效性错误必须立即零 setter 拒绝；明确 AX 范围一律使用 UTF-16
  code unit 并定义 expected result range；把例外更名为 selected-range
  recovery fallback；前置条件 2 要求紧邻 setter 获取并校验基值；逐项补齐
  `RecoveryTests` 对六项前置条件、R3 分支、setter 计数与 UTF-16 夹具的
  覆盖要求；如实记录 TOCTOU 残余风险不可原子消除、回读只能检测不能撤销。
  修订使下游 Tasks 与 Implementation Gate 一并重开：Tasks Gate 需要重写
  T-021／T-022 使其与批准后的恢复算法一致，Implementation 的其余修复
  （原 REVIEW 的 Finding 1、2、4、5、6）在 Plan Gate 与 Tasks Gate 依次
  取得 `PASS` 后进行。
