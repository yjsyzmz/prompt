# T-002 — 工程结构检查红灯证据

## 结论

**EXPECTED FAIL。** 已先编写工程结构检查；在尚未执行 T-003、仓库中不存在 Xcode 工程的状态下，该检查以非零退出码和明确原因失败。这是测试优先流程要求的预期红灯，不代表现有必过 CI 失败。

记录日期：2026-07-21（Asia/Shanghai）

## 检查契约

`scripts/project-structure-check.sh` 要求未来工程满足：

- 仓库只有一个 `.xcodeproj`，且没有独立 `.xcworkspace` 或 `Package.swift`；
- `.ci/xcode.env` 集中声明应用、单元测试与合成 AX 宿主三个互不相同的技术目标，工程不得包含其他目标；
- 三个目标均使用 macOS 14.0+、Swift 6、`arm64` 与 `x86_64`，并关闭 `ONLY_ACTIVE_ARCH` 和 App Sandbox；
- 应用与合成 AX 宿主为 application target，测试目标为 unit-test bundle；
- entitlement 不含 App Sandbox 或网络 client/server 能力；
- 不存在 Swift Package、CocoaPods、Carthage、外部 framework/xcframework 或远程 package 引用。

技术目标名将在 T-003 通过 `.ci/xcode.env` 集中配置，与最终 `PRODUCT_NAME` 和用户可见产品名分离。

## 预期失败执行

命令：

```bash
./scripts/project-structure-check.sh
```

预期结果：

```text
Project structure check failed: no Xcode project found; T-003 has not created the project yet.
exit_code=1
```

实际退出码与输出在本任务执行时验证，必须同时满足“退出码非零”和“命中上述缺少工程诊断”才视为 T-002 完成。

## 门禁接入边界

该检查当前不接入 GitHub Actions、`build.sh` 或 `unit-tests.sh`，因为在 T-003 前它按设计必然失败。T-003 创建最小工程并使检查转绿后，T-004 再建立本地与远程基础构建门禁。

## 范围核验

- 未创建 `.xcodeproj`、`.xcworkspace`、`Package.swift` 或 Swift 文件；
- 未安装项目依赖或第三方运行时包；
- 未编写应用、单元测试或合成 AX 宿主代码；
- 未执行 T-003 或后续任务；
- 变更仅包含结构检查、预期红灯证据和任务状态记录。
