# T-028 预览与应用生命周期装配 GREEN 证据

## 范围

- Parent SHA：`6b260951744bd6eeae54e164e1cb6e008b547362`
- 新增最薄 `PreviewPresentation.swift`、`PreviewContentView.swift`、`AppLifecycleController.swift`，并注册到应用与测试 target；`AppEntry.swift` 改为组装 `AppLifecycleController` 后运行。
- 只实现 T-027 测试要求的预览展示契约、最小 SwiftUI 内容和生命周期装配；接入已测试的确认、复制结果、取消、恢复、复制原文、打开设置、重新检测、剪贴板输入、重试和关闭动作。
- 未执行 T-029，未加入最终视觉系统、完整设置体验、网络、持久化或遥测。

## 实现

1. `PreviewPresentation.swift`：纯值类型展示模型。`PreviewStatus` 覆盖已批准的七种能力状态；`PreviewPresentationMapper` 输出与 T-027 逐字一致的中文文案和按钮矩阵；`PreviewViewState.canConfirmReplacement` 由按钮派生，只有 `ready` 暴露可用的确认替换。
2. `PreviewContentView.swift`：最小 SwiftUI 视图，只订阅不可变 `PreviewViewState` 并回发 `PreviewUserAction`，不接触 AX、剪贴板或窗口对象。`PreviewPanelController` 实现 plan.md 的 `PreviewPresenting`（`show`/`update`/`dismiss`），复用已测试的 `PanelProbeFactory`（nonactivating 面板配置）、`NonactivatingPanelController` 与 `ScreenGeometryConverter`（T-026 放置规则）。
3. `AppLifecycleController.swift`：启动/退出与依赖组装。装配已测试的 `GlobalHotKeyRegistrar`、`SecureInputGuard`、`AccessibilityPermissionFlow`、`ClipboardPolicy`、`DeterministicTransformer` 和 `InteractionSessionCoordinator`，把协调器状态映射为 `PreviewStatus` 并路由全部十个用户动作到已测试入口。
4. 动作路由：确认→`confirmReplacement()`；复制结果→`ClipboardPolicy.copyResultAfterExplicitAction`；取消→`cancel()`；恢复→`recoverOriginal()`；复制原文→`copyOriginal()`；打开设置→`openSettingsAfterExplicitAction()`；重新检测→`recheckAfterExplicitAction()`；剪贴板输入→显式读取后 `beginClipboardSession`；重试→重新触发直接会话；关闭→`close()` 或收起面板。
5. 权威 AX 写入/恢复由 `AccessibilityGateway` actor 拥有且为异步接口；其协调器集成按任务表由 T-030 端到端失败测试驱动（T-031 完成装配）。T-028 注入 fail-closed 的 `FailClosedSessionTextTarget`：确认前后都不会写入目标应用，写入请求一律拒绝并进入已测试的 `writeFailed` 呈现。
6. 快捷键使用临时 exclusive 组合（Control+Option+Command+P）装配；规格已把永久快捷键组合排除在 001 范围外。
7. 会话协调器的 nonisolated 协议由 `@preconcurrency` 一致性满足，运行时断言所有回调都在主 actor 上，与既有 `@MainActor` 会话模型一致。

## GREEN 运行

```text
./scripts/unit-tests.sh
Run 1: PASS — 89 tests, 0 failures (exit 0)
Run 2: PASS — 89 tests, 0 failures (exit 0)
```

两次运行中 `PreviewStateActionTests` 均为 5/5 通过，覆盖：

- 七种状态的已批准中文说明文案；
- 七种状态的完整按钮矩阵；
- 只有 `ready` 暴露且启用确认替换；
- 每个拒绝/失败状态至少一个可用安全下一步；
- 可见文案不含原始错误码、AX/OSStatus/NSPasteboard 标识或合成敏感标记。

## 控制检查

```text
./scripts/build.sh                    PASS — BUILD SUCCEEDED
./scripts/project-structure-check.sh  PASS
./scripts/sdd-check.sh                PASS
./scripts/secret-scan.sh              PASS
plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj  PASS
git diff --check                      PASS
```

## 已知限制

- 直接会话的目标捕获、`staleTarget` 触发与权威写入/恢复尚未接入 `AccessibilityGateway` 与 `ExternalTargetMonitor`；这些事件路由按 tasks.md 属于 T-029→T-031 的合成闭环范围。在集成前确认替换保持 fail-closed，不会修改任何目标应用。
- `recoverable` 会话状态在 T-028 不改变面板呈现；恢复动作路由已接入，其呈现由 T-030 失败测试驱动。

## 结论

T-028 已以最小生产实现使 T-027 的五个预览契约测试转绿，装配了应用生命周期与十个已测试动作，未越出任务边界。
