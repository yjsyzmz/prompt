# T-012 领域值与隐私契约 GREEN 证据

## 结论

T-012 已用一个最薄的 Foundation-only 领域文件解除 T-011 RED。完整单元测试套件执行 23 项、0 失败；其中 T-011 新增的确定性转换、错误映射与隐私契约共 7 项全部通过。

没有实现会话协调器、系统适配器、UI、网络、持久化、剪贴板或 T-013 及后续行为。

## 实现范围

生产文件：`Sources/SystemInteractionFoundation/DomainContracts.swift`

- `SourceText`、`TransformedText`：只封装当前内存中的文字，不采用 `Codable`；
- `TargetSnapshot`、`RecoverySnapshot`：只组合敏感值对象，不采用 `Codable`；
- `DeterministicTransformer`：只生成 `【系统交互验证】\n<原文>`，不解析、不规范化、不截断输入；
- `DomainFailure`：仅由无关联值的错误类别组成，不接收底层错误文本或用户内容；
- `DomainFailureMapper`：把所有已批准错误类别映射为不含原始错误码的中文说明和安全下一步；未知错误 fail-closed；
- `PrivacySafeLogEvent`：只保存日志类别、状态和无内容失败类别，不提供文字字段或日志传输行为。

实现文件仅 `import Foundation`。没有引用 AppKit、SwiftUI、AX、`URLSession`、Network、`NSPasteboard`、`UserDefaults`、`FileManager`、OSLog 或 Logger。

## T-011 契约结果

| 测试组 | 覆盖 | 结果 |
| --- | --- | --- |
| `DeterministicTransformerTests` | 中文、英文、混合、空白、多行、特殊字符与 10,000 字符逐字符保真 | 2/2 PASS |
| `ErrorMappingTests` | 15 个已知错误类别与未知错误的可理解说明、安全动作、原始码隐藏和 fail-closed | 2/2 PASS |
| `PrivacyContractTests` | 四种敏感值不可编码；错误和日志事件无文字存储 | 3/3 PASS |

完整结果：

```text
Executed 23 tests, with 0 failures (0 unexpected)
** TEST SUCCEEDED **
```

## 绿色检查

- `./scripts/unit-tests.sh`：PASS，23 tests，0 failures
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `./scripts/sdd-check.sh` 与 `--self-test`：PASS
- `./scripts/secret-scan.sh` 与 `--self-test`：PASS
- `git diff --check`：PASS
- 禁止依赖／API 扫描：仅匹配 `import Foundation`

## 范围与停止点

- 没有修改 T-011 测试来取得绿色；
- 没有实现协议适配、状态机、写入、恢复或内容清理流程；
- 没有执行 T-013；
- C2 尚未达成，仍需未来的 T-013 与 T-014。
