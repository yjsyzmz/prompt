# T-042 Chrome／ChatGPT whole-field recovery 复核

## 任务边界

- 任务：T-042 [Verification] 复核 Chrome／ChatGPT whole-field recovery。
- W1–W4 是 Plan 第三版修订（`0c9883f`）新增的独立算法，**不得沿用 T-033 旧证据**。
- 完成条件：记录 W1–W4 各步实测表现（含回读确认）、恢复后内容逐字节还原、
  标准 ⌘Z Undo 行为。
- 覆盖：FR-012、NFR-002、NFR-003、AC-006、AC-012、AC-017。
- 代码状态：`f8d5636`
- 验证日期：2026-07-30

## 夹具与驱动

- 目标：Google Chrome 150.0.7871.184，chatgpt.com 输入框（role=AXTextArea）
- 夹具：两行合成文字，含中英混合、emoji 😀 与组合字符 é
- 驱动：`pbcopy` 放入剪贴板后模拟 **⌘A + ⌘V 真实粘贴**，使 ChatGPT 的前端
  更新链路被真实触发；随后模拟 ⌃⌥⌘P 并通过辅助功能 API 点击面板按钮
- 捕获模式：粘贴后光标位于末尾、`selectedRange location=60 length=0`，
  零长度选区 → 判定为 **whole-field**，正是本任务要复核的路径

## 状态快照（指纹用于逐字节比较，不打印内容）

| 阶段 | UTF-16 长度 | 换行数 | 指纹 | 含标记 |
| --- | --- | --- | --- | --- |
| 粘贴后（原文） | 61 | 1 | `5CA4A4AE5F7B6822` | 否 |
| 确认替换后 | 70 | 2 | `503D558A29DF1B3C` | 是 |
| 恢复原文后 | 61 | 1 | **`5CA4A4AE5F7B6822`** | 否 |
| 恢复后按 ⌘Z | 70 | 2 | `503D558A29DF1B3C` | 是 |

**恢复后的指纹与粘贴后的原文指纹完全相同**，逐 UTF-16 code unit 还原成立。

## W1–W4 逐步实测

- **W1（完整 value 必须仍等于 expected transformed text）**：恢复被允许执行
  并成功，证明确认时读到的完整 value 与替换写入的结果逐字符一致；替换后
  指纹 `503D558A29DF1B3C` 与恢复前读取一致。
- **W2（`kAXValueAttribute` 可设置）**：写入实际发生（长度 70 → 61），
  证明该属性在此目标上可设置；若不可设置，按算法应零 setter 返回
  `recoveryTargetChanged`，面板会停在失败状态。
- **W3（恰好一次 setter 写入原文全文）**：内容一次性从 70 变为 61 且指纹
  回到原文值，未出现中间态或分段写入痕迹。
- **W4（写入后回读确认）**：面板呈现 `已替换所选文字，原文仍可恢复。`
  之后正常结束（恢复完成时面板窗口数为 0），未出现
  `recoveryTargetChanged`，说明回读确认通过。
  **异步应用的实测细节**引用同日采集的诊断数据（见
  `evidence/T-037-chatgpt-multiline-followup.md`）：`setText` 返回后立即回读
  得到的仍是写入前的长度，写入要靠既有的最多 5 次、约 500ms 回读重试才被
  确认。W4 在本目标上依赖该重试预算。
- **未使用 selected-range 能力**：本路径为 whole-field，算法禁止读取或计算
  selected range；实测中恢复在选区为零长度（location 0）时仍正常完成，
  与该约束一致。

## ⌘Z Undo 行为（AC-017）

恢复完成后按一次 ⌘Z，内容回到替换后的状态（长度 70、指纹
`503D558A29DF1B3C`、含标记）。**即在 Chrome／ChatGPT 中，应用的 AX 写入会
进入目标应用的 undo 栈**，⌘Z 撤销的是最近一次恢复写入。

这与 `evidence/T-041-textedit-selected-recovery-revalidation.md` 记录的
TextEdit 行为相反——TextEdit 中 AX 写入不进入 undo 栈，⌘Z 只移动选区。
两个观察共同构成 AC-017 的完整记录：**Undo 是否可用取决于目标应用如何对待
辅助功能写入，本应用不对此做任何承诺**。

## 结论

whole-field recovery（W1–W4）在真实 Chrome／ChatGPT 环境复核通过：替换与
恢复各执行一次 `kAXValueAttribute` 写入，恢复后内容与原文指纹完全一致，
回读确认生效（依赖既有重试预算），未触碰 selected-range 能力。
AC-006、AC-012 达成，AC-017 的目标应用 Undo 行为已记录，且与 TextEdit 的
差异被如实披露。本任务未沿用任何 T-033 旧数据。
