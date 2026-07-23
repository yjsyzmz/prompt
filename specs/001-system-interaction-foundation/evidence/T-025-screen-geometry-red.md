# T-025 屏幕几何转换 RED 证据

## 范围

- Parent SHA：`659b20657939bf8f459e2c4ce915e9145eb68ff8`
- 只新增 `ScreenGeometryConverterTests` 并注册到测试 target。
- 未修改 `Sources/`，未创建 `ScreenGeometryConverter.swift`，未实现生产几何转换、屏幕监听或面板控制器。

## 预期失败契约

新增 7 项测试，要求后续最薄实现证明：

1. 非空选区边界优先于插入点、元素与窗口边界；
2. 无选区时按插入点、元素、窗口、外部目标显示器、活跃显示器逐级降级；
3. AX 顶部原点坐标只转换一次为 AppKit 底部原点坐标，并保留负坐标；
4. 转换后选择与锚点相交面积最大的显示器；
5. 普通空间内的完整面板收敛于所选显示器 `visibleFrame` 的安全边距内；
6. 面板大于可用区域时缩限为安全区域，不产生越界或反向夹紧；
7. 显示器集合、主显示器、活跃显示器或坐标变化后使用最新屏幕快照重新计算，不复用旧几何。

测试使用纯值类型与合成屏幕快照，不读取真实屏幕布局，不依赖当前连接的显示器或缩放设置。

## RED 运行

沙箱内首次执行因无法写入 Xcode `DerivedData` 而在编译前停止，该次不计入 RED 证据。允许完整 Xcode 环境后连续执行两次：

```text
./scripts/unit-tests.sh
Run 1: exit 65
Run 2: exit 65
```

两次均在 arm64 与 x86_64 编译新增测试，并稳定因尚未实现的 T-026 契约失败：

- `ScreenGeometryConverter`
- `ScreenGeometryAnchorCandidates`
- `ScreenGeometrySnapshot`
- `ScreenGeometryDisplay`
- 对应的 anchor source 与 placement 值

后续出现的 enum member、`nil` contextual type 与 `Equatable` 诊断均由上述缺失类型引起，是同一 RED 边界的级联诊断，不是独立测试错误。

## 绿色控制检查

```text
./scripts/build.sh                    PASS — BUILD SUCCEEDED
./scripts/project-structure-check.sh  PASS
./scripts/sdd-check.sh                PASS
./scripts/secret-scan.sh              PASS
xcrun swiftc -parse ScreenGeometryConverterTests.swift  PASS
plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj  PASS
git diff --check                      PASS
git diff --name-only -- Sources       empty
```

## 结论

T-025 已建立稳定、可复现的屏幕几何 RED 边界。当前失败只要求 T-026 提供最薄纯值几何转换与面板放置契约；本任务没有实现生产几何、面板控制器或正式界面。
