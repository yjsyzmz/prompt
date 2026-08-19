# T-003 — 最小 Xcode 工程证据

## 结论

**PASS。** 已创建仅满足 T-002 契约的原生 macOS Xcode 工程骨架，工程结构检查已从预期红灯转为绿色。本任务只添加让三个目标成为有效构建产物所必需的无行为入口和测试发现占位，不包含产品行为，也没有完成 T-004 的构建与测试基线。

记录日期：2026-07-21（Asia/Shanghai）

## 工程结构

| 角色 | 技术目标 | Product type |
| --- | --- | --- |
| 应用 | `SystemInteractionFoundation` | `com.apple.product-type.application` |
| 单元测试 | `SystemInteractionFoundationTests` | `com.apple.product-type.bundle.unit-test` |
| 合成 AX 宿主 | `SyntheticAXHost` | `com.apple.product-type.application` |

工程只包含上述三个目标。`.ci/xcode.env` 集中声明工程、shared scheme 与目标角色；`Configurations/Shared.xcconfig` 集中配置可替换的 `PRODUCT_NAME` 规则及共同技术基线。技术目标名不构成最终产品名。

三个目标由 `xcodebuild -showBuildSettings` 共同确认：

- `MACOSX_DEPLOYMENT_TARGET = 14.0`；
- `SWIFT_VERSION = 6.0`；
- `ARCHS = arm64 x86_64`；
- `ONLY_ACTIVE_ARCH = NO`；
- `ENABLE_APP_SANDBOX = NO`。

工程没有 entitlement 文件、网络能力、Swift Package、CocoaPods、Carthage、外部 framework/xcframework 或远程 package 引用。

两个 application target 各包含一个立即返回的 Swift `@main` 入口；logic-test target 包含一个无断言、无产品依赖的发现占位。它们只保证工程目标是有效产物，不启动 UI、不申请权限、不访问系统或用户数据。首次推送后的既有自动工作流证明纯空 app 无法作为 hosted-test runner，因此测试目标改为独立 logic test；该修正属于工程骨架有效性，不实现产品测试。

## 验证结果

```text
$ xcodebuild -project SystemInteractionFoundation.xcodeproj -list
Targets:
    SystemInteractionFoundation
    SystemInteractionFoundationTests
    SyntheticAXHost

$ ./scripts/project-structure-check.sh
Project structure check passed.
```

结构检查由完整 Xcode 26.6 在标准开发环境中执行。受限命令环境首次阻止 Xcode 写入其标准 DerivedData 日志目录；授予标准 Xcode 缓存访问后，同一工程与同一检查直接通过，未修改检查契约或放宽任何断言。

## 范围核验

- 只有两个立即返回的结构入口和一个测试发现占位；没有产品实现或产品测试；
- 没有 `Package.swift` 或 `Package.resolved`；
- 没有界面、领域类型、系统适配器或合成 AX 宿主行为；
- 没有安装依赖、执行产品探针或人工兼容性验证；
- Solar 未主动运行或记录 `build.sh`、`unit-tests.sh` 的 T-004 基线；推送触发的既有自动工作流仅作为分支保护反馈处理；
- 未执行 T-004 或后续任务。
