# T-039 / T-046 可复现验收包汇总

## 任务边界

- 原任务：T-039 [Evidence] 汇总可复现验收包。
- 本文件于 2026-07-30 由 **T-046** 重写。T-039 的初版结论已被 Solar 的
  Implementation Gate REVIEW 推翻；Tasks Gate 重开后 T-046 是唯一的
  Implementation Gate `HANDOFF` 出口。
- 覆盖：FR-001 至 FR-013、NFR-001 至 NFR-007、AC-001 至 AC-017。
- 出口条件：逐项核对全部需求与验收场景，运行 build、unit-tests、
  `sdd-check`、`secret-scan`、`git diff --check`，无未解释失败。

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

- 单元与集成测试：**199 tests, 0 failures**
- 构建：`./scripts/build.sh` → `BUILD SUCCEEDED`
- 工程结构检查：由测试套件内的 `ProjectStructureTests` 承担，随
  `./scripts/unit-tests.sh` 一并执行 → passed。**更正**：本文件先前各版本与
  T-016／T-024／T-028／T-031 等证据文件记有 `./scripts/project-structure-check.sh`
  → passed，但该脚本在仓库中并不存在（`scripts/` 下只有 `build.sh`、
  `find-xcode-container.sh`、`sdd-check.sh`、`secret-scan.sh`、`unit-tests.sh`，
  且 `git log` 中该路径无任何提交记录）。结构检查本身确实在执行，只是入口是
  测试而非脚本；上述记法为笔误，已在此更正。
- SDD 制品校验：`./scripts/sdd-check.sh` → passed
- 凭据扫描：`./scripts/secret-scan.sh` → 无命中
- 空白与冲突标记：`git diff --check` → 无输出
- 测试总数演进：109（T-031）→ 121（首次 HANDOFF）→ 149（T-021 RED）→
  172（五项 Finding 修复后）→ 180（MUST 2）→ 184（MUST 3）→ 199（MUST 1），
  净增 90，全部由失败优先测试驱动
- 详见 `evidence/T-040-downstream-automation-revalidation.md` 与
  `evidence/T-047-second-review-must-fixes.md`

## 三、证据索引

**基础与探针**

- 工具链：`evidence/T-001-toolchain.md`
- 快捷键与安全输入探针：`evidence/T-007-hot-key-stop-conditions.md`
- 面板几何探针：`evidence/T-010-panel-stop-conditions.md`
- 合成 AX 宿主：`evidence/T-029-synthetic-ax-host.md`
- 合成端到端：`evidence/T-030-end-to-end-red.md`、
  `evidence/T-031-end-to-end-green.md`

**批准后的恢复算法（Plan `0c9883f`）**

- 失败优先测试：`evidence/T-021-recovery-algorithm-red.md`
- 最小实现：`evidence/T-022-recovery-algorithm-green.md`

**P5 真实环境验收**

- TextEdit 闭环：`evidence/T-032-textedit-closed-loop.md`
- Chrome/ChatGPT 闭环：`evidence/T-033-chrome-chatgpt-closed-loop.md`
- VS Code 后备闭环：`evidence/T-034-vscode-fallback-closed-loop.md`
- 权限／安全／失败恢复矩阵（11 项）：
  `evidence/T-035-permission-safety-recovery-matrix.md`
- 性能与显示（20 个延迟样本）：`evidence/T-036-performance-display.md`
- 代表性文字矩阵：`evidence/T-037-representative-text-matrix.md`
- ChatGPT 多行专项（Finding 5）：
  `evidence/T-037-chatgpt-multiline-followup.md`
- 隐私与安全审计（6 维）：`evidence/T-038-privacy-security-audit.md`

**P6 恢复算法重写后的下游复核**

- 自动化复核：`evidence/T-040-downstream-automation-revalidation.md`
- TextEdit selected recovery：
  `evidence/T-041-textedit-selected-recovery-revalidation.md`
- ChatGPT whole-field recovery：
  `evidence/T-042-chatgpt-wholefield-recovery-revalidation.md`
