# T-023 AXObserver 投递与隔离 RED 证据

## 范围

- Parent SHA：`9a7e7f3e641d07d82d3ad1f9a6a6e638ba0a16c3`
- 只新增 `AXObserverDeliveryIsolationTests` 并注册到测试 target。
- 未修改 `Sources/`，未创建 `ExternalTargetMonitor.swift`，未实现 `AXObserver`、`NSWorkspace` 或 T-024 生产监控代码。

## 预期失败契约

新增 6 项测试，要求后续最薄实现证明：

1. observer run-loop source 仅在 main run loop 的 common mode 安装一次；
2. callback envelope 只有 `sessionID` 与 `targetHandle`；
3. 系统 callback 同步返回后，事件才异步进入 actor；
4. actor 内忽略过期 session 或 target 的 callback；
5. 当前 callback 只能请求提前禁用直接操作；
6. 生产监控不得持有替换、AX setter 或恢复授权。

## RED 运行

测试自身的 async XCTest autoclosure 编译问题已先修正；该次运行不计入 RED 证据。修正后连续执行两次：

```text
./scripts/unit-tests.sh
Run 1: exit 65
Run 2: exit 65
```

两次均在 arm64 与 x86_64 编译新增测试，并稳定因尚未实现的 T-024 契约失败：

- `AXObserverRunLoopMode`
- `AXObserverRunLoopScheduling`
- `AXMonitorEventReceiving`
- `AXMonitorCallbackEnvelope`
- `AXMonitorInvalidationReceiving`
- `AXTargetMonitor`
- `AXMonitorEventRouter`

后续出现的 `.common`、`[Any]` Equatable 与无 async operation 诊断均是上述缺失类型引起的级联诊断，不是独立测试错误。

## 绿色控制检查

```text
./scripts/build.sh                    PASS — BUILD SUCCEEDED
./scripts/project-structure-check.sh  PASS
./scripts/sdd-check.sh                PASS
./scripts/secret-scan.sh              PASS
xcrun swiftc -parse AXObserverDeliveryIsolationTests.swift  PASS
plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj  PASS
git diff --check                      PASS
git diff --name-only -- Sources       empty
```

## 结论

T-023 已建立稳定、可复现的 RED 边界：当前失败仅要求 T-024 提供投递与隔离契约。监控是建议性的提前失效信号，不能替代确认时的权威重新验证，也不能授权写入或恢复。
