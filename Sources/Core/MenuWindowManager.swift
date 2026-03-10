import AppKit
import Combine
import SwiftUI
import Vision

@MainActor
final class MenuWindowManager: ObservableObject {
    // Undo last snap
    func undoSnap() {
        let ok = windowSnapService.undoLastSnap()
        statusMessage = ok ? "Restored previous window frame." : "Nothing to undo."
    }
    @Published var clipboardItems: [ClipboardItem] = []
    @Published var runningApps: [NSRunningApplication] = []
    @Published var contextState: ContextState = ContextState()
    @Published var pinnedApps: [PinnedApp] = []
    @Published var statusMessage: String = ""
    @Published var diagnosticsAXTrusted: Bool = false
    @Published var diagnosticsAutomationOK: Bool = false
    @Published var diagnosticsTargetBundleID: String = ""
    @Published var diagnosticsContextFolder: String = ""
    @Published var diagnosticsLastPastePath: String = "idle"
    @Published var diagnosticsAppleEventsEntitled: Bool = false
    @Published var diagnosticsSelectedTextDetected: Bool = false
    @Published var isPinned: Bool = false
    @Published var diagnosticsSelectionSource: String = "none"
    @Published var diagnosticsSelectionDetails: String = "idle"
    @Published var diagnosticsOCRState: String = "idle"
    @Published var diagnosticsOCRDestination: String = "none"
    @Published var diagnosticsAppBundlePath: String = ""
    @Published var diagnosticsSnapState: String = "idle"
    @Published var permissionSnapshot: PermissionStateMachine.Snapshot = .empty
    @Published var snapDisplays: [WindowSnapService.DisplayTarget] = []
    @Published var lookupResult: String?
    
    // Feature Managers
    @Published var snap: SnapManager!
    @Published var actions: ActionManager!
    @Published var switcher: SwitcherManager!
    @Published var settings: SettingsManager!

    private var panel: NSPanel?
    private var rightClickMonitor: Any?
    private var globalDismissMonitor: Any?
    private var localDismissMonitor: Any?

    internal let clipboardService: ClipboardService
    internal let appSwitcherService: AppSwitcherService
    internal let contextService: ContextService
    internal let fileOperationsService: FileOperationsService
    internal let accessibilityService = AccessibilityService()
    internal let permissionStateMachine = PermissionStateMachine()
    internal let windowSnapService = WindowSnapService()
    internal let entitlementService = EntitlementService()

    private var cancellables: Set<AnyCancellable> = []
    private var hasPromptedForAccessibility = false
    private var hasStarted = false
    var lastFrontmostApp: NSRunningApplication?
    var lastRightClickLocation: NSPoint?
    private var lastPanelShowTime: TimeInterval = 0

    private let panelSize = NSSize(width: 500, height: 430)
    private let extensionToPinnedBundleIDs: [String: [String]] = [
        "png": ["com.figma.Desktop", "com.adobe.Photoshop"],
        "jpg": ["com.figma.Desktop", "com.adobe.Photoshop"],
        "jpeg": ["com.figma.Desktop", "com.adobe.Photoshop"],
        "pdf": ["com.adobe.Reader", "com.apple.Preview"],
        "md": ["com.microsoft.VSCode", "com.apple.TextEdit"],
        "txt": ["com.microsoft.VSCode", "com.apple.TextEdit"]
    ]

    init(
        clipboardService: ClipboardService,
        appSwitcherService: AppSwitcherService,
        contextService: ContextService,
        fileOperationsService: FileOperationsService
    ) {
        self.clipboardService = clipboardService
        self.appSwitcherService = appSwitcherService
        self.contextService = contextService
        self.fileOperationsService = fileOperationsService

        clipboardService.$history
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.clipboardItems = $0 }
            .store(in: &cancellables)

