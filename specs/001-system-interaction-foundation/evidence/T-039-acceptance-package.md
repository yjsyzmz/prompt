# T-039 可复现验收包汇总

## 任务边界

- 任务：T-039 [Evidence] 汇总可复现验收包。
- 依赖：T-032 至 T-038 全部完成。
- 覆盖：FR-001 至 FR-013、NFR-001 至 NFR-007、AC-001 至 AC-017。
- 出口条件：逐项核对全部需求与验收场景，运行 build、unit-tests、
  `sdd-check`、`secret-scan`、`git diff --check`，无未解释失败后才可发布
  Implementation Gate `HANDOFF`。

## 一、环境与版本

- Mac：MacBook Pro（Mac15,3，Apple M3，8 GB）
- macOS：26.5.2（25F84）
- 工具链版本详见 `evidence/T-001-toolchain.md`
- 目标应用：TextEdit 1.20、Google Chrome 150.0.7871.184（chatgpt.com）、
  Visual Studio Code、Finder、Safari、微信（范围外观察）
- 显示环境：内置 Liquid Retina XDR（3024 x 1964 Retina）+ 外接
  1920 x 1080 @ 60Hz，均未镜像
- 应用构建：Debug、universal（arm64 + x86_64）
- 合成夹具：全部标记 `SYNTHETIC-001`，无真实用户内容

## 二、自动化结果

- 单元与集成测试：**121 tests, 0 failures**（`./scripts/unit-tests.sh`）
- 构建：`./scripts/build.sh` → `BUILD SUCCEEDED`
- 工程结构检查：`./scripts/project-structure-check.sh` → passed
- SDD 制品校验：`./scripts/sdd-check.sh` → passed
- 凭据扫描：`./scripts/secret-scan.sh` → 无命中
- 空白与冲突标记：`git diff --check` → 无输出
- 测试分层：领域与隐私契约、会话状态机、权限、剪贴板、AX 捕获、权威写入
  与恢复、AXObserver 隔离、屏幕几何、预览状态矩阵、合成 AX 宿主自检、
  端到端集成、延迟仪器、快捷键注册失败呈现

## 三、真实环境人工验证索引

- TextEdit 完整闭环：`evidence/T-032-textedit-closed-loop.md`
- Chrome/ChatGPT 完整闭环：`evidence/T-033-chrome-chatgpt-closed-loop.md`
- VS Code 后备闭环：`evidence/T-034-vscode-fallback-closed-loop.md`
- 权限／安全／失败恢复矩阵（11 项）：
  `evidence/T-035-permission-safety-recovery-matrix.md`
- 性能与显示（20 个延迟样本）：`evidence/T-036-performance-display.md`
- 代表性文字矩阵：`evidence/T-037-representative-text-matrix.md`
- 隐私与安全审计（6 个维度）：`evidence/T-038-privacy-security-audit.md`
- 高风险探针：`evidence/T-007-hot-key-stop-conditions.md`、
  `evidence/T-010-panel-stop-conditions.md`
- 范围外观察与用户决策：`evidence/out-of-scope-observations.md`

## 四、功能需求逐项核对

- **FR-001 全局触发**：热键注册与触发由 T-005/T-006 测试、T-007 真实探针
  覆盖；注册冲突或失败现在呈现 `hotKeyConflict` 状态（提交 `4b25cd1`），
  不再静默失效。达成。
- **FR-002 权限门禁**：T-015/T-016 测试；T-035 第 6、7、8 项真实验证
  权限缺失、深链降级、重新授权。达成（深链限制见第七节）。
- **FR-003 拒绝安全输入**：门禁位于任何捕获之前（审计见 T-038 第四节），
  T-007 探针 + T-035 第 9 项真实验证。达成。
- **FR-004 选区优先读取**：T-019/T-020 测试；T-032 选区路径、T-033 无选区
  全文路径真实验证。达成。
- **FR-005 空内容与不支持目标**：T-035 第 1、2 项真实验证，均提供可理解
  下一步。达成。
