import SwiftUI
import AppKit

@MainActor
class SnapManager: ObservableObject {
    private let windowManager: MenuWindowManager
    private let snapService: WindowSnapService
    
    init(windowManager: MenuWindowManager, snapService: WindowSnapService) {
        self.windowManager = windowManager
        self.snapService = snapService
    }
    
    func undoSnap() {
        let ok = snapService.undoLastSnap()
        windowManager.statusMessage = ok ? "Restored previous window frame." : "Nothing to undo."
    }
    
    func refreshSnapDisplays() {
        windowManager.snapDisplays = snapService.availableDisplays()
    }
    
    func snapWindowToGrid(columns: Int, rows: Int, column: Int, rowFromTop: Int, preferredDisplayID: CGDirectDisplayID?) {
        let probePoint = windowManager.lastRightClickLocation ?? NSEvent.mouseLocation
        let preferredPID = windowManager.lastFrontmostApp?.processIdentifier
        
        do {
            _ = try snapService.snapWindowUnderCursor(
                columns: columns,
                rows: rows,
                column: column,
                rowFromTop: rowFromTop,
                preferredDisplayID: preferredDisplayID,
                probeLocation: probePoint,
                preferredAppPID: preferredPID
            )
            windowManager.statusMessage = "Snapped to grid."
            windowManager.hidePanel()
        } catch {
            windowManager.statusMessage = error.localizedDescription
        }
    }
    
    func snapWindowCustomSpan(columns: Int, rows: Int, startColumn: Int, columnCount: Int, preferredDisplayID: CGDirectDisplayID?) {
        let probePoint = windowManager.lastRightClickLocation ?? NSEvent.mouseLocation
        let preferredPID = windowManager.lastFrontmostApp?.processIdentifier
        
        do {
            _ = try snapService.snapWindowCustomSpanUnderCursor(
                columns: columns,
                rows: rows,
                startColumn: startColumn,
                columnCount: columnCount,
                preferredDisplayID: preferredDisplayID,
                probeLocation: probePoint,
                preferredAppPID: preferredPID
            )
            windowManager.statusMessage = "Snapped custom span."
            windowManager.hidePanel()
        } catch {
            windowManager.statusMessage = error.localizedDescription
        }
    }
    
    func snapSidekick(direction: WindowSnapService.SidekickDirection, preferredDisplayID: CGDirectDisplayID?) {
        let probePoint = windowManager.lastRightClickLocation ?? NSEvent.mouseLocation
        let preferredPID = windowManager.lastFrontmostApp?.processIdentifier
        
        do {
            _ = try snapService.snapSidekick(
                direction: direction,
                preferredDisplayID: preferredDisplayID,
                probeLocation: probePoint,
                preferredAppPID: preferredPID
            )
            windowManager.statusMessage = "Deployed Sidekick."
            windowManager.hidePanel()
        } catch {
            windowManager.statusMessage = error.localizedDescription
        }
    }
    
    func snapEvenGrid(apps: [NSRunningApplication], preferredDisplayID: CGDirectDisplayID?) {
        let probePoint = windowManager.lastRightClickLocation ?? NSEvent.mouseLocation
        let layout: WindowSnapService.MultiSnapLayout = apps.count == 4 ? .grid2x2 : .columns
        
        do {
            _ = try snapService.snapMultipleApps(
                apps: apps,
                preferredDisplayID: preferredDisplayID,
                probeLocation: probePoint,
                layoutMode: layout
            )
            windowManager.statusMessage = "Tiled apps."
            windowManager.hidePanel()
        } catch {
            windowManager.statusMessage = error.localizedDescription
        }
    }
    
    func snapMainPlusStack(apps: [NSRunningApplication], preferredDisplayID: CGDirectDisplayID?) {
        let probePoint = windowManager.lastRightClickLocation ?? NSEvent.mouseLocation
        
        do {
            _ = try snapService.snapMultipleApps(
                apps: apps,
                preferredDisplayID: preferredDisplayID,
                probeLocation: probePoint,
                layoutMode: .mainPlusStack
            )
            windowManager.statusMessage = "Snapped Main + Stack."
            windowManager.hidePanel()
        } catch {
            windowManager.statusMessage = error.localizedDescription
        }
    }
    
    func distributeToScreens(apps: [NSRunningApplication]) {
        let probePoint = windowManager.lastRightClickLocation ?? NSEvent.mouseLocation
        let displays = snapService.availableDisplays()
        guard !displays.isEmpty else { return }
        
        let screensToUse = min(displays.count, apps.count)
        let appsPerScreen = apps.count / screensToUse
        let remainder = apps.count % screensToUse
        
        var appIndex = 0
        for screenIndex in 0..<screensToUse {
            let count = appsPerScreen + (screenIndex < remainder ? 1 : 0)
            let subset = Array(apps[appIndex..<appIndex + count])
            appIndex += count
            
            let displayID = displays[screenIndex].id
            do {
                _ = try snapService.snapMultipleApps(
                    apps: subset,
                    preferredDisplayID: displayID,
                    probeLocation: probePoint
                )
            } catch {
                continue
            }
        }
        
        windowManager.statusMessage = "Distributed apps across screens."
        windowManager.hidePanel()
    }
    
    func swapApps(appA: NSRunningApplication, appB: NSRunningApplication) {
        do {
            try snapService.swapApps(pidA: appA.processIdentifier, pidB: appB.processIdentifier)
            windowManager.statusMessage = "Swapped windows."
            windowManager.hidePanel()
        } catch {
            windowManager.statusMessage = error.localizedDescription
        }
    }
    
    private func getTargetScreen(for displayID: CGDirectDisplayID?) -> NSScreen {
        if let displayID = displayID,
           let screen = NSScreen.screens.first(where: { 
               ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID 
           }) {
            return screen
        }
        
        // Fallback to mouse location
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
