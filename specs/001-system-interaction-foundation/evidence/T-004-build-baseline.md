# T-004 — 基础构建与测试发现基线

## 结论

**PASS。** 本地干净 Debug build、两个 application target 的 universal 架构检查、单元测试发现、SDD/密钥检查以及 GitHub Actions 四项检查全部通过。没有跳过或降级 Xcode 检查，检查点 C0 达成。

记录日期：2026-07-21（Asia/Shanghai）

## 本地环境

| 项目 | 已验证值 |
| --- | --- |
| Xcode | 26.6，build `17F113` |
| Swift | Apple Swift 6.3.3 |
| macOS SDK | 26.5 |
| macOS | 26.5.2，build `25F84` |
| Mac | MacBook Pro，`Mac15,3`，Apple M3，8 核 |
| 主机架构 | `arm64` |

## 本地命令与结果

使用新建的 `/private/tmp` 临时 DerivedData 执行干净构建，命令结束后删除临时产物：

```bash
xcodebuild \
  -project SystemInteractionFoundation.xcodeproj \
  -scheme SystemInteractionFoundation \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath <temporary-directory>/DerivedData \
  clean build

lipo -archs <temporary-directory>/DerivedData/Build/Products/Debug/SystemInteractionFoundation.app/Contents/MacOS/SystemInteractionFoundation
lipo -archs <temporary-directory>/DerivedData/Build/Products/Debug/SyntheticAXHost.app/Contents/MacOS/SyntheticAXHost

./scripts/unit-tests.sh
./scripts/project-structure-check.sh
./scripts/sdd-check.sh
./scripts/sdd-check.sh --self-test
./scripts/secret-scan.sh
./scripts/secret-scan.sh --self-test
./scripts/find-xcode-container.sh --self-test
bash -n scripts/*.sh
```

结果：

| 检查 | 结果 |
| --- | --- |
| 干净 Debug build | `BUILD SUCCEEDED` |
| 主应用可执行文件 | `x86_64 arm64` |
| 合成 AX 宿主可执行文件 | `x86_64 arm64` |
| 单元测试发现 | 发现并执行 `ProjectStructureTests.testTargetIsDiscoverable` |
| 单元测试结果 | 1 test，0 failures，0 unexpected |
| 工程结构检查 | PASS |
| SDD 检查与自测 | PASS |
| 密钥扫描与自测 | PASS |
| Xcode container discovery 自测 | PASS |
| shell、pbxproj、shared scheme 语法 | PASS |

`./scripts/build.sh` 也在同一 T-004 会话中返回 `BUILD SUCCEEDED`。首次产物定位使用的 `SYMROOT` 环境假设未被脚本传递给 Xcode，因此该次定位断言提前退出；这不是构建失败。随后改用官方 `-derivedDataPath` 重新执行独立干净构建并完成上述可复现核验，没有修改工程或放宽检查。

## GitHub Actions

基线工程提交：`5b252a8680219975d2b959cd7f993a80b5d5903b`

Workflow：[quality run #15](https://github.com/yjsyzmz/prompt/actions/runs/29799554829)

| Job | Runner | 结果 |
| --- | --- | --- |
| `sdd-check` | `ubuntu-latest` | success |
| `secret-scan` | `ubuntu-latest` | success |
| `build` | `macos-latest` | success |
| `unit-tests` | `macos-latest` | success |

macOS job 的实际 runner 为 Apple Silicon `macos-26-arm64`、macOS 26.4，使用 Xcode 26.5。CI 执行仓库中的 `build.sh` 与 `unit-tests.sh`，不依赖 TCC/Accessibility 权限，也没有跳过失败步骤。

## 范围核验

- 本任务没有修改 Xcode 工程、配置、Swift 源码或测试；
- 没有新增依赖、entitlement、网络能力或签名配置；
- 没有运行 Accessibility、快捷键、Secure Event Input 或界面探针；
- 没有执行 T-005 或后续任务；
- 仓库变更仅包含本证据和任务状态记录。
