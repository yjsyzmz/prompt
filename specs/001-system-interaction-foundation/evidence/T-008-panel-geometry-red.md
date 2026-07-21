# T-008 非激活面板与显示几何探针红灯证据

## 结论

T-008 已建立 nonactivating panel 与显示几何的失败优先测试契约。新测试已加入现有 `SystemInteractionFoundationTests` 目标，并连续两次以相同原因按预期失败：T-009 尚未提供 panel factory、非激活展示边界与纯几何 probe 类型。

本任务没有创建 `NSPanel` 生产实现、几何实现、SwiftUI 内容或产品界面。当前红灯必须由后续单独授权的 T-009 转绿。

## 方案边界

采用“纯几何契约 + 可注入展示边界”：

- 可重复的 display/anchor/frame 数据验证几何，不依赖当前机器真实显示器布局。
- panel factory 的结构断言覆盖已批准 Plan 中的 AppKit 配置。
- presenter spy 只证明代码不会主动激活应用或请求 panel 成为 key window。
- TextEdit、Chrome/ChatGPT、真实全屏 Space 和实际焦点保持属于 T-010 人工探针；本任务不以 CI 结果替代真实兼容性证据。

没有为 T-008 新建重复设计文档。已批准的 `spec.md`、`research.md`、`plan.md` 和 `tasks.md` 已完整规定本测试方向，本任务只把既有决策转成失败测试。

## 测试契约

`Tests/SystemInteractionFoundationTests/PanelGeometryProbeTests.swift` 定义 8 个测试：

| 场景 | 关键断言 |
|---|---|
| panel 结构 | `.nonactivatingPanel`、floating、`hidesOnDeactivate=false`、`becomesKeyOnlyIfNeeded=true`、`.canJoinAllSpaces`、`.fullScreenAuxiliary` |
| 不抢焦点的展示路径 | `orderFront` 一次；应用激活和 `makeKeyAndOrderFront` 均为 0 次 |
| 后备锚点 | range → element → window → target display → active display 的固定顺序 |
| 屏幕边缘 | 四个角附近的结果均完整落在 `visibleFrame` 固定安全边距内 |
| 负坐标显示器 | 左侧负坐标屏幕保持为选中屏幕，不被错误夹到主屏 |
| 副显示器 | anchor 与副屏相交面积最大时选择副屏，并在副屏内完整可见 |
| 非默认缩放 | AppKit point 坐标和 panel size 不因 `backingScaleFactor=2` 被重复放大 |
| 全屏空间 | 使用目标显示器 `frame` 而非菜单栏/Dock 收缩后的 `visibleFrame`，panel size 保持不变 |

测试只使用合成矩形和显示器标识，不包含真实用户内容、剪贴板、截图或应用输入。

## T-009 所需的最小缺失契约

当前测试有意引用但不实现：

- `PanelProbeFactory`
- `NonactivatingPanelPresenter`
- `PanelProbeWindowPresenting`
- `PanelProbeApplicationActivating`
- `PanelProbeGeometry`
- `PanelProbeAnchorCandidates`
- `PanelProbeDisplay`
- placement 的 anchor source、display ID、confinement frame 与最终 frame

这些名称只服务于 T-009 的最小高风险 probe，不提前替代 T-025/T-026 的正式 `ScreenGeometryConverter` 和 panel controller 测试／实现。

## 可复现预期红灯

连续两次执行：

```text
./scripts/unit-tests.sh
```

两次结果一致：

- exit code：`65`
- Xcode 成功发现工程、三个目标和 `PanelGeometryProbeTests.swift`
- arm64 与 x86_64 测试编译均进入新文件
- 失败原因是 T-009 契约缺失，不是旧测试、工程发现、签名、依赖或运行时失败
- Xcode 结论：`TEST FAILED`

代表性诊断：

```text
cannot find 'PanelProbeFactory' in scope
cannot find 'NonactivatingPanelPresenter' in scope
cannot find type 'PanelProbeWindowPresenting' in scope
cannot find type 'PanelProbeApplicationActivating' in scope
cannot find 'PanelProbeGeometry' in scope
cannot find type 'PanelProbeAnchorCandidates' in scope
cannot find type 'PanelProbeDisplay' in scope
```

由上述根缺失类型派生的 contextual enum / `nil` 推断错误不另算独立故障；T-009 提供准确契约后应一起消失。

## 绿色控制项

- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，`BUILD SUCCEEDED`
- `bash -n scripts/*.sh`：PASS
- `./scripts/sdd-check.sh`：PASS
- `./scripts/sdd-check.sh --self-test`：PASS
- `./scripts/secret-scan.sh`：PASS
- `./scripts/secret-scan.sh --self-test`：PASS
- `./scripts/find-xcode-container.sh --self-test`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `git diff --check`：PASS

工程结构检查首次在受限沙箱中因为 Xcode 无法可靠读取 build settings 而错误报告 deployment target 缺失；在标准 Xcode 执行环境重跑同一命令后通过。该受限环境问题不是工程配置或 T-008 失败。

## 范围边界

- 未执行 T-009、T-010 或任何后续任务。
- 未创建或展示真实 `NSPanel`。
- 未创建 panel factory、presenter、geometry converter、SwiftUI view 或产品状态。
- 未运行 TextEdit、Chrome/ChatGPT、多显示器或全屏人工兼容性验证。
- 未修改 `Sources/` 下任何生产文件。
- 未安装依赖、增加 entitlement、读取真实内容或改变产品范围。
- 当前 `unit-tests` 红灯是 T-008 的要求，不得绕过；T-009 必须让它转绿。

## 下一步

下一项是 T-009：只实现本文件记录的最小 nonactivating `NSPanel` 与 probe geometry，使 T-008 测试转绿。T-009 需要新的用户明确授权；本任务在此停止。

## T-009 关闭记录

T-009 获得单独授权后已在 `evidence/T-009-panel-geometry-green.md` 记录绿色证据。上述 8 个失败测试现已全部通过；本文件保留为测试优先开发的红灯基线，不再代表当前分支状态。
