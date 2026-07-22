# T-019 AX 目标捕获 RED 证据

## 结论

T-019 已完成失败优先测试的定义与执行。canonical 单元测试连续两次以 exit 65 失败；arm64 与 x86_64 均发现并编译新测试，失败只来自 T-020 尚未实现的 AX 捕获 gateway、原始读取协议和值类型。没有新增或修改任何 `Sources/` 文件，也没有调用真实 `AXUIElement`、申请 TCC 权限或读取现实应用内容。

生产应用构建、工程结构、测试源语法和仓库门禁仍为绿色。完整单元测试必须保持 RED，直到 T-020 提供最薄 AX 捕获实现。

## 基线

- RED 起点父 SHA：`4e47bad3093ef80c967262d67f2303e7e63d40db`
- 平台：macOS 26.5.2，Xcode 26.6，Swift 6
- 测试文件：`Tests/SystemInteractionFoundationTests/AXTargetCaptureTests.swift`
- 测试目标：`SystemInteractionFoundationTests`
- 测试只使用带 `SYNTHETIC-001` 标识的非敏感合成文字

## 已定义契约

新增十一项失败优先测试：

1. secure 元素在任何选区、全文、边界读取和 `SourceText` 创建前被拒绝；
2. 非空选区优先，只读取选中文字，不读取全文；
3. 零长度选区回退到全文，且不读取 selected text；
4. 空字符串返回 `emptySource`，不创建内容值；
5. unsupported 元素在内容读取前被拒绝；
6. read-only 元素在内容读取前被拒绝；
7. 纯空白是合法输入，并逐字符保真；
8. 可用的 range bounds 作为可选 anchor 返回；
9. bounds 不可用不把成功捕获升级为内容失败；
10. selected text 读取错误 fail-closed，不回退全文且不创建内容值；
11. whole value 读取错误 fail-closed，不创建内容值。

测试通过 `AXCaptureReading` fake 精确记录 capability、range、selected text、full value 与 bounds 的读取次数，并通过 `AXSourceTextCreating` spy 记录敏感内容值创建次数。安全、unsupported、read-only、空内容与读取错误路径的创建次数均必须为 0。

## RED 执行结果

命令：

```text
./scripts/unit-tests.sh
```

连续两次结果：exit 65，`TEST FAILED`。两个架构的测试目标均发现新测试，核心诊断为：

```text
Cannot find 'AXTextRange' in scope
Cannot find type 'AXFocusedElementCapability' in scope
Cannot find type 'AXCapturedTarget' in scope
Cannot find type 'AccessibilityGateway' in scope
Cannot find type 'AXCaptureReading' in scope
Cannot find type 'AXSourceTextCreating' in scope
```

其余上下文推断诊断均由这些 T-020 契约缺失导致。测试源已单独通过 Swift parse，既有生产源没有新的编译诊断。

## 绿色控制

- `xcrun swiftc -parse Tests/SystemInteractionFoundationTests/AXTargetCaptureTests.swift`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `./scripts/sdd-check.sh`：PASS
- `./scripts/secret-scan.sh`：PASS
- `git diff --check`：PASS

## 范围与解除条件

- 没有修改 `Sources/`；
- 没有导入 ApplicationServices 或调用 `AXUIElement`；
- 没有读取、写入、持有或记录真实用户内容；
- 没有实现 AX 捕获、写入、observer、TCC 集成或 T-020；
- 只有 T-020 的最薄 `AccessibilityGateway` 捕获实现与生产 AX reader 使十一项契约全部编译并通过后，单元测试才可恢复绿色。
