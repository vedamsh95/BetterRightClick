import SwiftUI

struct SettingsTab: View {
    @ObservedObject var windowManager: MenuWindowManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                permissionsSection
                diagnosticsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 2)
        }
        .onAppear {
            windowManager.refreshPermissionsAndContext()
            windowManager.refreshSnapDisplays()
        }
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Permissions")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    windowManager.refreshPermissionsAndContext()
                }
                .buttonStyle(.bordered)
            }

            permissionRow(
                title: "Accessibility",
                granted: windowManager.permissionSnapshot.accessibilityGranted,
                detail: "Required for context probes and window snap actions.",
                actionTitle: "Grant",
                action: { windowManager.requestAccessibilityAccess() }
            )

            permissionRow(
                title: "Apple Events (System Events)",
                granted: windowManager.permissionSnapshot.appleEventsGranted,
                detail: "Used for automation fallback paths.",
                actionTitle: "Grant",
                action: { windowManager.requestAppleEventsAccess() }
            )

            permissionRow(
                title: "Screen Recording",
                granted: windowManager.permissionSnapshot.screenRecordingGranted,
                detail: "Required for screenshot and screen content flows.",
                actionTitle: "Grant",
                action: { windowManager.requestScreenRecordingAccess() }
            )

            Text("Apple Events Entitlement: \(windowManager.permissionSnapshot.appleEventsEntitled ? "Yes" : "No")")
                .font(.caption2)
            Text("Apple Events Last Error: \(windowManager.permissionSnapshot.appleEventsLastError)")
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)

            if !windowManager.permissionSnapshot.appleEventsEntitled {
                Text("Apple Events cannot be granted because automation entitlement is missing in this build.")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else if !windowManager.permissionSnapshot.appleEventsGranted {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tip: Click Grant, then allow BetterRightClick under Privacy & Security > Automation.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    
                    HStack {
                        Text("If it stays stuck as 'Missing', macOS may have ghost-banned it.")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        
                        Button("Reset macOS Permissions") {
                            let process = Process()
                            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
                            process.arguments = ["reset", "AppleEvents", "com.example.BetterRightClick"]
                            try? process.run()
                            
                            // Also try explicitly opening the correct TCC section
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                            
                            windowManager.refreshPermissionsAndContext()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var diagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Diagnostics")
                    .font(.headline)
                Spacer()
                Button("Copy Diagnostics") {
                    windowManager.copyDiagnosticsSnapshot()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button("Reveal App") {
                    windowManager.revealThisAppInFinder()
                }
                .buttonStyle(.bordered)

                Button("Copy App Path") {
                    windowManager.copyAppBundlePath()
                }
                .buttonStyle(.bordered)
            }

            Text("Snap State: \(windowManager.diagnosticsSnapState)")
                .font(.caption2)
                .lineLimit(3)
                .truncationMode(.middle)
            Text("Target Bundle: \(windowManager.diagnosticsTargetBundleID)")
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Selected Text Detected: \(windowManager.diagnosticsSelectedTextDetected ? "Yes" : "No")")
                .font(.caption2)
            Text("Selection Source: \(windowManager.diagnosticsSelectionSource)")
                .font(.caption2)
            Text("Selection Details: \(windowManager.diagnosticsSelectionDetails)")
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)
            Text("OCR State: \(windowManager.diagnosticsOCRState)")
                .font(.caption2)
                .lineLimit(2)
                .truncationMode(.middle)
            Text("OCR Destination: \(windowManager.diagnosticsOCRDestination)")
                .font(.caption2)
            Text("Context Folder: \(windowManager.diagnosticsContextFolder)")
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Last Paste Path: \(windowManager.diagnosticsLastPastePath)")
                .font(.caption2)
            Text("App Path: \(windowManager.diagnosticsAppBundlePath)")
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)

            if !windowManager.statusMessage.isEmpty {
                Text(windowManager.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        detail: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(granted ? "Granted" : "Missing")
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(granted ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                .clipShape(Capsule())

            if !granted {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
