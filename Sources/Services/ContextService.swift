import AppKit
import ApplicationServices

@MainActor
final class ContextService {
    private(set) var lastSelectionDiagnostics: String = "idle"

    func captureContext(
        mouseLocation: NSPoint? = nil,
        allowFinderScript: Bool = false,
        preferredApp: NSRunningApplication? = nil
    ) -> ContextState {
        let frontmost = preferredApp ?? NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier
        let appName = frontmost?.localizedName

        var state = ContextState(
            frontmostBundleID: bundleID,
            frontmostAppName: appName,
            directoryURL: nil,
            selectedFileURLs: [],
            targetURL: nil,
            targetKind: .none
        )

        if bundleID == "com.apple.finder" {
            lastSelectionDiagnostics = "finder-context (selection text detection skipped)"
            if allowFinderScript {
                let finder = captureFinderContext()
                state.directoryURL = finder.directoryURL
                state.selectedFileURLs = finder.selectedFileURLs
            }

            if let hovered = detectFileUnderCursor(mouseLocation: mouseLocation) {
                state.targetURL = hovered
                state.targetKind = classify(url: hovered)

                if isDirectory(hovered) {
                    state.directoryURL = hovered
                } else {
                    state.directoryURL = hovered.deletingLastPathComponent()
                }
            } else if let firstSelected = state.selectedFileURLs.first {
                state.targetURL = firstSelected
                state.targetKind = classify(url: firstSelected)
            }

            if state.directoryURL == nil, let target = state.targetURL {
                state.directoryURL = isDirectory(target) ? target : target.deletingLastPathComponent()
            }

            if state.directoryURL == nil {
                state.directoryURL = desktopDirectoryURL()
            }

            if state.targetKind == .none, let dir = state.directoryURL {
                state.targetURL = dir
                state.targetKind = .folder
            }
        } else {
            // Attempt to get selected text for non-Finder apps using Accessibility API
            if let selection = getSelectedTextViaAccessibility(preferredApp: frontmost) {
                state.selectedText = selection.text
                state.selectedTextSource = selection.source
                lastSelectionDiagnostics = "selected-text found | source=\(selection.source) | len=\(selection.text.count)"
            } else {
                if !lastSelectionDiagnostics.contains("selected-text") {
                    lastSelectionDiagnostics = "no selected text detected"
                }
            }
        }

        return state
    }

    private func getSelectedTextViaAccessibility(preferredApp: NSRunningApplication?) -> (text: String, source: String)? {
        guard AXIsProcessTrusted() else {
            lastSelectionDiagnostics = "AX not trusted"
            return nil
        }

        var candidates: [AXUIElement] = []
        let systemWide = AXUIElementCreateSystemWide()

        // 1) Element under mouse during right-click.
        let loc = NSEvent.mouseLocation
        var hit: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(loc.x), Float(loc.y), &hit) == .success,
           let hitElement = hit {
            candidates.append(hitElement)
        }

