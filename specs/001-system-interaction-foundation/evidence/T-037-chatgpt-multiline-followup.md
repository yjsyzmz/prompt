# Finding 5 后续：ChatGPT 多行闭环专项验证

## 任务边界

- 来源：Solar 对 `ebb6978` 的 Implementation Gate REVIEW，Finding 5（MUST）——
  ChatGPT 代表性多行验证缺失，原豁免理由（"回车即发送消息"）不成立。
- 追加来源：Solar 第二轮 Implementation Gate REVIEW，MUST 1——必须用不含内容的
  分级诊断区分 A1–A4、capability、secureInput、B1、contentRead、settable、
  setter、readback，并在此基础上采集多次真实环境稳定性数据。
- 目标：取得 Plan 第 327 行要求的"Chrome/ChatGPT 代表性多行完整闭环"证据，
  并给出可支撑 Plan 第 542 行 Rollout 硬性退出条件的稳定性数据。
- 本文件只记录多行专项验证；T-037 的其余覆盖不受影响。

## 验证环境

- Mac：MacBook Pro（Mac15,3，Apple M3，8 GB）
- macOS：26.5.2（25F84）
- 目标应用：Google Chrome（chatgpt.com），输入框 role=AXTextArea
- 验证日期：2026-07-30（首轮）、2026-07-31（MUST 1 分级诊断轮）

## 第一轮（2026-07-30，代码状态 `1ce9d01`）

夹具为两行合成文字，71 UTF-16 code unit、1 个换行；转换结果 80 UTF-16 code
unit、2 个换行。通过 `pbcopy` 放入剪贴板后用 System Events 模拟 ⌘A + ⌘V 真实
粘贴，再模拟 ⌃⌥⌘P 并用辅助功能 API 点击面板按钮。

**方法论修正（重要）：** 2026-07-29 的一次"验证通过"是无效的——当时用 AX
直接写入夹具，等于"用 AX 写入验证 AX 写入能力"，构成循环论证，且真人复测
即失败。改用模拟粘贴后前端链路被真实触发，结论才成立。

结果：连续 3 次、预览停留 10 秒、预览停留 20 秒，共 5 次全部替换并恢复成功。

关键观察——**写入是异步应用的**：`setText` 返回后立即回读，拿到的仍是写入前
的长度，多行写入必须依靠既有的回读重试（最多 5 次、约 500ms）才能确认成立。

## 第二轮（2026-07-31，代码状态 `2792b1d`，MUST 1 分级诊断）

### 诊断手段

`AccessibilityGateway` 的替换路径现在对 11 个拒绝点逐一记录
`ReplacementStageReport`。该结构在类型上不含任何 `String` 字段，只携带阶段
标识、`DomainFailure` 分类和两个 UTF-16 长度，生产侧经 `os_log`
（subsystem `com.systeminteractionfoundation.verification`，category
`replacement-stage`）输出，符合 FR-013 与 NFR-006。

夹具：两行合成文字，55 UTF-16 code unit、1 个换行；第一行中英混合，第二行含
emoji 😀 与组合字符 é。转换结果 64 UTF-16 code unit。

采集方式：`log stream --level info` 全程抓取，两批各 20 次，共 40 次触发。

### 结果

| 批次 | 粘贴到快捷键的间隔 | 触发 | 替换成功 | 捕获阶段失败 | 替换阶段失败 |
| --- | --- | --- | --- | --- | --- |
| A | 1.2 秒 | 20 | 17 | 3 | 0 |
| B | 3.0 秒 | 20 | 20 | 0 | 0 |

37 条阶段记录，全部为：

```text
replacement-stage=completed failure=none expected-utf16=55 observed-utf16=64
```

`failure != none` 的记录数为 0；`setter`、`readback` 以及 A1–A4 各阶段的拒绝
记录数均为 0。

### 批次 A 三次失败的定位

第 7、16、18 次的面板文案是「没有可处理的文字，或当前输入位置不支持直接读取。」
即 `emptyOrUnsupported`，属于**捕获**阶段；这三次没有产生任何替换阶段记录，
说明流程从未进入 `replaceAfterAuthoritativeValidation`。把粘贴到快捷键的间隔
从 1.2 秒提高到 3.0 秒后，20 次全部成功。据此判定：这三次失败是自动化脚本的
粘贴沉降时序造成的——ChatGPT 前端尚未把新内容反映到无障碍树，快捷键就已触发。
它与真人报告的「未能安全替换原文」是不同现象，不能混为一谈。

## 归因更正

本文件此前写有"确定失败发生在 `validate` 的 A1–A4 之一"。**该结论撤回。**
它建立在 2026-07-29 一次尚无埋点的采集上，属于推测；本轮 40 次触发中 A1–A4
的拒绝记录为 0，没有任何证据支持那个归因。

## 一个有证据支撑的假设：部分历史失败是分类错误而非写入失败

MUST 2 之前，`GatewaySessionTextTarget.replace` 只返回 `Bool`，因此
`validate` 的**任何**拒绝（A1–A4、capability、secureInput、B1、settable）
最终都呈现为 `writeFailed`，文案恰好就是真人多次报告的那一句
「未能安全替换原文，结果仍可复制。」

也就是说，历史上被记为"多行写入失败"的现象里，至少有一部分可能根本没有发生
写入，而是目标已经变化却被贴上了写入失败的标签。MUST 2 已把这两类分开：
未发生写入的拒绝现在显示 `staleTarget` 或 `targetNotWritable`。

**这仍然只是假设。** 那几次历史失败没有留下阶段数据，无法回溯归类。要证实
或推翻它，需要在新的呈现下再次遇到失败并读取当次的阶段记录。

## 已知限制

1. 40 次自动化触发中替换阶段零失败，但样本全部来自同一台机器、同一个 Chrome
   版本、同一个夹具。跨机器、跨 Chrome 版本、跨输入框类型的稳定性未验证。
2. 真人操作的节奏与自动化不同（选区来源、停留时长、期间是否切换窗口）。
   自动化零失败不能替代真人复测。
3. 历史间歇失败无法回溯归类（见上一节）。
4. 每次重建二进制后 macOS 会使辅助功能授权失效——系统设置里的开关仍显示为
   开启，但 TCC 记录已与新可执行文件不匹配。本轮重建后授权仍然有效，未触发
   该问题，但该现象已在 2026-07-30 观测到，仍应保留在验收包的已知限制中。

## 建议（不在本任务范围内实施）

1. 分级诊断已进入生产装配（`AppLifecycleController.makeReplacementDiagnostics`），
   建议保留。本轮定位过程证明：缺少它时失败会被反复错误归因——先后误判为
   "Chromium 拒绝多行写入""元素被重建""换行符不被接受""失败发生在 A1–A4"，
   共浪费七轮外部探针和一次错误结论。
2. 若后续再遇到多行失败，第一步应读取 `replacement-stage` 记录，而不是先提
   假设。
