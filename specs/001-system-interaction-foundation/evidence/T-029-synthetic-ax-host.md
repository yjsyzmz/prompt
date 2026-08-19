# T-029 合成 AX 宿主证据

## 任务边界

- 任务：T-029 [Test Harness] 建立合成 AX 宿主。
- 依赖：T-004（构建基线）、T-020（`AccessibilityGateway` 捕获实现）均已通过。
- 约束：只使用 `SYNTHETIC-001` 合成文字；宿主不读取真实应用内容，不把内容写入日志或测试产物。

## 实现

- `Tests/SystemInteractionFoundationTests/SyntheticAXHostFixtures.swift`：`SyntheticAXTextHost`，一个进程内合成宿主，同时实现网关的两个协议 `AXCaptureReading` 与 `AXAuthoritativeTargetAccessing`，让真实的 `AccessibilityGateway` actor 在不接触任何真实应用的情况下跑完整的捕获与权威写入/恢复管线。
- 夹具覆盖任务要求的全部八类场景：
  - 选区：`selectionFixture()`（前缀/选中段/后缀三段模型，可断言选区外字节不变）
  - 全文：`wholeFieldFixture()`（零长度选区回退全文）
  - 空值：`emptyFixture()`
  - 只读：`readOnlyFixture()`
  - 安全输入：`secureInputFixture()`（capability=.secure 且全局安全输入开启）
  - 元素失效：`invalidateElement()`（元素代数自增，身份校验失败）
  - 窗口切换：`switchWindow()`（窗口代数自增）
  - 可控 setter 失败：`failNextSetterAttempts(_:)`（按次注入失败，计数 `setterAttemptCount`）
- 合成语义与 T-021 权威 fake 保持一致：选区标识在写入后保持稳定，选中内容由 `segment` 表示；身份快照在捕获时（`focusedElementCapability()`）记录。
- 所有夹具文字均带 `SYNTHETIC-001` 标记；宿主为纯内存状态（`NSLock` 保护），无任何日志输出或真实内容来源。
- 决策：合成宿主实现为进程内夹具而非独立进程。跨进程真实 AX 需要为测试运行器授予辅助功能权限，无法在 CI 中复现；进程内夹具驱动的是同一个生产 `AccessibilityGateway` 管线，与 T-019～T-024 的既有测试策略一致。`Tests/SyntheticAXHost` 应用 target 保持 T-003 的最小占位，供 P5 真实环境验证使用。

## 自检测试

`Tests/SystemInteractionFoundationTests/SyntheticAXHostFixtureTests.swift`（9 个测试，全部通过真实网关执行）：

1. 选区夹具捕获选中合成文字与正确 `captureMode`；
2. 全文夹具回退 `wholeField`；
3. 空值夹具返回 `.emptySource`；
4. 只读夹具返回 `.unsupportedTarget` 且零 setter；
5. 安全输入夹具返回 `.secureInputActive` 且零内容读取、零 setter；
6. 元素失效阻断权威写入（`.invalidTarget`，零 setter，内容不变）；
7. 窗口切换阻断权威写入；
8. 可控 setter 失败：首次 `.writeFailed` 且全文不变，第二次成功且恰好各计一次；
9. 全部夹具内容均携带 `SYNTHETIC-001` 标记。

## 验证结果

- `./scripts/unit-tests.sh` 连续两次：PASS，98 tests, 0 failures（89 既有 + 9 新增，arm64+x86_64）。
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：OK（两个新文件仅注册到测试 target）。
