import SwiftUI
import AppKit

@MainActor
class SettingsManager: ObservableObject {
    private let windowManager: MenuWindowManager
    private let accessibilityService: AccessibilityService
    private let permissionStateMachine: PermissionStateMachine
    private let entitlementService: EntitlementService
    private let contextService: ContextService
    
    init(
        windowManager: MenuWindowManager,
        accessibilityService: AccessibilityService,
        permissionStateMachine: PermissionStateMachine,
        entitlementService: EntitlementService,
        contextService: ContextService
    ) {
        self.windowManager = windowManager
        self.accessibilityService = accessibilityService
        self.permissionStateMachine = permissionStateMachine
        self.entitlementService = entitlementService
        self.contextService = contextService
    }
    
    func refreshDiagnostics(probePermissions: Bool = false) {
        windowManager.permissionSnapshot = permissionStateMachine.refresh(
            accessibilityService: accessibilityService,
            entitlementService: entitlementService,
            previous: windowManager.permissionSnapshot,
            probeAppleEvents: false
        )

        updateDiagnosticsProperties()

        if probePermissions {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let appleEventsResult = self.permissionStateMachine.probeAppleEventsAutomation(promptIfNeeded: false)
                DispatchQueue.main.async {
                    self.windowManager.permissionSnapshot.appleEventsGranted = appleEventsResult.granted
                    self.windowManager.permissionSnapshot.appleEventsLastError = appleEventsResult.errorSummary
                    self.updateDiagnosticsProperties()
                }
            }
        }
        windowManager.statusMessage = "Diagnostics refreshed"
    }
    
    private func updateDiagnosticsProperties() {
        windowManager.diagnosticsAXTrusted = windowManager.permissionSnapshot.accessibilityGranted
        windowManager.diagnosticsAutomationOK = windowManager.permissionSnapshot.appleEventsGranted
        windowManager.diagnosticsAppleEventsEntitled = windowManager.permissionSnapshot.appleEventsEntitled
        windowManager.diagnosticsTargetBundleID = windowManager.contextState.frontmostBundleID
            ?? windowManager.lastFrontmostApp?.bundleIdentifier
            ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            ?? "(unknown)"
        windowManager.diagnosticsContextFolder = windowManager.contextState.directoryURL?.path ?? "(not detected)"
        windowManager.diagnosticsAppBundlePath = Bundle.main.bundleURL.path
    }
    
    func requestAccessibilityAccess() {
        permissionStateMachine.requestAccessibility(accessibilityService: accessibilityService)
        refreshDiagnostics(probePermissions: true)
    }

    func requestAppleEventsAccess() {
        permissionStateMachine.requestAppleEvents()
        refreshDiagnostics(probePermissions: true)
    }

    func requestScreenRecordingAccess() {
        permissionStateMachine.requestScreenRecording()
        refreshDiagnostics(probePermissions: true)
    }

    func openScreenRecordingSettings() {
        permissionStateMachine.openScreenRecordingSettings()
    }

    func openAutomationSettings() {
        permissionStateMachine.openAutomationSettings()
    }

    func refreshPermissionsAndContext() {
        windowManager.refreshContext(useFinderScript: false, allowSelectionProbe: false)
        refreshDiagnostics(probePermissions: true)
    }

    func revealThisAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func copyAppBundlePath() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Bundle.main.bundleURL.path, forType: .string)
        windowManager.statusMessage = "Copied app bundle path."
    }

    func copyDiagnosticsSnapshot() {
        let lines = [
            "AX Trusted: \(windowManager.diagnosticsAXTrusted ? "Yes" : "No")",
            "Automation (System Events): \(windowManager.diagnosticsAutomationOK ? "Yes" : "No")",
            "Screen Recording: \(windowManager.permissionSnapshot.screenRecordingGranted ? "Yes" : "No")",
            "Target Bundle: \(windowManager.diagnosticsTargetBundleID)",
            "Selected Text Detected: \(windowManager.diagnosticsSelectedTextDetected ? "Yes" : "No")",
            "Selection Source: \(windowManager.diagnosticsSelectionSource)",
            "Selection Details: \(windowManager.diagnosticsSelectionDetails)",
            "OCR State: \(windowManager.diagnosticsOCRState)",
            "OCR Destination: \(windowManager.diagnosticsOCRDestination)",
            "Snap State: \(windowManager.diagnosticsSnapState)",
            "Apple Events Entitlement: \(windowManager.diagnosticsAppleEventsEntitled ? "Yes" : "No")",
            "Apple Events Last Error: \(windowManager.permissionSnapshot.appleEventsLastError)",
            "Context Folder: \(windowManager.diagnosticsContextFolder)",
            "Last Paste Path: \(windowManager.diagnosticsLastPastePath)",
            "App Path: \(windowManager.diagnosticsAppBundlePath)"
        ]

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        windowManager.statusMessage = "Copied diagnostics to clipboard."
    }
    
    func clearLookup() {
        windowManager.lookupResult = nil
    }
}
