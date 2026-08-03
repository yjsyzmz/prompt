import AppKit
import XCTest

/// Implementation Gate REVIEW（第二轮）MUST 2：确认替换被授权校验拒绝时，
/// 面板必须解释真实的拒绝原因，不能一律说成「未能安全替换原文」。
///
/// NFR-007：失败必须给出可理解的说明与安全的下一步。把「目标已经变化、
/// 从未发生写入」和「确实尝试了写入但失败」混为一谈，会让用户以为目标
/// 内容可能已被改动，而事实上一个 setter 都没调用过。
@MainActor
final class ReplacementFailureMappingTests: XCTestCase {
    private let mapper = PreviewPresentationMapper()

    // MARK: - 从未发生写入的拒绝，不能呈现为写入失败

    func testWindowChangeBeforeWriteIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.switchWindow()
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(
            env.host.setterAttemptCount,
            0,
            "A3 rejects before any setter runs, so nothing was written"
        )
        XCTAssertNotEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .writeFailed).message,
            "a pre-write rejection must not be reported as a failed write"
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message
        )
    }

    func testElementInvalidationBeforeWriteIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.invalidateElement()
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message,
            "A4 identity mismatch is a stale target, not a write failure"
        )
    }

    func testApplicationTerminationBeforeWriteIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.terminateApplication()
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message,
            "A1 rejects a terminated application before any write"
        )
    }

    func testFocusMovedToAnotherApplicationIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.moveFocusToDifferentApplication()
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(env.host.setterAttemptCount, 0)
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .staleTarget).message,
            "A2 rejects a changed frontmost application before any write"
        )
    }

    func testExternalContentEditBeforeWriteIsNotPresentedAsWriteFailure() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.editSegmentExternally("SYNTHETIC-001 外部改过的文字")
        env.controller.handle(.confirmReplacement)

        XCTAssertEqual(
            env.host.setterAttemptCount,
            0,
            "B1 compares content before the setter, so nothing was written"
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .sourceOrSelectionChanged).message,
            """
            T-054：内容变化有自己的分组，不再与 staleTarget 共用文案；两者的下一步
            不同——一个要重新选取，一个是输入位置已经不在了。
            """
        )
    }

    // MARK: - 真正尝试过写入的失败仍必须呈现为写入失败

    func testForcedSetterFailureRemainsAWriteFailure() async {
        let env = MappingEnvironment.make()
        env.host.failNextSetterAttempts(100)

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.confirmReplacement)

        XCTAssertGreaterThan(
            env.host.setterAttemptCount,
            0,
            "this path did attempt a write"
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .writeFailed).message,
            "an attempted-but-failed write keeps the writeFailed explanation"
        )
    }

    // MARK: - 两类失败必须在文案上可区分

    func testStaleAndWriteFailureCopyAreDistinguishable() {
        XCTAssertNotEqual(
            mapper.viewState(for: .staleTarget).message,
            mapper.viewState(for: .writeFailed).message
        )
    }

    // MARK: - 拒绝状态一律不得展示内容，且必须留有安全出口

    func testRejectionStatesDiscloseNoContentAndKeepCopyAvailable() async {
        let env = MappingEnvironment.make()

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.host.switchWindow()
        env.controller.handle(.confirmReplacement)

        guard let state = env.presenter.lastState else {
            XCTFail("a rejection must present a state")
            return
        }
        XCTAssertNil(state.sourceText, "FR-013: a refusal state discloses no content")
        XCTAssertNil(state.resultText)
        XCTAssertTrue(
            state.buttons.contains { $0.action == .copyResult && $0.isEnabled },
            "NFR-007 requires a safe next step: the result stays copyable"
        )
        XCTAssertFalse(
            state.canConfirmReplacement,
            "a rejected target must not offer another confirmation"
        )
    }

    // MARK: - T-054：七组失败映射逐项固化

    /// Tasks Gate 裁决的分组边界。映射必须是全量的：`DomainFailure` 的每一个取值
    /// 都有确定归属，不允许由 `default` 悄悄吞掉将来新增的取值。
    func testEveryDomainFailureMapsToItsAdjudicatedStatus() {
        let expected: [DomainFailure: PreviewStatus] = [
            .invalidTarget: .staleTarget,
            .sourceChanged: .sourceOrSelectionChanged,
            .secureInputActive: .secureInput,
            .accessibilityPermissionRequired: .permissionRequired,
            .attributeNotSettable: .targetNotWritable,
            .unsupportedTarget: .targetNotWritable,
            .axTimedOut: .targetTemporarilyUnavailable,
            .axCannotComplete: .targetTemporarilyUnavailable,
            .writeFailed: .writeFailed,
            .recoveryTargetChanged: .staleTarget,
            .hotKeyConflict: .unspecifiedFailure,
            .emptySource: .unspecifiedFailure,
            .pasteboardReadFailed: .unspecifiedFailure,
            .pasteboardWriteFailed: .unspecifiedFailure,
            .panelPlacementFallback: .unspecifiedFailure,
            .unknown: .unspecifiedFailure,
        ]

        XCTAssertEqual(
            Set(expected.keys),
            Set(DomainFailure.allCases),
            "映射表必须保持全量：新增 DomainFailure 必须有被裁决的归属"
        )
        for failure in DomainFailure.allCases {
            XCTAssertEqual(
                mapper.status(forReplacementRejection: failure),
                expected[failure],
                "\(failure) 未被路由到裁决指定的状态"
            )
        }
    }

    /// 只有 setter 与 readback 失败可以呈现为写入失败。
    func testOnlyWriteFailedIsPresentedAsAWriteFailure() {
        for failure in DomainFailure.allCases where failure != .writeFailed {
            XCTAssertNotEqual(
                mapper.status(forReplacementRejection: failure),
                .writeFailed,
                "\(failure) 从未触碰目标，不得声称发生过写入"
            )
        }
    }

    /// `sourceChanged` 必须与 `staleTarget` 文案可区分：一个是内容变了，一个是
    /// 输入位置变了，用户的下一步不同。
    func testSourceChangeIsDistinguishableFromStaleTarget() {
        XCTAssertNotEqual(
            mapper.viewState(for: .sourceOrSelectionChanged).message,
            mapper.viewState(for: .staleTarget).message
        )
    }

    /// 兜底状态既不得声称目标已变化，也不得声称发生过写入。
    func testUnspecifiedFailureClaimsNeitherChangeNorWrite() {
        let state = mapper.viewState(for: .unspecifiedFailure)

        XCTAssertNotEqual(state.message, mapper.viewState(for: .staleTarget).message)
        XCTAssertNotEqual(state.message, mapper.viewState(for: .writeFailed).message)
        XCTAssertNil(state.sourceText)
        XCTAssertNil(state.resultText)
        XCTAssertTrue(
            state.buttons.contains { $0.action == .copyResult && $0.isEnabled },
            "fail-closed 状态仍须保留复制结果这一安全出口"
        )
        XCTAssertFalse(state.canConfirmReplacement)
    }

    /// 目标暂不可用必须同时提供重试、复制与关闭。
    func testTemporarilyUnavailableOffersRetryCopyAndClose() {
        let actions = mapper.viewState(for: .targetTemporarilyUnavailable)
            .buttons
            .map(\.action)

        XCTAssertTrue(actions.contains(.retry))
        XCTAssertTrue(actions.contains(.copyResult))
        XCTAssertTrue(actions.contains(.close))
    }

    // MARK: - T-054：真实路由与 setter 次数

    /// 每一类失败都必须有一条贯穿 gateway → coordinator → presentation 的真实
    /// 路由证据，而不是只测映射函数或只测面板文案。非写入类失败一律断言零 setter。
    func testRealRoutingForEveryReachableFailureClass() async {
        let cases: [(String, (SyntheticAXTextHost) -> Void, PreviewStatus)] = [
            ("A1 应用退出", { $0.terminateApplication() }, .staleTarget),
            ("A2 切到其他应用", { $0.moveFocusToDifferentApplication() }, .staleTarget),
            ("A3 窗口变化", { $0.switchWindow() }, .staleTarget),
            ("A4 元素变化", { $0.invalidateElement() }, .staleTarget),
            ("B1 内容变化",
             { $0.editSegmentExternally("SYNTHETIC-001 外部改过的文字") },
             .sourceOrSelectionChanged),
            ("安全输入", { $0.activateGlobalSecureInput() }, .secureInput),
            ("元素转只读", { $0.makeReadOnly() }, .targetNotWritable),
            ("属性不可写", { $0.blockReplacementAttribute() }, .targetNotWritable),
            ("AX 超时",
             { $0.failNextContentReads(1, with: .axTimedOut) },
             .targetTemporarilyUnavailable),
            ("AX 无法完成",
             { $0.failNextContentReads(1, with: .axCannotComplete) },
             .targetTemporarilyUnavailable),
            ("权限缺失",
             { $0.failNextContentReads(1, with: .accessibilityPermissionRequired) },
             .permissionRequired),
            ("未知失败",
             { $0.failNextContentReads(1, with: .unknown) },
             .unspecifiedFailure),
        ]

        for (label, mutate, expectedStatus) in cases {
            let env = MappingEnvironment.make()
            env.hotKey.press()
            await env.controller.captureWork?.value
            mutate(env.host)
            env.controller.handle(.confirmReplacement)

            XCTAssertEqual(
                env.presenter.lastState?.message,
                mapper.viewState(for: expectedStatus).message,
                "\(label) 必须呈现为 \(expectedStatus)"
            )
            XCTAssertEqual(
                env.host.setterAttemptCount,
                0,
                "\(label) 从未到达 setter，必须实测零写入"
            )
        }
    }

    /// 写入类失败必须真的调用过 setter——「未发生写入」是实测而非推断。
    func testWriteFailureIsTheOnlyClassThatReachesTheSetter() async {
        let env = MappingEnvironment.make()
        env.host.failNextSetterAttempts(100)

        env.hotKey.press()
        await env.controller.captureWork?.value
        env.controller.handle(.confirmReplacement)

        XCTAssertGreaterThan(
            env.host.setterAttemptCount,
            0,
            "writeFailed 这一类的定义就是确实尝试过写入"
        )
        XCTAssertEqual(
            env.presenter.lastState?.message,
            mapper.viewState(for: .writeFailed).message
        )
    }

    /// 被判定在替换路径上不可达的取值需要证明，而不是靠「应该不会发生」。
    func testFailuresJudgedUnreachableAreNeverProducedByTheReplacementPath() async {
        let unreachable: Set<DomainFailure> = [
            .emptySource,
            .pasteboardReadFailed,
            .pasteboardWriteFailed,
            .panelPlacementFallback,
            .hotKeyConflict,
        ]
        let injections: [(SyntheticAXTextHost) -> Void] = [
            { $0.terminateApplication() },
            { $0.moveFocusToDifferentApplication() },
            { $0.switchWindow() },
            { $0.invalidateElement() },
            { $0.editSegmentExternally("SYNTHETIC-001 外部改过的文字") },
            { $0.activateGlobalSecureInput() },
            { $0.makeReadOnly() },
            { $0.blockReplacementAttribute() },
            { $0.failNextContentReads(1, with: .axTimedOut) },
            { $0.failNextContentReads(1, with: .axCannotComplete) },
            { $0.failNextContentReads(1, with: .unknown) },
            { $0.failNextSetterAttempts(100) },
            { $0.acceptSetterWithoutApplying() },
            { _ in },
        ]

        for mutate in injections {
            let host = SyntheticAXTextHost.selectionFixture()
            let gateway = AccessibilityGateway(
                captureReader: host,
                authoritativeTarget: host
            )
            guard
                case .success(let captured) = await gateway.capture(
                    sessionID: InteractionSessionID()
                ),
                let pid = await gateway.authoritativePID(for: captured.targetHandle)
            else {
                XCTFail("选区夹具必须能成功捕获")
                return
            }
            mutate(host)
            let outcome = await gateway.replaceAfterAuthoritativeValidation(
                AXWriteSnapshot(
                    targetHandle: captured.targetHandle,
                    pid: pid,
                    captureMode: captured.captureMode,
                    originalText: captured.sourceText,
                    transformedText: DeterministicTransformer()
                        .transform(captured.sourceText)
                )
            )
            if case .failure(let failure) = outcome {
                XCTAssertFalse(
                    unreachable.contains(failure),
                    "\(failure) 被判定在替换路径上不可达，却真的出现了"
                )
            }
        }
    }
}

