import AppKit

@main
enum AppEntry {
    @MainActor private static var lifecycle: AppLifecycleController?

    static func main() {
        MainActor.assumeIsolated {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)

            let controller = AppLifecycleController()
            lifecycle = controller
            controller.start()

            application.run()
        }
    }
}
