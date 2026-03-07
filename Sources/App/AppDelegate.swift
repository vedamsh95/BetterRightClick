import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowManager: MenuWindowManager?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
}
