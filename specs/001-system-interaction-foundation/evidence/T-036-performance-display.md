# T-036 性能与显示证据

## 任务边界

- 任务：T-036 [Evidence] 采集性能与显示证据。
- 依赖：T-032、T-033（见对应证据文件）。
- 覆盖：FR-001、FR-007、NFR-001、NFR-005、AC-001、AC-015。
- 关闭 Plan Gate NIT-2。

## 测量边界（Plan Gate NIT-2 的强制约束）

- **起点**：`AppLifecycleController.beginDirectInteraction()` 的第一条语句，
  即全局快捷键回调进入应用后的第一个可观测点。
- **终点**：首个预览视图状态呈现完成（`presentViewState` 中 `presenter.show`
  或 `presenter.update` 返回之后）。
- **明确排除**：物理按键到 hot-key callback 之间的操作系统投递延迟。
  该延迟无法在不引入通用按键监听的前提下观测，而 plan 与 T-036 均禁止
  引入按键监听，因此不纳入 300ms 预算。
- **不含内容**：仪器只记录经过的纳秒数并以毫秒输出，不记录任何被捕获的
  文字，符合 FR-013 与 NFR-006。

## 仪器实现

- 协议 `PresentationLatencyRecording` 与生产实现
  `OSLogPresentationLatencyRecorder`，见
  `Sources/SystemInteractionFoundation/SystemInteractionAdapters.swift`。
- 时钟为既有的 `SystemMonotonicClock`（`DispatchTime.now().uptimeNanoseconds`），
  单调时钟，不受系统时间调整影响。
- 装配点见 `Sources/SystemInteractionFoundation/AppLifecycleController.swift`
  的 `beginDirectInteraction()` 与 `presentViewState(_:)`。
- 由 `Tests/SystemInteractionFoundationTests/PresentationLatencyInstrumentationTests.swift`
  驱动：测量窗口、每次触发仅一个样本、安全输入拒绝也计入明确状态。
  仪器不存在时该测试无法编译（RED），补齐后 118 tests、0 failures。
- 采集命令（事后查询，`log stream` 默认不含 info 级别）：

  ```text
  /usr/bin/log show --start '<起始时间>' --info --style compact \
    --predicate 'subsystem == "com.systeminteractionfoundation.verification"'
  ```

## 环境

- Mac：MacBook Pro（Mac15,3，Apple M3，8 GB）
- macOS：26.5.2（25F84）
- 显示器布局：内置 Liquid Retina XDR（3024 x 1964 Retina）+ 外接显示器
  1920 x 1080 @ 60Hz，均未镜像；缩放为各自默认设置
- 目标应用：TextEdit 1.20；Google Chrome 150.0.7871.184（chatgpt.com）
- 应用构建：Debug、universal，代码状态 `8b75e6f`（含本任务仪器）
- 输入内容：仅 `SYNTHETIC-001` 标记的合成文字
- 采集日期：2026-07-28

## 结果一：TextEdit 连续 10 次（选区路径）

样本（毫秒，按触发顺序）：

```text
51.7  10.6  15.2  8.4  7.5  8.2  5.7  11.4  10.3  7.6
```

- 300ms 内：10 / 10（要求至少 9 / 10）
- 最大值 51.7ms，最小值 5.7ms
- 首次偏高属于首轮路径预热，仍远低于预算

## 结果二：Chrome / ChatGPT 连续 10 次（无选区全文路径）

样本（毫秒，按触发顺序）：

```text
62.4  6.6  13.9  118.4  7.2  8.5  7.2  6.6  8.3  5.5
```

- 300ms 内：10 / 10（要求至少 9 / 10）
- 最大值 118.4ms，最小值 5.5ms
- 该路径需要设置 `AXManualAccessibility` / `AXEnhancedUserInterface` 并在
  辅助功能树可用前重试（见 `evidence/T-033-chrome-chatgpt-closed-loop.md`），
  因此偶发样本明显高于 TextEdit；最差样本仍有约 2.5 倍余量

## 结果三：显示与面板行为（AC-015、NFR-005）

- 面板在双显示器、非镜像、内置 Retina 与外接 1080p 混合缩放环境下完整
  显示于活跃显示器内，未跨屏截断。
- 面板为 nonactivating `NSPanel`，触发期间目标应用始终保持焦点与输入位置
  （TextEdit 与 ChatGPT 的 20 次触发中均未发生焦点被夺取）。
- 单屏、多屏、全屏、屏幕边缘与非默认缩放的几何边界已由 T-010 探针在真实
  环境验证（见 `evidence/T-010-panel-stop-conditions.md`），本任务不重复。

## 结论

两个必须支持的应用各 10 次连续触发，全部 20 个样本均在 300ms 预算内
（要求为每组至少 9 / 10），NFR-001、AC-001 达成。测量起点为 hot-key
callback 且不含操作系统投递延迟，未引入任何按键监听，Plan Gate NIT-2
的可审计边界成立。面板显示与不抢焦点行为在多显示器环境符合 NFR-005、
AC-015。T-036 未触发硬停止条件。
