import AppKit

/// Borderless panels refuse key status by default, which silently breaks
/// every SwiftUI control hosted inside. The preview panel must be able to
/// become key so its buttons receive clicks, while `.nonactivatingPanel`
/// still keeps the application itself from activating.
final class KeyableNonactivatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
struct PanelProbeFactory {
    func makePanel(contentRect: CGRect) -> NSPanel {
        let panel = KeyableNonactivatingPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }
}

@MainActor
protocol PanelProbeWindowPresenting: AnyObject {
    func orderFrontRegardless()
    func makeKeyAndOrderFront()
}

extension NSPanel: PanelProbeWindowPresenting {
    func makeKeyAndOrderFront() {
        makeKeyAndOrderFront(nil)
    }
}

@MainActor
protocol PanelProbeApplicationActivating: AnyObject {
    func activateIgnoringOtherApps()
}

@MainActor
struct NonactivatingPanelPresenter {
    private let panel: any PanelProbeWindowPresenting
    private let application: any PanelProbeApplicationActivating

    init(
        panel: any PanelProbeWindowPresenting,
        application: any PanelProbeApplicationActivating
    ) {
        self.panel = panel
        self.application = application
    }

    func show() {
        panel.orderFrontRegardless()
    }
}

struct PanelProbeAnchorCandidates: Equatable {
    let rangeBounds: CGRect?
    let elementBounds: CGRect?
    let windowBounds: CGRect?
    let targetDisplayID: String?
    let activeDisplayID: String
}

struct PanelProbeDisplay: Equatable {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat
}

enum PanelProbeAnchorSource: Equatable {
    case range
    case element
    case window
    case targetDisplay
    case activeDisplay
}

enum PanelProbeConfinementFrame: Equatable {
    case visibleFrame
    case fullFrame
}

struct PanelProbePlacement: Equatable {
    let frame: CGRect
    let displayID: String
    let anchorSource: PanelProbeAnchorSource
    let confinementFrame: PanelProbeConfinementFrame
}

struct PanelProbeGeometry {
    let safeMargin: CGFloat

    func place(
        panelSize: CGSize,
        anchors: PanelProbeAnchorCandidates,
        displays: [PanelProbeDisplay],
        isFullScreen: Bool
    ) -> PanelProbePlacement {
        precondition(!displays.isEmpty, "Panel placement requires at least one display")

        let resolvedAnchor = resolveAnchor(anchors, displays: displays)
        let display = resolveDisplay(
            for: resolvedAnchor,
            anchors: anchors,
            displays: displays
        )
        let confinementFrame = isFullScreen ? display.frame : display.visibleFrame
        let safeFrame = confinementFrame.insetBy(dx: safeMargin, dy: safeMargin)
        let proposedOrigin = CGPoint(
            x: resolvedAnchor.bounds.midX,
            y: resolvedAnchor.bounds.minY - panelSize.height
        )
        let frame = CGRect(
            origin: CGPoint(
                x: clamp(
                    proposedOrigin.x,
                    minimum: safeFrame.minX,
                    maximum: safeFrame.maxX - panelSize.width
                ),
                y: clamp(
                    proposedOrigin.y,
                    minimum: safeFrame.minY,
                    maximum: safeFrame.maxY - panelSize.height
                )
            ),
            size: panelSize
        )

        return PanelProbePlacement(
            frame: frame,
            displayID: display.id,
            anchorSource: resolvedAnchor.source,
            confinementFrame: isFullScreen ? .fullFrame : .visibleFrame
        )
    }

    private func resolveAnchor(
        _ anchors: PanelProbeAnchorCandidates,
        displays: [PanelProbeDisplay]
    ) -> ResolvedAnchor {
        if let bounds = anchors.rangeBounds {
            return ResolvedAnchor(bounds: bounds, source: .range)
        }
        if let bounds = anchors.elementBounds {
            return ResolvedAnchor(bounds: bounds, source: .element)
        }
        if let bounds = anchors.windowBounds {
            return ResolvedAnchor(bounds: bounds, source: .window)
        }
        if
            let targetDisplayID = anchors.targetDisplayID,
            let display = displays.first(where: { $0.id == targetDisplayID })
        {
            return ResolvedAnchor(
                bounds: pointBounds(at: display.frame.center),
                source: .targetDisplay
            )
        }

        let activeDisplay = displays.first(where: { $0.id == anchors.activeDisplayID })
            ?? displays[0]
        return ResolvedAnchor(
            bounds: pointBounds(at: activeDisplay.frame.center),
            source: .activeDisplay
        )
    }

    private func resolveDisplay(
        for anchor: ResolvedAnchor,
        anchors: PanelProbeAnchorCandidates,
        displays: [PanelProbeDisplay]
    ) -> PanelProbeDisplay {
        switch anchor.source {
        case .targetDisplay:
            if
                let targetDisplayID = anchors.targetDisplayID,
                let display = displays.first(where: { $0.id == targetDisplayID })
            {
                return display
            }
        case .activeDisplay:
            if let display = displays.first(where: { $0.id == anchors.activeDisplayID }) {
                return display
            }
        case .range, .element, .window:
            if let display = displayWithLargestIntersection(
                anchor.bounds,
                displays: displays
            ) {
                return display
            }
        }

        if
            let targetDisplayID = anchors.targetDisplayID,
            let display = displays.first(where: { $0.id == targetDisplayID })
        {
            return display
        }
        return displays.first(where: { $0.id == anchors.activeDisplayID }) ?? displays[0]
    }

    private func displayWithLargestIntersection(
        _ bounds: CGRect,
        displays: [PanelProbeDisplay]
    ) -> PanelProbeDisplay? {
        displays
            .map { display in
                (display: display, area: bounds.intersection(display.frame).area)
            }
            .filter { $0.area > 0 }
            .max { lhs, rhs in lhs.area < rhs.area }?
            .display
    }

    private func pointBounds(at point: CGPoint) -> CGRect {
        CGRect(origin: point, size: .zero)
    }

    private func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

private struct ResolvedAnchor {
    let bounds: CGRect
    let source: PanelProbeAnchorSource
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard !isNull, !isInfinite else {
            return 0
        }
        return width * height
    }
}
