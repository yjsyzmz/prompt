# T-040 自动化下游复核

## 任务边界

- 任务：T-040 [Verification] 自动化下游复核。
- 前置：T-022 已转绿（见 `evidence/T-022-recovery-algorithm-green.md`）。
- 完成条件：T-027、T-030／T-031 所在的完整相关测试与全量门禁连续两次全绿、
  无未解释失败，并记录测试总数与前后差异。
- 覆盖：FR-005、FR-007、FR-008、FR-009、FR-010、FR-012、NFR-002、AC-009、
  AC-012、AC-013。
- 代码状态：`29e15ef`
- 执行日期：2026-07-30

## 结果：连续两次全绿

两次运行结果完全一致：

```text
./scripts/unit-tests.sh              Executed 172 tests, with 0 failures  → TEST SUCCEEDED
./scripts/build.sh                   BUILD SUCCEEDED（universal Debug）
./scripts/project-structure-check.sh Project structure check passed.
./scripts/sdd-check.sh               SDD artifact validation passed.
./scripts/secret-scan.sh             No credential patterns detected in repository files.
git diff --check                     无输出
```

无 flaky、无未解释失败，因此不需要按恢复规则重跑。

## 测试总数变化

| 阶段 | 总数 | 说明 |
| --- | --- | --- |
| T-031 GREEN（原始合成闭环） | 109 | 端到端装配完成 |
| Implementation Gate 提交 `ebb6978` | 121 | 含延迟仪器与快捷键冲突状态 |
| T-021 RED | 149 | 新增 `AXRecoveryAlgorithmTests` 28 项 |
| T-022 GREEN | 149 | 全部转绿，未新增测试 |
| Finding 1／2 修复 | 160 | 预览内容披露、生产监控装配 |
| Finding 4 修复 | 164 | 会话竞态与安全输入 |
| Finding 6 修复 | 172 | 失败状态与恢复指引 |
| **本次复核** | **172** | 与 Finding 6 后一致，无回退 |

净增 63 项（109 → 172），全部由失败优先测试驱动。

## 受影响测试套件的复核结论

T-027、T-030／T-031 的既有勾选在 Tasks Gate 重开后被标注为"复核前不代表
覆盖已达成"。本次两次运行中，相关套件全部通过：

- `PreviewStateActionTests`（T-027 状态矩阵，已扩展至十种预览状态）→ passed
- `EndToEndIntegrationTests`（T-030／T-031 合成闭环）→ passed
- `AXRecoveryAlgorithmTests`（T-021／T-022 批准算法）→ passed
- `AXAuthoritativeWriteRecoveryTests`（replacement 与 A1–A4）→ passed
- `AXObserverDeliveryIsolationTests`、`ProductionTargetMonitorAssemblyTests`
  （FR-009 监控隔离与生产装配）→ passed
- `PreviewContentDisclosureTests`（Finding 1）→ passed
- `SessionLifecycleRaceTests`（Finding 4）→ passed
- `FailureRecoveryGuidanceTests`（Finding 6）→ passed
- `HotKeyRegistrationFailurePresentationTests`（FR-001／AC-002）→ passed
- `PrivacyContractTests`、`ClipboardPolicyTests`（FR-013、NFR-006）→ passed
- `DeterministicTransformerTests`、`ErrorMappingTests`、
  `InteractionSessionCoordinatorTests`、`AXTargetCaptureTests`、
  `AccessibilityPermissionFlowTests`、`PanelGeometryProbeTests`、
  `HotKeySecureInputProbeTests`、`PresentationLatencyInstrumentationTests`、
  `ProjectStructureTests` → passed

## 结论

自动化层面的下游复核通过：批准后的恢复算法与五项 Implementation 修复共存，
未使任何既有测试回退。检查点 **C3 与 C4 的自动化前提已满足**；两者的最终
判定仍需 T-041 至 T-045 的真实环境复核完成后由 T-046 汇总，本任务不单独
宣布检查点达成。
