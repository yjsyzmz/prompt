# T-017 剪贴板显式访问策略 RED 证据

## 结论

T-017 已完成预期失败测试的定义与执行。canonical 单元测试连续两次以 exit 65 失败；失败只来自 T-018 尚未实现的剪贴板策略、访问协议与本机写入隐私契约。没有新增或修改任何 `Sources/` 文件，也没有读取、写入或观察真实剪贴板。

生产应用构建、工程结构、测试源语法和 Xcode 项目文件仍为绿色。完整单元测试必须保持 RED，直到 T-018 提供最薄剪贴板策略与适配器实现。

## 基线

- RED 起点父 SHA：`f5a53366d900c70a484e8bf52b7dd7fa6759d0ee`
- 平台：macOS 26.5.2，Xcode 26.6，Swift 6
- 测试文件：`Tests/SystemInteractionFoundationTests/ClipboardPolicyTests.swift`
- 测试目标：`SystemInteractionFoundationTests`
- 测试只使用带 `SYNTHETIC-001` 标识的非敏感合成文字

## 已定义契约

新增六项失败优先测试：

1. 普通预览出现后取消，剪贴板读取和写入次数均为 0；
2. 普通预览本身不产生任何剪贴板读取或写入；
3. Secure Input 拒绝路径不产生任何剪贴板读取或写入；
4. 只有 `readFromClipboardAfterExplicitAction()` 才触发恰好一次读取且零写入；
5. 只有 `copyResultAfterExplicitAction(_:)` 才触发恰好一次结果写入且零读取；
6. 只有 `copyOriginalAfterExplicitAction(_:)` 才触发恰好一次原文写入且零读取。

两项写入测试都精确断言写入记录携带 `.currentHostOnly`。测试通过注入的 `PasteboardAccessing` spy 统计读写次数并记录写入值与隐私选项，不接触 `NSPasteboard.general`。

## RED 执行结果

命令：

```text
./scripts/unit-tests.sh
```

连续两次结果：exit 65，`TEST FAILED`。`arm64` 与 `x86_64` 测试目标均发现并编译新测试文件，核心诊断为：

```text
Cannot find type 'ClipboardPolicy' in scope
Cannot find type 'PasteboardAccessing' in scope
Cannot find type 'PasteboardWritePrivacy' in scope
```

`Record` 的 `Equatable` 合成和 `.currentHostOnly` 上下文推断诊断均为 `PasteboardWritePrivacy` 缺失造成的级联结果。测试源已单独通过 Swift parse，既有 T-001 至 T-016 生产源没有新的编译诊断。

## 绿色控制

- `xcrun swiftc -parse Tests/SystemInteractionFoundationTests/ClipboardPolicyTests.swift`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `./scripts/sdd-check.sh`：PASS
- `./scripts/secret-scan.sh`：PASS
- `git diff --check`：PASS

## 范围与解除条件

- 没有修改 `Sources/`；
- 没有导入、调用或封装 `NSPasteboard`；
- 没有观察 `changeCount`、后台轮询、自动读取或模拟 Command-C/Command-V；
- 没有执行 T-018 或任何后续任务；
- 只有 T-018 的最薄策略和生产适配器使上述六项契约全部编译并通过后，单元测试才可恢复绿色。
