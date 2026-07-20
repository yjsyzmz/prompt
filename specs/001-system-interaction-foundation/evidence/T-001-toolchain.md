# T-001 — 可复现工具链证据

## 结论

**PASS。** 当前机器已经安装并选择 Apple 官方稳定版完整 Xcode，Swift 6 可用，Xcode 首次启动组件和许可状态均已就绪。T-001 完成；本轮未执行 T-002 或任何后续任务。

记录日期：2026-07-20（Asia/Shanghai）

## 环境

| 项目 | 已验证值 |
| --- | --- |
| Xcode 路径 | `/Applications/Xcode.app` |
| Developer directory | `/Applications/Xcode.app/Contents/Developer` |
| Xcode | 26.6，build `17F113` |
| Swift | Apple Swift 6.3.3，Swift 6 language mode 可用 |
| macOS SDK | 26.5 |
| macOS | 26.5.2，build `25F84` |
| Mac | MacBook Pro，model `Mac15,3` |
| 芯片与架构 | Apple M3，`arm64`，8 核（4 Performance + 4 Efficiency） |
| 验证时根卷可用空间 | 约 364 GiB |

Apple 的 [Xcode 支持与系统要求](https://developer.apple.com/support/xcode/) 将 Xcode 26.6 列为稳定版本，支持 macOS Tahoe 26.2–26.x，并提供 Swift 6 language mode。

## 验证命令与结果

| 验证 | 结果 |
| --- | --- |
| `xcode-select -p` | 返回完整 Xcode 的 Developer directory |
| `xcodebuild -version` | `Xcode 26.6` / `Build version 17F113` |
| `swift --version` | Apple Swift 6.3.3，target `arm64-apple-macosx26.0` |
| `xcodebuild -checkFirstLaunchStatus` | 退出码 0 |
| `xcrun --find swiftc` | 解析到 Xcode 默认 toolchain 内的 `swiftc` |
| `xcrun --sdk macosx --show-sdk-version` | `26.5` |

Xcode 与 Apple SDKs Agreement 由用户在明确确认后接受。证据不记录 Apple Account、设备序列号、凭据或其他敏感标识。

## 范围核验

- 未安装项目依赖或第三方运行时包；
- 未创建 `.xcodeproj`、`.xcworkspace`、`Package.swift` 或 Swift 文件；
- 未编写、构建或运行应用与测试；
- 未执行 T-002 或任何后续任务；
- 仓库变更仅为 SDD 阶段簿记、T-001 完成标记和本证据文件。

## 下一门禁

T-002 尚未获用户授权。开始 T-002 前必须重新确认授权范围；T-002 只允许先编写并运行预期失败的工程结构检查，不得直接创建 Xcode 工程。
