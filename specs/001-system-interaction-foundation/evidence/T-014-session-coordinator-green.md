# T-014 会话协调器 GREEN 证据

## 结论

T-014 已以最薄纯 Swift 实现使 T-013 的会话状态机与副作用契约全部转绿。实现只包含领域状态、动作、会话内容、三个依赖协议和 `@MainActor InteractionSessionCoordinator`，没有接入 AppKit、Accessibility、网络、持久化或正式界面。

canonical 单元测试在实现与清理顺序自查后各运行一次，两次均执行 30 项测试、0 failure；其中 T-013 的 7 项协调器测试全部通过。C2 的当前领域安全不变量已成立。

## 实现范围

- `InteractionSessionID` 使用随机 UUID；
- 主状态限定为 `idle`、`checkingPermission`、`capturingTarget`、`previewing`、`applying`、`recoverable`、`ended`；
- T-013 当前使用的 capability 为 `ready`、`writeFailed`、`recoveryUnavailable`；
- 依赖通过 `SessionTextTargetAccessing`、`SessionPasteboardAccessing`、`SessionStateObserving` 注入；
- 直接会话只有 `previewing(ready)` 且非 `clipboardInput` 才能调用一次替换；
- clipboard 输入只暴露复制结果和取消，确认动作无副作用；
- 恢复验证失败后只暴露复制原文和关闭，后续确认或恢复均无直接写入；
- 所有 callback 同时核对 current session ID 和预期状态，旧 session callback 直接忽略；
- 新会话先移除旧 session ID 和内容引用并发布 `ended`，再生成新 UUID；
- 取消、关闭或恢复成功时先把 session ID 与 `SessionContent` 置空，再发布 `ended`。

最后两项保证协调器不再持有原文和转换结果。Swift `String` 不提供内存取证级安全擦除，因此本实现只声明释放应用持有的引用，不声明底层字节立即覆写。

## 自动测试

命令：

```text
./scripts/unit-tests.sh
```

两次结果均为：

```text
Test Suite 'InteractionSessionCoordinatorTests' passed
Executed 7 tests, with 0 failures
Test Suite 'All tests' passed
Executed 30 tests, with 0 failures
TEST SUCCEEDED
```

测试目标构建为 `arm64` 与 `x86_64` universal binary。覆盖完整状态路径、单一活动会话、旧 callback 隔离、确认前零 setter、取消零写入/零剪贴板、clipboardInput 禁止直接替换、恢复不可用后的动作矩阵及禁止再次写入。

## 其他检查

- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `./scripts/sdd-check.sh`：PASS
- `./scripts/secret-scan.sh`：PASS
- `xcrun swiftc -parse Sources/SystemInteractionFoundation/InteractionSessionCoordinator.swift`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `git diff --check`：PASS

## 范围确认

- 未执行 T-015；
- 未实现 Accessibility 权限流程或系统设置跳转；
- 未接入真实 AX target、NSPasteboard 或 panel；
- 未增加 UI、网络、持久化、AI 或提示词功能；
- 未修改 T-013 测试以降低要求。
