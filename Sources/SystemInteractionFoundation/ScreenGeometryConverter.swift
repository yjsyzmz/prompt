import AppKit

struct ScreenGeometryAnchorCandidates: Equatable {
    let selectionBoundsAX: CGRect?
    let cursorBoundsAX: CGRect?
    let elementBoundsAX: CGRect?
    let windowBoundsAX: CGRect?
    let targetDisplayID: String?
    let activeDisplayID: String
}

struct ScreenGeometryDisplay: Equatable {
    let id: String
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScaleFactor: CGFloat
}

struct ScreenGeometrySnapshot: Equatable {
    let revision: UInt64
    let primaryDisplayID: String
    let displays: [ScreenGeometryDisplay]
}

enum ScreenGeometryAnchorSource: Equatable {
    case selection
    case cursor
    case element
    case window
    case targetDisplay
    case activeDisplay
}

struct ScreenGeometryPlacement: Equatable {
    let frame: CGRect
    let displayID: String
    let anchorSource: ScreenGeometryAnchorSource
}

struct ScreenGeometryConverter {
    let safeMargin: CGFloat

    func appKitRect(
        fromAX rect: CGRect,
        primaryDisplayFrame: CGRect
    ) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryDisplayFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    func place(
        panelSize: CGSize,
        anchors: ScreenGeometryAnchorCandidates,
        snapshot: ScreenGeometrySnapshot,
        isFullScreen: Bool
    ) -> ScreenGeometryPlacement {
        precondition(!snapshot.displays.isEmpty, "Screen placement requires a display")

        let primaryDisplay = snapshot.displays.first {
            $0.id == snapshot.primaryDisplayID
        } ?? snapshot.displays[0]
        let anchor = resolveAnchor(
            anchors,
            primaryDisplayFrame: primaryDisplay.frame,
            displays: snapshot.displays
        )
        let display = resolveDisplay(
            for: anchor,
            anchors: anchors,
            displays: snapshot.displays
        )
        let confinementFrame = isFullScreen ? display.frame : display.visibleFrame
        let safeFrame = safeFrame(inside: confinementFrame)
        let fittedSize = CGSize(
            width: min(max(panelSize.width, 0), safeFrame.width),
            height: min(max(panelSize.height, 0), safeFrame.height)
        )
        let proposedOrigin = CGPoint(
            x: anchor.bounds.midX,
            y: anchor.bounds.minY - fittedSize.height
        )
        let frame = CGRect(
            origin: CGPoint(
                x: clamp(
                    proposedOrigin.x,
                    minimum: safeFrame.minX,
                    maximum: safeFrame.maxX - fittedSize.width
                ),
                y: clamp(
                    proposedOrigin.y,
                    minimum: safeFrame.minY,
                    maximum: safeFrame.maxY - fittedSize.height
                )
            ),
            size: fittedSize
        )

        return ScreenGeometryPlacement(
            frame: frame,
            displayID: display.id,
            anchorSource: anchor.source
        )
    }

    private func resolveAnchor(
        _ anchors: ScreenGeometryAnchorCandidates,
        primaryDisplayFrame: CGRect,
        displays: [ScreenGeometryDisplay]
    ) -> ResolvedScreenAnchor {
        if let bounds = anchors.selectionBoundsAX {
            return convertedAnchor(
                bounds,
                source: .selection,
                primaryDisplayFrame: primaryDisplayFrame
            )
        }
        if let bounds = anchors.cursorBoundsAX {
            return convertedAnchor(
                bounds,
                source: .cursor,
                primaryDisplayFrame: primaryDisplayFrame
            )
        }
        if let bounds = anchors.elementBoundsAX {
            return convertedAnchor(
                bounds,
                source: .element,
                primaryDisplayFrame: primaryDisplayFrame
            )
        }
        if let bounds = anchors.windowBoundsAX {
            return convertedAnchor(
                bounds,
                source: .window,
                primaryDisplayFrame: primaryDisplayFrame
            )
        }
        if
            let targetDisplayID = anchors.targetDisplayID,
            let display = displays.first(where: { $0.id == targetDisplayID })
        {
            return ResolvedScreenAnchor(
                bounds: pointBounds(at: display.frame.center),
                source: .targetDisplay
            )
        }

        let activeDisplay = displays.first { $0.id == anchors.activeDisplayID }
            ?? displays[0]
        return ResolvedScreenAnchor(
            bounds: pointBounds(at: activeDisplay.frame.center),
            source: .activeDisplay
        )
    }

    private func convertedAnchor(
        _ bounds: CGRect,
        source: ScreenGeometryAnchorSource,
        primaryDisplayFrame: CGRect
    ) -> ResolvedScreenAnchor {
        ResolvedScreenAnchor(
            bounds: appKitRect(
                fromAX: bounds,
                primaryDisplayFrame: primaryDisplayFrame
            ),
            source: source
        )
    }

    private func resolveDisplay(
        for anchor: ResolvedScreenAnchor,
        anchors: ScreenGeometryAnchorCandidates,
        displays: [ScreenGeometryDisplay]
    ) -> ScreenGeometryDisplay {
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
        case .selection, .cursor, .element, .window:
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
        return displays.first(where: { $0.id == anchors.activeDisplayID })
            ?? displays[0]
    }

    private func displayWithLargestIntersection(
        _ bounds: CGRect,
        displays: [ScreenGeometryDisplay]
    ) -> ScreenGeometryDisplay? {
        displays
            .map { display in
                (display: display, area: bounds.intersection(display.frame).area)
            }
            .filter { $0.area > 0 }
            .max { lhs, rhs in lhs.area < rhs.area }?
            .display
    }

    private func safeFrame(inside frame: CGRect) -> CGRect {
        let margin = max(safeMargin, 0)
        let horizontalInset = min(margin, frame.width / 2)
        let verticalInset = min(margin, frame.height / 2)
        return frame.insetBy(dx: horizontalInset, dy: verticalInset)
    }

    private func pointBounds(at point: CGPoint) -> CGRect {
        CGRect(origin: point, size: .zero)
    }

    private func clamp(_ value: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(max(value, minimum), maximum)
    }
}

@MainActor
final class NonactivatingPanelController {
    private let panel: NSPanel
    private let geometry: ScreenGeometryConverter

    init(panel: NSPanel, geometry: ScreenGeometryConverter) {
        precondition(
            panel.styleMask.contains(.nonactivatingPanel),
            "Panel controller requires a nonactivating NSPanel"
        )
        self.panel = panel
        self.geometry = geometry
    }

    @discardableResult
    func show(
        panelSize: CGSize,
        anchors: ScreenGeometryAnchorCandidates,
        snapshot: ScreenGeometrySnapshot,
        isFullScreen: Bool
    ) -> ScreenGeometryPlacement {
        let placement = geometry.place(
            panelSize: panelSize,
            anchors: anchors,
            snapshot: snapshot,
            isFullScreen: isFullScreen
        )
        panel.setFrame(placement.frame, display: false)
        panel.orderFrontRegardless()
        return placement
    }
}

private struct ResolvedScreenAnchor {
    let bounds: CGRect
    let source: ScreenGeometryAnchorSource
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
