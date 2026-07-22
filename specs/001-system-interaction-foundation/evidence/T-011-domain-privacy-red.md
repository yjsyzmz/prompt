# T-011 领域值与隐私契约 RED 证据

## 结论

T-011 已完成预期失败测试的定义与执行。canonical 单元测试连续两次以 exit 65 失败；失败只来自 T-012 尚未实现的领域契约，没有加入生产 stub、跳过测试或范围外实现。

本任务保持测试优先边界：生产应用构建、工程结构和项目文件语法仍为绿色，但完整单元测试必须保持 RED，直到 T-012 提供最薄领域实现。

## 基线

- RED 起点 SHA：`5009b10654198bea7f672c67dcbcb3eecc33513b`
- 平台：macOS 26.5.2，Xcode 26.6，Swift 6
- 测试文件：`Tests/SystemInteractionFoundationTests/DomainValuePrivacyContractTests.swift`
- 测试目标：`SystemInteractionFoundationTests`
- 合成标识：仅 `SYNTHETIC-001` 系列，不含真实用户内容或类似凭据的字符串

## 已定义契约

### 确定性转换

- 固定前缀必须精确为 `【系统交互验证】\n`；
- 中文、英文、中英混合、纯空白、多行、Emoji／组合字符／标点与转义字符逐字符保真；
- 10,000 字符合成输入不截断；
- 去除固定前缀后的结果必须与输入完全相等。

### 错误映射

- 覆盖 Plan 中的快捷键、权限、安全输入、空输入、不支持目标、AX 超时／无法完成、目标失效、原文变化、属性不可写、写入失败、恢复目标变化、剪贴板读写失败和面板定位后备类别；
- 每个已知类别必须产生非空的可理解说明和至少一个对应安全动作；
- 未知错误必须 fail-closed、提供安全下一步，并且不得暴露原始 `AXError`、`OSStatus` 或数值错误码。

### 隐私契约

- `SourceText`、`TransformedText`、`TargetSnapshot` 和 `RecoverySnapshot` 不得符合 `Encodable` 或 `Decodable`；
- `DomainFailure` 的全部类别不得携带 `String`／`Substring` 存储；
- `PrivacySafeLogEvent` 只接受类别、状态与无内容失败类型，不得具有文字存储；
- 错误展示、错误描述和日志事件不得出现合成内容标识。

## RED 执行结果

命令：

```text
./scripts/unit-tests.sh
```

连续两次结果：exit 65，`TEST FAILED`。两个架构的测试目标都在编译新测试文件时失败，核心诊断为：

```text
Cannot find 'SourceText' in scope
Cannot find 'DeterministicTransformer' in scope
Cannot find type 'DomainFailure' in scope
Cannot find type 'RecoveryAction' in scope
Cannot find 'DomainFailureMapper' in scope
Cannot find 'TransformedText' in scope
Cannot find 'TargetSnapshot' in scope
Cannot find 'RecoverySnapshot' in scope
Cannot find 'PrivacySafeLogEvent' in scope
```

这些符号全部属于 T-012 的最薄领域实现。测试源已另行通过 `xcrun swiftc -parse`，因此 RED 不是 Swift 语法错误。

## 绿色控制

- `xcrun swiftc -parse Tests/SystemInteractionFoundationTests/DomainValuePrivacyContractTests.swift`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS

RED 起点 SHA 的 GitHub `unit-tests` 已通过，证明既有测试基线在加入 T-011 前为绿色。当前预期失败不得通过修改 CI 或排除新文件来绕过。

## 范围与解除条件

- 没有修改 `Sources/`；
- 没有实现任何领域值、错误映射、转换器、日志类型、协议或产品行为；
- 没有执行 T-012 或任何后续任务；
- 只有 T-012 的最薄实现使上述契约全部编译并通过后，单元测试才可恢复绿色。
