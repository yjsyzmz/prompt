# T-031 最小闭环装配 GREEN 证据

## 任务边界

- 任务：T-031 [Implementation] 完成最小闭环装配。
- 依赖：T-030 稳定 RED（见 `evidence/T-030-end-to-end-red.md`）。
- 约束：仅补齐 T-030 暴露的依赖注入、事件路由与状态同步，不加入未被失败测试要求的功能。

## 实现（严格对应 T-030 的 RED 边界）

- `Sources/SystemInteractionFoundation/SessionIntegration.swift`（新增）
  - `TargetChangeMonitoring`：会话级目标监控抽象；监控只能提前禁用界面，不授权写入（写入门禁仍是网关权威校验）。
  - `WorkspaceTargetChangeMonitor`：生产实现，复用已测试的 `NSWorkspaceActivationMonitor` 与网关的 `AXMonitorEventReceiving` 投递；元素级 `AXObserver` 挂载保留在已测试的 `AXTargetMonitor`，待真实环境验收任务接线。
  - `GatewaySessionTextTarget`：把协调器同步的 `SessionTextTargetAccessing` 契约桥接到 `AccessibilityGateway` actor。通过 detached task + 信号量短暂驻留主线程完成权威校验与单次写入；网关从不跳回主 actor，不会死锁。恢复上下文由成功写入产生，失败时保持 fail-closed。
- `Sources/SystemInteractionFoundation/AccessibilityGateway.swift`（三个最小新增方法）
  - `deactivateMonitoring(for sessionID:)`：仅当活跃监控信封属于该会话时才注销，避免旧会话清理与新会话激活竞争。
  - `authoritativePID(for targetHandle:)`：优先权威适配器的前台 PID，回退到保留 AX 引用的 PID。
  - `releaseTarget(_:)`：会话结束后释放保留的 AX 引用。
- `Sources/SystemInteractionFoundation/AppLifecycleController.swift`
  - 装配注入改为 `gateway:` + `targetMonitor:`；会话文字目标由内部 `GatewaySessionTextTarget` 承担（替代 T-028 的 `FailClosedSessionTextTarget` 占位）。
  - 捕获路由：`protectedReadDidBegin` → `permissionResolved` → 可等待的 `captureWork`（`gateway.capture` → PID → `beginSession` → 激活监控 → `captureCompleted`），每步校验会话仍然有效，失败按 `DomainFailure` 映射到 `secureInput` / `permissionRequired` / `emptyOrUnsupported` 并结束会话。
  - 监控路由：`MonitorInvalidationBridge` 把网关的失效回调跳回主 actor；仅当会话、句柄匹配且处于 `previewing(.ready)` 时展示 `staleTarget`（只禁按钮，不改写入门禁）。
  - 状态同步：`recoverable` 展示"恢复原文/复制结果/关闭"；`ready` 按 `coordinator.availableActions` 过滤确认按钮（剪贴板输入永不提供直接替换）；`ended` 走 `finishSession`——清空敏感引用、停监控、关面板，并在可等待的 `cleanupWork` 中按会话注销监控与释放 AX 句柄。
  - 生产 `convenience init()`：`AccessibilityGateway(captureReader: SystemAXCaptureReader())`（写入走网关内置的保留引用权威回退路径）+ `WorkspaceTargetChangeMonitor`。

## 验证结果

- `./scripts/unit-tests.sh` 连续两次：PASS，109 tests, 0 failures（98 既有 + 11 个 T-030 端到端集成测试，arm64+x86_64）。
- `./scripts/build.sh`：exit 0（universal Debug 构建）。
- `./scripts/project-structure-check.sh`：exit 0。
- `./scripts/sdd-check.sh`：exit 0。
- `./scripts/secret-scan.sh`：exit 0。
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：OK。
- `git diff --check`：无空白错误。

## 已知限制（待 P5 真实环境验收）

- 生产目标监控当前只覆盖应用切换（workspace activation）；元素/窗口级 `AXObserver` 通知的接线将在 T-032/T-033 真实闭环验证中按需补齐（`AXTargetMonitor` 与 run-loop 调度器已在 T-023/T-024 完成并测试）。
- `recoverable` 状态的中文文案是 T-031 的最小组合展示，不属于 T-027 冻结的七状态矩阵；最终视觉系统仍在 001 范围之外。
- 真实应用中的完整读-预览-写-恢复闭环、性能与隐私证据属于 T-032 至 T-039，需要辅助功能授权与人工操作。
