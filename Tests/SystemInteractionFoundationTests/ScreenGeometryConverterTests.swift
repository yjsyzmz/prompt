import AppKit
import XCTest

final class ScreenGeometryConverterTests: XCTestCase {
    private let margin: CGFloat = 12
    private let panelSize = CGSize(width: 320, height: 180)

    func testSelectionBoundsTakePriorityOverCursorElementAndWindow() {
        let converter = ScreenGeometryConverter(safeMargin: margin)
        let placement = converter.place(
            panelSize: panelSize,
            anchors: anchors(
                selection: CGRect(x: 400, y: 220, width: 80, height: 24),
                cursor: CGRect(x: 500, y: 260, width: 2, height: 24),
                element: CGRect(x: 300, y: 180, width: 500, height: 120),
                window: CGRect(x: 200, y: 100, width: 900, height: 700)
            ),
            snapshot: snapshot(),
            isFullScreen: false
        )

        XCTAssertEqual(placement.anchorSource, .selection)
    }

    func testCursorFallsBackThroughElementWindowTargetAndActiveDisplay() {
        let converter = ScreenGeometryConverter(safeMargin: margin)
        let currentSnapshot = snapshot()
        let cursor = CGRect(x: 500, y: 260, width: 2, height: 24)
        let element = CGRect(x: 300, y: 180, width: 500, height: 120)
        let window = CGRect(x: 200, y: 100, width: 900, height: 700)

        XCTAssertEqual(
            converter.place(
                panelSize: panelSize,
                anchors: anchors(cursor: cursor, element: element, window: window),
                snapshot: currentSnapshot,
                isFullScreen: false
            ).anchorSource,
            .cursor
        )
        XCTAssertEqual(
            converter.place(
                panelSize: panelSize,
                anchors: anchors(element: element, window: window),
                snapshot: currentSnapshot,
                isFullScreen: false
            ).anchorSource,
            .element
        )
        XCTAssertEqual(
            converter.place(
                panelSize: panelSize,
                anchors: anchors(window: window),
                snapshot: currentSnapshot,
                isFullScreen: false
            ).anchorSource,
            .window
        )

        let targetPlacement = converter.place(
            panelSize: panelSize,
            anchors: anchors(targetDisplayID: "secondary"),
            snapshot: currentSnapshot,
            isFullScreen: false
        )
        XCTAssertEqual(targetPlacement.anchorSource, .targetDisplay)
        XCTAssertEqual(targetPlacement.displayID, "secondary")

        let activePlacement = converter.place(
            panelSize: panelSize,
            anchors: anchors(targetDisplayID: nil),
            snapshot: currentSnapshot,
            isFullScreen: false
        )
        XCTAssertEqual(activePlacement.anchorSource, .activeDisplay)
        XCTAssertEqual(activePlacement.displayID, "primary")
    }

    func testAXTopLeftCoordinatesConvertToAppKitBottomLeftCoordinates() {
        let converter = ScreenGeometryConverter(safeMargin: margin)
        let primaryFrame = CGRect(x: 0, y: 0, width: 1_440, height: 900)

        XCTAssertEqual(
            converter.appKitRect(
                fromAX: CGRect(x: 150, y: 100, width: 200, height: 40),
                primaryDisplayFrame: primaryFrame
            ),
            CGRect(x: 150, y: 760, width: 200, height: 40)
        )
        XCTAssertEqual(
            converter.appKitRect(
                fromAX: CGRect(x: -700, y: -180, width: 100, height: 30),
                primaryDisplayFrame: primaryFrame
            ),
            CGRect(x: -700, y: 1_050, width: 100, height: 30)
        )
    }

    func testDisplayWithLargestConvertedAnchorIntersectionIsSelected() {
        let converter = ScreenGeometryConverter(safeMargin: margin)
        let placement = converter.place(
            panelSize: panelSize,
            anchors: anchors(
                selection: CGRect(x: 1_420, y: 350, width: 100, height: 30)
            ),
            snapshot: snapshot(),
            isFullScreen: false
        )

        XCTAssertEqual(placement.displayID, "secondary")
        XCTAssertEqual(placement.anchorSource, .selection)
    }

