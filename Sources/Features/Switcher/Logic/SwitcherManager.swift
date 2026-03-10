import SwiftUI
import AppKit

@MainActor
class SwitcherManager: ObservableObject {
    private let windowManager: MenuWindowManager
    private let appSwitcherService: AppSwitcherService
    private let clipboardService: ClipboardService
    
    init(windowManager: MenuWindowManager, appSwitcherService: AppSwitcherService, clipboardService: ClipboardService) {
        self.windowManager = windowManager
        self.appSwitcherService = appSwitcherService
        self.clipboardService = clipboardService
    }
    
    func refreshApps() {
        appSwitcherService.refreshRunningApps()
    }
    
    func focusApp(_ app: NSRunningApplication) {
        _ = app.activate(options: [.activateAllWindows])
        windowManager.hidePanel()
    }
    
    func activatePinnedApp(_ pinned: PinnedApp) {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == pinned.id }) {
            _ = running.activate(options: [.activateAllWindows])
            windowManager.hidePanel()
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: pinned.id) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            windowManager.hidePanel()
            return
        }

        windowManager.statusMessage = "App not installed: \(pinned.name)"
    }
    
    func minimizeAllActiveApps() {
        windowManager.hidePanel()

        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier != Bundle.main.bundleIdentifier &&
            $0.activationPolicy == .regular &&
            !$0.isTerminated
        }

        var hiddenCount = 0
        for app in apps {
            if app.hide() {
                hiddenCount += 1
            }
        }

        windowManager.statusMessage = hiddenCount > 0
            ? "Minimized/hidden \(hiddenCount) active app(s)."
            : "No active apps were minimized."
    }
    
    func copyClipboardItemToPasteboard(_ item: ClipboardItem) {
        let ok = clipboardService.copyToPasteboard(item)
        windowManager.statusMessage = ok ? "Copied item to clipboard." : "Failed to copy item to clipboard."
    }
    
    func pasteClipboardItem(_ item: ClipboardItem) {
        guard clipboardService.copyToPasteboard(item) else {
            windowManager.statusMessage = "Failed to prepare clipboard item for paste."
            return
        }
        
        // Use the coordinator's helper for keystroke injection
        windowManager.postPasteCommandToFrontmostApp(preferMatchStyle: false)
    }
}
