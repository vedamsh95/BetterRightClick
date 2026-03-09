import AppKit
import ApplicationServices
import CoreGraphics

struct PermissionStateMachine {
    struct Snapshot {
        var accessibilityGranted: Bool
        var appleEventsGranted: Bool
        var screenRecordingGranted: Bool
        var appleEventsEntitled: Bool
        var appleEventsLastError: String

        static let empty = Snapshot(
            accessibilityGranted: false,
            appleEventsGranted: false,
            screenRecordingGranted: false,
            appleEventsEntitled: false,
            appleEventsLastError: "not checked"
        )
    }

    func refresh(
        accessibilityService: AccessibilityService,
        entitlementService: EntitlementService,
        previous: Snapshot,
        probeAppleEvents: Bool
    ) -> Snapshot {
        let accessibilityGranted = accessibilityService.isTrusted(promptIfNeeded: false)
        let appleEventsResult = probeAppleEvents
            ? probeAppleEventsAutomation(promptIfNeeded: false)
            : (granted: previous.appleEventsGranted, errorSummary: previous.appleEventsLastError)
        let screenRecordingGranted = preflightScreenRecordingAccess()
        let appleEventsEntitled = entitlementService.hasEntitlement("com.apple.security.automation.apple-events")

        return Snapshot(
            accessibilityGranted: accessibilityGranted,
            appleEventsGranted: appleEventsResult.granted,
            screenRecordingGranted: screenRecordingGranted,
            appleEventsEntitled: appleEventsEntitled,
            appleEventsLastError: appleEventsResult.errorSummary
        )
    }

    func requestAccessibility(accessibilityService: AccessibilityService) {
        _ = accessibilityService.isTrusted(promptIfNeeded: true)
        accessibilityService.openSettings()
    }

    func requestAppleEvents() {
        _ = probeAppleEventsAutomation(promptIfNeeded: true)
        openAutomationSettings()
    }

    func requestScreenRecording() {
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
        }
        openScreenRecordingSettings()
    }

    func openAutomationSettings() {
        _ = openFirstAvailableSettingsURL([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "x-apple.systempreferences:com.apple.SystemSettings.PrivacySecurity.extension?Privacy_Automation",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ])
    }

    func openScreenRecordingSettings() {
        _ = openFirstAvailableSettingsURL([
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.SystemSettings.PrivacySecurity.extension?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ])
    }

    private func preflightScreenRecordingAccess() -> Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    func probeAppleEventsAutomation(promptIfNeeded: Bool) -> (granted: Bool, errorSummary: String) {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents")
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, promptIfNeeded)
        
        switch Int(status) {
        case 0: // noErr
            return (true, "granted")
        case -1743: // errAEEventNotPermitted
            return (false, "not granted (-1743)")
        case -600: // procNotFound
            // System events isn't running, but we often still have permission if it starts
            return (true, "granted (System Events not running)")
        default:
            return (false, "error \(status)")
        }
    }

    private func openFirstAvailableSettingsURL(_ candidates: [String]) -> Bool {
        for value in candidates {
            guard let url = URL(string: value) else { continue }
            if NSWorkspace.shared.open(url) {
                return true
            }
        }

        return false
    }
}
