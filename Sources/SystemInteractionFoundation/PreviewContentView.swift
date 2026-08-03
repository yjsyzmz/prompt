import AppKit
import SwiftUI

struct PreviewContentView: View {
    let state: PreviewViewState
    let onAction: (PreviewUserAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.message)
                .fixedSize(horizontal: false, vertical: true)
            if let sourceText = state.sourceText {
                disclosure(title: "原文", text: sourceText)
            }
            if let resultText = state.resultText {
                disclosure(title: "将写入的结果", text: resultText)
            }
            HStack(spacing: 8) {
                ForEach(state.buttons, id: \.action) { button in
                    Button(button.title) {
                        onAction(button.action)
                    }
                    .disabled(!button.isEnabled)
                    .accessibilityLabel(button.title)
                }
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }

    private func disclosure(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 120)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

@MainActor
protocol PreviewPresenting: AnyObject {
    func show(_ state: PreviewViewState, anchorRect: CGRect?)
    func update(_ state: PreviewViewState)
    func dismiss()
}

/// The panel never activates the app, so the first click must not be
/// swallowed as a window-focusing click; deliver it straight to the control.
private final class FirstMouseHostingView: NSHostingView<PreviewContentView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    required init(rootView: PreviewContentView) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

@MainActor
final class PreviewPanelController: PreviewPresenting, PreviewPanelFocusOwnership {
    private static let panelSize = CGSize(width: 380, height: 140)

    var onAction: (PreviewUserAction) -> Void = { _ in }

    private let panel: NSPanel
    private let hostingView: FirstMouseHostingView
    private let placementController: NonactivatingPanelController

    init() {
        panel = PanelProbeFactory().makePanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize)
        )
        hostingView = FirstMouseHostingView(
            rootView: PreviewContentView(
                state: PreviewViewState(message: "", buttons: []),
                onAction: { _ in }
            )
        )
        panel.contentView = hostingView
        placementController = NonactivatingPanelController(
            panel: panel,
            geometry: ScreenGeometryConverter(safeMargin: 8)
        )
    }

    func show(_ state: PreviewViewState, anchorRect: CGRect?) {
        applyRootView(state)

        guard let snapshot = Self.currentScreenSnapshot() else {
            panel.center()
            panel.orderFrontRegardless()
            return
        }

        placementController.show(
            panelSize: Self.panelSize,
            anchors: ScreenGeometryAnchorCandidates(
                selectionBoundsAX: anchorRect,
                cursorBoundsAX: nil,
                elementBoundsAX: nil,
                windowBoundsAX: nil,
                targetDisplayID: nil,
                activeDisplayID: snapshot.primaryDisplayID
            ),
            snapshot: snapshot,
            isFullScreen: false
        )
    }

    func update(_ state: PreviewViewState) {
        applyRootView(state)
    }

    func dismiss() {
        panel.orderOut(nil)
    }

    /// T-053: the A2 exemption is scoped to this panel, not to this process.
    /// Read live at action time; the caller must not remember the answer.
    func currentSessionPanelIsKey() -> Bool {
        NSApp.keyWindow === panel
    }

    private func applyRootView(_ state: PreviewViewState) {
        hostingView.rootView = PreviewContentView(state: state) { [weak self] action in
            self?.onAction(action)
        }
    }

    private static func currentScreenSnapshot() -> ScreenGeometrySnapshot? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return nil
        }

        let displays = screens.map { screen in
            ScreenGeometryDisplay(
                id: displayID(of: screen),
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                backingScaleFactor: screen.backingScaleFactor
            )
        }
        return ScreenGeometrySnapshot(
            revision: 0,
            primaryDisplayID: displays[0].id,
            displays: displays
        )
    }

    private static func displayID(of screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return "unknown-display"
        }
        return number.stringValue
    }
}
