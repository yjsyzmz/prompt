# T-009 最小面板探针绿色证据

## 结论

T-009 已实现 T-008 失败测试要求的最小生产边界，8 个 panel/geometry probe 测试全部转绿，完整单元测试套件 16/16 通过。

本任务没有执行 T-010 人工兼容性验证，没有展示真实面板，没有创建正式界面，也没有提前实现 T-025/T-026 的正式屏幕坐标转换器或面板控制器。

## 最小实现

`Sources/SystemInteractionFoundation/PanelProbeAdapters.swift` 提供：

- `PanelProbeFactory`：创建带 `.nonactivatingPanel` style mask 的 floating `NSPanel`，设置 `hidesOnDeactivate=false`、`becomesKeyOnlyIfNeeded=true`、`.canJoinAllSpaces` 和 `.fullScreenAuxiliary`。
- `NonactivatingPanelPresenter`：展示路径只调用 `orderFrontRegardless()`，不调用 `makeKeyAndOrderFront`，也不激活应用。
- `PanelProbeGeometry`：按 range → element → window → target display → active display 解析锚点；按锚点最大相交面积选择显示器；普通空间收敛至 `visibleFrame`，全屏空间收敛至 `frame`，并保留固定安全边距。
- 几何全程使用 AppKit point 坐标；`backingScaleFactor` 作为探针显示器元数据保留，但不重复放大坐标或 panel size。

该源文件只接入 `SystemInteractionFoundation` 与 `SystemInteractionFoundationTests` 两个目标。没有增加依赖、entitlement、网络、持久化、剪贴板或内容读取能力。

## SwiftUI 边界说明

`tasks.md` 的 T-009 原始描述提到“最小 SwiftUI 占位内容”，但 T-008 没有为占位内容建立失败测试，且本次用户授权明确限定为“只实现 T-008 要求的最小 factory、展示边界与 probe geometry”。依据测试优先约束，本任务没有添加未被 T-008 驱动的 SwiftUI 内容；正式最小内容仍由 T-027/T-028 的测试与实现任务负责。

## 自动测试

执行：

```text
./scripts/unit-tests.sh
```

结果：

- exit code：`0`
- `PanelGeometryProbeTests`：8/8 通过，0 failures
- `HotKeySecureInputProbeTests`：7/7 通过，0 failures
- `ProjectStructureTests`：1/1 通过，0 failures
- 完整套件：16/16 通过，0 failures
- Xcode 结论：`TEST SUCCEEDED`

T-008 覆盖的结构配置、非激活展示调用、锚点后备、四侧边缘、负坐标、副显示器、不同缩放与全屏 frame 场景均已转绿。

## 基线验证

- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `./scripts/sdd-check.sh`：PASS
- `./scripts/sdd-check.sh --self-test`：PASS
- `./scripts/secret-scan.sh`：PASS
- `./scripts/secret-scan.sh --self-test`：PASS
- `git diff --check`：PASS

## 范围与剩余风险

- 自动测试只能证明工厂属性、展示调用边界和合成几何；不能证明真实应用与真实 Space 中的焦点行为。
- 未在 TextEdit、Chrome/ChatGPT、单屏、多屏、全屏、边缘位置或非默认缩放环境展示和观察面板。
- 未执行 T-010 或任何后续任务。
- C1 高风险假设尚未完成，必须等待 T-010 人工停止条件探针。

## 下一步

下一项是 T-010：只执行单屏、多屏、全屏、屏幕边缘与非默认缩放下的人工面板停止条件探针，并验证 TextEdit 与 Chrome/ChatGPT 中保持目标焦点且面板完整可见。T-010 需要新的用户明确授权；本任务在此停止。

## T-010 进展记录

T-010 获得单独授权后已执行真实多屏、边缘、全屏、非默认缩放及 TextEdit、Chrome/ChatGPT 探针，结果记录于 `evidence/T-010-panel-stop-conditions-partial.md`。由于当前 Mac 连接 HP E223，且未能通过可访问的系统控件安全停用副屏，真正的物理单显示器配置尚未覆盖；T-010 保持未完成，C1 尚未达成。