// MARK: - Environment

@MainActor
private struct MappingEnvironment {
    let controller: AppLifecycleController
    let host: SyntheticAXTextHost
    let hotKey: MappingHotKeyFake
    let presenter: MappingPresenterSpy

    static func make() -> MappingEnvironment {
        let host = SyntheticAXTextHost.selectionFixture()
        let gateway = AccessibilityGateway(
            captureReader: host,
            authoritativeTarget: host
        )
        let hotKey = MappingHotKeyFake()
        let presenter = MappingPresenterSpy()
        let controller = AppLifecycleController(
            hotKeySystemClient: hotKey,
            permissionChecker: MappingPermissionFake(),
            settingsOpener: MappingSettingsFake(),
            secureInputChecker: MappingSecureInputFake(),
            pasteboard: MappingPasteboardSpy(),
            gateway: gateway,
            targetMonitor: MappingMonitorSpy(),
            presenter: presenter
        )
        _ = controller.start()
        return MappingEnvironment(
            controller: controller,
            host: host,
            hotKey: hotKey,
            presenter: presenter
        )
    }
}

@MainActor
private final class MappingHotKeyFake: HotKeySystemClient {
    private var callback: (() -> Void)?

    func registerExclusive(
        callback: @escaping () -> Void
    ) -> HotKeySystemRegistrationOutcome {
        self.callback = callback
        return .registered(HotKeyRegistrationToken(id: 1))
    }

