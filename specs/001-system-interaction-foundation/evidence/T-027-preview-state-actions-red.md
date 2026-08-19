# T-027 预览状态与操作 RED 证据

## 范围

- Parent SHA：`f33122d8dff672851c9a50c4c19797c7de4b15f6`
- 只新增 `PreviewStateActionTests` 并注册到测试 target。
- 未修改 `Sources/`，未创建 `PreviewPresentationMapper`、SwiftUI preview、`AppLifecycleController` 或 T-028 生产装配。

## 预期失败契约

新增 5 项测试，要求后续最薄实现证明：

1. `ready`、`permissionRequired`、`secureInput`、`emptyOrUnsupported`、`staleTarget`、`writeFailed`、`recoveryUnavailable` 均有明确且可理解的中文说明；
2. 七种状态具有 Plan 规定的精确按钮动作和标题矩阵；
3. 只有 `ready` 包含并启用“确认替换”，其他状态完全不暴露确认动作；
4. 每个拒绝或失败状态至少提供一个已启用的安全下一步；
5. 状态说明与按钮标题不出现 AX/`OSStatus`/pasteboard 原始标识、数字错误码或合成敏感标记。

测试只定义纯展示模型契约，不依赖 SwiftUI、AppKit、Accessibility、剪贴板或真实用户内容。

## RED 运行

```text
./scripts/unit-tests.sh
Run 1: exit 65
Run 2: exit 65
```

两次均在 arm64 与 x86_64 编译新增测试，并稳定因尚未实现的 T-028 契约失败：

- `PreviewStatus`
- `PreviewButton`
- `PreviewViewState`
- `PreviewPresentationMapper`
- 对应的预览用户动作

后续 enum member、key-path contextual type 以及 Swift 字典表达式诊断均由上述缺失类型引起，是同一 RED 边界的级联诊断，不是独立测试语法错误。

## 绿色控制检查

```text
./scripts/build.sh                    PASS — BUILD SUCCEEDED
./scripts/project-structure-check.sh  PASS
./scripts/sdd-check.sh                PASS
./scripts/secret-scan.sh              PASS
xcrun swiftc -parse PreviewStateActionTests.swift  PASS
plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj  PASS
git diff --check                      PASS
git diff --name-only -- Sources       empty
```

## 结论

T-027 已建立稳定、可复现的预览状态与安全操作 RED 边界。当前失败只要求 T-028 提供纯展示模型和最薄预览装配；本任务没有实现正式预览界面或应用生命周期。
