import AppKit
import ApplicationServices
import Foundation

enum AXObserverRunLoopMode: Equatable, Sendable {
    case common
}

struct AXMonitorCallbackEnvelope: Equatable, Sendable {
    let sessionID: InteractionSessionID
    let targetHandle: TargetHandle
}

protocol AXMonitorEventReceiving: Sendable {
    func receive(_ envelope: AXMonitorCallbackEnvelope) async
}

protocol AXMonitorInvalidationReceiving: Sendable {
    func disableDirectActions(for envelope: AXMonitorCallbackEnvelope) async
}

actor AXMonitorEventRouter: AXMonitorEventReceiving {
    private let invalidationSink: any AXMonitorInvalidationReceiving
    private var activeEnvelope: AXMonitorCallbackEnvelope?

    init(invalidationSink: any AXMonitorInvalidationReceiving) {
        self.invalidationSink = invalidationSink
    }

    func activate(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {
        activeEnvelope = AXMonitorCallbackEnvelope(
            sessionID: sessionID,
            targetHandle: targetHandle
        )
    }

    func deactivate() {
        activeEnvelope = nil
    }

    func receive(_ envelope: AXMonitorCallbackEnvelope) async {
        guard envelope == activeEnvelope else {
            return
        }
        await invalidationSink.disableDirectActions(for: envelope)
    }
}

@MainActor
protocol AXObserverRunLoopScheduling: AnyObject {
    func installObserverSource(
        mode: AXObserverRunLoopMode,
        callback: @escaping @Sendable () -> Void
    )
    func removeObserverSource()
}

extension AXObserverRunLoopScheduling {
    func removeObserverSource() {}
}

@MainActor
protocol WorkspaceActivationMonitoring: AnyObject {
    func start(callback: @escaping @Sendable () -> Void)
    func stop()
}

@MainActor
final class AXTargetMonitor {
    private let runLoopScheduler: any AXObserverRunLoopScheduling
    private let workspaceActivationMonitor: any WorkspaceActivationMonitoring
    private let eventReceiver: any AXMonitorEventReceiving
    private var isMonitoring = false

    init(
        runLoopScheduler: any AXObserverRunLoopScheduling,
        eventReceiver: any AXMonitorEventReceiving,
        workspaceActivationMonitor: any WorkspaceActivationMonitoring = NSWorkspaceActivationMonitor()
    ) {
        self.runLoopScheduler = runLoopScheduler
        self.eventReceiver = eventReceiver
        self.workspaceActivationMonitor = workspaceActivationMonitor
    }

    func startMonitoring(
        sessionID: InteractionSessionID,
        targetHandle: TargetHandle
    ) {
        stopMonitoring()
        let envelope = AXMonitorCallbackEnvelope(
            sessionID: sessionID,
            targetHandle: targetHandle
        )
        let delivery: @Sendable () -> Void = { [eventReceiver, envelope] in
            Task {
                await eventReceiver.receive(envelope)
            }
        }

        runLoopScheduler.installObserverSource(
            mode: .common,
            callback: delivery
        )
        workspaceActivationMonitor.start(callback: delivery)
        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring else {
            return
        }
        workspaceActivationMonitor.stop()
        runLoopScheduler.removeObserverSource()
        isMonitoring = false
    }
}

@MainActor
final class NSWorkspaceActivationMonitor: WorkspaceActivationMonitoring {
    private let notificationCenter: NotificationCenter
    private var token: NSObjectProtocol?

    init(notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.notificationCenter = notificationCenter
    }

    func start(callback: @escaping @Sendable () -> Void) {
        stop()
        token = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { _ in
            callback()
        }
    }

    func stop() {
        guard let token else {
            return
        }
        notificationCenter.removeObserver(token)
        self.token = nil
    }
}

@MainActor
final class SystemAXObserverRunLoopScheduler: AXObserverRunLoopScheduling {
    private final class CallbackBox: @unchecked Sendable {
        let callback: @Sendable () -> Void

        init(callback: @escaping @Sendable () -> Void) {
            self.callback = callback
        }
    }

    private var targetElement: AXUIElement?
    private var applicationElement: AXUIElement?
    private let pid: pid_t
    private var observer: AXObserver?
    private var source: CFRunLoopSource?
    private var callbackBox: CallbackBox?

    init(
        pid: pid_t,
        targetElement: AXUIElement
    ) {
        self.pid = pid
        self.targetElement = targetElement
        applicationElement = AXUIElementCreateApplication(pid)
    }

    func installObserverSource(
        mode: AXObserverRunLoopMode,
        callback: @escaping @Sendable () -> Void
    ) {
        removeObserverSource()
        guard
            mode == .common,
            let targetElement,
            let applicationElement
        else {
            return
        }

        let callbackBox = CallbackBox(callback: callback)
        var createdObserver: AXObserver?
        let creationError = AXObserverCreate(
            pid,
            { _, _, _, context in
                guard let context else {
                    return
                }
                Unmanaged<CallbackBox>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                    .callback()
            },
            &createdObserver
        )
        guard creationError == .success, let createdObserver else {
            return
        }

        let context = Unmanaged.passUnretained(callbackBox).toOpaque()
        for notification in Self.applicationNotifications {
            AXObserverAddNotification(
                createdObserver,
                applicationElement,
                notification as CFString,
                context
            )
        }
        for notification in Self.targetNotifications {
            AXObserverAddNotification(
                createdObserver,
                targetElement,
                notification as CFString,
                context
            )
        }

        let source = AXObserverGetRunLoopSource(createdObserver)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.callbackBox = callbackBox
        self.observer = createdObserver
        self.source = source
    }

    func removeObserverSource() {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let observer, let applicationElement {
            for notification in Self.applicationNotifications {
                AXObserverRemoveNotification(
                    observer,
                    applicationElement,
                    notification as CFString
                )
            }
        }
        if let observer, let targetElement {
            for notification in Self.targetNotifications {
                AXObserverRemoveNotification(
                    observer,
                    targetElement,
                    notification as CFString
                )
            }
        }
        source = nil
        observer = nil
        callbackBox = nil
        targetElement = nil
        applicationElement = nil
    }

    private static let applicationNotifications = [
        kAXFocusedUIElementChangedNotification,
        kAXFocusedWindowChangedNotification,
    ]

    private static let targetNotifications = [
        kAXSelectedTextChangedNotification,
        kAXValueChangedNotification,
        kAXUIElementDestroyedNotification,
    ]
}
