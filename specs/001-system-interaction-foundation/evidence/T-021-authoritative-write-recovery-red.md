# T-021 权威重新验证、写入与恢复 RED 证据

## 结论

T-021 已完成失败优先测试的定义与执行。canonical 单元测试连续两次以 exit 65 失败；arm64 与 x86_64 均发现并编译新测试，失败只来自 T-022 尚未实现的权威目标访问协议、写入快照、恢复上下文以及 `AccessibilityGateway` 写入/恢复入口。没有新增或修改任何 `Sources/` 文件，也没有执行真实 AX 写入或恢复。

生产应用构建、工程结构、测试源语法和仓库门禁仍为绿色。完整单元测试必须保持 RED，直到 T-022 提供最薄的权威重新验证、单次 setter 与恢复实现。

## 基线

- RED 起点父 SHA：`f510590ba9f536619eb5d24c2635953d76ef66f9`
- 平台：macOS 26.5.2，Xcode 26.6，Swift 6
- 测试文件：`Tests/SystemInteractionFoundationTests/AXAuthoritativeWriteRecoveryTests.swift`
- 测试目标：`SystemInteractionFoundationTests`
- 测试只使用带 `SYNTHETIC-001` 标识的非敏感合成文字

## 已定义契约

新增十四项失败优先测试：

1. selected replacement 严格按固定顺序完成全部权威检查，并且只调用一次 selected setter；
2. whole-field replacement 只调用一次 whole-field setter，不调用 selected setter；
3. 目标应用已停止时在第一项检查后 fail-closed；
4. 外部目标应用 PID 改变时 fail-closed；
5. 窗口身份改变时 fail-closed，且不继续检查元素；
6. 元素身份改变时 fail-closed，且不继续读取 capability；
7. read-only、secure 元素或全局 Secure Input 任一成立时均阻止 setter；
8. selected range 改变时不读取 selected text、不调用 setter；
9. selected text 改变时不调用 setter；
10. whole-field 原文改变时不调用 setter；
11. 对应替换属性不再 settable 时不调用 setter；
12. setter 失败时只尝试原 setter 一次、原文保持不变，并提供复制结果路径；
13. 成功替换后可在权威验证通过时用同一 setter 恢复原文；
14. 恢复前结果已变化时阻止任何额外 setter，并提供复制原文路径。

测试要求七项确认前权威检查在同一个 `AccessibilityGateway` actor 操作内按以下顺序完成：

1. 目标应用仍在运行且 PID 匹配；
2. 当前外部目标应用仍是原 PID；
3. AX window 与 element 身份仍匹配原目标；
4. 元素仍可编辑、不是 secure subrole，且全局 Secure Input 未启用；
5. selected 模式的 range 与 selected text 均未变化，或 whole-field 模式的全文未变化；
6. 对应 AX 属性仍可写；
7. 恢复时当前内容仍等于预期转换结果。

测试通过 `AXAuthoritativeTargetAccessing` spy 精确记录检查顺序、两个 setter 的调用次数及合成内容变化。任何检查失败都必须立即返回领域失败，且 setter 总调用次数为 0；setter 自身失败不得尝试另一种写法。

## RED 执行结果

命令：

```text
./scripts/unit-tests.sh
```

连续两次结果：exit 65，`TEST FAILED`。两个架构的测试目标均发现新测试，核心诊断为：

```text
Cannot find type 'AXAuthoritativeTargetAccessing' in scope
Cannot find type 'AXWriteSnapshot' in scope
Cannot find type 'AXRecoveryContext' in scope
Value of type 'AccessibilityGateway' has no member 'replaceAfterAuthoritativeValidation'
Value of type 'AccessibilityGateway' has no member 'restoreAfterAuthoritativeValidation'
Extra argument 'authoritativeTarget' in call
```

其余 `Equatable` 与泛型推断诊断均由上述 T-022 契约缺失级联产生。测试源已单独通过 Swift parse，既有生产源没有新的编译诊断。

## 绿色控制

- `xcrun swiftc -parse Tests/SystemInteractionFoundationTests/AXAuthoritativeWriteRecoveryTests.swift`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `./scripts/sdd-check.sh`：PASS
- `./scripts/secret-scan.sh`：PASS
- `git diff --check`：PASS
- `test -z "$(git diff --name-only -- Sources)"`：PASS

## 范围与解除条件

- 没有修改 `Sources/`；
- 没有调用真实 `AXUIElementSetAttributeValue` 或读取现实应用内容；
- 没有实现权威重新验证、生产 setter、恢复或 T-022；
- 没有尝试剪贴板写入、模拟粘贴或备用 AX setter；
- 只有 T-022 的最薄 actor 内权威重新验证、单次 AX 写入与恢复实现使十四项契约全部编译并通过后，单元测试才可恢复绿色。
