# T-005 快捷键与 Secure Event Input 探针红灯证据

## 结论

T-005 已建立快捷键、Secure Event Input 与性能计时的测试优先契约。测试已加入现有 `SystemInteractionFoundationTests` 目标，并按预期在编译阶段失败，因为 T-006 尚未提供对应的生产协议与适配器。

本任务没有创建生产适配器、生产占位类型或产品行为。预期红灯必须由 T-006 转绿。

## 测试契约

`Tests/SystemInteractionFoundationTests/HotKeySecureInputProbeTests.swift` 覆盖：

| 场景 | 关键断言 |
|---|---|
| 独占快捷键注册成功 | 返回 `registered`，底层注册只调用一次 |
| 快捷键冲突 | 底层冲突被映射为 `conflict` |
| 注销 | 只释放当前有效 token，重复注销不重复调用底层 |
| 重复回调 | 两次系统 callback 各向上传递一次，不丢失、不倍增 |
| Secure Event Input | 在任何内容读取前返回 `blocked`，内容读取 spy 调用次数为 0 |
| 单调时钟起点 | 注册阶段不采样；第一次采样发生在 hot-key callback 内 |
| 无通用按键监听 | 扫描生产 Swift 源码并拒绝 `CGEventTap`、NSEvent 全局/本地 monitor、IOHID 与 Input Monitoring TCC 符号 |

协议替身只描述 T-006 必须满足的最小边界：独占快捷键系统客户端、Secure Event Input 检查器和单调时钟读取器。测试不要求 Input Monitoring 权限，也不模拟或监听任意键盘事件。

## 预期红灯

执行：

```text
./scripts/unit-tests.sh
```

结果：

- exit code：`65`
- Xcode 已解析工程和测试目标，并开始编译 `HotKeySecureInputProbeTests.swift`
- 最终失败原因是 T-006 生产契约缺失，而不是工程发现、模块导入或测试目标配置失败
- 代表性诊断：
  - `cannot find type 'HotKeySystemClient' in scope`
  - `cannot find type 'HotKeySystemRegistrationOutcome' in scope`
  - `cannot find type 'HotKeyRegistrationToken' in scope`
  - `cannot find type 'SecureEventInputChecking' in scope`
  - `cannot find type 'MonotonicClockReading' in scope`
- Xcode 结论：`TEST FAILED`，测试构建失败后取消执行

首次运行曾先暴露应用模块的 Debug testability 未开启。T-005 只在项目 Debug 配置加入 `ENABLE_TESTABILITY = YES`，随后重新运行并确认最终红灯准确落在缺失的 T-006 契约上。

## 绿色控制项

- `./scripts/project-structure-check.sh`：PASS
- `./scripts/build.sh`：PASS，生产应用与 Synthetic AX Host 构建成功
- `bash -n scripts/*.sh`：PASS
- `./scripts/sdd-check.sh`：PASS
- `./scripts/sdd-check.sh --self-test`：PASS
- `./scripts/secret-scan.sh`：PASS
- `./scripts/secret-scan.sh --self-test`：PASS
- `./scripts/find-xcode-container.sh --self-test`：PASS
- `plutil -lint SystemInteractionFoundation.xcodeproj/project.pbxproj`：PASS
- `git diff --check`：PASS
- 对当前生产源码执行禁用符号扫描：无匹配

## 范围边界

- 未执行 T-006 或后续任务。
- 未调用 `RegisterEventHotKey`、`UnregisterEventHotKey` 或 `IsSecureEventInputEnabled`。
- 未实现生产协议、适配器、协调器、快捷键行为或内容读取。
- 未加入 `CGEventTap`、NSEvent monitor、IOHID、Input Monitoring 权限或任何通用按键监听路径。
- 未安装依赖，未增加 entitlement，未修改产品范围。
- 当前 `unit-tests` 红灯是 T-005 的预期状态；T-006 完成最薄生产实现后必须转绿。

## 下一步

下一项是 T-006：实现最薄快捷键与安全输入适配器，并让本文件记录的测试契约转绿。T-006 需要新的用户明确授权；本任务在此停止。

## 后续关闭记录

T-006 已让本文件记录的预期红灯转绿。最终实现与绿色验证证据见 `T-006-hot-key-secure-input-adapters.md`；本文件保留 T-005 测试先行时的历史红灯状态。
