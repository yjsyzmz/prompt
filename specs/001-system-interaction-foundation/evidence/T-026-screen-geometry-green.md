# T-026 屏幕几何转换与面板控制器 GREEN 证据

## 范围

- Parent SHA：`4601d2080f240c52c11581c4df93bf0074d88cfc`
- 新增最薄 `ScreenGeometryConverter.swift` 并注册到应用与测试 target。
- 只实现 T-025 已定义的几何值、转换、放置和 nonactivating 面板控制器。
- 未执行 T-027，未增加预览状态、按钮、文案、正式 SwiftUI 内容或产品视觉。

## 实现

1. `ScreenGeometryAnchorCandidates` 明确区分选区、插入点、元素、窗口、目标显示器和活跃显示器候选。
2. `ScreenGeometryConverter` 按已批准顺序选择首个可用锚点。
3. AX 顶部原点矩形仅在 converter 内转换为 AppKit 底部原点矩形，负坐标保持不变。
4. 精确锚点优先选择相交面积最大的显示器；无相交时安全降级到目标显示器、活跃显示器或首个显示器。
5. 普通空间使用 `visibleFrame`，全屏使用 display `frame`；面板先缩限到安全区域，再夹紧原点。
6. converter 不保存屏幕快照，每次调用都使用传入的最新 `ScreenGeometrySnapshot`，屏幕变化不会复用旧几何。
7. `NonactivatingPanelController` 只接受带 `.nonactivatingPanel` style mask 的 `NSPanel`，应用 frame 后调用 `orderFrontRegardless()`；不激活应用、不令 panel 成为 key window。

## GREEN 运行

```text
./scripts/unit-tests.sh
Run 1: PASS — 84 tests, 0 failures
Run 2: PASS — 84 tests, 0 failures
```

两次运行中 `ScreenGeometryConverterTests` 均为 7/7 通过，覆盖：

- 选区 → 插入点 → 元素 → 窗口 → 目标显示器 → 活跃显示器；
- AX → AppKit 坐标转换；
- 最大相交显示器；
- `visibleFrame` 安全边距收敛；
- 超大面板缩限；
- 最新屏幕快照重算。

## 控制检查

```text
./scripts/build.sh                    PASS — BUILD SUCCEEDED
./scripts/project-structure-check.sh  PASS
./scripts/sdd-check.sh                PASS
./scripts/secret-scan.sh              PASS
xcrun swiftc -parse ScreenGeometryConverter.swift  PASS
plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj  PASS
git diff --check                      PASS
```

## 结论

T-026 已以最小生产实现使 T-025 转绿，并保持既有 nonactivating 面板边界。没有实现 T-027 或正式预览界面。
