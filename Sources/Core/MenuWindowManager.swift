import AppKit
import Combine
import SwiftUI
import Vision

@MainActor
final class MenuWindowManager: ObservableObject {
    @Published private(set) var clipboardItems: [ClipboardItem] = []
    @Published private(set) var runningApps: [NSRunningApplication] = []
    @Published private(set) var contextState: ContextState = ContextState()
    @Published private(set) var pinnedApps: [PinnedApp] = []
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var diagnosticsAXTrusted: Bool = false
    @Published private(set) var diagnosticsAutomationOK: Bool = false
    @Published private(set) var diagnosticsTargetBundleID: String = ""
    @Published private(set) var diagnosticsContextFolder: String = ""
    @Published private(set) var diagnosticsLastPastePath: String = "idle"
    @Published private(set) var diagnosticsAppleEventsEntitled: Bool = false
    @Published private(set) var diagnosticsSelectedTextDetected: Bool = false
    @Published private(set) var diagnosticsSelectionSource: String = "none"
    @Published private(set) var diagnosticsSelectionDetails: String = "idle"
    @Published private(set) var diagnosticsOCRState: String = "idle"
    @Published private(set) var diagnosticsOCRDestination: String = "none"
    @Published private(set) var diagnosticsAppBundlePath: String = ""
    @Published private(set) var lookupResult: String?

    private var panel: NSPanel?
    private var rightClickMonitor: Any?
    private var globalDismissMonitor: Any?
    private var localDismissMonitor: Any?

    private let clipboardService: ClipboardService
    private let appSwitcherService: AppSwitcherService
    private let contextService: ContextService
    private let fileOperationsService: FileOperationsService
    private let accessibilityService = AccessibilityService()
    private let entitlementService = EntitlementService()

