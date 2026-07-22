# T-022 权威重新验证、写入与恢复 GREEN 证据

## 结论

T-022 已实现 T-021 要求的最薄权威重新验证、单次 AX 写入与恢复。T-021 的十四项契约测试全部转绿；完整 68 项单元测试连续两次通过，arm64 与 x86_64 均成功编译。生产构建与仓库门禁为绿色。

实现严格停留在 T-022：没有新增 `AXObserver`、目标监控、剪贴板访问、模拟粘贴、清空、全选、分段写入或备用 setter，也未执行 T-023。

## 基线

- 实现起点父 SHA：`c9e3d2f96d8855437bb14a7a69a4c50a1c11504f`
- 平台：macOS 26.5.2，Xcode 26.6，Swift 6
- 生产实现：`Sources/SystemInteractionFoundation/AccessibilityGateway.swift`
- 驱动测试：`Tests/SystemInteractionFoundationTests/AXAuthoritativeWriteRecoveryTests.swift`
- 所有自动测试文字均为带 `SYNTHETIC-001` 标识的非敏感合成内容

## 实现内容

新增不可序列化且可跨 actor 安全传递的内存值：

- `AXWriteSnapshot`：目标 handle、PID、捕获模式、原文和转换结果；
- `AXRecoveryContext`：目标 handle、PID、捕获模式、原文和预期转换结果；
- `AXAuthoritativeTargetAccessing`：用于对固定顺序、失败路径和 setter 次数进行独立测试的权威访问边界。

`AccessibilityGateway` actor 在确认写入与恢复时串行执行：

1. 目标应用仍运行且 PID 匹配；
2. 当前外部目标应用 PID 未变化；
3. window 与 element 身份仍匹配 actor 保存的原始 AX 引用；
4. 元素仍可编辑、不是 secure subrole，且全局 Secure Event Input 未启用；
5. selected 模式的 range 与 selected text 未变化，或 whole-field 的全文未变化；
6. 对应属性仍可设置；
7. 恢复时当前位置内容仍等于 expected transformed text。

任一检查失败立即返回领域错误，setter 调用数为 0。只有全部检查通过后才执行写入：

- selected 模式只调用一次 `kAXSelectedTextAttribute` setter；
- whole-field 模式只调用一次 `kAXValueAttribute` setter；
- setter 失败返回失败，不尝试另一属性或第二种直接写入；
- 成功替换才创建恢复上下文；
- 恢复前结果变化时不写入，并保留复制原文的安全路径。

生产 AX 路径继续由 actor 持有 target handle 到 element/window/PID 的映射。`SystemAXCaptureReader` 仅在捕获时把原始引用、window 与 PID 交给 actor，不向领域层、日志或持久化暴露用户内容或 AX 引用。

## 测试结果

命令：

```text
./scripts/unit-tests.sh
```

连续两次结果：

```text
Executed 68 tests, with 0 failures (0 unexpected)
TEST SUCCEEDED
```

其中 `AXAuthoritativeWriteRecoveryTests` 的十四项全部通过，证明：

- 七项检查具有预期顺序并 fail-closed；
- 应用、外部 PID、window、element、capability、Secure Input、range、内容或 settable 状态变化均不会触发 setter；
- selected 与 whole-field 只使用各自唯一 setter；
- setter 失败不改变合成原文且保留复制结果路径；
- 成功写入后可以恢复；
- 恢复前结果变化时零额外 setter 且保留复制原文路径。

## 绿色控制

- `./scripts/unit-tests.sh`：连续两次 PASS，68/68
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/sdd-check.sh`：PASS
- `./scripts/secret-scan.sh`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `xcrun swiftc -parse ...`：PASS
- `git diff --check`：PASS

## 范围审计

- 没有修改 T-021 测试来制造绿色；
- 没有加入 `AXObserver`、`NSWorkspace` 监控或 session callback；
- 没有自动或后台剪贴板访问；
- 没有清空、全选、模拟粘贴、分段写入或备用 setter；
- 没有日志、文件、网络、持久化或真实用户内容；
- T-023 及后续任务未执行。
