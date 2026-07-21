# T-007 快捷键停止条件人工探针

## 结论

**PASS。** 普通输入、Secure Event Input 和真实快捷键注册冲突三种环境均符合已批准的 Spec/Plan。Secure Event Input 没有完全抑制 global hot-key callback，因此未触发返回 Spec/Plan Gate 的硬停止条件；回调到达后，安全输入门禁在任何内容读取前返回 `blocked`，模拟内容读取计数保持为 0。

本任务只验证 T-006 的快捷键与安全输入边界。没有读取、记录、转换、展示、复制或修改任何输入内容，也没有执行 T-008。

## 环境

- 执行时间：2026-07-21 14:21 CST
- 设备：MacBook Pro `Mac15,3`
- CPU / 架构：Apple M3，8 cores，`arm64`
- 内存：8 GB
- macOS：26.5.2（25F84）
- Xcode：26.6（17F113）
- Swift：6.3.3
- 测试构建：本地临时、未签名、非沙盒 AppKit `.app`，`LSUIElement=true`
- 临时快捷键：`Control + Option + Command + 9`
- 输入样本：没有捕获输入内容；探针只维护整数型模拟读取计数
- 显示条件：窗口/面板不属于 T-007，未进入全屏或几何验证；这些环境由 T-010 单独记录

## 探针方法

1. 在 `/private/tmp` 创建不入库的 AppKit 探针宿主，并与仓库中的 `SystemInteractionAdapters.swift` 一起编译。
2. 宿主使用 `NSApplication` 主事件循环，调用生产 `HIToolboxHotKeySystemClient`、`GlobalHotKeyRegistrar`、`HIToolboxSecureEventInputChecker`、`SecureInputGuard` 与 `CapabilityProbeClock`。
3. 用户在普通文本输入环境和 Secure Event Input 环境分别亲自按下一次临时快捷键。没有通过 `CGEventTap`、`NSEvent` monitor、IOHID、Computer Use 或合成键盘事件触发。
4. Secure Event Input 由独立临时进程通过 Apple 的 `EnableSecureEventInput` 建立，通过 `DisableSecureEventInput` 清理。该进程不包含文本控件或内容值。
5. 冲突由两个独立 `.app` 进程同时注册相同 exclusive 快捷键产生，不使用 fake 或协议替身。

首次纯 CLI 诊断中 `RegisterEventHotKey` 返回 `eventInternalErr (-9868)`，因为该进程不是完整 macOS 应用宿主；将同一探针放入最小 `.app` 后，handler 安装与 hot-key 注册均返回 `noErr`。随后一次以 `RunCurrentEventLoop` 等待的宿主虽然注册成功但没有投递 callback；切换为 Plan 规定的正式 `NSApplication` 主事件循环后重新执行全部人工场景。上述宿主初始化尝试不计为产品行为结论，也没有修改生产代码。

## 结果一：普通输入

前置状态：用户保持普通文本输入框焦点；全局 Secure Event Input 为关闭。

```text
REGISTER outcome=registered
READY mode=listen shortcut=Control+Option+Command+9 secureInputAtStart=false
CALLBACK secureInput=false decision=allowed contentReadCount=1 monotonicNanoseconds=72308611534791
```

结果：

- exclusive 快捷键注册成功，真实按键 callback 到达。
- callback 内取得非零单调时钟采样。
- 安全输入门禁允许一次**模拟**内容读取闭包；没有访问真实输入框内容。
- 满足 T-007 对普通输入、FR-001 与 AC-001 中快捷键投递假设的验证范围。NFR-001 的完整 UI 时延证据仍属于 T-036。

## 结果二：Secure Event Input

建立和清理状态：

```text
SECURE_HOLDER enableStatus=0 secureInputEnabled=true
READY mode=secure-hold
SECURE_HOLDER disableStatus=0 secureInputEnabled=false
```

真实按键结果：

```text
REGISTER outcome=registered
READY mode=listen shortcut=Control+Option+Command+9 secureInputAtStart=true
CALLBACK secureInput=true decision=blocked contentReadCount=0 monotonicNanoseconds=73872333691125
```

结果：

- Secure Event Input 开启时，exclusive 快捷键仍能注册且真实 callback 到达。
- callback 观察到 `secureInput=true`，`SecureInputGuard` 返回 `blocked`。
- 模拟内容读取闭包没有执行，`contentReadCount=0`。
- callback 没有被操作系统完全抑制，因此 T-007 的硬停止条件未触发；AC-004 的应用内安全拒绝路径在此系统环境中可实施。
- 清理调用成功，之后 `secureInputEnabled=false`，没有留下全局安全输入状态。

本探针只证明全局 Secure Event Input 分支；焦点元素 `kAXSecureTextFieldSubrole` 的零内容值验证仍由 T-019/T-020 和后续 T-035/T-038 覆盖。

## 结果三：快捷键冲突

第一个独立进程：

```text
REGISTER outcome=registered
READY mode=hold shortcut=Control+Option+Command+9
```

第二个独立进程：

```text
CONTENDER outcome=conflict
```

结果：

- 第一个进程持有相同组合键的 exclusive 注册时，第二个进程得到明确 `.conflict`。
- 没有返回伪成功或进入静默无响应状态；满足 T-007 对 FR-001、AC-002 注册冲突检测边界的验证。
- 面向用户的冲突文案与安全下一步属于 T-027/T-028，不在本任务实现。

## 停止条件判定与后续边界

- `Secure Event Input 完全抑制 callback`：**未发生**。
- `Secure Event Input 下内容读取计数非零`：**未发生**。
- `快捷键占用时未得到 conflict`：**未发生**。
- T-007：可标记完成。
- 检查点 C1：尚未达成；仍需 T-008 → T-009 → T-010 的 nonactivating panel 探针全部通过。
- 本记录不授权 T-008，也不是 Implementation Gate `HANDOFF`。

## 仓库回归检查

- `./scripts/sdd-check.sh`：PASS
- `./scripts/secret-scan.sh`：PASS
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/unit-tests.sh`：PASS，8 tests，0 failures
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `git diff --check`：PASS

单元测试首次在受限沙箱内运行时因 Xcode 无权写入用户 `DerivedData` 而停止；在允许 Xcode 使用其标准 `DerivedData` 目录后原命令重跑通过。该环境权限失败不属于代码、测试断言或 T-007 探针失败。
