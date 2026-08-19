# T-018 剪贴板策略与适配器转绿证据

## 实现边界

- 新增 `ClipboardPolicy`，仅把用户明确触发的“从剪贴板读取”“复制结果”“复制原文”路由到剪贴板依赖。
- 新增 `PasteboardAccessing` 作为可计数的测试边界；普通预览、取消与 Secure Event Input 拒绝事件均为零剪贴板访问。
- 新增 `SystemPasteboardClient`，只通过 `NSPasteboard.general` 读写 `.string`。
- 每次显式写入均先调用 `prepareForNewContents(with: .currentHostOnly)`，随后只调用一次 `setString`。
- Swift SDK 中该类型实际命名为 `NSPasteboard.ContentsOptions.currentHostOnly`；它对应任务中所述的 `NSPasteboard.WritingOptions.currentHostOnly` 写入隐私语义。
- 未加入后台轮询、`changeCount` 观察、自动读取、模拟按键/粘贴、AX 写入或 T-019 之后的能力。

## 自动验证

执行两次：

```text
./scripts/unit-tests.sh
```

两次结果一致：

- `ClipboardPolicyTests`：6 项通过，0 失败。
- 全套单元测试：43 项通过，0 失败。
- `TEST SUCCEEDED`。

其余验证：

```text
./scripts/build.sh
./scripts/project-structure-check.sh
./scripts/sdd-check.sh
./scripts/secret-scan.sh
xcrun swiftc -parse Sources/SystemInteractionFoundation/ClipboardPolicy.swift
plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj
git diff --check
```

结果：全部通过，构建为 `BUILD SUCCEEDED`，未发现凭据模式或工程结构问题。

源码审计确认新增实现不含 `changeCount`、计时器/轮询、`CGEvent`、按键发送或模拟粘贴路径。

## 结论

T-017 定义的显式访问次数和 `currentHostOnly` 隐私约束已由最薄实现满足，T-018 完成。未执行 T-019。
