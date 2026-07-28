# T-034 VS Code 后备闭环验证证据

## 任务边界

- 任务：T-034 [Verification] 验证 VS Code 后备闭环。
- 依赖：T-031 GREEN（见 `evidence/T-031-end-to-end-green.md`）。
- 要求记录：先记录直接读写实际能力；无可靠支持时验证用户主动剪贴板
  输入、明确复制结果和手动粘贴路径，证明无自动剪贴板访问且不修改
  无关文字。
- 覆盖：FR-010, NFR-002, NFR-003, NFR-006, AC-010。

## 验证环境

- Mac：MacBook Pro（Mac15,3，Apple M3，8 GB）
- macOS：26.5.2（25F84）
- 目标应用：Visual Studio Code（Electron/Chromium 宿主，无标题编辑器缓冲区）
- 应用构建：Debug、universal，代码状态 `c3c1fa2`
- 输入内容：仅 `SYNTHETIC-001` 标记的合成文字；无真实用户内容

## 第一步：直接读写能力（2026-07-28，人工操作）

- 操作：VS Code 无标题文件内输入 `SYNTHETIC-001 测试文字`，光标置于
  编辑器内，触发 ⌃⌥⌘P。
- 结果：直接读取失败，未进入可确认预览（操作者反馈："第一步失败了"）。
- 定性：VS Code 编辑器区域是 Electron 自绘文本视图，不暴露可用的标准
  辅助功能文本属性，捕获阶段即 fail-closed，不写入目标。行为符合
  FR-010 与 spec 对 VS Code 的"后备路径"定位——spec 未要求 VS Code
  支持直接替换。

## 第二步：用户主动剪贴板后备路径（2026-07-28，人工操作）

- 操作序列：用户在 VS Code 选中合成文字并手动按 ⌘C → 在面板点击
  "使用剪贴板" → 预览出现后点击"复制结果" → 回到 VS Code 手动按 ⌘V。
- 结果：粘贴内容为
  `【系统交互验证】\nSYNTHETIC-001 测试文字`
  与 `DeterministicTransformer` 的预期输出逐字符一致（操作者反馈
  2026-07-28）。后备闭环（用户复制 → 显式读取 → 预览 → 显式复制结果
  → 用户手动粘贴）走通。
- 无自动剪贴板访问：剪贴板读取仅由"使用剪贴板"点击触发
  （`AppLifecycleController.beginClipboardInputSession`，见
  `Sources/SystemInteractionFoundation/AppLifecycleController.swift:206`），
  写入仅由"复制结果"点击触发；第一步的直接读取失败路径未发生任何
  剪贴板访问（面板在用户点击前不读剪贴板）。该约束的精确计数由
  T-017/T-018 的 spy 测试覆盖（见 `evidence/T-017-clipboard-policy-red.md`、
  `evidence/T-018-clipboard-policy-green.md`），NFR-006 保持成立。
- 不修改无关文字：应用在此路径下不执行任何 AX 写入，文档内容的唯一
  变化来自用户本人的 ⌘V 粘贴动作，粘贴范围即用户自己的选区，其余
  文字未被触碰。

## 结论

T-034 要求记录的行为均已验证：VS Code 直接读写不受支持并 fail-closed
（无写入、无剪贴板访问），用户主动剪贴板输入 + 明确复制结果 + 手动粘贴
的后备路径完整可用且输出正确。AC-010 达成，NFR-006 未被破坏。VS Code
的直接替换不属于 spec 必须支持场景，本任务不触发硬停止条件。
