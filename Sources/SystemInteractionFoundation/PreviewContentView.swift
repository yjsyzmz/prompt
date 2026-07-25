import AppKit
import SwiftUI

struct PreviewContentView: View {
    let state: PreviewViewState
    let onAction: (PreviewUserAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(state.message)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                ForEach(state.buttons, id: \.action) { button in
                    Button(button.title) {
                        onAction(button.action)
                    }
                    .disabled(!button.isEnabled)
                }
            }
        }
        .padding(16)
        .frame(width: 360, alignment: .leading)
    }
}

@MainActor
protocol PreviewPresenting: AnyObject {
    func show(_ state: PreviewViewState, anchorRect: CGRect?)
    func update(_ state: PreviewViewState)
    func dismiss()
}

@MainActor
final class PreviewPanelController: PreviewPresenting {
    private static let panelSize = CGSize(width: 380, height: 140)

    var onAction: (PreviewUserAction) -> Void = { _ in }

    private let panel: NSPanel
    private let hosting: NSHostingController<PreviewContentView>
    private let placementController: NonactivatingPanelController

    init() {
        panel = PanelProbeFactory().makePanel(
            contentRect: CGRect(origin: .zero, size: Self.panelSize)
        )
        hosting = NSHostingController(
            rootView: PreviewContentView(
                state: PreviewViewState(message: "", buttons: []),
                onAction: { _ in }
            )
        )
        panel.contentViewController = hosting
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

    private func applyRootView(_ state: PreviewViewState) {
        hosting.rootView = PreviewContentView(state: state) { [weak self] action in
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