- 恢复状态与访问计数：
  `evidence/T-043-recovery-state-and-counts-revalidation.md`
- UTF-16 特殊字符夹具：
  `evidence/T-044-utf16-recovery-fixtures-revalidation.md`
- 定向隐私审计：`evidence/T-045-recovery-privacy-audit.md`

**P7 第二轮 Implementation Gate REVIEW 的三项 MUST**

- 失败分类保留、剪贴板重试语义、不含内容的分级诊断：
  `evidence/T-047-second-review-must-fixes.md`

**范围外观察与决策**：`evidence/out-of-scope-observations.md`

## 四、功能需求逐项核对

- **FR-001 全局触发**：T-005／T-006 测试 + T-007 真实探针；注册冲突或失败
  呈现 `hotKeyConflict` 并提供 `retryRegistration`（`4b25cd1`、`e724ba3`，
  由 `HotKeyRegistrationFailurePresentationTests` 与
  `FailureRecoveryGuidanceTests` 断言）。达成。
- **FR-002 权限门禁**：T-015／T-016 测试 + T-035 第 6–8 项；深链回退现在
  始终给出手动导航路径（`e724ba3`）。达成。
- **FR-003 拒绝安全输入**：门禁位于任何捕获之前，且拒绝时结束旧会话
  （`e22c7b8`）；T-007 探针 + T-035 第 9 项 + T-038 第四节。达成。
- **FR-004 选区优先读取**：T-019／T-020 测试；T-032／T-041 选区路径、
  T-033／T-042 无选区全文路径。达成。
- **FR-005 空内容与不支持目标**：T-035 第 1、2 项。达成。
- **FR-006 确定性验证结果**：T-011／T-012 测试 + T-037 六类文字 +
  T-044 代理对与组合字符逐 code unit 精确。达成。
- **FR-007 安全悬浮预览**：T-008／T-009／T-025／T-026 测试 + T-010 探针 +
  T-036 多显示器；预览现在披露原文与结果（`abe4389`，
  `PreviewContentDisclosureTests`）。达成。
- **FR-008 显式预览操作**：T-027 按钮矩阵（十种状态）+ T-043 两条恢复路径的
  按钮矩阵实测。达成。
- **FR-009 目标重新验证**：共享前置检查 A1–A4 与路径化 settable 检查
  （T-021／T-022）；元素级 `AXObserver` 已进入生产装配（`abe4389`，
  `ProductionTargetMonitorAssemblyTests`）；T-033／T-035 第 3 项过期拦截。
  达成。
- **FR-010 替换与后备**：T-032／T-041 选区替换、T-033／T-042 全文替换；
  Chromium 选区写入不生效时 fail-closed；VS Code 剪贴板后备（T-034）。达成。
- **FR-011 单一活动会话**：T-013／T-014 测试 + T-035 第 4 项重复触发。达成。
- **FR-012 原文可恢复**：批准算法的 W1–W4 与 C1–C4／R1–R3；T-041 命中 R2
  fallback、T-042 whole-field 恢复指纹一致、T-043 恢复失败零额外写入、
  T-044 特殊字符逐 code unit 还原。达成。
- **FR-013 临时内容生命周期**：T-038 第三、六节 + T-045 审计项二、四；
  竞态路径新增 `releaseStaleCapture`／`clearActiveTargetState`（`e22c7b8`，
  `SessionLifecycleRaceTests`）。达成。

## 五、非功能需求逐项核对

- **NFR-001 响应速度**：TextEdit 与 ChatGPT 各 10 次，20/20 样本在 300ms 内
  （最大 118.4ms），要求为每组至少 9/10。达成。
- **NFR-002 确认前零修改**：全部自动化路径断言确认前 setter 为 0；
  T-032／T-033 预览前零写入；T-043 恢复失败零额外写入。达成。
- **NFR-003 最低兼容标准**：TextEdit 与 ChatGPT 完整闭环（含多行，见
  T-037 后续文件），VS Code 显式剪贴板后备闭环。达成。
- **NFR-004 输入健壮性**：T-037 六类文字含精确 10,000 字符长文本；
  T-044 代理对与组合字符。达成。
