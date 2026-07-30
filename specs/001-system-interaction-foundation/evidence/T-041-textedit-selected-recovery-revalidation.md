# T-041 TextEdit selected recovery 复核

## 任务边界

- 任务：T-041 [Verification] 复核 TextEdit selected recovery。
- 前置：T-040 自动化下游复核已通过。
- 完成条件：记录选区捕获→替换→恢复原文的完整闭环、expected result range 之外
  的内容保持完全不变、目标应用标准 ⌘Z Undo 行为，并注明走的是 R1 还是 R2
  fallback 分支。
- 覆盖：FR-012、NFR-002、NFR-003、AC-005、AC-012、AC-017。
- 代码状态：`90f2a0e`
- 验证日期：2026-07-30

## 夹具与驱动

文档由三段构成，便于逐段核对范围外保真（全部为 `SYNTHETIC-001` 合成文字）：

```text
SYNTHETIC-001 前缀行\n      前缀，18 UTF-16 code unit
SYNTHETIC-001 选区正文      选区正文，18 UTF-16 code unit（location 18）
\nSYNTHETIC-001 后缀行      后缀，18 UTF-16 code unit
                            合计 54
```

驱动方式：临时驱动程序通过辅助功能 API 写入文档并把 `kAXSelectedTextRange`
精确设为 `(location: 18, length: 18)`，使捕获模式为 selected；随后模拟 ⌃⌥⌘P，
并通过辅助功能 API 点击面板按钮。驱动程序不参与替换或恢复，只负责布置夹具与
读取结果，跑完即删除。

选区布置结果：`selected=[SYNTHETIC-001 选区正文]`、`selectionMatchesSegment=true`。

## 结果一：替换（AC-005）

面板：`已替换所选文字，原文仍可恢复。`

```text
docLen=63                 54 + marker 9
prefixIntact=true         前缀 18 个 code unit 完全不变
suffixIntact=true         后缀 18 个 code unit 完全不变
containsMarker=true       结果以【系统交互验证】开头
equalsOriginal=false
selectedRange location=45 length=0
```

替换只作用于原选区，范围外逐 code unit 不变。

## 结果二：恢复走 R2 fallback（AC-012、FR-012）

**分支判定（本任务的关键记录）：** 替换成功后 TextEdit 把选区塌陷为零长度
插入点，位置 `45`。expected result range 为
`(location: 18, length: 27)`（前缀 18 起始，长度 = marker 9 + 正文 18），
即区间 `[18, 45]`。插入点 45 **正好落在该区间的右端点**，因此重新验证判定为
**类别 R2 情形 1**，恢复走 selected-range recovery fallback，而非 R1 的
selected setter。

这直接验证了 Plan 第三版修订中"零长度插入点落在 expected result range 内
（**含两端**）"这一条件的必要性——若右端点被排除，本次恢复会被误判为 C2
排除项而拒绝。

恢复结果：

```text
面板窗口数=0              会话正常结束
docLen=54                 回到原始长度
equalsOriginal=true       与原文逐字符一致
containsMarker=false      标记已移除
prefixIntact=true         范围外仍完全不变
suffixIntact=true
```

fallback 的六项门禁在真实环境全部通过，写入内容仅替换记录范围，范围外零改动。

## 结果三：⌘Z Undo 行为（AC-017，如实记录差异）

恢复完成后连续按两次 ⌘Z：

```text
第一次 ⌘Z：docLen=54、equalsOriginal=true，selectedRange 变为 (18, 18)
第二次 ⌘Z：docLen=54、equalsOriginal=true，selectedRange 变为 (0, 54)
```

**观察：本轮场景下 ⌘Z 只改变选区，不改变内容。** 原因是本次夹具布置、替换与
恢复全部通过辅助功能 API 完成，而 AX 写入不进入 TextEdit 的 undo 栈，栈中没有
可撤销的内容变更。

这与 `evidence/T-032-textedit-closed-loop.md` 中"在 TextEdit 里按 ⌘Z，就变
回去了"的人工观察**不一致，两者都成立**：T-032 的文档含操作者自己的键盘编辑
历史，undo 栈非空；本轮为纯脚本夹具，栈为空。因此：

- 面向真实用户的 Undo 行为以 T-032 的人工记录为准；
- 本轮记录补充一项事实：**应用的 AX 写入不会污染目标应用的 undo 栈**，
  这对"不干扰用户既有编辑历史"是正向结论，但也意味着脚本化场景无法用 ⌘Z
  验证内容还原。

## 结论

TextEdit selected recovery 闭环复核通过：替换只动选区、恢复逐字符还原原文、
两个方向的范围外内容均逐 code unit 不变；恢复路径经确认走 **R2 fallback**，
其"含两端"边界条件在真实环境被实际命中并成立。⌘Z 行为按上节如实记录，
与 T-032 的人工观察互补而非冲突。AC-005、AC-012 达成，AC-017 的目标应用
Undo 行为已记录。