    private var cancellables: Set<AnyCancellable> = []
    private var hasPromptedForAccessibility = false
    private var lastFrontmostApp: NSRunningApplication?
    private var lastRightClickLocation: NSPoint?
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
    }

    func start() {
        ensurePanel()
        clipboardService.startMonitoring()
        clipboardService.captureCurrentSnapshot()
        appSwitcherService.refreshRunningApps()
        refreshContext()
        refreshDiagnostics()

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
        removeEventMonitors()
        clipboardService.stopMonitoring()
    }

    func hidePanel() {
        panel?.orderOut(nil)
    }

    func refreshApps() {
        appSwitcherService.refreshRunningApps()
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
        diagnosticsContextFolder = contextState.directoryURL?.path ?? "(not detected)"
        diagnosticsSelectedTextDetected = !(contextState.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        diagnosticsSelectionSource = contextState.selectedTextSource ?? "none"
        diagnosticsSelectionDetails = contextService.lastSelectionDiagnostics
    }

    func refreshDiagnostics() {
        diagnosticsAXTrusted = accessibilityService.isTrusted(promptIfNeeded: false)
        diagnosticsAppleEventsEntitled = entitlementService.hasEntitlement("com.apple.security.automation.apple-events")
        diagnosticsTargetBundleID = contextState.frontmostBundleID
            ?? lastFrontmostApp?.bundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            ?? "(unknown)"
        diagnosticsContextFolder = contextState.directoryURL?.path ?? "(not detected)"
        diagnosticsAppBundlePath = Bundle.main.bundleURL.path
    }

    func requestAccessibilityAccess() {
        diagnosticsAXTrusted = accessibilityService.isTrusted(promptIfNeeded: true)
        accessibilityService.openSettings()
        hasPromptedForAccessibility = true
    }

    func refreshPermissionsAndContext() {
        refreshContext(useFinderScript: false, allowSelectionProbe: false)
        refreshDiagnostics()
    }

    func revealThisAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func copyAppBundlePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Bundle.main.bundleURL.path, forType: .string)
        statusMessage = "Copied app bundle path."
    }

    func copyDiagnosticsSnapshot() {
        let lines = [
            "AX Trusted: \(diagnosticsAXTrusted ? "Yes" : "No")",
            "Automation (System Events): \(diagnosticsAutomationOK ? "Yes" : "No")",
            "Target Bundle: \(diagnosticsTargetBundleID)",
            "Selected Text Detected: \(diagnosticsSelectedTextDetected ? "Yes" : "No")",
            "Selection Source: \(diagnosticsSelectionSource)",
            "Selection Details: \(diagnosticsSelectionDetails)",
            "OCR State: \(diagnosticsOCRState)",
            "OCR Destination: \(diagnosticsOCRDestination)",
            "Apple Events Entitlement: \(diagnosticsAppleEventsEntitled ? "Yes" : "No")",
            "Context Folder: \(diagnosticsContextFolder)",
            "Last Paste Path: \(diagnosticsLastPastePath)",
            "App Path: \(diagnosticsAppBundlePath)"
        ]

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        statusMessage = "Copied diagnostics to clipboard."
    }

    func takeScreenshot() {
        hidePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "BRC_Screenshot_\(formatter.string(from: Date())).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", tempURL.path]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0,
               FileManager.default.fileExists(atPath: tempURL.path) {
                NSApp.activate(ignoringOtherApps: true)

                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = filename
                panel.allowedContentTypes = [.png]
                panel.isExtensionHidden = false
                panel.title = "Save Screenshot"
                panel.message = "Choose where to save your screenshot."

                if panel.runModal() == .OK, let destination = panel.url {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try? FileManager.default.removeItem(at: destination)
                    }

                    do {
                        try FileManager.default.moveItem(at: tempURL, to: destination)
                        statusMessage = "Screenshot saved to \(destination.lastPathComponent)."
                        diagnosticsLastPastePath = "screenshot: saved-via-save-panel"
                    } catch {
                        statusMessage = "Failed to save screenshot: \(error.localizedDescription)"
                        diagnosticsLastPastePath = "screenshot: save-failed"
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                } else {
                    statusMessage = "Screenshot captured, but save was cancelled."
                    diagnosticsLastPastePath = "screenshot: save-cancelled"
                    try? FileManager.default.removeItem(at: tempURL)
                }
            } else {
                statusMessage = "Screenshot cancelled or blocked by Screen Recording permission."
                diagnosticsLastPastePath = "screenshot: cancelled-or-blocked"
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            statusMessage = "Failed to start screenshot tool: \(error.localizedDescription)"
            diagnosticsLastPastePath = "screenshot: failed-to-start"
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    func minimizeAllActiveApps() {
        hidePanel()

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

        statusMessage = hiddenCount > 0
            ? "Minimized/hidden \(hiddenCount) active app(s)."
            : "No active apps were minimized."
    }

    func focusApp(_ app: NSRunningApplication) {
        _ = app.activate(options: [.activateAllWindows])
        hidePanel()
    }

    func copyClipboardItemToPasteboard(_ item: ClipboardItem) {
        let ok = clipboardService.copyToPasteboard(item)
        statusMessage = ok ? "Copied item to clipboard." : "Failed to copy item to clipboard."
    }

    func pasteClipboardItem(_ item: ClipboardItem) {
        guard clipboardService.copyToPasteboard(item) else {
            statusMessage = "Failed to prepare clipboard item for paste."
            return
        }

        // Instantly trigger Cmd+V after loading the item into native clipboard
        postPasteCommandToFrontmostApp(preferMatchStyle: false)
    }

    enum TextStyle {
        case plainText, uppercase, lowercase, titleCase
    }

    var canUseTextTools: Bool {
        true
    }

    var canUseOCRTools: Bool {
        if contextState.targetKind == .image {
            return true
        }

        if let first = contextState.selectedFileURLs.first {
            let ext = first.pathExtension.lowercased()
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"]
            return imageExts.contains(ext)
        }

        return false
    }

    func lookupText(_ text: String) {
        if let result = DCSCopyTextDefinition(nil, text as CFString, CFRangeMake(0, text.count))?.takeRetainedValue() as String? {
            lookupResult = result
        } else {
            lookupResult = "No definition found for '\(text)'"
        }
    }

    func clearLookup() {
        lookupResult = nil
    }

    func lookupCurrentTextContext() {
        guard let text = resolveSelectedTextForTools() else {
            statusMessage = "No selected text detected for lookup."
            return
        }
        lookupText(text)
    }

    func formatCurrentTextContext(style: TextStyle) {
        guard let text = resolveSelectedTextForTools() else {
            statusMessage = "No selected text detected for formatting."
            return
        }

        let formattedText: String
        switch style {
        case .plainText: formattedText = text
        case .uppercase: formattedText = text.uppercased()
        case .lowercase: formattedText = text.lowercased()
        case .titleCase: formattedText = text.capitalized
        }

        if contextService.replaceSelectedTextInFocusedElement(with: formattedText) {
            statusMessage = "Formatted selected text replaced via Accessibility."
            diagnosticsLastPastePath = "ax-set-selected-text"
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formattedText, forType: .string)
        statusMessage = "Formatted selected text pasted (fallback)."
        postPasteCommandToFrontmostApp(preferMatchStyle: false)
    }

    private func resolveSelectedTextForTools() -> String? {
        if let current = contextState.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty {
            diagnosticsSelectedTextDetected = true
            diagnosticsSelectionDetails = "using cached selection (len=\(current.count))"
            return current
        }

        // Re-capture right now in case panel-open timing missed it.
        refreshContext(useFinderScript: false, allowSelectionProbe: false)
        if let refreshed = contextState.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !refreshed.isEmpty {
            diagnosticsSelectedTextDetected = true
            diagnosticsSelectionDetails = "selection refreshed from AX (len=\(refreshed.count))"
            return refreshed
        }

        // Explicit user action fallback only: probe selection via Cmd+C snapshot/restore.
        if let probed = probeSelectedTextFromActiveApp()?.trimmingCharacters(in: .whitespacesAndNewlines), !probed.isEmpty {
            contextState.selectedText = probed
            contextState.selectedTextSource = "cmd-c-probe-action"
            diagnosticsSelectedTextDetected = true
            diagnosticsSelectionSource = contextState.selectedTextSource ?? "none"
            diagnosticsSelectionDetails = "selected-text found via on-demand cmd-c probe"
            return probed
        }

        diagnosticsSelectedTextDetected = false
        diagnosticsSelectionDetails = "no selected text detected (AX + on-demand probe)"

        return nil
    }

    func formatSelectedText(style: TextStyle) {
        guard let text = contextState.selectedText else { return }
        let formattedText: String
        switch style {
        case .plainText: formattedText = text
        case .uppercase: formattedText = text.uppercased()
        case .lowercase: formattedText = text.lowercased()
        case .titleCase: formattedText = text.capitalized
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formattedText, forType: .string)
        statusMessage = "Formatted text pasted."
        postPasteCommandToFrontmostApp(preferMatchStyle: false)
    }

    func createNewFile(_ type: NewFileType) {
        refreshContext(useFinderScript: false)

        let destinationDirectory = resolvedActionDirectory(preferFinderContext: true)
        let saveURL: URL?

        if let dir = destinationDirectory,
           fileOperationsService.isWritableDirectory(dir) {
            saveURL = nextUntitledURL(in: dir, type: type)
        } else {
            saveURL = presentSavePanelForNewFile(type: type)
        }

        guard let targetURL = saveURL else {
            statusMessage = "Create file cancelled."
            return
        }

        do {
            try fileOperationsService.createFile(type: type, at: targetURL)
            statusMessage = "Created \(targetURL.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
        } catch {
            statusMessage = "Create file failed: \(error.localizedDescription)"
        }
    }

    func deleteTargetPermanently() {
        guard let url = contextState.targetURL else { return }
        do {
            try FileManager.default.removeItem(at: url)
            hidePanel()
            statusMessage = "Deleted permanently."
        } catch {
            statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    func ocrImage() {
        let sourceURL = resolveImageSourceForOCR()
        diagnosticsOCRState = "resolve-source: \(sourceURL?.path ?? "nil")"
        diagnosticsOCRDestination = "none"
        guard let url = sourceURL, let image = NSImage(contentsOf: url) else {
            statusMessage = "Failed to load image for OCR."
            diagnosticsOCRState = "failed: NSImage load"
            return
        }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            statusMessage = "Failed to load image for OCR."
            diagnosticsOCRState = "failed: cgImage conversion"
            return
        }

        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else {
                DispatchQueue.main.async {
                    self?.statusMessage = "OCR failed: \(error?.localizedDescription ?? "Unknown")"
                    self?.diagnosticsOCRState = "failed: VNRecognizeTextRequest callback error"
                }
                return
            }
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            DispatchQueue.main.async {
                if !recognizedText.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recognizedText, forType: .string)
                    self?.statusMessage = "OCR text copied to clipboard and paste triggered in active app."
                    self?.diagnosticsOCRState = "success: observations=\(observations.count), textLen=\(recognizedText.count)"
                    self?.diagnosticsOCRDestination = "clipboard (+ paste attempt)"
                    self?.postPasteCommandToFrontmostApp(preferMatchStyle: false)
                } else {
                    self?.statusMessage = "No text found in image."
                    self?.diagnosticsOCRState = "success: observations=\(observations.count), empty text"
                    self?.diagnosticsOCRDestination = "none"
                }
            }
        }
        
        do {
            try requestHandler.perform([request])
        } catch {
            statusMessage = "OCR request failed: \(error.localizedDescription)"
            diagnosticsOCRState = "failed: requestHandler.perform"
        }
    }

    private func resolveImageSourceForOCR() -> URL? {
        if let target = contextState.targetURL, isImageURL(target) {
            return target
        }

        if let selected = contextState.selectedFileURLs.first(where: { isImageURL($0) }) {
            return selected
        }

        // Fallback so OCR remains usable even when Finder/Desktop context detection misses.
        hidePanel()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = []
        panel.title = "Choose Image For OCR"

        guard panel.runModal() == .OK, let picked = panel.url else {
            diagnosticsOCRState = "cancelled: file-picker"
            return nil
        }

        return picked
    }

    private func isImageURL(_ url: URL) -> Bool {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"]
        return imageExts.contains(url.pathExtension.lowercased())
    }

    func stageCutFromCurrentContext() {
        refreshContext(useFinderScript: false)

        if !contextState.selectedFileURLs.isEmpty {
            fileOperationsService.stageCutItems(contextState.selectedFileURLs)
            statusMessage = "Staged \(fileOperationsService.cutItemCount) item(s) for cut."
            return
        }

        if let target = contextState.targetURL, contextState.targetKind != .folder {
            fileOperationsService.stageCutItems([target])
            statusMessage = "Staged 1 item for cut (target under cursor)."
            return
        }

        statusMessage = "No file selected to cut."
    }

    func pasteCutIntoCurrentDirectory() {
        refreshContext(useFinderScript: false)
        let directory = resolvedActionDirectory(preferFinderContext: true) ??
            presentDirectoryPicker(title: "Choose Destination Folder")

        guard let directory else {
            statusMessage = "Paste cut cancelled."
            return
        }

        do {
            let moved = try fileOperationsService.pasteCutItems(into: directory)
            statusMessage = moved > 0
                ? "Moved \(moved) item(s) into \(directory.lastPathComponent)."
                : "Nothing moved."
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
        } catch {
            statusMessage = "Paste cut failed: \(error.localizedDescription)"
        }
    }

    func flattenCurrentDirectory() {
        refreshContext(useFinderScript: false)
        let directory = resolvedActionDirectory(preferFinderContext: true) ??
            presentDirectoryPicker(title: "Choose Folder To Flatten")

        guard let directory else {
            statusMessage = "Flatten cancelled."
            return
        }

        do {
            let moved = try fileOperationsService.flattenDirectory(root: directory)
            statusMessage = "Flatten complete: moved \(moved) file(s)."
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
        } catch {
            statusMessage = "Flatten failed: \(error.localizedDescription)"
        }
    }

    func activatePinnedApp(_ pinned: PinnedApp) {
        if let running = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == pinned.id }) {
            _ = running.activate(options: [.activateAllWindows])
            hidePanel()
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: pinned.id) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            hidePanel()
            return
        }

        statusMessage = "App not installed: \(pinned.name)"
    }

    func openTargetInFinder() {
        if let target = contextState.targetURL {
            NSWorkspace.shared.activateFileViewerSelecting([target])
            statusMessage = "Revealed target in Finder."
            return
        }

        if let directory = contextState.directoryURL {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
            statusMessage = "Opened folder in Finder."
            return
        }

        statusMessage = "No target item under cursor."
    }

    func openTargetWithDefaultApp() {
        guard let target = contextState.targetURL else {
            statusMessage = "No target item under cursor."
            return
        }

        NSWorkspace.shared.open(target)
        statusMessage = "Opened target with default app."
        hidePanel()
    }

    var cutItemCount: Int {
        fileOperationsService.cutItemCount
    }

    private func resolvedActionDirectory(preferFinderContext: Bool) -> URL? {
        if preferFinderContext,
           contextState.frontmostBundleID == "com.apple.finder",
           let dir = contextState.directoryURL {
            return dir
        }

        if let dir = contextState.directoryURL {
            return dir
        }

        if let target = contextState.targetURL {
            return contextState.targetKind == .folder ? target : target.deletingLastPathComponent()
        }

        return nil
    }

    private func nextUntitledURL(in directory: URL, type: NewFileType) -> URL {
        let fm = FileManager.default
        var index = 0

        while true {
            let name = index == 0 ? "Untitled" : "Untitled \(index)"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension(type.rawValue)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func presentSavePanelForNewFile(type: NewFileType) -> URL? {
        hidePanel()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "Untitled.\(type.rawValue)"
        panel.title = "Create New \(type.label) File"

        let response = panel.runModal()
        guard response == .OK, let selected = panel.url else { return nil }

        if selected.pathExtension.lowercased() == type.rawValue {
            return selected
        }

        return selected.appendingPathExtension(type.rawValue)
    }

    private func presentDirectoryPicker(title: String) -> URL? {
        hidePanel()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = title

        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }

    private func ensureAccessibilityForInputEvents() -> Bool {
        if accessibilityService.isTrusted(promptIfNeeded: false) {
            return true
        }

        if !hasPromptedForAccessibility {
            _ = accessibilityService.isTrusted(promptIfNeeded: true)
            accessibilityService.openSettings()
            hasPromptedForAccessibility = true
        }

        return false
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
        refreshDiagnostics()

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

    private func postPasteCommandToFrontmostApp(preferMatchStyle: Bool) {
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
            if !panel.frame.contains(mouse) {
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

    private func postCommandVKeystroke(tap: CGEventTapLocation) {
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

    private func postCommandCKeystroke(tap: CGEventTapLocation) {
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

    private func probeSelectedTextFromActiveApp() -> String? {
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

}