- **NFR-005 显示安全**：T-010 探针 + T-036 第三节。达成。
- **NFR-006 隐私**：T-038 第一、二、五节 + T-045；剪贴板三个用户显式入口且
  `currentHostOnly`，T-043 实测指纹前后一致。达成。
- **NFR-007 恢复信息可理解**：十种预览状态均为中文可理解说明且至少一个安全
  下一步；恢复失败按原因细化文案（T-043）；剪贴板读取失败与空内容区分、
  复制失败显式呈现（`e724ba3`）。达成。

## 六、验收场景逐项核对

- **AC-001**：T-032／T-033 + T-036 延迟样本。达成。
- **AC-002**：T-007 注册层 `.conflict` + `hotKeyConflict` 状态与
  `retryRegistration` 动作。达成。
- **AC-003**：T-035 第 6–8 项 + 深链回退手动导航指引。达成。
- **AC-004**：T-007 探针 + T-035 第 9 项 + T-038 第四节。达成。
- **AC-005**：T-032 + T-041（范围外逐 code unit 不变）。达成。
- **AC-006**：T-033 + T-042（whole-field W1–W4）。达成。
- **AC-007**：T-035 第 1、2 项。达成。
- **AC-008**：T-017 spy 计数 + T-043 剪贴板指纹实测。达成。
- **AC-009**：T-033、T-035 第 3 项 + 生产元素级监控。达成。
- **AC-010**：T-034 VS Code 后备闭环。达成。
- **AC-011**：T-035 第 4 项 + T-030 旧会话回调被忽略。达成。
- **AC-012**：T-032／T-041／T-042 恢复成功。达成。
- **AC-013**：T-035 第 11 项 + T-043 失败路径（2 按钮、零额外写入）。达成。
- **AC-014**：T-038 第三、六节 + T-045。达成。
- **AC-015**：T-010 + T-036 第三节。达成。
- **AC-016**：T-037 + T-044。达成。
- **AC-017**：T-032（TextEdit 人工 ⌘Z）、T-033（ChatGPT ⌘Z）、
  T-041（脚本场景下 AX 写入不进 TextEdit undo 栈）、
  T-042（Chrome 会把 AX 写入放进 undo 栈）。已记录，含跨应用差异。

## 七、已知限制与残余风险（提交审核时如实披露）

1. **Chromium 网页内容不支持选区直接写入**：ChatGPT 输入框存在非空选区时
   写入返回成功但不生效，回读确认失败后 fail-closed；同一场景还可能因选区
   变化通知先被判为过期目标。两条路径都不写入、原文不变、结果可复制。
   AC-005 的必须环境为 TextEdit，不影响验收。详见 T-033。
2. **Chromium 异步应用辅助功能写入**：`setText` 返回后立即回读仍是旧值，
   必须依赖最多 5 次、约 500ms 的回读重试；多行尤其贴近该预算边缘。
   详见 T-042 与 T-037 后续文件。
3. **ChatGPT 多行的历史间歇失败无法回溯归类**：2026-07-31 用不含内容的分级
   诊断采集 40 次触发，37 次进入替换路径且全部 `completed`，`failure != none`
   的记录数为 0；另 3 次失败在**捕获**阶段（`emptyOrUnsupported`），延长自动化
   的粘贴沉降间隔后消失，属脚本时序而非产品缺陷。六个假设此前已被实测排除
   （换行形式、元素来源、引用陈旧、增强模式时序、面板在屏、确认前停留时长）。
   **此处更正前一版验收包的表述**：原文称"失败发生在 `validate` 的 A1–A4 之一"，
   该归因建立在一次尚无埋点的采集上，本轮 A1–A4 拒绝记录为 0，结论撤回。
   历史失败未留下阶段数据，无法回溯归类。详见 T-037 后续文件与 T-047。
4. **R2 判定无法区分插入点来源**：`kAXSelectedTextRange` 只反映当前状态，
   "应用写入后自动塌陷"与"用户随后把光标移入结果范围"在 AX 层完全相同，
   两者都会进入受约束 fallback。安全性由六项前置条件的内容与范围外一致性
   校验保证，而非插入点来源。已在 Plan `0c9883f` 中明确批准并披露。