- **FR-006 确定性验证结果**：`DeterministicTransformer` 逐字符保真，
  T-011/T-012 测试 + T-037 六类文字真实验证。达成。
- **FR-007 安全悬浮预览**：T-008/T-009/T-025/T-026 测试 + T-010 探针 +
  T-036 第三节多显示器验证。达成。
- **FR-008 显式预览操作**：T-027 按钮矩阵测试 + T-032/T-033 真实确认、
  复制、取消。达成。
- **FR-009 目标重新验证**：写入前七步权威验证（T-021/T-022）；
  T-033 与 T-035 第 3 项真实验证过期目标拦截且零写入。达成。
- **FR-010 替换与后备**：T-032/T-033 成功替换；Chromium 选区写入不生效时
  fail-closed 并保留复制结果（T-033）；VS Code 剪贴板后备（T-034）。达成。
- **FR-011 单一活动会话**：T-013/T-014 测试 + T-035 第 4 项重复触发真实
  验证（面板刷新、无叠加）。达成。
- **FR-012 原文可恢复**：T-032/T-033 恢复成功；T-035 第 11 项真实验证
  恢复失败时保留原文并只提供复制原文；Undo 观察见 T-032/T-033。达成。
- **FR-013 临时内容生命周期**：T-038 第三、六节审计（不可 `Codable`、
  会话结束释放引用与 AX 句柄）。达成。

## 五、非功能需求逐项核对

- **NFR-001 响应速度**：TextEdit 与 ChatGPT 各 10 次，20/20 样本在 300ms
  内（最大 118.4ms），要求为每组至少 9/10。达成。
- **NFR-002 确认前零修改**：全部自动化路径断言确认前 setter 为 0；
  T-032/T-033 真实验证预览前零写入；所有拒绝路径零写入。达成。
- **NFR-003 最低兼容标准**：TextEdit 与 ChatGPT 完成完整闭环；VS Code
  完成显式剪贴板后备闭环并单独记录直接读写不受支持。达成。
- **NFR-004 输入健壮性**：T-037 记录中文、英文、混合、多行、特殊字符
  （含 emoji 与组合字符）、精确 10,000 字符长文本，无崩溃、无静默截断、
  无无关修改；长度已随结果记录，不作无限长度保证。达成。
- **NFR-005 显示安全**：T-010 探针覆盖单屏／多屏／全屏／边缘／非默认缩放；
  T-036 第三节记录双显示器布局与缩放。达成。
- **NFR-006 隐私**：T-038 第一、二、五节审计——无持久化真实内容、无内容
  日志／截图／测试产物／遥测，剪贴板仅三个用户显式入口且 `currentHostOnly`。
  达成。
- **NFR-007 恢复信息可理解**：八种预览状态全部为中文可理解说明且至少一个
  安全下一步，界面不显示原始错误码（T-027 测试 + T-035 真实文案记录）。
  达成。

## 六、验收场景逐项核对

- **AC-001**：T-032/T-033 触发成功 + T-036 延迟样本。达成。
- **AC-002**：T-007 注册层 `.conflict` + `hotKeyConflict` 状态呈现
  （`4b25cd1`，由测试断言 `start()` 在冲突与失败时呈现该状态）。达成。
- **AC-003**：T-035 第 6、7、8 项。达成。
- **AC-004**：T-007 探针 + T-035 第 9 项 + T-038 第四节。达成。
- **AC-005**：T-032 选区替换与前后字节不变。达成。
- **AC-006**：T-033 ChatGPT 全文替换。达成。
- **AC-007**：T-035 第 1、2 项。达成。
- **AC-008**：T-017 spy 计数 + T-032/T-033 取消零副作用。达成。
- **AC-009**：T-033 与 T-035 第 3 项过期目标拦截。达成。
- **AC-010**：T-034 VS Code 后备闭环。达成。
- **AC-011**：T-035 第 4 项重复触发 + T-030 旧会话回调被忽略。达成。
- **AC-012**：T-032/T-033 恢复原文。达成。
- **AC-013**：T-035 第 11 项恢复失败保留原文。达成。
- **AC-014**：T-038 第三、六节。达成。
- **AC-015**：T-010 + T-036 第三节。达成。
- **AC-016**：T-037 全部文字形态。达成。
- **AC-017**：T-032（TextEdit ⌘Z 还原）与 T-033（ChatGPT ⌘Z 还原）记录
  目标应用 Undo 行为。达成。

