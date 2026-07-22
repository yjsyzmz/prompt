# T-024 外部目标监控 GREEN 证据

## 范围

- Parent SHA：`30951be27435e866f13520debbff8d2f88ec31cf`
- 新增最薄 `ExternalTargetMonitor.swift`，未修改 T-022 的 `AccessibilityGateway.swift` 权威重新验证与 setter。
- 未执行 T-025，未加入几何、正式界面、网络、持久化或其他产品功能。

## 实现边界

- `AXTargetMonitor` 与系统适配器位于 `@MainActor`。
- AXObserver run-loop source 挂载到 main run loop 的 common modes。
- 应用级 AX 元素监听焦点元素和焦点窗口变化；目标 AX 元素监听选区、值与销毁变化。
- `NSWorkspace.didActivateApplicationNotification` 作为额外的提前失效信号。
- 系统 callback 只构造包含 `sessionID` 与 `targetHandle` 的 `AXMonitorCallbackEnvelope`，随后通过异步 `Task` 投递给 actor receiver。
- `AXMonitorEventRouter` 只接受当前 session/target，忽略过期 callback；有效事件只能调用 `disableDirectActions`。
- `stopMonitoring()` 幂等地注销 workspace observation、移除 main run-loop source、注销 AX notifications，并释放 observer、callback box、应用与目标 AX 引用。
- 监控文件不包含替换、恢复、AX setter 或第二写入策略；最终写入授权仍只来自 T-022 的权威重新验证。

## 测试结果

首次完整运行中，5/6 个原始 T-023 行为测试通过；唯一失败是受限 XCTest 进程不能直接读取仓库源码。复用既有源码审计资源机制，把生产监控源码复制进 test bundle 后该问题消失，不涉及产品行为变化。

随后补充 workspace 投递与幂等释放两项生命周期测试，连续两次执行：

```text
./scripts/unit-tests.sh
Run 1: 76 tests, 0 failures — TEST SUCCEEDED
Run 2: 76 tests, 0 failures — TEST SUCCEEDED
```

其中 `AXObserverDeliveryIsolationTests` 共 8 项，全部通过：

1. main run loop common mode 安装；
2. envelope 只有 session/target ID；
3. AX callback 同步返回后异步进入 actor；
4. NSWorkspace 激活回调同步返回后异步进入 actor；
5. 过期 callback 被 actor 忽略；
6. 当前 callback 只能禁用直接操作；
7. 重复停止只释放一次 source 与 workspace observation；
8. 生产监控源码不含任何写入或恢复授权符号。

## 绿色门禁

```text
./scripts/build.sh                    PASS — BUILD SUCCEEDED
./scripts/project-structure-check.sh  PASS
./scripts/sdd-check.sh                PASS
./scripts/secret-scan.sh              PASS
xcrun swiftc -parse                    PASS
plutil -lint                           PASS
git diff --check                       PASS
monitor write-authority source scan    PASS — no matches
```

## 结论

T-024 已把 T-023 的预期 RED 转为稳定 GREEN，并实现主 run loop AXObserver、NSWorkspace 提前失效信号、actor 隔离、过期 callback 丢弃与显式资源释放。监控只改善按钮失效时机，不改变确认或恢复时的 fail-closed 权威检查。
