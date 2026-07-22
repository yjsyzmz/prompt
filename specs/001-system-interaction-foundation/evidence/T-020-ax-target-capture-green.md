# T-020 AX 目标捕获转绿证据

## 实现边界

- 新增 `AccessibilityGateway` actor，按随机 `TargetHandle` 在 actor 隔离内保留不透明 `AXTargetReference`；领域返回值不包含原始 `AXUIElement`，也不采用 `Codable`。
- 新增 `AXTextRange`、`AXFocusedElementCapability`、`AXCapturedTarget`、`AXCaptureReading` 与 `AXSourceTextCreating` 最小契约。
- 新增只读 `SystemAXCaptureReader`，通过 `AXUIElementCreateSystemWide` 获取当前 focused element，只调用 AX copy/query API。
- `CaptureMode` 仅补充 T-019 所需的 `selectedText(AXTextRange)`。
- 未实现 AX setter、目标重新验证、恢复、observer、模拟输入、剪贴板、UI、持久化或 T-021 行为。

## 固定捕获顺序

1. 查询 focused element；
2. 先读取 subrole，secure element 立即返回 `secureInputActive`；subrole 查询错误 fail-closed；
3. 通过 `AXUIElementIsAttributeSettable` 与 role 区分 editable、read-only 和 unsupported；
4. 读取 selected range；
5. range 长度大于 0 时只读取 selected text，否则读取完整 value；
6. 空字符串返回 `emptySource`，纯空白保持合法；
7. 尝试读取 range bounds，几何不可用不升级为内容失败；
8. 最后创建 `SourceText`、随机 handle，并由 actor 保留原始目标引用。

内容读取错误映射到已有 `DomainFailure` 并 fail-closed，不在 selected text 失败后回退全文。

## 自动验证

`./scripts/unit-tests.sh` 在最终实现上连续两次通过：

- `AXTargetCaptureTests`：11 项通过，0 失败；
- 全套单元测试：54 项通过，0 失败；
- arm64 与 x86_64 均完成编译；
- `TEST SUCCEEDED`。

其余验证：

```text
./scripts/build.sh
./scripts/project-structure-check.sh
./scripts/sdd-check.sh
./scripts/secret-scan.sh
xcrun swiftc -parse Sources/SystemInteractionFoundation/AccessibilityGateway.swift Sources/SystemInteractionFoundation/InteractionSessionCoordinator.swift
plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj
git diff --check
```

结果全部通过，生产构建为 `BUILD SUCCEEDED`。

## 禁止能力审计

新增生产文件不存在以下符号或依赖：

- `AXUIElementSetAttributeValue`；
- `AXObserver`；
- `CGEvent` 或模拟按键；
- `NSPasteboard`；
- `Codable`、`UserDefaults`、`FileManager` 或 `URLSession`。

生产 reader 仅出现 `AXUIElementCopyAttributeValue`、`AXUIElementCopyParameterizedAttributeValue`、`AXUIElementIsAttributeSettable`、`AXValueCreate` 与 `AXValueGetValue`。

## 结论

T-019 的十一项 AX 捕获契约已由最薄 T-020 实现转绿，全套测试与生产构建通过。未执行 T-021。
