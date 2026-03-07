import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: MenuWindowManager?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        terminateDuplicateInstancesIfNeeded()

        windowManager = MenuWindowManager(
            clipboardService: ClipboardService(),
            appSwitcherService: AppSwitcherService(),
            contextService: ContextService(),
            fileOperationsService: FileOperationsService()
        )
        windowManager?.start()
    }

    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        windowManager?.shutdown()
    }

    private func terminateDuplicateInstancesIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier

        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            guard app.processIdentifier != currentPID else { continue }
            _ = app.terminate()
        }
    }
}