5. **whole-field setter 的 TOCTOU 残余风险**：AX 无 compare-and-swap 语义。
   紧邻基值校验、范围内外一致性检查、外部监控与写后回读只能降低基值读取与
   setter 之间被并发改写的概率，不能原子消除；回读用于检测不符并报告
   `recoveryTargetChanged`，不能撤销已发生的覆盖。已在 Plan 中如实记录。
6. **VS Code 不支持直接读写**：Electron 自绘编辑器不暴露可用 AX 文本属性，
   只能走用户主动剪贴板后备路径。spec 已预期。详见 T-034。
7. **面板按钮的无障碍验收未完成**：已为按钮与内容区域加
   `accessibilityLabel`，但 VoiceOver 操作与焦点顺序的完整验收超出 001 范围，
   已建立追踪项 https://github.com/yjsyzmz/prompt/issues/3。
8. **脚本化验证的环境干扰**：AppleScript／System Events 驱动会启用系统增强
   辅助功能模式；T-035 中需要 `ready` 状态的场景因此采用真人操作。P6 的驱动
   改用真实粘贴事件后未再出现该干扰。
9. **微信输入框不支持直接读取**（范围外）：自绘 UI 不暴露 AX 文本属性，
   读取阶段 fail-closed。详见 `evidence/out-of-scope-observations.md`。
10. **验证环境注意事项**：每次重建二进制后 macOS 会使辅助功能授权失效——
    开关仍显示开启但 TCC 记录不匹配。需将开关关闭再打开（可通过辅助功能 API
    自动完成）。不知此点会把授权失效误判为读写缺陷。2026-07-31 的重建后授权
    仍然有效，说明该现象并非每次重建必然出现。
11. **稳定性样本的覆盖面有限**：2026-07-31 的 40 次触发全部来自同一台机器、
    同一 Chrome 版本、同一个两行夹具，且由自动化驱动。跨机器、跨 Chrome 版本、
    跨输入框类型以及真人操作节奏下的稳定性未验证。详见 T-037 后续文件。
12. **分级诊断经 `os_log` 输出**：`replacement-stage` 记录会进入统一日志。
    `ReplacementStageReport` 在类型上不含 `String` 字段，只有阶段标识、失败
    分类与 UTF-16 长度，因此不存在内容外泄路径；但长度本身是可观测的元数据，
    已如实披露。详见 T-047 与 T-045。

## 八、范围决策记录

用户于 2026-07-28 选择方案 A：Chrome 页面内选区替换与"所有输入框无差别
可用"两项硬需求超出 Feature 001 已批准范围，作为新 Feature 走独立
Spec Gate；Feature 001 按现有规格收尾。详见
`evidence/out-of-scope-observations.md`。

## 九、Gate 历史与生产变更清单

**Gate 历史**

- Implementation Gate 首次审核 `ebb6978` → `CHANGES REQUESTED`（6 项 MUST）
- Plan Gate 重开三版修订：`1333438` → `dd939a4` → `0c9883f`（Solar `PASS`）
- Tasks Gate 重开两版修订：`ae99e29` → `a8d0327`（Solar `PASS`）
- Implementation Gate 第二次审核 `9bb221e` → `CHANGES REQUESTED`（3 项 MUST）
- 本次为三项 MUST 修复后的第三次 Implementation Gate `HANDOFF`

**T-031 之后的全部生产代码变更**

1. `d95228e` — T-032 真实环境阻塞修复（工作区监控忽略自身激活、面板可接受
   点击、Chromium 手动辅助功能后备、恢复与权限文案、写入回读确认）。其中
   `restoreCollapsedSelection` 属未经批准的设计变更，已由重开的 Plan Gate
   正式处置（见下条与第七节第 4、5 项）。