        // 2) Focused element from frontmost app (usually more reliable than system-wide focus).
        if let app = preferredApp ?? NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var focusedInApp: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedInApp) == .success,
               let axElement = focusedInApp,
               CFGetTypeID(axElement) == AXUIElementGetTypeID() {
                candidates.append(unsafeBitCast(axElement, to: AXUIElement.self))
            }
        }

        if candidates.isEmpty {
            lastSelectionDiagnostics = "AX candidates empty"
        } else {
            lastSelectionDiagnostics = "AX candidates=\(candidates.count)"
        }

        // 3) System-wide focused element fallback.
        var focusedSystemWide: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedSystemWide) == .success,
           let axElement = focusedSystemWide,
           CFGetTypeID(axElement) == AXUIElementGetTypeID() {
            candidates.append(unsafeBitCast(axElement, to: AXUIElement.self))
        }

        for (index, candidate) in candidates.enumerated() {
            if let selection = selectedTextFromElementOrParents(candidate) {
                let prefix = index == 0 ? "mouse" : (index == 1 ? "focused-app" : "focused-system")
                return (selection.text, "\(prefix):\(selection.source)")
            }
        }

        lastSelectionDiagnostics = "AX inspected \(candidates.count) candidates, no selected text"

        return nil
    }

    private func selectedTextFromElementOrParents(_ start: AXUIElement) -> (text: String, source: String)? {
        var current: AXUIElement? = start
        for depth in 0..<10 {
            guard let element = current else { break }

            if let selection = selectedText(on: element) {
                return (selection.text, "depth\(depth)-\(selection.source)")
            }

            current = parent(of: element)
        }
        return nil
    }

    private func selectedText(on element: AXUIElement) -> (text: String, source: String)? {
        var selectedTextRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
           let ref = selectedTextRef {
            if let text = ref as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return (text, "selected-text")
            }
            if let attr = ref as? NSAttributedString {
                let text = attr.string
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return (text, "selected-text-attributed")
                }
            }
        }

        if let ranged = selectedTextFromRanges(on: element) {
            return (ranged, "selected-ranges")
        }

        if let byValueRange = selectedTextFromValueAndRange(on: element) {
            return (byValueRange, "value+selected-range")
        }

        return nil
    }

    func replaceSelectedTextInFocusedElement(with text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedInApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedInApp) == .success,
                            let focused = focusedInApp,
                            CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return false
        }

                let focusedElement = unsafeBitCast(focused, to: AXUIElement.self)
        let setResult = AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        return setResult == .success
    }

    private func selectedTextFromRanges(on element: AXUIElement) -> String? {
        var rangesRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangesAttribute as CFString, &rangesRef) == .success,
              let ranges = rangesRef as? [AXValue],
              !ranges.isEmpty else {
            return nil
        }

        var combined: [String] = []
        for axRange in ranges {
            guard AXValueGetType(axRange) == .cfRange else { continue }
            var cfRange = CFRange(location: 0, length: 0)
            guard AXValueGetValue(axRange, .cfRange, &cfRange) else { continue }

            var stringRef: CFTypeRef?
            let result = AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXStringForRangeParameterizedAttribute as CFString,
                axRange,
                &stringRef
            )

            if result == .success,
               let raw = stringRef as? String,
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                combined.append(raw)
            } else if cfRange.length > 0 {
                // Keep scanning other ranges; some apps expose ranges but not string-for-range.
                continue
            }
        }

        guard !combined.isEmpty else { return nil }
        return combined.joined(separator: "\n")
    }

    private func selectedTextFromValueAndRange(on element: AXUIElement) -> String? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
                            let rangeRaw = rangeRef,
                            CFGetTypeID(rangeRaw) == AXValueGetTypeID() else {
                        return nil
                }

                let axRange = unsafeBitCast(rangeRaw, to: AXValue.self)
                guard AXValueGetType(axRange) == .cfRange else {
            return nil
        }

        var cfRange = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axRange, .cfRange, &cfRange), cfRange.length > 0 else {
            return nil
        }

        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
              let rawValue = valueRef else {
            return nil
        }

        let fullText: String?
        if let str = rawValue as? String {
            fullText = str
        } else if let attr = rawValue as? NSAttributedString {
            fullText = attr.string
        } else {
            fullText = nil
        }

        guard let text = fullText, !text.isEmpty else { return nil }

        let utf16 = text.utf16
        let start = max(0, cfRange.location)
        let end = min(utf16.count, start + max(0, cfRange.length))
        guard start < end else {
            return nil
        }

        let from = String.Index(utf16Offset: start, in: text)
        let to = String.Index(utf16Offset: end, in: text)

        let sliced = String(text[from..<to]).trimmingCharacters(in: .whitespacesAndNewlines)
        return sliced.isEmpty ? nil : sliced
    }

    private func captureFinderContext() -> ContextState {
        let script = #"""
        tell application "Finder"
            set targetURLString to ""
            try
                if exists Finder window 1 then
                    set targetURLString to URL of (target of front window)
                end if
            end try

            set selectedURLStrings to {}
            try
                set selectedItems to selection
                repeat with selectedItem in selectedItems
                    set end of selectedURLStrings to URL of selectedItem
                end repeat
            end try

            set AppleScript's text item delimiters to linefeed
            set selectedJoined to selectedURLStrings as string
            set AppleScript's text item delimiters to ""

            return targetURLString & linefeed & selectedJoined
        end tell
        """#

        guard let output = runAppleScript(script) else {
            return ContextState()
        }

        let lines = output.components(separatedBy: "\n")
        let targetURLString = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines)

        let rawSelection = lines.dropFirst().joined(separator: "\n")
        let selectedParts = rawSelection
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let selectedURLs = selectedParts
            .compactMap { URL(string: $0) }
            .map { sanitizeContextURL($0) }
            .compactMap { $0 }

        let directoryURL: URL?
        if targetURLString?.isEmpty == false, let parsed = URL(string: targetURLString!) {
            directoryURL = sanitizeContextURL(parsed) ?? desktopDirectoryURL()
        } else {
            directoryURL = desktopDirectoryURL()
        }

        return ContextState(directoryURL: directoryURL, selectedFileURLs: selectedURLs)
    }

    private func desktopDirectoryURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func detectFileUnderCursor(mouseLocation: NSPoint?) -> URL? {
        let point = mouseLocation ?? NSEvent.mouseLocation
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        let result = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        guard result == .success, let start = hit else { return nil }

        var current: AXUIElement? = start
        for _ in 0..<18 {
            guard let element = current else { break }

            if let rawURL = attributeURL("AXURL", on: element) ??
                attributeURL("AXDocument", on: element) ??
                attributeURL("AXFilename", on: element) ??
                attributeURL("AXPath", on: element) {
                return sanitizeContextURL(rawURL)
            }

            current = parent(of: element)
        }

        return nil
    }

    private func classify(url: URL) -> ContextTargetKind {
        if isDirectory(url) {
            return .folder
        }

        let ext = url.pathExtension.lowercased()
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp", "svg"]
        let textExts: Set<String> = ["txt", "md", "rtf", "json", "xml", "yaml", "yml", "csv", "log", "swift", "js", "ts", "py", "java"]

        if imageExts.contains(ext) { return .image }
        if textExts.contains(ext) { return .text }
        return .file
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private func attributeURL(_ attribute: String, on element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else { return nil }

        if let nsURL = value as? URL {
            return nsURL.isFileURL ? nsURL : nil
        }

        if let string = value as? String {
            if string.hasPrefix("file://") {
                return URL(string: string)
            }
            if string.hasPrefix("/") {
                return URL(fileURLWithPath: string)
            }
        }

        return nil
    }

    private func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func sanitizeContextURL(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }

        let path = url.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let allowedPrefixes = [home, "/Volumes", "/Applications", "/Users/Shared"]
        if path.hasPrefix("/var/protected") || path.hasPrefix("/System/Volumes/Preboot") {
            return nil
        }

        if allowedPrefixes.contains(where: { path.hasPrefix($0) }) {
            return url
        }

        return nil
    }

    private func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil {
            return nil
        }
        return result.stringValue
    }
}