## 七、已知限制（提交审核时如实披露）

1. **Chromium 网页内容不支持选区直接写入**：ChatGPT 输入框存在非空选区时
   写入返回成功但不生效，回读确认失败后 fail-closed；同一场景还可能因
   Chromium 的选区变化通知先被判为过期目标。两条路径都不写入、原文不变、
   结果可复制。不属于任何必须验收场景（AC-005 的必须环境为 TextEdit）。
   详见 T-033。
2. **Chromium 异步应用辅助功能写入**：需最多 5 次、约 500ms 回读重试才能
   避免把成功替换误判为失败。10,000 字符规模下仍足够（T-037）。
3. **VS Code 不支持直接读写**：Electron 自绘编辑器不暴露可用的 AX 文本
   属性，只能走用户主动剪贴板后备路径。spec 已预期。
4. **辅助功能设置深链不生效**：点击"打开设置"后系统设置停在"通用"页，
   需用户自行导航到隐私与安全性 → 辅助功能。属 spec 已预期的降级分支，
   但体验不佳。详见 T-035 第 7 项。
5. **面板按钮未向辅助功能暴露标题**：AX 树中按钮标题为 `missing value`，
   读屏用户听不到按钮名称。spec 未定义无障碍要求，超出 001 范围，
   建议在后续 Feature 处置。
6. **脚本化验证的环境干扰**：AppleScript/System Events 驱动会启用系统
   增强辅助功能模式，与实现中的 `AXEnhancedUserInterface` 叠加后使目标
   立即被判过期，因此所有需要 `ready` 状态的场景一律采用真人操作。
   详见 T-035 采集方式说明。
7. **微信输入框不支持直接读取**（范围外）：自绘 UI 不暴露 AX 文本属性，
   读取阶段 fail-closed。微信不属于必须支持应用。详见
   `evidence/out-of-scope-observations.md`。

## 八、范围决策记录

用户于 2026-07-28 选择方案 A：Chrome 页面内选区替换与"所有输入框无差别
可用"两项硬需求超出 Feature 001 已批准范围，作为新 Feature 走独立
Spec Gate；Feature 001 按现有规格收尾。决策与技术评估见
`evidence/out-of-scope-observations.md`。

## 九、本轮实现变更说明

P5 验收阶段产生两处生产代码变更，均由失败优先测试驱动：

1. `8b75e6f` — 新增延迟仪器（`PresentationLatencyRecording` +
   `OSLogPresentationLatencyRecorder`）。T-036 要求从 hot-key callback
   起算的 300ms 证据，而原实现没有任何生产测量点。仪器只输出毫秒数，
   不含内容，未引入按键监听。
2. `4b25cd1` — 新增 `PreviewStatus.hotKeyConflict` 并在 `start()` 注册
   失败时呈现。修复 FR-001／AC-002 的实现缺口：原先 `AppEntry` 丢弃
   `start()` 返回值且状态矩阵无冲突状态，快捷键被占用时应用静默无响应。

## 结论

全部 13 条功能需求、7 条非功能需求、17 个验收场景均已逐项核对并有可复现
证据支撑。121 个自动化测试全绿，build、project-structure、sdd-check、
secret-scan、`git diff --check` 五道门禁无未解释失败。C5 达成，
可以发布 Implementation Gate `HANDOFF`。第七节的 7 项已知限制与第八节的
范围决策一并提交 Reviewer 裁决。