        appSwitcherService.$runningApps
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.runningApps = $0 }
            .store(in: &cancellables)
            
        // Initialize sub-managers
        self.snap = SnapManager(windowManager: self, snapService: windowSnapService)
        self.actions = ActionManager(windowManager: self, fileService: fileOperationsService)
        self.switcher = SwitcherManager(windowManager: self, appSwitcherService: appSwitcherService, clipboardService: clipboardService)
        self.settings = SettingsManager(
            windowManager: self,
            accessibilityService: accessibilityService,
            permissionStateMachine: permissionStateMachine,
            entitlementService: entitlementService,
            contextService: contextService
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Defensive cleanup in case startup is called after partial initialization.
        removeEventMonitors()

        ensurePanel()
        clipboardService.startMonitoring()
        clipboardService.captureCurrentSnapshot()
        appSwitcherService.refreshRunningApps()
        refreshContext()
        settings.refreshDiagnostics(probePermissions: false)
        snap.refreshSnapDisplays()

        if !accessibilityService.isTrusted(promptIfNeeded: true) {
            accessibilityService.openSettings()
            hasPromptedForAccessibility = true
        }

        rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) { [weak self] _ in
            Task { @MainActor in
                self?.requestShowPanelFromRightClick()
            }
        }

        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleDismissEvent(event)
            }
        }

        localDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            Task { @MainActor in
                self?.handleDismissEvent(event)
            }
            return event
        }
    }

    func shutdown() {
        guard hasStarted else { return }
        hasStarted = false

        removeEventMonitors()
        panel?.orderOut(nil)
        clipboardService.stopMonitoring()
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    func refreshContext(useFinderScript: Bool = false, allowSelectionProbe: Bool = false) {
        let workspaceFrontmost = NSWorkspace.shared.frontmostApplication
        let preferredApp: NSRunningApplication?
        if workspaceFrontmost?.bundleIdentifier == Bundle.main.bundleIdentifier {
            preferredApp = lastFrontmostApp
        } else {
            preferredApp = workspaceFrontmost
        }

        contextState = contextService.captureContext(
            mouseLocation: lastRightClickLocation,
            allowFinderScript: useFinderScript,
            preferredApp: preferredApp
        )

        updatePinnedApps()
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let rootView = SuperMenuRootView(windowManager: self)
            .frame(width: panelSize.width, height: panelSize.height)

        let hosting = NSHostingView(rootView: rootView)
        hosting.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = NSView(frame: NSRect(origin: .zero, size: panelSize))
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true

        panel.contentView?.addSubview(hosting)
        guard let content = panel.contentView else { return }
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: content.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        self.panel = panel
    }

    private func showPanelAtCurrentMouseLocation() {
        ensurePanel()

        let mouse = NSEvent.mouseLocation
        lastRightClickLocation = mouse

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastFrontmostApp = frontmost
        }

        // Capture context before bringing our panel to front so the source app's
        // focused element/selection is still readable via Accessibility.
        clipboardService.captureCurrentSnapshot()
        appSwitcherService.refreshRunningApps()
        // Keep panel-open capture AppleScript-free for stability in Finder/Desktop.
        refreshContext(useFinderScript: false, allowSelectionProbe: false)
        settings.refreshDiagnostics(probePermissions: false)
        snap.refreshSnapDisplays()

        guard let panel else { return }
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            let visible = screen.visibleFrame
            let gap: CGFloat = 14
            let estimatedNativeMenuWidth: CGFloat = 260

            let preferRightSide = mouse.x < visible.midX
            let preferAboveCursor = mouse.y < visible.midY

            var x = preferRightSide
                ? mouse.x + estimatedNativeMenuWidth + gap
                : mouse.x - panelSize.width - gap

            if x < visible.minX || x + panelSize.width > visible.maxX {
                x = min(max(mouse.x + gap, visible.minX), visible.maxX - panelSize.width)
            }

            var topLeftY = preferAboveCursor
                ? mouse.y + panelSize.height + gap
                : mouse.y - gap

            topLeftY = min(max(topLeftY, visible.minY + panelSize.height), visible.maxY)
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: topLeftY))
        } else {
            panel.setFrameTopLeftPoint(NSPoint(x: mouse.x + 8, y: mouse.y - 8))
        }

        panel.orderFrontRegardless()
    }

    private func requestShowPanelFromRightClick() {
        let now = Date().timeIntervalSinceReferenceDate
        // Global monitors can occasionally deliver duplicate events.
        if now - lastPanelShowTime < 0.12 {
            return
        }
        lastPanelShowTime = now
        showPanelAtCurrentMouseLocation()
    }

    internal func postPasteCommandToFrontmostApp(preferMatchStyle: Bool) {
        hidePanel()
        
        // CRITICAL STEP: Completely hide our application explicitly so the previous application perfectly regains key focus.
        NSApp.hide(nil)
        panel?.orderOut(nil)

        // Give the OS time to restore focus to the underlying application.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self else { return }

            let axTrusted = self.accessibilityService.isTrusted(promptIfNeeded: true)
            self.diagnosticsAXTrusted = axTrusted
            
            if !axTrusted && !self.hasPromptedForAccessibility {
                self.accessibilityService.openSettings()
                self.hasPromptedForAccessibility = true
            }

            // Explicitly reactivate the app that was frontmost on panel open,
            // then send paste to reduce focus races.
            if let target = self.lastFrontmostApp, !target.isTerminated {
                _ = target.activate(options: [.activateAllWindows])
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if preferMatchStyle {
                    self.postPasteAndMatchStyleKeystroke(tap: .cgSessionEventTap)
                    self.diagnosticsLastPastePath = "match-style+cgevent"
                } else {
                    self.postCommandVKeystroke(tap: .cgSessionEventTap)
                    self.diagnosticsLastPastePath = "cgevent"
                }
                self.statusMessage = "Paste dispatched via CGEvent."
            }
        }
    }

    private func updatePinnedApps() {
        let ext = contextState.primaryExtension ?? ""
        let bundleIDs = extensionToPinnedBundleIDs[ext] ?? []

        pinnedApps = bundleIDs.map { id in
            let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String }
                ?? id
            return PinnedApp(id: id, name: name)
        }
    }

    private func checkSystemEventsAutomation() -> Bool {
        let source = #"""
        tell application "System Events"
            return name of first process
        end tell
        """#

        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        return error == nil
    }

    private func handleDismissEvent(_ event: NSEvent) {
        guard let panel, panel.isVisible else { return }

        if event.type == .keyDown && event.keyCode == 53 {
            hidePanel()
            return
        }

        if event.type == .leftMouseDown || event.type == .rightMouseDown {
            let mouse = NSEvent.mouseLocation
            if !panel.frame.contains(mouse) && !isPinned {
                hidePanel()
            }
        }
    }

    private func removeEventMonitors() {
        if let rightClickMonitor {
            NSEvent.removeMonitor(rightClickMonitor)
            self.rightClickMonitor = nil
        }

        if let globalDismissMonitor {
            NSEvent.removeMonitor(globalDismissMonitor)
            self.globalDismissMonitor = nil
        }

        if let localDismissMonitor {
            NSEvent.removeMonitor(localDismissMonitor)
            self.localDismissMonitor = nil
        }
    }

    internal func postCommandVKeystroke(tap: CGEventTapLocation) {
        let sourceState = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x37, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x37, keyDown: false)

        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand

        cmdDown?.post(tap: tap)
        vDown?.post(tap: tap)
        vUp?.post(tap: tap)
        cmdUp?.post(tap: tap)
    }

    internal func postCommandCKeystroke(tap: CGEventTapLocation) {
        let sourceState = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x37, keyDown: true)
        let cDown = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x08, keyDown: true)
        let cUp = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x08, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x37, keyDown: false)

        cDown?.flags = .maskCommand
        cUp?.flags = .maskCommand

        cmdDown?.post(tap: tap)
        cDown?.post(tap: tap)
        cUp?.post(tap: tap)
        cmdUp?.post(tap: tap)
    }

    internal func probeSelectedTextFromActiveApp() -> String? {
        guard ensureAccessibilityForInputEvents() else { return nil }

        let snapshot = clipboardService.snapshotGeneralPasteboard()
        let sentinel = "__BRC_SENTINEL_\(UUID().uuidString)__"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(sentinel, forType: .string)

        // Trigger native copy in the currently focused app, then read text.
        postCommandCKeystroke(tap: .cgSessionEventTap)
        postCommandCKeystroke(tap: .cghidEventTap)
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.15, false)

        let probedText = NSPasteboard.general.string(forType: .string)
        let selected = (probedText == sentinel) ? nil : clipboardService.currentText()
        _ = clipboardService.restoreGeneralPasteboard(from: snapshot)
        return selected
    }

    private func postPasteAndMatchStyleKeystroke(tap: CGEventTapLocation) {
        let sourceState = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x37, keyDown: true)
        let shiftDown = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x38, keyDown: true)
        let optionDown = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x3A, keyDown: true)
        let vDown = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x09, keyDown: true)
        let vUp = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x09, keyDown: false)
        let optionUp = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x3A, keyDown: false)
        let shiftUp = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x38, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: sourceState, virtualKey: 0x37, keyDown: false)

        let flags: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate]
        vDown?.flags = flags
        vUp?.flags = flags

        cmdDown?.post(tap: tap)
        shiftDown?.post(tap: tap)
        optionDown?.post(tap: tap)
        vDown?.post(tap: tap)
        vUp?.post(tap: tap)
        optionUp?.post(tap: tap)
        shiftUp?.post(tap: tap)
        cmdUp?.post(tap: tap)
    }

    private func ensureAccessibilityForInputEvents() -> Bool {
        if accessibilityService.isTrusted(promptIfNeeded: false) {
            return true
        }
        
        // If we've already prompted recently, don't nag.
        if hasPromptedForAccessibility {
            return false
        }
        
        hasPromptedForAccessibility = true
        accessibilityService.openSettings()
        statusMessage = "Accessibility access required for input simulation."
        return false
    }

}
