# T-013 会话状态机与副作用测试 RED 证据

## 结论

T-013 已完成预期失败测试的定义与执行。canonical 单元测试连续两次以 exit 65 失败；失败只来自 T-014 尚未实现的会话协调器契约。没有新增生产协调器、生产 stub、跳过测试或范围外产品行为。

生产应用构建、工程结构、测试源语法和 Xcode 项目文件仍为绿色。完整单元测试必须保持 RED，直到 T-014 以最薄实现提供已定义契约。

## 基线

- RED 起点父 SHA：`7d9492df6c3a9660baa11a0ba9cbcbefd8ede75c`
- 平台：macOS 26.5.2，Xcode 26.6，Swift 6
- 测试文件：`Tests/SystemInteractionFoundationTests/InteractionSessionCoordinatorTests.swift`
- 测试目标：`SystemInteractionFoundationTests`
- 合成内容：仅 `SYNTHETIC-001`，不包含真实用户内容或类似凭据的字符串

## 已定义契约

新增七项失败优先测试，覆盖：

1. 直接会话按 `idle → checkingPermission → capturingTarget → previewing(ready) → applying → recoverable → ended` 完整路径转换，并且只发生一次替换；
2. 新会话取代旧会话后只保留一个 current session ID，旧 session 的权限与捕获 callback 均无效；
3. `previewing(ready)` 且用户尚未确认时，替换和恢复 setter 合计调用次数为 0；
4. 取消后进入 `ended`，直接写入次数和剪贴板写入次数均为 0；
5. `clipboardInput` 只提供复制结果和取消，调用确认也不能触发直接替换；
6. 恢复前验证失败后从 `recoverable` 进入 `previewing(recoveryUnavailable)`，只提供复制原文和关闭，重复确认或恢复不得产生第二次直接写入；
7. `recoveryUnavailable` 中复制原文只进行一次显式剪贴板写入，随后关闭不会增加任何直接写入或剪贴板写入。

测试通过注入式 target、pasteboard 和 state observer spy 精确记录状态与副作用次数。短暂的 `applying` 状态由 observer 验证，不要求生产代码暴露测试专用历史数组。

## RED 执行结果

命令：

```text
./scripts/unit-tests.sh
```

连续两次结果：exit 65，`TEST FAILED`。`arm64` 与 `x86_64` 测试目标均发现并编译新测试文件，核心诊断为：

```text
Cannot find type 'InteractionSessionCoordinator' in scope
Cannot find type 'SessionTextTargetAccessing' in scope
Cannot find type 'SessionPasteboardAccessing' in scope
Cannot find type 'SessionStateObserving' in scope
Cannot find type 'SessionContent' in scope
Cannot find type 'InteractionSessionState' in scope
```

其余状态、动作和 `CaptureMode` 的上下文推断诊断均是上述缺失 T-014 契约的级联结果。测试源已单独通过 Swift parse，既有 T-001 至 T-012 生产源没有新的编译诊断。

## 绿色控制

- `xcrun swiftc -parse Tests/SystemInteractionFoundationTests/InteractionSessionCoordinatorTests.swift`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `git diff --check`：PASS

首次在受限沙箱内调用 Xcode 时，DerivedData 与 CoreSimulator 服务访问被操作系统拒绝；在获准的完整 Xcode 环境重跑后，工程结构与生产构建均通过，因此该环境噪声不计为产品或测试失败。

## 范围与解除条件

- 没有修改 `Sources/`；
- 没有实现 `InteractionSessionCoordinator`、会话状态、动作、协议或任何生产行为；
- 没有执行 T-014 或任何后续任务；
- 只有 T-014 的最薄协调器实现使七项契约测试全部编译并通过后，单元测试才可恢复绿色并达成 C2。
