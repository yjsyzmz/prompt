# T-044 UTF-16 范围相关特殊字符夹具复核

## 任务边界

- 任务：T-044 [Verification] 复核 UTF-16 范围相关的特殊字符夹具。
- 范围限定：只重跑与新 UTF-16 范围算法直接相关的 TextEdit selected recovery
  夹具，**不重跑完整文字矩阵**（完整矩阵见 `evidence/T-037-representative-text-matrix.md`）。
- 完成条件：每类夹具记录具体码点构成、替换与恢复后逐 UTF-16 code unit 一致、
  范围外内容完全不变。
- 覆盖：FR-006、FR-012、NFR-004、AC-016。
- 代码状态：`b0dd630`
- 验证日期：2026-07-30

## 夹具码点构成

三段都刻意包含代理对与组合字符，以便发现任何按字符而非按 code unit 的
范围计算错误：

| 段 | UTF-16 长度 | 码点构成（位置为 UTF-16 索引） |
| --- | --- | --- |
| 前缀 | 20 | `[0]` 代理对（U+1F600 😀）、`[18]` 组合重音（U+0301） |
| 选区正文 | 24 | `[19]` 代理对（U+1D11E 𝄞）、`[22]` 代理对（U+1F600 😀） |
| 后缀 | 20 | `[1]` 代理对（U+1D11E 𝄞）、`[19]` 组合重音（U+0301） |
| 合计 | 64 | 原文指纹 `93A89DF24601413B` |

选区精确设为 `(location: 20, length: 24)`，读回的选区文本与正文段
**逐字符相等**（`selectionExact=true`），说明范围设置未劈开任何代理对。

组合字符使用分解形式（`e` + U+0301）而非预组合的 `é`，这样任何 Unicode
规范化都会改变 code unit 序列并被指纹比较捕获。

## 结果一：替换（FR-006、AC-016）

```text
docUnits=73                        64 + marker 9
digest=0132A5E401A8BC4F
prefixIdentical=true               前缀 20 个 code unit 完全不变
suffixIdentical=true               后缀 20 个 code unit 完全不变
replacedSpanExact=true             替换范围内容逐 code unit 等于「marker + 原正文」
containsMarker=true
selectedRange location=53 length=0
```

`replacedSpanExact=true` 是本任务的核心断言：从 `location 20` 起、长度为
`marker(9) + 正文(24) = 33` 的区间，其内容与期望值逐 UTF-16 code unit 完全
相等。代理对与组合序列在写入过程中既未被截断，也未被重新规范化。

## 结果二：恢复（FR-012）

```text
docUnits=64
digest=93A89DF24601413B            与原文指纹完全相同
equalsOriginal=true
prefixIdentical=true
suffixIdentical=true
containsMarker=false
```

恢复后文档与原文**逐 UTF-16 code unit 完全一致**，含代理对与组合序列的三段
全部原样还原。

## 分支判定：再次命中 R2 fallback 的边界条件

替换成功后选区塌陷为零长度插入点，位置 `53`。expected result range 为
`(location: 20, length: 33)`，即区间 `[20, 53]`——插入点正好落在**右端点**。
因此本次恢复同样走类别 R2 情形 1 的 selected-range recovery fallback。

这是 T-041 之外的第二次独立命中，进一步确认 Plan 第三版修订中"含两端"
这一条件在真实 TextEdit 环境下是必需的：若上界取开区间，含特殊字符的恢复
同样会被误拒。

## 结论

UTF-16 范围算术在含代理对与组合字符的真实夹具上验证通过：范围设置未劈开
代理对，替换范围内容逐 code unit 精确，范围外前后缀完全不变，恢复后与原文
指纹完全相同。FR-006、FR-012、NFR-004、AC-016 达成。本任务未重跑完整文字
矩阵，符合 Solar 裁决的限定范围。
