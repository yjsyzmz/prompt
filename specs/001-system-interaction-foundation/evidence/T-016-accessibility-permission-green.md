# T-016 Accessibility 权限流程 GREEN 证据

## 结论

T-016 已以最薄实现使 T-015 的 Accessibility 权限流程契约全部转绿。权限门禁每次通过系统信任检查获得当前状态；未授权时不会开始受保护的 AX 读取或写入。设置跳转、重新检测与剪贴板输入只暴露带 `AfterExplicitAction` 语义的入口，不会由权限检查自动触发。

canonical 单元测试连续两次执行 37 项测试、0 failure；其中 T-015 的 7 项权限流程测试全部通过。

## 实现范围

- `AccessibilityPermissionFlow` 保存最小的 `idle`、`authorized`、`permissionRequired` 和设置跳转结果状态；
- 每次捕获、确认写入或显式重新检测都调用 `AccessibilityPermissionChecking.currentStatus()`，不缓存虚假的授权结果；
- `SystemAccessibilityPermissionChecker` 直接使用 `AXIsProcessTrusted()`；
- 未授权时，受保护读取和写入依赖的调用次数保持为 0；
- `openSettingsAfterExplicitAction()` 先尝试 Accessibility 具体页面，失败时只降级一次到 Privacy & Security 通用页面；
- `SystemAccessibilitySettingsOpener` 只封装 `NSWorkspace.open(_:)` 与两个系统设置 URL；
- `startClipboardInputAfterExplicitAction()` 只转发已明确发生的用户动作，本任务没有实现或访问真实 `NSPasteboard`；
- 所有协议和流程均限定在 `@MainActor`，避免 UI 驱动的权限副作用跨执行域发生。

## 自动测试

命令：

```text
./scripts/unit-tests.sh
```

连续两次结果均为：

```text
Test Suite 'AccessibilityPermissionFlowTests' passed
Executed 7 tests, with 0 failures
Test Suite 'All tests' passed
Executed 37 tests, with 0 failures
TEST SUCCEEDED
```

七项测试覆盖已授权、未授权、具体设置页成功、深链失败后降级、显式重新检测、权限缺失时 AX 零读写，以及剪贴板路径只能由显式动作启动。

## 其他检查

- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `./scripts/sdd-check.sh`：PASS
- `./scripts/secret-scan.sh`：PASS
- `xcrun swiftc -parse Sources/SystemInteractionFoundation/AccessibilityPermissionFlow.swift`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `git diff --check`：PASS

## 环境

- macOS 26.5.2（25F84）
- Xcode 26.6（17F113）
- Apple Swift 6.3.3

## 范围确认

- 未执行 T-017；
- 未实现真实剪贴板适配器，也未读取或写入剪贴板；
- 未实现 AX 文字读取、AX 写入、权限弹窗、正式 UI、网络或持久化；
- 未修改 T-015 测试以降低要求；
- 系统设置跳转和剪贴板路径均只能通过命名为显式用户动作的流程方法调用。
