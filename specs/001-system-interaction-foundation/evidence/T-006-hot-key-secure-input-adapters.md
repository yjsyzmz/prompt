# T-006 快捷键与 Secure Event Input 最薄适配器证据

## 结论

T-006 已实现让 T-005 测试转绿所需的最薄生产边界。实现使用当前 macOS SDK 公开的 HIToolbox API，不需要 Input Monitoring、通用按键监听、第三方依赖或新增 entitlement。

本任务只证明代码级适配器和协议契约成立。真实快捷键投递、冲突环境和 Secure Event Input 对 callback 的实际影响属于 T-007，本任务没有执行或声称这些人工探针已通过。

## 生产实现

`Sources/SystemInteractionFoundation/SystemInteractionAdapters.swift` 包含：

- `GlobalHotKeyRegistrar`：位于 `@MainActor`，保存单一活动 token，映射注册成功、冲突和失败，并让重复注销保持幂等。
- `HIToolboxHotKeySystemClient`：安装 `kEventHotKeyPressed` handler，以 `kEventHotKeyExclusive` 调用 `RegisterEventHotKey`，保存 `EventHotKeyRef`，并在注销时调用 `UnregisterEventHotKey` 与 `RemoveEventHandler`。
- 冲突映射：`eventHotKeyExistsErr` 转换为有限的 `.conflict` 结果，不把原始 OSStatus 暴露为产品状态。
- `HIToolboxSecureEventInputChecker`：只调用 `IsSecureEventInputEnabled`。
- `SecureInputGuard`：在允许的 content-read closure 执行前检查安全输入；启用时返回 `.blocked` 且不调用 closure。
- `SystemMonotonicClock` 与 `CapabilityProbeClock`：使用 `DispatchTime.now().uptimeNanoseconds`，由 hot-key callback 调用点开始采样。

快捷键 key code、modifier、signature 和 identifier 都由初始化参数传入；本任务没有固定最终产品快捷键，也没有把适配器装配进应用生命周期。

## T-005 红转绿

执行：

```text
./scripts/unit-tests.sh
```

结果：

- exit code：`0`
- `HotKeySecureInputProbeTests`：7 tests，0 failures
- `ProjectStructureTests`：1 test，0 failures
- 总计：8 tests，0 failures，0 unexpected
- Xcode：`TEST SUCCEEDED`

通过场景：

- 独占快捷键注册成功；
- 快捷键冲突；
- 注销及重复注销；
- 重复 callback 各传递一次；
- Secure Event Input 开启时零内容读取；
- 单调时钟首次采样发生在 hot-key callback 内；
- 生产适配器源码不包含通用按键监听 API。

现有独立 logic-test target 不链接应用可执行文件，因此同一生产源文件同时编译进测试目标。为避免测试进程读取 `Documents` 源码目录时触发 macOS 隐私限制，test target 的 Copy Files 阶段只把该源码复制到测试 bundle 的 Resources 目录供静态审计；源码副本不会进入产品应用包。

## 其他验证

- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS
- `bash -n scripts/*.sh`：PASS
- `./scripts/sdd-check.sh`：PASS
- `./scripts/sdd-check.sh --self-test`：PASS
- `./scripts/secret-scan.sh`：PASS
- `./scripts/secret-scan.sh --self-test`：PASS
- `./scripts/find-xcode-container.sh --self-test`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `git diff --check`：PASS
- 生产源码禁用符号扫描：`CGEventTap`、NSEvent global/local monitor、IOHIDManager、Input Monitoring TCC symbol 均无匹配
- 生产源码允许符号核验：存在 `RegisterEventHotKey`、`kEventHotKeyExclusive`、`eventHotKeyExistsErr`、`UnregisterEventHotKey`、`IsSecureEventInputEnabled` 与 monotonic uptime sampling

## 范围边界

- 未执行 T-007 或任何人工快捷键探针。
- 未选择或启用实际快捷键组合，未修改 `AppEntry`，未装配应用生命周期。
- 未实现 UI、会话协调器、文字读取、AX、权限、剪贴板、panel、模型、网络、持久化或遥测。
- 未加入 `CGEventTap`、NSEvent monitor、IOHID、Input Monitoring 或通用键盘监听。
- 未增加依赖、entitlement、目标或最终产品命名。

## 下一步

下一项是 T-007：在普通输入、Secure Event Input 和真实快捷键冲突环境执行人工停止条件探针。T-007 需要新的用户明确授权；本任务在此停止。
