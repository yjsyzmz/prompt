import AppKit
import XCTest

@MainActor
final class PanelGeometryProbeTests: XCTestCase {
    private let margin: CGFloat = 12
    private let panelSize = CGSize(width: 320, height: 180)

    func testPanelFactoryCreatesNonactivatingFullScreenAuxiliaryPanel() {
        let panel = PanelProbeFactory().makePanel(
            contentRect: CGRect(origin: .zero, size: panelSize)
        )

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.level, .floating)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }

    func testShowingPanelDoesNotActivateApplicationOrMakePanelKey() {
        let panel = PanelWindowSpy()
        let application = ApplicationActivationSpy()
        let presenter = NonactivatingPanelPresenter(
            panel: panel,
            application: application
        )

        presenter.show()

        XCTAssertEqual(panel.orderFrontCallCount, 1)
        XCTAssertEqual(panel.makeKeyAndOrderFrontCallCount, 0)
        XCTAssertEqual(application.activateCallCount, 0)
    }

    func testAnchorFallbackOrderIsRangeElementWindowTargetThenActiveDisplay() {
        let displays = standardDisplays()
        let geometry = PanelProbeGeometry(safeMargin: margin)
        let range = CGRect(x: 1_180, y: 500, width: 20, height: 20)
        let element = CGRect(x: 1_000, y: 420, width: 240, height: 80)
        let window = CGRect(x: 900, y: 200, width: 500, height: 500)

        let rangePlacement = geometry.place(
            panelSize: panelSize,
            anchors: anchors(range: range, element: element, window: window),
            displays: displays,
            isFullScreen: false
        )
        XCTAssertEqual(rangePlacement.anchorSource, .range)

        let elementPlacement = geometry.place(
            panelSize: panelSize,
            anchors: anchors(range: nil, element: element, window: window),
            displays: displays,
            isFullScreen: false
        )
        XCTAssertEqual(elementPlacement.anchorSource, .element)

        let windowPlacement = geometry.place(
            panelSize: panelSize,
            anchors: anchors(range: nil, element: nil, window: window),
            displays: displays,
            isFullScreen: false
        )
        XCTAssertEqual(windowPlacement.anchorSource, .window)

        let targetDisplayPlacement = geometry.place(
            panelSize: panelSize,
            anchors: anchors(
                range: nil,
                element: nil,
                window: nil,
                targetDisplayID: "secondary"
            ),
            displays: displays,
            isFullScreen: false
        )
        XCTAssertEqual(targetDisplayPlacement.anchorSource, .targetDisplay)
        XCTAssertEqual(targetDisplayPlacement.displayID, "secondary")

        let activeDisplayPlacement = geometry.place(
            panelSize: panelSize,
            anchors: anchors(
                range: nil,
                element: nil,
                window: nil,
                targetDisplayID: nil
            ),
            displays: displays,
            isFullScreen: false
        )
        XCTAssertEqual(activeDisplayPlacement.anchorSource, .activeDisplay)
        XCTAssertEqual(activeDisplayPlacement.displayID, "primary")
    }

    func testScreenEdgesClampCompletePanelInsideVisibleFrame() {
        let display = PanelProbeDisplay(
            id: "primary",
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 852),
            backingScaleFactor: 2
        )
        let geometry = PanelProbeGeometry(safeMargin: margin)
        let placements = [
            CGRect(x: 0, y: 24, width: 1, height: 1),
            CGRect(x: 1_439, y: 24, width: 1, height: 1),
            CGRect(x: 0, y: 875, width: 1, height: 1),
            CGRect(x: 1_439, y: 875, width: 1, height: 1),
        ].map { anchor in
            geometry.place(
                panelSize: panelSize,
                anchors: anchors(range: anchor),
                displays: [display],
                isFullScreen: false
            )
        }
        let safeFrame = display.visibleFrame.insetBy(dx: margin, dy: margin)

        for placement in placements {
            XCTAssertEqual(placement.displayID, "primary")
            XCTAssertTrue(
                safeFrame.contains(placement.frame),
                "Expected \(placement.frame) inside \(safeFrame)"
            )
        }
    }

    func testNegativeCoordinateDisplayIsNotClampedOntoPrimaryDisplay() {
        let leftDisplay = PanelProbeDisplay(
            id: "left",
            frame: CGRect(x: -1_600, y: 0, width: 1_600, height: 1_000),
            visibleFrame: CGRect(x: -1_600, y: 0, width: 1_600, height: 976),
            backingScaleFactor: 1
        )
        let primary = standardDisplays()[0]
        let geometry = PanelProbeGeometry(safeMargin: margin)

        let placement = geometry.place(
            panelSize: panelSize,
            anchors: anchors(
                range: CGRect(x: -1_500, y: 400, width: 20, height: 20)
            ),
            displays: [leftDisplay, primary],
            isFullScreen: false
        )

        XCTAssertEqual(placement.displayID, "left")
        XCTAssertLessThan(placement.frame.maxX, 0)
        XCTAssertTrue(
            leftDisplay.visibleFrame
                .insetBy(dx: margin, dy: margin)
                .contains(placement.frame)
        )
    }

    func testLargestAnchorIntersectionSelectsSecondaryDisplay() {
        let displays = standardDisplays()
        let geometry = PanelProbeGeometry(safeMargin: margin)

        let placement = geometry.place(
            panelSize: panelSize,
            anchors: anchors(
                range: CGRect(x: 1_420, y: 500, width: 100, height: 30)
            ),
            displays: displays,
            isFullScreen: false
        )

        XCTAssertEqual(placement.displayID, "secondary")
        XCTAssertTrue(
            displays[1].visibleFrame
                .insetBy(dx: margin, dy: margin)
                .contains(placement.frame)
        )
    }

    func testBackingScaleDoesNotMultiplyAppKitPointCoordinatesOrPanelSize() {
        let scaledDisplay = PanelProbeDisplay(
            id: "scaled",
            frame: CGRect(x: 0, y: 0, width: 1_280, height: 800),
            visibleFrame: CGRect(x: 0, y: 24, width: 1_280, height: 752),
            backingScaleFactor: 2
        )
        let geometry = PanelProbeGeometry(safeMargin: margin)

        let placement = geometry.place(
            panelSize: panelSize,
            anchors: anchors(
                range: CGRect(x: 1_250, y: 760, width: 10, height: 10),
                targetDisplayID: "scaled",
                activeDisplayID: "scaled"
            ),
            displays: [scaledDisplay],
            isFullScreen: false
        )

        XCTAssertEqual(placement.frame.size, panelSize)
        XCTAssertTrue(
            scaledDisplay.visibleFrame
                .insetBy(dx: margin, dy: margin)
                .contains(placement.frame)
        )
    }

    func testFullScreenPlacementUsesDisplayFrameInsteadOfVisibleFrame() {
        let display = PanelProbeDisplay(
            id: "fullscreen",
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 852),
            backingScaleFactor: 2
        )
        let fullScreenPanelSize = CGSize(width: 320, height: 860)
        let geometry = PanelProbeGeometry(safeMargin: margin)

        let placement = geometry.place(
            panelSize: fullScreenPanelSize,
            anchors: anchors(
                range: CGRect(x: 700, y: 880, width: 10, height: 10),
                targetDisplayID: "fullscreen",
                activeDisplayID: "fullscreen"
            ),
            displays: [display],
            isFullScreen: true
        )

        XCTAssertEqual(placement.confinementFrame, .fullFrame)
        XCTAssertEqual(placement.frame.size, fullScreenPanelSize)
        XCTAssertTrue(
            display.frame
                .insetBy(dx: margin, dy: margin)
                .contains(placement.frame)
        )
        XCTAssertFalse(
            display.visibleFrame
                .insetBy(dx: margin, dy: margin)
                .contains(placement.frame)
        )
    }

    private func anchors(
        range: CGRect? = nil,
        element: CGRect? = nil,
        window: CGRect? = nil,
        targetDisplayID: String? = "secondary",
        activeDisplayID: String = "primary"
    ) -> PanelProbeAnchorCandidates {
        PanelProbeAnchorCandidates(
            rangeBounds: range,
            elementBounds: element,
            windowBounds: window,
            targetDisplayID: targetDisplayID,
            activeDisplayID: activeDisplayID
        )
    }

    private func standardDisplays() -> [PanelProbeDisplay] {
        [
            PanelProbeDisplay(
                id: "primary",
                frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 24, width: 1_440, height: 852),
                backingScaleFactor: 2
            ),
            PanelProbeDisplay(
                id: "secondary",
                frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_056),
                backingScaleFactor: 1
            ),
        ]
    }
}

@MainActor
private final class PanelWindowSpy: PanelProbeWindowPresenting {
    private(set) var orderFrontCallCount = 0
    private(set) var makeKeyAndOrderFrontCallCount = 0

    func orderFrontRegardless() {
        orderFrontCallCount += 1
    }

    func makeKeyAndOrderFront() {
        makeKeyAndOrderFrontCallCount += 1
    }
}

@MainActor
private final class ApplicationActivationSpy: PanelProbeApplicationActivating {
    private(set) var activateCallCount = 0

    func activateIgnoringOtherApps() {
        activateCallCount += 1
    }
}
