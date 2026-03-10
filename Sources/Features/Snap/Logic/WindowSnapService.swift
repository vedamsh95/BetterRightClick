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

    enum SidekickDirection {
        case left
        case right
    }
    
    enum MultiSnapLayout {
        case columns
        case grid2x2
        case dualMonitor2x2
        case mainPlusStack
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

        lastSnappedWindow = window
        lastSnappedWindowFrame = frame(of: window)

        executePhysically(window: window, targetRect: targetRect)

        return targetDisplay
    }

    func snapWindowCustomSpanUnderCursor(
        columns: Int,
        rows: Int,
        startColumn: Int,
        columnCount: Int,
        preferredDisplayID: CGDirectDisplayID?,
        probeLocation: NSPoint?,
        preferredAppPID: pid_t?
    ) throws -> DisplayTarget {
        guard AXIsProcessTrusted() else { throw SnapError.accessibilityDenied }
        guard columns > 0, rows > 0, startColumn >= 0, columnCount > 0, startColumn + columnCount <= columns else { throw SnapError.invalidGrid }

        let displays = availableDisplays()
        guard !displays.isEmpty else { throw SnapError.noDisplays }

        let targetDisplay = resolveTargetDisplay(displays: displays, preferredDisplayID: preferredDisplayID, probeLocation: probeLocation)
        
        // Calculate a bounding box that spans from startColumn across columnCount
        let cellWidth = targetDisplay.visibleFrame.width / CGFloat(columns)
        let totalWidth = cellWidth * CGFloat(columnCount)
        let x = targetDisplay.visibleFrame.minX + CGFloat(startColumn) * cellWidth
        
        let targetRect = NSRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: targetDisplay.visibleFrame.minY,
            width: totalWidth.rounded(.toNearestOrAwayFromZero),
            height: targetDisplay.visibleFrame.height
        )

        let (windowResult, traceLog) = targetWindowElement(probeLocation: probeLocation, preferredAppPID: preferredAppPID)
        guard let window = windowResult else {
            throw SnapError.noWindowDetected(traceLog)
        }

        // Store previous frame for undo
        lastSnappedWindow = window
        lastSnappedWindowFrame = frame(of: window)

        executePhysically(window: window, targetRect: targetRect)
        return targetDisplay
    }

    private func executePhysically(window: AXUIElement, targetRect: NSRect) {
        let axPosition = toAXTopLeft(for: targetRect)
        var targetPoint = axPosition
        var targetSize = targetRect.size
        
        // 1. Safe Size: Shrink the window temporarily so it doesn't collide with screen boundaries during the move
        var safeSize = CGSize(width: 100, height: 100)
        if let safeSizeValue = AXValueCreate(.cgSize, &safeSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, safeSizeValue)
        }
        // 2. Move to new coordinate
        if let pointValue = AXValueCreate(.cgPoint, &targetPoint) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        }
        // 3. Expand to final target size
        if let sizeValue = AXValueCreate(.cgSize, &targetSize) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    func snapSidekick(
        direction: SidekickDirection,
        preferredDisplayID: CGDirectDisplayID?,
        probeLocation: NSPoint?,
        preferredAppPID: pid_t?
    ) throws -> DisplayTarget {
        guard AXIsProcessTrusted() else { throw SnapError.accessibilityDenied }

        let displays = availableDisplays()
        guard !displays.isEmpty else { throw SnapError.noDisplays }

        let targetDisplay = resolveTargetDisplay(displays: displays, preferredDisplayID: preferredDisplayID, probeLocation: probeLocation)
        let f = targetDisplay.visibleFrame
        
        // 1. Calculate Sidekick Geometry (30%)
        let sidekickWidth = (f.width * 0.3).rounded(.toNearestOrAwayFromZero)
        let mainWidth = f.width - sidekickWidth
        
        let sidekickRect = NSRect(
            x: direction == .left ? f.minX : f.maxX - sidekickWidth,
            y: f.minY,
            width: sidekickWidth,
            height: f.height
        )
        
        let mainRect = NSRect(
            x: direction == .left ? f.minX + sidekickWidth : f.minX,
            y: f.minY,
            width: mainWidth,
            height: f.height
        )

        // 2. Identify and Snap the Primary Target (Sidekick)
        let (windowResult, traceLog) = targetWindowElement(probeLocation: probeLocation, preferredAppPID: preferredAppPID)
        guard let sidekickWindow = windowResult else {
            throw SnapError.noWindowDetected(traceLog)
        }

        lastSnappedWindow = sidekickWindow
        lastSnappedWindowFrame = frame(of: sidekickWindow)
        executePhysically(window: sidekickWindow, targetRect: sidekickRect)

        // 3. Identify the Secondary Target (Main Window) using CGWindowList Z-Order
        // We look for the first window directly beneath our sidekick belonging to a standard application.
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let sidekickPID = pid(of: sidekickWindow)
        
        guard let rawInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return targetDisplay // Return cleanly if we can't find a secondary
        }

        var secondaryPID: pid_t? = nil
        var secondaryPoint: NSPoint? = nil
        
        for info in rawInfo {
            guard let layer = info[kCGWindowLayer as String] as? NSNumber, layer.intValue == 0,
                  let ownerPID = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            
            let pid = ownerPID.int32Value
            if pid == ownPID || pid == sidekickPID { continue }
            
            // Validate it's a real user app with a dock icon
            guard let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular else { continue }
            
            // Get center point of this background window for probe detection
            guard let boundsDict = info[kCGWindowBounds as String] as? NSDictionary else { continue }
            var bounds = CGRect.zero
            if CGRectMakeWithDictionaryRepresentation(boundsDict, &bounds) {
                secondaryPID = pid
                // Convert CG bounds center back into AppKit for standard AX probing
                secondaryPoint = NSPoint(x: bounds.midX, y: targetDisplay.visibleFrame.maxY - bounds.midY)
                break
            }
        }
        
        // 4. Snap the Secondary Process
        if let secondaryPID, let (mainWindow, _) = windowElement(forApplicationPID: secondaryPID, excluding: ownPID, near: secondaryPoint, fallbackActivation: true) as? (AXUIElement, String) {
            executePhysically(window: mainWindow, targetRect: mainRect)
        }

        return targetDisplay
    }

    func snapMultipleApps(
        apps: [NSRunningApplication],
        preferredDisplayID: CGDirectDisplayID?,
        probeLocation: NSPoint?,
        layoutMode: MultiSnapLayout = .columns
    ) throws -> DisplayTarget {
        guard AXIsProcessTrusted() else { throw SnapError.accessibilityDenied }
        guard !apps.isEmpty else { throw SnapError.invalidGrid }

        let displays = availableDisplays()
        guard !displays.isEmpty else { throw SnapError.noDisplays }

        let targetDisplay = resolveTargetDisplay(displays: displays, preferredDisplayID: preferredDisplayID, probeLocation: probeLocation)
        let f = targetDisplay.visibleFrame
        let ownPID = ProcessInfo.processInfo.processIdentifier
        
        // Determine effective layout — auto-fallback to 2x2 if columns would be < 400px
        var effectiveLayout = layoutMode
        if effectiveLayout == .columns && apps.count >= 3 {
            let candidateWidth = f.width / CGFloat(apps.count)
            if candidateWidth < 400 && apps.count == 4 {
                effectiveLayout = .grid2x2
            }
        }
        
        switch effectiveLayout {
        case .columns:
            let rects = calculateEvenHorizontalFrames(bounds: f, count: apps.count)
            for (index, app) in apps.enumerated() {
                let pid = app.processIdentifier
                if pid == ownPID { continue }
                executeSnapCommand(pid: pid, ownPID: ownPID, index: index, targetRect: rects[index])
            }
            
        case .grid2x2:
            guard apps.count == 4 else { throw SnapError.invalidGrid }
            let rects = calculate2x2Frames(bounds: f)
            for (index, app) in apps.enumerated() {
                let pid = app.processIdentifier
                if pid == ownPID { continue }
                executeSnapCommand(pid: pid, ownPID: ownPID, index: index, targetRect: rects[index])
            }
            
        case .dualMonitor2x2:
            let allDisplays = availableDisplays()
            guard apps.count == 4, allDisplays.count >= 2 else {
                // Fall back to single-screen 2x2
                guard apps.count == 4 else { throw SnapError.invalidGrid }
                let rects = calculate2x2Frames(bounds: f)
                for (index, app) in apps.enumerated() {
                    let pid = app.processIdentifier
                    if pid == ownPID { continue }
                    executeSnapCommand(pid: pid, ownPID: ownPID, index: index, targetRect: rects[index])
                }
                break
            }
            // 2 apps per monitor, strictly within each monitor's visibleFrame
            let f1 = allDisplays[0].visibleFrame
            let f2 = allDisplays[1].visibleFrame
            let rects1 = calculateEvenHorizontalFrames(bounds: f1, count: 2)
            let rects2 = calculateEvenHorizontalFrames(bounds: f2, count: 2)
            let dualRects = rects1 + rects2
            for (index, app) in apps.enumerated() {
                let pid = app.processIdentifier
                if pid == ownPID { continue }
                executeSnapCommand(pid: pid, ownPID: ownPID, index: index, targetRect: dualRects[index])
            }
            
        case .mainPlusStack:
            guard apps.count >= 2 else { throw SnapError.invalidGrid }
            let rects = calculateMainPlusStackFrames(bounds: f, count: apps.count)
            for (index, app) in apps.enumerated() {
                let pid = app.processIdentifier
                if pid == ownPID { continue }
                executeSnapCommand(pid: pid, ownPID: ownPID, index: index, targetRect: rects[index])
            }
        }

        return targetDisplay
    }
    
    // MARK: - Flawless Grid Math (edge-clamped, no sub-pixel gaps)
    
    private func calculateEvenHorizontalFrames(bounds: NSRect, count: Int) -> [NSRect] {
        guard count > 0 else { return [] }
        let cellWidth = (bounds.width / CGFloat(count)).rounded(.toNearestOrAwayFromZero)
        var rects: [NSRect] = []
        for i in 0..<count {
            let x = bounds.minX + CGFloat(i) * cellWidth
            // Last cell clamps to maxX to eliminate sub-pixel gaps
            let w = (i == count - 1) ? (bounds.maxX - x) : cellWidth
            rects.append(NSRect(x: x.rounded(.toNearestOrAwayFromZero), y: bounds.minY, width: w.rounded(.toNearestOrAwayFromZero), height: bounds.height))
        }
        return rects
    }
    
    private func calculate2x2Frames(bounds: NSRect) -> [NSRect] {
        let halfW = (bounds.width / 2.0).rounded(.toNearestOrAwayFromZero)
        let halfH = (bounds.height / 2.0).rounded(.toNearestOrAwayFromZero)
        let rightW = bounds.maxX - (bounds.minX + halfW)
        let bottomH = bounds.maxY - (bounds.minY + halfH)
        return [
            NSRect(x: bounds.minX, y: bounds.minY, width: halfW, height: halfH),
            NSRect(x: bounds.minX + halfW, y: bounds.minY, width: rightW, height: halfH),
            NSRect(x: bounds.minX, y: bounds.minY + halfH, width: halfW, height: bottomH),
            NSRect(x: bounds.minX + halfW, y: bounds.minY + halfH, width: rightW, height: bottomH)
        ]
    }
    
    private func calculateMainPlusStackFrames(bounds: NSRect, count: Int) -> [NSRect] {
        let mainWidth = (bounds.width * 0.7).rounded(.toNearestOrAwayFromZero)
        let stackWidth = bounds.maxX - (bounds.minX + mainWidth)
        let stackCount = count - 1
        let stackCellH = (bounds.height / CGFloat(stackCount)).rounded(.toNearestOrAwayFromZero)
        
        var rects: [NSRect] = []
        // Main panel (70% left)
        rects.append(NSRect(x: bounds.minX, y: bounds.minY, width: mainWidth, height: bounds.height))
        // Stack (30% right, vertical slices)
        for i in 0..<stackCount {
            let y = bounds.minY + CGFloat(i) * stackCellH
            let h = (i == stackCount - 1) ? (bounds.maxY - y) : stackCellH
            rects.append(NSRect(x: bounds.minX + mainWidth, y: y, width: stackWidth, height: h.rounded(.toNearestOrAwayFromZero)))
        }
        return rects
    }

    private func executeSnapCommand(pid: pid_t, ownPID: pid_t, index: Int, targetRect: NSRect) {
        if let (window, _) = windowElement(forApplicationPID: pid, excluding: ownPID, near: nil, fallbackActivation: true) as? (AXUIElement, String) {
            if index == 0 {
                lastSnappedWindow = window
                lastSnappedWindowFrame = frame(of: window)
            }
            executePhysically(window: window, targetRect: targetRect)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }

    func distributeAppsToGridCell(
        apps: [NSRunningApplication],
        columns: Int,
        rows: Int,
        column: Int,
        rowFromTop: Int,
        preferredDisplayID: CGDirectDisplayID?,
        probeLocation: NSPoint?
    ) throws -> DisplayTarget {
        guard AXIsProcessTrusted() else { throw SnapError.accessibilityDenied }
        guard !apps.isEmpty else { throw SnapError.invalidGrid }
        guard columns > 0, rows > 0, column >= 0, rowFromTop >= 0, column < columns, rowFromTop < rows else { throw SnapError.invalidGrid }

        let displays = availableDisplays()
        guard !displays.isEmpty else { throw SnapError.noDisplays }

        let targetDisplay = resolveTargetDisplay(displays: displays, preferredDisplayID: preferredDisplayID, probeLocation: probeLocation)
        let boundingBox = rectForGrid(visibleFrame: targetDisplay.visibleFrame, columns: columns, rows: rows, column: column, rowFromTop: rowFromTop)
        
        // 2. Divide this specific bounding box among the apps
        let appCount = apps.count
        let cellWidth = boundingBox.width / CGFloat(appCount)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        
        for (index, app) in apps.enumerated() {
            let pid = app.processIdentifier
            if pid == ownPID { continue }
            
            let rectX = boundingBox.minX + (CGFloat(index) * cellWidth)
            let subRect = NSRect(
                x: rectX.rounded(.toNearestOrAwayFromZero),
                y: boundingBox.minY,
                width: cellWidth.rounded(.toNearestOrAwayFromZero),
                height: boundingBox.height
            )
            
            executeSnapCommand(pid: pid, ownPID: ownPID, index: index, targetRect: subRect)
        }
        
        return targetDisplay
    }

    func distributeAppsToCustomSpan(
        apps: [NSRunningApplication],
        columns: Int,
        rows: Int,
        startColumn: Int,
        columnCount: Int,
        preferredDisplayID: CGDirectDisplayID?,
        probeLocation: NSPoint?
    ) throws -> DisplayTarget {
        guard AXIsProcessTrusted() else { throw SnapError.accessibilityDenied }
        guard !apps.isEmpty else { throw SnapError.invalidGrid }
        guard columns > 0, rows > 0, startColumn >= 0, columnCount > 0, startColumn + columnCount <= columns else { throw SnapError.invalidGrid }

        let displays = availableDisplays()
        guard !displays.isEmpty else { throw SnapError.noDisplays }

        let targetDisplay = resolveTargetDisplay(displays: displays, preferredDisplayID: preferredDisplayID, probeLocation: probeLocation)
        
        let displayCellWidth = targetDisplay.visibleFrame.width / CGFloat(columns)
        let totalWidth = displayCellWidth * CGFloat(columnCount)
        let x = targetDisplay.visibleFrame.minX + CGFloat(startColumn) * displayCellWidth
        
        let boundingBox = NSRect(
            x: x.rounded(.toNearestOrAwayFromZero),
            y: targetDisplay.visibleFrame.minY,
            width: totalWidth.rounded(.toNearestOrAwayFromZero),
            height: targetDisplay.visibleFrame.height
        )
        
        let appCount = apps.count
        let subCellWidth = boundingBox.width / CGFloat(appCount)
        let ownPID = ProcessInfo.processInfo.processIdentifier
        
        for (index, app) in apps.enumerated() {
            let pid = app.processIdentifier
            if pid == ownPID { continue }
            
            let rectX = boundingBox.minX + (CGFloat(index) * subCellWidth)
            let subRect = NSRect(
                x: rectX.rounded(.toNearestOrAwayFromZero),
                y: boundingBox.minY,
                width: subCellWidth.rounded(.toNearestOrAwayFromZero),
                height: boundingBox.height
            )
            
            executeSnapCommand(pid: pid, ownPID: ownPID, index: index, targetRect: subRect)
        }
        
        return targetDisplay
    }

    func swapApps(pidA: pid_t, pidB: pid_t) throws {
        guard AXIsProcessTrusted() else { throw SnapError.accessibilityDenied }
        
        let ownPID = ProcessInfo.processInfo.processIdentifier

        // 1. Fetch Windows using Fallback Activation
        guard let (windowA, _) = windowElement(forApplicationPID: pidA, excluding: ownPID, near: nil, fallbackActivation: true) as? (AXUIElement, String) else {
            throw SnapError.noWindowDetected("Failed to capture App A")
        }
        guard let (windowB, _) = windowElement(forApplicationPID: pidB, excluding: ownPID, near: nil, fallbackActivation: true) as? (AXUIElement, String) else {
            throw SnapError.noWindowDetected("Failed to capture App B")
        }
        
        // 2. Read existing bounds accurately via AppKit math wrapper
        guard let frameA = frame(of: windowA), let frameB = frame(of: windowB) else {
            throw SnapError.failedToSetSize // generic error fallback
        }
        
        // Ensure accurate AppKit -> AX coordinate conversion for the target frames
        // BUT wait, `executePhysically` expects an AppKit NSRect. `frame(of:)` returns AppKit NSRect!
        // We can just swap the AppKit rects directly!
        let targetRectForA = frameB
        let targetRectForB = frameA
        
        // 3. Track state
        lastSnappedWindow = windowA
        lastSnappedWindowFrame = frameA

        // 4. Execute physical move sequence on both
        executePhysically(window: windowA, targetRect: targetRectForA)
        executePhysically(window: windowB, targetRect: targetRectForB)
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