# T-048 键盘焦点归属引发的连锁缺陷

## 任务边界

- 触发来源：MUST 1 的分级诊断上线后，用户手动复测仍然失败。分级诊断第一次
  让失败落到具体阶段，由此定位出一串同源缺陷。
- 本文件记录这条缺陷链的完整定位与修复过程，以及它对既有验收证据可信度的影响。
- 验证日期：2026-07-31

## 缺陷链

四个缺陷同源：**判断"当前"目标时使用了系统级键盘焦点，而预览面板在用户点击
按钮的那一刻合法地持有键盘焦点。**

`PanelProbeAdapters.swift:8` 的 `KeyableNonactivatingPanel` 显式设
`canBecomeKey = true`，注释写明是为了让面板内的 SwiftUI 按钮能收到点击。也就是
说，**让按钮可点这一设计本身，就会让所有基于系统焦点的目标校验判定失败。**

| # | 位置 | 表现 | 修复 |
| --- | --- | --- | --- |
| 1 | `validate` 的 A2 | 鼠标点「确认替换」被判 `invalidTarget` | `153eb41` |
| 2 | `windowMatches`／`elementMatches`（A3／A4） | A2 修好后失败下移到 A3 | `efc73e6` |
| 3 | `sharedPrechecks` 的 A2 | 替换成功但「恢复原文」被拒 | `6093146` |
| 4 | A1–A4 存在两份独立拷贝 | 修一处不会修另一处，缺陷可再生 | `6093146` |

## 定位过程

### 第一步：分级诊断给出阶段

用户手动失败后读 `replacement-stage` 记录，四次尝试全部：

```text
replacement-stage=frontmostApplication failure=invalidTarget
```

对照数据分离得很干净：**鼠标点击确认 5 次全部停在 A2；辅助功能 API 的
AXPress 确认 40 次全部 `completed`。** 差别只在按钮怎么点。

### 第二步：确认焦点归属

诊断报告只带长度，不带 PID，所以"聚焦应用变成本进程"当时只是推断。加入
不含内容的布尔字段 `focusedApplicationIsSelf`（`d90ba37`，A2 行为一行未改），
请用户再点一次，得到：

```text
replacement-stage=frontmostApplication failure=invalidTarget focus-is-self=true
```

推断转为实测。

### 第三步：发现实现不符合已批准的 Plan

`plan.md:197` 的 A2 批准原文是：

> 除工具自身 non-activating panel 外，没有其他应用成为用户的新外部目标；

**豁免本来就在批准的算法里**，实现漏掉了。因此这不是对已批准制品的变更，
不触发 Plan Gate 重开，属于 Implementation 层的符合性缺陷。

（过程更正：我曾判断改 A2 需要重开 Plan Gate，读到 `plan.md:197` 后撤回。）

### 第四步：失败逐级下移，逐级修

修 A2 后失败下移到 A3。根因同类：`currentFocusedElement()` 读的是
`AXUIElementCreateSystemWide()` 的 `kAXFocusedUIElementAttribute`，跟的是跨应用
的键盘焦点。改为 `focusedElement(inApplicationWithPID:)`，用
`AXUIElementCreateApplication(pid)` 问目标应用自身的焦点元素——该值不受哪个
应用持有系统焦点影响。不变量未变，只改了"当前"的解析方式；原系统级辅助函数
已无调用者，删除。

再修后替换成功，但「恢复原文」失败。原因是 A1–A4 有两份拷贝，`sharedPrechecks`
那份没有豁免。这次没有补第二份，而是抽出共用的
`frontmostApplicationIsAcceptable(pid:)`，两条路径都调用它；
`currentExternalPID() == pid` 这种写法在文件中已归零。

## 安全边界

唯一被豁免的是**本进程**。用户切到任何其他应用时 A2 照常拒绝；A1（应用存活）、
A3（窗口身份）、A4（元素身份）、能力检查、Secure Input、B1（内容未变）、
settable 全部原样保留。丢掉的只有"用户切到了本工具自己的面板"这一种情形，
而它正是点确认／恢复按钮的必然组成部分。

## 验证结果

| 场景 | 结果 |
| --- | --- |
| 鼠标点「确认替换」 | 成功，`replacement-stage=completed`，expected 62 → observed 71 |
| 接着点「恢复原文」 | 成功，原文还原 |
| 自动化测试 | 203 tests / 0 failures |

## 测试覆盖的实际边界（必须如实披露）

- **缺陷 1、3、4 可单元测试**：合成宿主走 `authoritativeTarget` 分支，
  `setFrontmostApplication` 能把聚焦应用指向测试进程本身。缺陷 3 的 RED 是
  203 tests / 1 failure 的真实失败。
- **缺陷 2 无法单元测试**：A3／A4 的真实 AX 解析在 `authoritativeTarget` 为
  `nil` 时才走，而合成宿主必然提供它；真实 AX 那半段代码没有可注入点。该修复
  的唯一证据是真机手动验证。
- **既有"真实环境验收"证据的可信度需要重新评估**：40 次 AXPress 驱动的自动化
  全绿，而真人一次即失败——因为 AXPress 不会让面板成为 key。这意味着 P5／P6
  中凡是脚本驱动的闭环证据，都无法覆盖"面板持有键盘焦点"这一真人必经路径。
  `T-032`、`T-033` 当初标记为人工通过，但若该缺陷是确定性的，人工点击本不该
  成功。**这一矛盾尚未解释，没有数据可供回溯判断，不予推测。**

## 方法论结论

1. 用 AXPress 点按钮来验证"点按钮"这一动作，与用 AX 写入验证 AX 写入能力
   （2026-07-29 已记录的循环论证）属于同一类错误：驱动方式绕过了被测路径的
   关键条件。真人操作不可被这种自动化替代。
2. 同一不变量存在两份实现拷贝，是缺陷 3 得以存在的直接原因。此类共享前置检查
   应保持单一定义。
3. 分级诊断是这条链能被定位的前提。此前七轮外部探针加一次错误归因，都源于
   失败只有一个笼统分类而没有阶段标识。