2. `c3c1fa2` — 回读重试（最多 5 次、约 500ms）。
3. `8b75e6f` — 延迟仪器（只输出毫秒，不含内容，未引入按键监听）。
4. `4b25cd1` — `PreviewStatus.hotKeyConflict` 与注册失败呈现。
5. `b20446d` — **批准后的恢复算法**：A1–A4 共享前置检查、路径化 settable
   检查、replacement B1–B2、recovery 按 capture mode 分支、whole-field
   W1–W4、selected C1–C4 与 R1／R2／R3、含六项门禁的
   `restoreViaSelectedRangeFallback`；删除 `restoreCollapsedSelection` 与
   `recoveryTextFromFullValue`。
6. `abe4389` — Finding 1 预览披露原文与结果；Finding 2 元素级 `AXObserver`
   进入生产装配，删除仅监听应用激活的 `WorkspaceTargetChangeMonitor`。
7. `e22c7b8` — Finding 4 过期捕获释放 handle 与监控、安全输入拒绝时结束旧
   会话；新增资源计数查询。
8. `e724ba3` — Finding 6 复制失败呈现、剪贴板读取失败与空内容区分、设置深链
   手动导航指引、快捷键冲突重新注册。
9. `1ce9d01` — Finding 7 按钮与内容区域的 `accessibilityLabel`。
10. `d505e32` — 第二轮 MUST 2：`PreviewCapability.replacementRejected`、
    `SessionTextTargetAccessing.replace` 改为 `Result<Void, DomainFailure>`、
    `PreviewStatus.targetNotWritable`、`replacementRejectionStatus(for:)`。
    未发生写入的拒绝不再显示为写入失败。
11. `8f72296` — 第二轮 MUST 3：`PreviewUserAction.retryCopy` 与
    `pendingCopyRetry`，复制失败后的重试重放同一次复制而非重开会话。
12. `f1bda7a` — 第二轮 MUST 1：`ReplacementStage`、`ReplacementStageReport`、
    `ReplacementDiagnosticsRecording`，替换路径 11 个拒绝点逐一可分；报告在
    类型上不含 `String`，记录保持同步以避免在 A4 与 setter 之间引入
    suspension point。
13. `2792b1d` — 第二轮 MUST 1 的生产装配：`OSLogReplacementDiagnosticsRecorder`
    经 `makeReplacementDiagnostics()` 注入 `convenience init()`。

Finding 5 未产生代码变更，其结论为证据补齐 + 特定应用限制记录。

## 十、检查点

- **C0–C2**：维持达成（T-004、T-007／T-010、T-014）。
- **C3 — 系统边界可控**：达成。T-021／T-022 按批准算法重写并转绿；T-040
  自动化复核确认 T-027 与各适配器套件全部通过；权威写入验证未被监控事件取代。
- **C4 — 合成闭环通过**：达成。T-030／T-031 套件在 T-040 的两次运行中通过，
  全部生产装配仍由失败测试驱动。
- **C5 — 真实验收完整**：达成。TextEdit 与 ChatGPT 完整闭环（含多行）、
  VS Code 后备闭环、性能／显示／输入／隐私证据，以及 P6 的 T-040 至 T-045
  全部完成且可复现。2026-07-31 追加 40 次 ChatGPT 多行触发的分级诊断数据，
  见 T-037 后续文件。

## 结论

全部 13 条功能需求、7 条非功能需求、17 个验收场景均已逐项核对并有可复现证据
支撑。199 个自动化测试全绿，build、unit-tests（含 `ProjectStructureTests`）、
sdd-check、secret-scan、`git diff --check` 无未解释失败。C3、C4、C5 达成。

第七节的 12 项已知限制与残余风险、第八节的范围决策一并提交 Reviewer 裁决。
需要 Reviewer 重点确认的披露事项：第 3 项（ChatGPT 多行历史间歇失败无法回溯
归类，并撤回前一版的 A1–A4 归因）、第 4、5 项（R2 来源不可区分、whole-field
setter 的 TOCTOU）、第 11 项（稳定性样本覆盖面有限）、第 12 项（分级诊断的
长度元数据经统一日志可观测）。

可以针对三项 MUST 修复后的新 SHA 发布 Implementation Gate `HANDOFF`。
