# T-030 端到端集成测试 RED 证据

## 任务边界

- 任务：T-030 [Test] 编写端到端集成测试（失败优先）。
- 依赖：T-006、T-016、T-018、T-022、T-024、T-026、T-028、T-029 均已通过。
- 目标：以 T-029 合成宿主和 spy 驱动完整生产装配，先建立稳定 RED，边界由缺失的 T-031 集成契约构成。

## 测试内容

`Tests/SystemInteractionFoundationTests/EndToEndIntegrationTests.swift`（11 个测试，全部 `@MainActor` 异步驱动真实 `AppLifecycleController` + `AccessibilityGateway` + `InteractionSessionCoordinator`）：

1. **完整闭环**：快捷键→权限→读取→预览（ready）→确认→单次写入（选区外字节不变）→恢复原文→会话结束清理；结束后过期监控回调被忽略。
2. **取消**：零写入、零剪贴板读写、面板关闭、监控停止。
3. **复制结果**：恰好一次 `currentHostOnly` 剪贴板写入，零 setter。
4. **安全输入**：拒绝并展示安全输入文案，零内容读取、零 setter、零剪贴板。
5. **权限缺失**：展示权限文案，零内容读取。
6. **空目标**：展示"空或不支持"文案，零 setter。
7. **过期目标**：窗口切换 + 监控事件 → staleTarget 文案且确认不可用；仍强行确认时由权威校验拦截（`writeFailed`，setter 保持 0）——监控只禁用按钮，不授权写入。
8. **写入失败**：可控 setter 失败 → writeFailed 文案、原文不变、结果仍可复制。
9. **恢复不可用**：确认后结果被外部修改 → 恢复校验失败不再写入（setter 仍为 1）、recoveryUnavailable 文案、复制原文恰好一次、关闭结束。
10. **新会话替代**：第二次快捷键结束旧会话、重启监控，旧会话监控回调被忽略。
11. **剪贴板输入**：预览不提供确认替换按钮，确认动作零 setter。

每条相关路径都断言确认前 `setterAttemptCount == 0`。

## RED 边界（缺失的 T-031 集成契约）

编译失败完全由以下缺失成员构成，无既有测试回归：

- `AppLifecycleController` 缺少 `gateway:`、`targetMonitor:` 装配注入（现构造仍要求 `textTarget:`）；
- `AppLifecycleController` 缺少可等待的 `captureWork` / `cleanupWork` 集成任务句柄；
- 缺少 `TargetChangeMonitoring` 目标监控抽象。

## 复现结果

- `./scripts/unit-tests.sh` 第一次：exit 65（编译失败，errors 仅指向上述缺失契约）
- `./scripts/unit-tests.sh` 第二次：exit 65（同样 34 条 error 输出，稳定复现）
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：OK
