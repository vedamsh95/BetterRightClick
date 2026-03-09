import AppKit
import ApplicationServices

// MARK: - Undo Snap State
private var lastSnappedWindow: AXUIElement?
private var lastSnappedWindowFrame: CGRect?

struct WindowSnapService {
    struct DisplayTarget: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
        let visibleFrame: NSRect
    }

    enum SnapError: LocalizedError {
        case accessibilityDenied
        case noDisplays
        case noWindowDetected(String)
        case invalidGrid
        case failedToSetPosition
        case failedToSetSize

        var errorDescription: String? {
            switch self {
            case .accessibilityDenied:
                return "Accessibility permission is required to move other app windows."
            case .noDisplays:
                return "No displays were detected."
            case .noWindowDetected(let reason):
                return "Could not detect a target window under cursor. Trace: \(reason)"
            case .invalidGrid:
                return "Invalid grid selection."
            case .failedToSetPosition:
                return "Failed to set window position via Accessibility."
            case .failedToSetSize:
                return "Failed to set window size via Accessibility."
            }
        }
    }

    func availableDisplays() -> [DisplayTarget] {
        NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }

            let id = CGDirectDisplayID(number.uint32Value)
            let fallbackName = "Display \(number.intValue)"
            let name = (screen.localizedName.isEmpty ? fallbackName : screen.localizedName)
            return DisplayTarget(id: id, name: name, visibleFrame: screen.visibleFrame)
        }
    }

    // MARK: - 3. The Shrink-Move-Expand Maneuver
    func snapWindowUnderCursor(
        columns: Int,
        rows: Int,
        column: Int,
        rowFromTop: Int,
        preferredDisplayID: CGDirectDisplayID?,
        probeLocation: NSPoint?,
        preferredAppPID: pid_t?
    ) throws -> DisplayTarget {
        guard AXIsProcessTrusted() else { throw SnapError.accessibilityDenied }
        guard columns > 0, rows > 0, column >= 0, rowFromTop >= 0, column < columns, rowFromTop < rows else { throw SnapError.invalidGrid }

        let displays = availableDisplays()
        guard !displays.isEmpty else { throw SnapError.noDisplays }

        let targetDisplay = resolveTargetDisplay(displays: displays, preferredDisplayID: preferredDisplayID, probeLocation: probeLocation)
        let targetRect = rectForGrid(visibleFrame: targetDisplay.visibleFrame, columns: columns, rows: rows, column: column, rowFromTop: rowFromTop)

        let (windowResult, traceLog) = targetWindowElement(probeLocation: probeLocation, preferredAppPID: preferredAppPID)
        guard let window = windowResult else {
            throw SnapError.noWindowDetected(traceLog)
        }

        // Store previous frame for undo
        lastSnappedWindow = window
        lastSnappedWindowFrame = frame(of: window)

        let axPosition = toAXTopLeft(for: targetRect)
        var targetPoint = axPosition
        var targetSize = targetRect.size
        // 1. Safe Size: Shrink the window temporarily so it doesn't collide with screen boundaries during the move
        var safeSize = CGSize(width: 100, height: 100)
        if let safeSizeValue = AXValueCreate(.cgSize, &safeSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, safeSizeValue)
        }
        // 2. Move to new coordinate
        guard let pointValue = AXValueCreate(.cgPoint, &targetPoint),
              AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue) == .success else {
            throw SnapError.failedToSetPosition
        }
        // 3. Expand to final target size
        guard let sizeValue = AXValueCreate(.cgSize, &targetSize),
              AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success else {
            throw SnapError.failedToSetSize
        }
        return targetDisplay
    }

    // MARK: - Undo Snap
    func undoLastSnap() -> Bool {
        guard let window = lastSnappedWindow, let frame = lastSnappedWindowFrame else { return false }
        var pos = frame.origin
        var size = frame.size
        guard let posValue = AXValueCreate(.cgPoint, &pos),
              let sizeValue = AXValueCreate(.cgSize, &size) else { return false }
        let posResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return posResult == .success && sizeResult == .success
    }

    private func resolveTargetDisplay(
        displays: [DisplayTarget],
        preferredDisplayID: CGDirectDisplayID?,
        probeLocation: NSPoint?
    ) -> DisplayTarget {
        if let preferredDisplayID,
           let selected = displays.first(where: { $0.id == preferredDisplayID }) {
            return selected
        }

        let mouse = probeLocation ?? NSEvent.mouseLocation
        if let hovered = displays.first(where: { NSMouseInRect(mouse, $0.visibleFrame, false) }) {
            return hovered
        }

        return displays[0]
    }

    private func rectForGrid(
        visibleFrame: NSRect,
        columns: Int,
        rows: Int,
        column: Int,
        rowFromTop: Int
    ) -> NSRect {
        let cellWidth = visibleFrame.width / CGFloat(columns)
        let cellHeight = visibleFrame.height / CGFloat(rows)

        // UI grid indexes from top-left; AppKit frame math indexes rows from bottom.
        let rowFromBottom = (rows - 1) - rowFromTop

        let x = visibleFrame.minX + CGFloat(column) * cellWidth
        let y = visibleFrame.minY + CGFloat(rowFromBottom) * cellHeight

        return NSRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: y.rounded(.toNearestOrAwayFromZero),
            width: cellWidth.rounded(.toNearestOrAwayFromZero),
            height: cellHeight.rounded(.toNearestOrAwayFromZero)
        )
    }

    // MARK: - 1. Coordinate Math Fixes
    private func toAXTopLeft(for rect: NSRect) -> CGPoint {
        // CoreGraphics (AX) Y = Primary Screen Height - AppKit Rect Max Y
        guard let primaryScreen = NSScreen.screens.first else { return CGPoint(x: rect.minX, y: rect.minY) }
        return CGPoint(x: rect.minX, y: primaryScreen.frame.maxY - rect.maxY)
    }

    private func toAXPoint(_ point: NSPoint) -> CGPoint {
        guard let primaryScreen = NSScreen.screens.first else { return point }
        return CGPoint(x: point.x, y: primaryScreen.frame.maxY - point.y)
    }

    private func targetWindowElement(probeLocation: NSPoint?, preferredAppPID: pid_t?) -> (AXUIElement?, String) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let systemWide = AXUIElementCreateSystemWide()

        let nsMouse = probeLocation ?? NSEvent.mouseLocation
        let axMouse = toAXPoint(nsMouse)
        
        var t = "pt=\(nsMouse)|"

        var hitElement: AXUIElement?
        if AXUIElementCopyElementAtPosition(systemWide, Float(axMouse.x), Float(axMouse.y), &hitElement) == .success,
           let hitElement {
           
           if let window = windowElement(startingAt: hitElement) {
               if pid(of: window) != ownPID {
                   return (window, t + "AX=Hit")
               } else {
                   t += "AX=Self|"
               }
           } else {
               t += "AX=NoWinDepth|"
           }
        } else {
           t += "AX=Fail|"
        }

        if let ownerPID = windowOwnerPID(at: nsMouse, excluding: ownPID) {
            t += "ownPID=\(ownerPID)|"
            let (w, r) = windowElement(forApplicationPID: ownerPID, excluding: ownPID, near: nsMouse)
            t += r
            if let window = w { return (window, t) }
        } else {
            t += "ownPID=nil|"
        }

        if let preferredAppPID {
            t += "prefPID=\(preferredAppPID)|"
            let (w, r) = windowElement(forApplicationPID: preferredAppPID, excluding: ownPID, near: nsMouse)
            t += r
            if let window = w { return (window, t) }
        }

        if let app = NSWorkspace.shared.frontmostApplication {
            t += "frontPID=\(app.processIdentifier)|"
            let (w, r) = windowElement(forApplicationPID: app.processIdentifier, excluding: ownPID, near: nsMouse)
            t += r
            if let window = w { return (window, t) }
        }

        return (nil, t)
    }

    private func windowOwnerPID(at point: NSPoint, excluding excludedPID: pid_t) -> pid_t? {
        let axPoint = toAXPoint(point)
        guard let rawInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in rawInfo {
            guard let ownerNumber = info[kCGWindowOwnerPID as String] as? NSNumber else {
                continue
            }

            let ownerPID = pid_t(ownerNumber.int32Value)
            if ownerPID == excludedPID {
                continue
            }

            if let layerNumber = info[kCGWindowLayer as String] as? NSNumber,
               layerNumber.intValue != 0 {
                continue
            }

            guard let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds),
                  bounds.contains(axPoint) else {
                continue
            }

            return ownerPID
        }

        return nil
    }

    private func windowElement(forApplicationPID appPID: pid_t, excluding excludedPID: pid_t, near point: NSPoint?, fallbackActivation: Bool = true) -> (AXUIElement?, String) {
        let appElement = AXUIElementCreateApplication(appPID)
        var t = "appE|"

        if let point {
            let (w, r) = windowContaining(point: toAXPoint(point), in: appElement, excluding: excludedPID)
            t += r
            if let containingWindow = w {
                return (containingWindow, t)
            }
        }

        if let focusedWindow = attributeElement(appElement, attribute: kAXFocusedWindowAttribute as CFString),
           pid(of: focusedWindow) != excludedPID {
            return (focusedWindow, t + "foc")
        }
        t += "nofoc|"

        if let mainWindow = attributeElement(appElement, attribute: kAXMainWindowAttribute as CFString),
           pid(of: mainWindow) != excludedPID {
            return (mainWindow, t + "main")
        }
        t += "nomain|"

        if let firstWindow = firstWindow(of: appElement), pid(of: firstWindow) != excludedPID {
            return (firstWindow, t + "first")
        }
        t += "nofirst|"

        // MARK: Xcode / Secure Input Fallback
        // If all queries failed, but we definitively know the PID from CGWindowList, 
        // macOS Accessibility might be blocking enumeration until the app is active.
        if fallbackActivation, let app = NSRunningApplication(processIdentifier: appPID) {
            t += "activating|"
            // Force the app active
            app.activate(options: .activateIgnoringOtherApps)
            
            // Allow macOS to process the activation
            Thread.sleep(forTimeInterval: 0.1)
            
            // Query focused window again after activation
            if let activeFocused = attributeElement(appElement, attribute: kAXFocusedWindowAttribute as CFString),
               pid(of: activeFocused) != excludedPID {
                return (activeFocused, t + "activated_foc")
            }
            t += "activated_nofoc|"
            
            if let activeMain = attributeElement(appElement, attribute: kAXMainWindowAttribute as CFString),
               pid(of: activeMain) != excludedPID {
                return (activeMain, t + "activated_main")
            }
            t += "activated_nomain|"
        }

        return (nil, t)
    }

    private func windowContaining(point: CGPoint, in appElement: AXUIElement, excluding excludedPID: pid_t) -> (AXUIElement?, String) {
        let wins = windows(of: appElement)
        var t = "wins=\(wins.count)|"
        for window in wins where pid(of: window) != excludedPID {
            guard let frame = frame(of: window) else {
                t += "nofrm|"
                continue
            }
            if frame.contains(point) {
                return (window, t + "match")
            } else {
                t += "miss(\(Int(frame.minX)),\(Int(frame.minY)))|"
            }
        }

        return (nil, t)
    }

    private func windows(of appElement: AXUIElement) -> [AXUIElement] {
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        
        var rawRef: CFTypeRef? = windowsRef
        
        // Fallback for Electron apps that don't support kAXWindowsAttribute
        if result != .success || rawRef == nil {
            var childrenRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &childrenRef) == .success {
                rawRef = childrenRef
            } else {
                return []
            }
        }

        if let elements = rawRef as? [AXUIElement] {
            return elements.filter { 
                attributeString($0, attribute: kAXRoleAttribute as CFString) == kAXWindowRole as String 
            }
        }

        let array = rawRef as! CFArray
        let count = CFArrayGetCount(array)
        guard count > 0 else { return [] }

        var windows: [AXUIElement] = []
        for index in 0..<count {
            let item = CFArrayGetValueAtIndex(array, index)
            let element = unsafeBitCast(item, to: AXUIElement.self)
            if attributeString(element, attribute: kAXRoleAttribute as CFString) == kAXWindowRole as String {
                windows.append(element)
            }
        }
        return windows
    }

    private func firstWindow(of appElement: AXUIElement) -> AXUIElement? {
        var mainWindow: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &mainWindow) == .success,
           let raw = mainWindow,
           CFGetTypeID(raw) == AXUIElementGetTypeID() {
            return unsafeBitCast(raw, to: AXUIElement.self)
        }

        return windows(of: appElement).first
    }

    // MARK: - 2. Electron App Depth Fix
    private func windowElement(startingAt element: AXUIElement) -> AXUIElement? {
        var current: AXUIElement? = element
        // Increased to accommodate extremely deep Electron/React Native DOMs (VS Code, Slack, Figma)
        for _ in 0..<100 {
            guard let element = current else { break }

            if let role = attributeString(element, attribute: kAXRoleAttribute as CFString),
               role == kAXWindowRole as String {
                return element
            }

            if let directWindow = attributeElement(element, attribute: kAXWindowAttribute as CFString) {
                return directWindow
            }

            current = attributeElement(element, attribute: kAXParentAttribute as CFString)
        }
        return nil
    }

    private func attributeString(_ element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func attributeElement(_ element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let raw = value,
              CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            return nil
        }

        return unsafeBitCast(raw, to: AXUIElement.self)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = attributePoint(element, attribute: kAXPositionAttribute as CFString),
              let size = attributeSize(element, attribute: kAXSizeAttribute as CFString) else {
            return nil
        }

        return CGRect(origin: origin, size: size)
    }

    private func attributePoint(_ element: AXUIElement, attribute: CFString) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(unsafeBitCast(axValue, to: AXValue.self), .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func attributeSize(_ element: AXUIElement, attribute: CFString) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(axValue, to: AXValue.self), .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }
}