    func unregister(_ token: HotKeyRegistrationToken) {
        callback = nil
    }

    func press() {
        callback?()
    }
}

@MainActor
private final class MappingPresenterSpy: PreviewPresenting {
    var lastState: PreviewViewState?

    func show(_ state: PreviewViewState, anchorRect: CGRect?) {
        lastState = state
    }

    func update(_ state: PreviewViewState) {
        lastState = state
    }

    func dismiss() {
        lastState = nil
    }
}

@MainActor
private final class MappingPermissionFake: AccessibilityPermissionChecking {
    func currentStatus() -> AccessibilityPermissionStatus {
        .authorized
    }
}

@MainActor
private final class MappingSettingsFake: AccessibilitySettingsOpening {
    func openAccessibilitySettings() -> Bool {
        true
    }

    func openPrivacyAndSecuritySettings() -> Bool {
        true
    }
}

@MainActor
private final class MappingSecureInputFake: SecureEventInputChecking {
    func isSecureEventInputEnabled() -> Bool {
        false
    }
}

@MainActor
private final class MappingPasteboardSpy: PasteboardAccessing {
    func readStringAfterExplicitAction() -> String? {
        "SYNTHETIC-001 剪贴板文字"
    }

    func writeLocalStringAfterExplicitAction(
        _ value: String,
        privacy: PasteboardWritePrivacy
    ) -> Bool {
        true
    }
}

@MainActor
private final class MappingMonitorSpy: TargetChangeMonitoring {
    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {}

    func stopMonitoring() {}
}
