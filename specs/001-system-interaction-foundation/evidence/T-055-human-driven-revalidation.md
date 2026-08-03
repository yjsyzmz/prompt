# T-055 真人鼠标／触控板复核（进行中）

## 任务边界

- 来源：Solar 第三次 Implementation Gate REVIEW，Finding 5（MUST）；范围由 Tasks
  Gate 裁定为 TextEdit 与 Chrome/ChatGPT 两处闭环加关键失败场景，不含 VS Code，
  不重跑全部 P5。
- **本文件记录的是未完成状态。** 已完成部分与未执行部分逐项分开列出，未执行的
  不得计入通过。
- 执行日期：2026-08-03，代码状态 `a645769`（T-052 至 T-054 已落地）。

## 环境

- 应用以 `a645769` 重建后重启（PID 87440）。
- 全程真人鼠标／触控板点击，未使用 AXPress 或 AppleScript 代点。
- `log stream --level info --predicate 'subsystem == "com.systeminteractionfoundation.verification"'`
  全程抓取，共取得 22 条阶段记录。

## 已完成并通过

| 项 | 结果 |
| --- | --- |
| (a) TextEdit 连续五次「确认替换 → 恢复原文」 | **通过**，五次全部成功 |
| (b) Chrome/ChatGPT 连续五次（多行） | **通过**，五次全部成功 |

阶段记录中 19 条 `replacement-stage=completed failure=none`，与上述成功次数一致。

## 未执行（缺口，不得计入通过）

- (c) Undo 行为（TextEdit 与 ChatGPT 分别记录，AC-017）
- (d) 范围保真（前后缀逐字未改、选区未漂移、含 emoji 与组合字符，AC-012）
- (e) 恢复后的外部变化（会话已结束、无后续写入、面板不再提供恢复）
- (f1) 确认前切换到另一应用
- (f2) 确认前外部改动原文
- (f3) 替换成功后、恢复前改动结果
- (f4) f3 被拒后复制原文并重试
- (f5) 替换成功后、恢复前切换窗口
- (f6) 替换成功后、恢复前切换元素

## 本轮暴露的三项缺陷

### 缺陷 A：Google 搜索框在预览期间被判目标变化

真人报告：在 google.com 搜索框选中文字并唤出预览后，**鼠标移向面板按钮的过程中**
页面焦点回到输入框，面板随即显示「原输入位置已经变化，不能安全替换。」
同一操作在 ChatGPT 与 TextEdit 均成功。

### 缺陷 B：ChatGPT 二次替换被判目标变化

真人报告：在 ChatGPT 中成功替换一次后，就现有文本再次按 ⌃⌥⌘P 唤出预览，鼠标移向
面板时同样显示「原输入位置已经变化，不能安全替换。」

### 缺陷 C：ChatGPT 出现三次 readback 写入失败

阶段记录中有 3 条：

```text
replacement-stage=readback failure=writeFailed focus-is-self=na
```

setter 报告成功但回读未确认，五次重试预算耗尽。这与缺陷 A／B 是**不同**的问题。

## 关键诊断事实：缺陷 A 与 B 尚不可归因

22 条阶段记录中，`frontmostApplication`、`windowIdentity`、`elementIdentity` 的
拒绝记录**均为零条**。即缺陷 A 与 B 发生时，`replaceAfterAuthoritativeValidation`
从未被调用——面板在用户点击「确认替换」之前就已进入拒绝状态。

产生该文案的代码是 `AppLifecycleController.swift:364`：目标变化监听器
（`AXObserver`）触发后，只要会话仍在 `previewing(.ready)`，即直接
`present(.staleTarget)`。

**该路径没有任何埋点。** T-049 的分级诊断只覆盖替换路径，监听器路径是盲区。

因此：

- 已排除的：这两个缺陷**不是**写入失败，也不是 B1 内容比较拒绝（T-054 已把
  `sourceChanged` 分流为独立文案「原文或选区已经变化」，而用户看到的是
  `staleTarget` 文案）。
- **未确定的**：监听器判定目标变化的具体依据（窗口、元素、还是焦点应用）。
  网页应用在预览期间重绘输入元素是符合现象的解释，但目前**没有证据**，不予采信。

前一轮已因凭推断行事付出代价（七个外部探针建立在错误前提上，并产生过一个后来被
撤回的归因结论）。本轮在监听器路径的阶段数据取得之前不做任何定性。

## 结论

T-055 **未完成**。(a)(b) 两项通过；(c)(d)(e) 与 f1–f6 共九项未执行；另暴露三项
缺陷，其中两项因监听器路径缺少埋点而无法归因。补齐埋点与后续修复已作为新任务
提交 Tasks Gate 审核，不在本任务范围内自行开工。