    func testPlacementConvergesInsideSelectedDisplayVisibleFrame() {
        let converter = ScreenGeometryConverter(safeMargin: margin)
        let currentSnapshot = snapshot()
        let safeFrame = currentSnapshot.displays[1].visibleFrame.insetBy(
            dx: margin,
            dy: margin
        )

        let placement = converter.place(
            panelSize: panelSize,
            anchors: anchors(
                selection: CGRect(x: 3_350, y: 1_055, width: 10, height: 10)
            ),
            snapshot: currentSnapshot,
            isFullScreen: false
        )

        XCTAssertEqual(placement.displayID, "secondary")
        XCTAssertTrue(
            safeFrame.contains(placement.frame),
            "Expected \(placement.frame) inside \(safeFrame)"
        )
    }

    func testPanelLargerThanAvailableRegionShrinksToSafeFrame() {
        let display = ScreenGeometryDisplay(
            id: "compact",
            frame: CGRect(x: 0, y: 0, width: 300, height: 220),
            visibleFrame: CGRect(x: 0, y: 24, width: 300, height: 196),
            backingScaleFactor: 2
        )
        let converter = ScreenGeometryConverter(safeMargin: margin)
        let safeFrame = display.visibleFrame.insetBy(dx: margin, dy: margin)

        let placement = converter.place(
            panelSize: CGSize(width: 640, height: 480),
            anchors: ScreenGeometryAnchorCandidates(
                selectionBoundsAX: nil,
                cursorBoundsAX: CGRect(x: 150, y: 100, width: 2, height: 20),
                elementBoundsAX: nil,
                windowBoundsAX: nil,
                targetDisplayID: "compact",
                activeDisplayID: "compact"
            ),
            snapshot: ScreenGeometrySnapshot(
                revision: 1,
                primaryDisplayID: "compact",
                displays: [display]
            ),
            isFullScreen: false
        )

        XCTAssertEqual(placement.frame, safeFrame)
    }

    func testScreenChangeUsesLatestSnapshotInsteadOfCachedDisplayGeometry() {
        let converter = ScreenGeometryConverter(safeMargin: margin)
        let initial = ScreenGeometrySnapshot(
            revision: 1,
            primaryDisplayID: "built-in",
            displays: [
                ScreenGeometryDisplay(
                    id: "built-in",
                    frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                    visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 852),
                    backingScaleFactor: 2
                ),
            ]
        )
        let changed = ScreenGeometrySnapshot(
            revision: 2,
            primaryDisplayID: "external",
            displays: [
                ScreenGeometryDisplay(
                    id: "external",
                    frame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080),
                    visibleFrame: CGRect(x: -1_920, y: 0, width: 1_920, height: 1_056),
                    backingScaleFactor: 1
                ),
            ]
        )

        let first = converter.place(
            panelSize: panelSize,
            anchors: anchors(
                targetDisplayID: nil,
                activeDisplayID: "built-in"
            ),
            snapshot: initial,
            isFullScreen: false
        )
        let second = converter.place(
            panelSize: panelSize,
            anchors: anchors(
                targetDisplayID: nil,
                activeDisplayID: "external"
            ),
            snapshot: changed,
            isFullScreen: false
        )

        XCTAssertEqual(first.displayID, "built-in")
        XCTAssertEqual(second.displayID, "external")
        XCTAssertLessThan(second.frame.maxX, 0)
        XCTAssertTrue(
            changed.displays[0].visibleFrame
                .insetBy(dx: margin, dy: margin)
                .contains(second.frame)
        )
    }

    private func anchors(
        selection: CGRect? = nil,
        cursor: CGRect? = nil,
        element: CGRect? = nil,
        window: CGRect? = nil,
        targetDisplayID: String? = "secondary",
        activeDisplayID: String = "primary"
    ) -> ScreenGeometryAnchorCandidates {
        ScreenGeometryAnchorCandidates(
            selectionBoundsAX: selection,
            cursorBoundsAX: cursor,
            elementBoundsAX: element,
            windowBoundsAX: window,
            targetDisplayID: targetDisplayID,
            activeDisplayID: activeDisplayID
        )
    }

    private func snapshot() -> ScreenGeometrySnapshot {
        ScreenGeometrySnapshot(
            revision: 1,
            primaryDisplayID: "primary",
            displays: [
                ScreenGeometryDisplay(
                    id: "primary",
                    frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                    visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 852),
                    backingScaleFactor: 2
                ),
                ScreenGeometryDisplay(
                    id: "secondary",
                    frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
                    visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_056),
                    backingScaleFactor: 1
                ),
            ]
        )
    }
}
