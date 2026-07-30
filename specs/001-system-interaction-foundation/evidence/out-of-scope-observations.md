# 范围外兼容性观察与决策记录

本文档记录人工验证期间发现的、超出 Feature 001 规格范围的观察和用户决策。
这些条目不参与 Feature 001 验收，仅为后续 Feature 的 Spec Gate 提供输入。

## 观察 1：微信输入框不支持直接读取（2026-07-28）

- 环境：与 T-032/T-033 相同（macOS 26.5.2，代码状态 `c3c1fa2`）。
- 现象：焦点位于微信聊天输入框、包含合成文字时触发 ⌃⌥⌘P，面板显示
  "没有可处理的文字，或当前输入位置不支持直接读取。"（`emptyOrUnsupported`），
  未发生任何写入。
- 定性：微信使用自绘 UI，其输入框不暴露标准辅助功能文本属性
  （`kAXValue` / `kAXSelectedText`），读取阶段即 fail-closed。行为符合
  FR-010（不确定即不动原文）。微信不属于 spec 定义的必须支持应用
  （TextEdit、Chrome/ChatGPT、VS Code），不影响 NFR-003 达标判定。

## 需求 2：Chrome 选区替换与"所有输入框无差别可用"（2026-07-28）

- 用户提出两个硬需求：(1) Chrome 页面内选区替换必须可用；
  (2) 所有输入框（含微信）无差别可用。
- 技术评估：两者均需引入当前 plan 明确排除的第二种写入策略
  （全文拼接写入或模拟粘贴注入），后者还与 NFR-006
  （禁止自动触碰剪贴板）冲突，属于范围变更。

## 用户决策（2026-07-28）

- 用户选择方案 A：Feature 001 按现有规格范围收尾验收；
  上述两个需求作为新 Feature 走独立 Spec Gate 处理。
- 影响：T-033 中 Chromium 选区限制维持"特定应用限制"定性；
  微信观察按本文档记录，不新增 Feature 001 验收项。

## 观察 3：预览面板按钮缺少辅助功能名称（2026-07-29）

- 来源：Solar 对 `ebb6978` 的 Implementation Gate REVIEW，Finding 7（SHOULD）。
- 现象：通过 AppleScript／System Events 读取本应用面板时，按钮的 AX 标题为
  `missing value`，读屏用户听不到按钮名称，只能感知按钮数量与顺序。
- 定性：Feature 001 的 spec 未定义读屏与无障碍验收条款，因此不阻塞 001 的
  Implementation Gate；按 Reviewer 要求转为可追踪需求，不再以 Open question
  形式悬置。
- **追踪项：** https://github.com/yjsyzmz/prompt/issues/3
  （其中定义了按钮 AX 标签、VoiceOver 操作、焦点顺序、内容区域可读性与
  验证方式共五项验收标准。）
- 本轮已做的低成本改善：`PreviewContentView` 为原文／结果两段内容加了
  `accessibilityLabel`，并为每个按钮加了与可见标题一致的
  `accessibilityLabel`；完整的 VoiceOver 操作与焦点顺序验收仍留待上述追踪项。

## 观察 4：验证环境——重建二进制后辅助功能授权失效（2026-07-30）

- 现象：每次重新构建应用后，系统设置中的辅助功能开关**仍显示为开启**，但
  TCC 记录已与新的可执行文件不匹配，应用持续显示
  "需要辅助功能权限才能读取或替换目标文字。"
- 处理：将该应用的开关关闭再打开即可恢复。该操作可完全自动完成——通过
  辅助功能 API 定位 `checkbox "SystemInteractionFoundation"` 后点击两次，
  不需要人工介入。
- 影响：属验证环境注意事项，不是产品缺陷。若不知此点，会把授权失效误判为
  读取或写入缺陷。本项应随验收包一并提交，供后续 P6 复核参考。
