# T-010 面板停止条件探针阶段证据

## 结论

T-010 已完成真实多显示器、主／副屏边缘、全屏 Space、非默认缩放以及 TextEdit、Chrome/ChatGPT 两类目标的人工探针。所有已执行样例均满足：

- panel 展示前后目标应用保持 frontmost；
- 目标输入区保持 focused / active；
- panel `isVisible=true`、`isKeyWindow=false`；
- probe 应用 `isActive=false`，展示边界的应用激活调用数为 0；
- 320×180 point panel 完整包含在目标显示器的安全 frame 内。

已执行样例没有触发“目标焦点与完整面板不能同时成立”的硬停止条件。但是，当前机器始终连接两块显示器；分别在每块屏幕上运行不等于真正的单显示器环境。未能通过当前可访问的 macOS 控件安全停用 HP E223，因此 T-010 **保持部分完成**，`tasks.md` 不勾选，C1 不宣告达成。完成 T-010 需要物理断开副屏后补测单显示器样例。

## 环境

- Mac：MacBook Pro `Mac15,3`，Apple M3，8 核 CPU，8 GB 内存
- macOS：26.5.2（25F84）
- TextEdit：1.20
- Google Chrome：150.0.7871.127
- 合成内容：仅 `SYNTHETIC-001`
- probe：`/private/tmp` 一次性 harness，直接编译 T-009 的 `PanelProbeFactory`、`NonactivatingPanelPresenter` 与 `PanelProbeGeometry`；未进入仓库、未接入产品入口
- 面板：320×180 points，安全边距 12 points，无交互、无 AX 读写、无剪贴板访问

未将真实用户内容、截图、窗口标题、URL、剪贴板或输入内容写入仓库证据。

## 显示器基线

默认配置下 `NSScreen` 报告：

| 屏幕 | frame（points） | visibleFrame（points） | scale | 布局 |
| --- | --- | --- | --- | --- |
| Built-in Retina Display | `(0, 0, 1512, 982)` | `(0, 54, 1512, 895)` | 2 | 主屏 |
| HP E223 | `(-154, 982, 1920, 1080)` | `(-154, 982, 1920, 1050)` | 1 | 位于主屏上方，X 为负坐标 |

这同时覆盖真实异构 scale factor、负坐标和非水平排列。单显示器专用配置尚未覆盖。

## 人工矩阵

| 目标／环境 | 位置 | 关键证据 | 结果 |
| --- | --- | --- | --- |
| TextEdit，主屏默认缩放 | 左上、右上、左下、右下 | `frontmostBefore/After=com.apple.TextEdit`；输入区保持 focused；四个 frame 均完整包含于主屏 safe frame | PASS |
| TextEdit，真实副屏 | 左上、右下 | screen=`HP E223`、scale=1；负 X 与上方 Y 坐标保留；panel 完整包含 | PASS |
| TextEdit，全屏 Space | 右上 | full-screen rule 使用 `(12, 12, 1488, 958)`；panel=`(1180, 769, 320, 180)`；TextEdit 保持 frontmost/focused | PASS |
| Chrome/ChatGPT，普通窗口 | 右下 | `frontmostBefore/After=com.google.Chrome`；ChatGPT textbox 在展示期间仍是 DOM `activeElement`，内容为未发送的 `SYNTHETIC-001`；panel 完整包含 | PASS |
| Chrome/ChatGPT，全屏 Space | 左上 | full-screen rule；panel=`(12, 769, 320, 180)`；Chrome 保持 frontmost，ChatGPT textbox 仍 active | PASS |
| TextEdit，非默认缩放 | 右上 | 从系统标注的 `1512×982（默认）` 临时切至 `1352×878`；`NSScreen.frame` 同步变为 1352×878；panel=`(1020, 656, 320, 180)` 并完整包含；输入区保持 focused | PASS |
| 物理单显示器 | — | 当前无法在不依赖用户物理操作的情况下安全停用 HP E223 | NOT RUN |

副屏右下短样例在 panel 已验证后的关闭采样时被另一个后台应用抢到 frontmost；展示后的权威采样仍为 TextEdit，且其他 TextEdit 样例稳定。该环境干扰未归因于 panel，也没有被用作 PASS 的唯一证据。

## 非默认缩放恢复

探针前内建屏为系统明确标记的 `1512×982（默认）`。探针期间临时选择 1352×878，完成后恢复默认。最终 `NSScreen` 报告重新为：

- Built-in Retina Display：1512×982，scale 2
- HP E223：1920×1080，scale 1

没有保留显示器设置变化。

## 清理与范围

- Chrome/ChatGPT 的合成内容没有发送；agent 创建的 ChatGPT 测试标签页已关闭，原 Chrome 页面已恢复。
- TextEdit 合成文稿触发“立即删除且无法撤销”确认。未获得永久删除的单独确认，因此取消删除并保留一份标题为“未命名”、内容仅为 `SYNTHETIC-001` 的文稿窗口。
- 未修改生产源文件、Xcode 工程、测试或依赖。
- 未执行 T-011 或任何后续任务。
- 未测试 AX 读取、替换、恢复、剪贴板、提示词处理或正式 UI。

## 下一步与解除条件

请物理断开 HP E223，使 `NSScreen.screens.count == 1`，然后重新执行 T-010 的 TextEdit 主屏边缘样例。只有该样例同时满足 frontmost、focused、non-key 与完整包含条件后，才勾选 T-010 并宣告 C1 达成；在此之前不得开始 T-011。
