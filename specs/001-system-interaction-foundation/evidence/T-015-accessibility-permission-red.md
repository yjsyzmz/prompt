# T-015 Accessibility 权限流程 RED 证据

## 结论

T-015 已完成预期失败测试的定义与执行。canonical 单元测试连续两次以 exit 65 失败；失败只来自 T-016 尚未实现的权限流程、状态与依赖协议。没有新增生产权限适配器、生产 stub、系统设置跳转或 AX 调用。

生产应用构建、工程结构、测试源语法和 Xcode 项目文件仍为绿色。完整单元测试必须保持 RED，直到 T-016 提供最薄权限门禁实现。

## 基线

- RED 起点父 SHA：`c5eafad3ad467552d5f4c7a86a9141f14ea6c87b`
- 平台：macOS 26.5.2，Xcode 26.6，Swift 6
- 测试文件：`Tests/SystemInteractionFoundationTests/AccessibilityPermissionFlowTests.swift`
- 测试目标：`SystemInteractionFoundationTests`
- 测试不创建、读取或记录任何用户内容

## 已定义契约

新增七项失败优先测试：

1. 已授权时进入 `authorized` 并开始一次受保护读取，写入和剪贴板启动次数仍为 0；
2. 未授权时进入 `permissionRequired`，AX 读、AX 写、设置跳转和剪贴板启动次数均为 0；
3. 用户显式打开设置且 Accessibility 具体页面成功时，只调用一次具体页面，不调用通用页面；
4. Accessibility 具体页面失败时，按顺序降级调用一次 Privacy & Security 通用页面；
5. 用户显式重新检测并发现已授权时，权限检查累计两次并继续一次读取；
6. 权限持续缺失时，捕获、确认写入和重新检测路径均不得产生 AX 读写，且不得自动启动剪贴板；
7. 剪贴板输入在未授权状态下不会自动启动，只有显式用户动作才启动一次，并保持 AX 访问为 0。

测试通过权限状态、设置跳转、受保护文字访问与显式剪贴板输入四类 spy 精确统计副作用。设置与剪贴板入口的方法名包含 `AfterExplicitAction`，把用户动作约束写入接口。

## RED 执行结果

命令：

```text
./scripts/unit-tests.sh
```

连续两次结果：exit 65，`TEST FAILED`。`arm64` 与 `x86_64` 测试目标均发现并编译新测试文件，核心诊断为：

```text
Cannot find type 'AccessibilityPermissionStatus' in scope
Cannot find type 'AccessibilityPermissionFlow' in scope
Cannot find type 'AccessibilityPermissionChecking' in scope
Cannot find type 'AccessibilitySettingsOpening' in scope
Cannot find type 'PermissionProtectedTextAccessing' in scope
Cannot find type 'ExplicitClipboardInputStarting' in scope
```

状态成员与构造器的上下文推断诊断均为上述缺失 T-016 契约的级联结果。测试源已单独通过 Swift parse，既有 T-001 至 T-014 生产源没有新的编译诊断。

## 绿色控制

- `xcrun swiftc -parse Tests/SystemInteractionFoundationTests/AccessibilityPermissionFlowTests.swift`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `git diff --check`：PASS

## 范围与解除条件

- 没有修改 `Sources/`；
- 没有调用或封装 `AXIsProcessTrusted`、`AXIsProcessTrustedWithOptions` 或 `NSWorkspace`；
- 没有实现设置 URL、权限提示、AX 读写或剪贴板访问；
- 没有执行 T-016 或任何后续任务；
- 只有 T-016 的最薄权限实现使上述七项契约全部编译并通过后，单元测试才可恢复绿色。
