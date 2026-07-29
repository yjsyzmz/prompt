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

**勘误（2026-07-28）：** 本节初版只列出 `8b75e6f` 与 `4b25cd1`，漏报了
T-031 之后的 `d95228e` 与 `c3c1fa2`。Solar 在 Implementation Gate 审核中
指出该披露不完整。以下为 T-031（合成闭环 GREEN）之后全部生产代码变更的
完整清单，按提交顺序排列：

1. `d95228e` — **T-032 真实环境阻塞修复（11 个文件，+490 行）。** 内容：
   工作区监控忽略本应用自身激活（预览点击不再误判 staleTarget）；
   nonactivating 面板可成为 key window 并接受 first mouse（按钮可点击）；
   系统级焦点查询失败时启用 Chromium/Electron 手动辅助功能后备
   （`AXManualAccessibility`／`AXEnhancedUserInterface`）；补充具体的恢复
   与权限重新检测文案；所有直接写入与恢复增加回读确认。
   **其中包含一项未经 Plan Gate 批准的设计变更**：
   `restoreCollapsedSelection` 在 selected 模式恢复时改用 whole-field
   setter，以应对 TextEdit 写入后选区塌陷。该变更已按用户 2026-07-28 的
   决策重开 Plan Gate 正式批准（见 `plan.md` 的"塌陷选区例外"与
   Plan Gate record 修订记录）。
2. `c3c1fa2` — **回读重试（`AccessibilityGateway.swift` +22 行、
   `AXAuthoritativeWriteRecoveryTests.swift` +29 行）。** Chromium 渲染进程
   异步应用辅助功能写入，单次立即回读会把成功的替换误判为失败；改为最多
   5 次、约 500ms 重试后才 fail-closed。
3. `8b75e6f` — 新增延迟仪器（`PresentationLatencyRecording` +
   `OSLogPresentationLatencyRecorder`）。T-036 要求从 hot-key callback
   起算的 300ms 证据，而原实现没有任何生产测量点。仪器只输出毫秒数，
   不含内容，未引入按键监听。
4. `4b25cd1` — 新增 `PreviewStatus.hotKeyConflict` 并在 `start()` 注册
   失败时呈现。修复 FR-001／AC-002 的实现缺口：原先 `AppEntry` 丢弃
   `start()` 返回值且状态矩阵无冲突状态，快捷键被占用时应用静默无响应。

## 结论

**本包结论已于 2026-07-28 被 Reviewer 推翻，正在修订中。**

Solar 对 `ebb697826cb5e67546ea01aabda1181cd9e15471` 的 Implementation Gate
审核结论为 `CHANGES REQUESTED`，提出 6 项 MUST，本包原先"全部达成"的判定
不可采信。已确认成立的需求覆盖缺口：

1. 有效预览未展示原文与确定性结果（FR-006／FR-007／FR-008、US-002）；
2. `AXTargetMonitor` 未进入生产装配，同应用内窗口／元素／选区变化不会提前
   禁用确认（FR-009／AC-009）；
3. P5 生产变更披露不完整，且含未经批准的恢复写入策略变化（已见第九节勘误，
   并已重开 Plan Gate）；
4. 过期异步捕获可能遗留 AX handle 与内容引用；安全输入重复触发不结束旧会话
   （FR-013／AC-014）；
5. ChatGPT 代表性多行验证缺失（NFR-004、Plan 第 327 行）；
6. 剪贴板读写失败静默、设置深链回退缺手动导航说明、快捷键冲突状态缺重新
   注册指引（NFR-007／FR-002／AC-002／AC-003）。

修订顺序：先完成 Plan Gate 修订与审核（塌陷选区例外），取得 `PASS` 后再
逐项修复上述 Implementation 缺口、补齐测试与证据，然后针对新 SHA 重新发布
Implementation Gate `HANDOFF`。第七节的已知限制清单也将随之更新——其中
第 4 项（设置深链）已被 Reviewer 判定为 FR-002／AC-003 的实现缺口，不能
仅作为限制接受；第 5 项（按钮 AX 名称）需建立可追踪需求而非仅留 Open
question。
