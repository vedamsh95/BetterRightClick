import SwiftUI

struct ActionsTab: View {
    @ObservedObject var windowManager: MenuWindowManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Menu("New File") {
                        ForEach(NewFileType.allCases) { type in
                            Button(type.label) {
                                windowManager.createNewFile(type)
                            }
                        }
                    }

                    Button("Take Screenshot") {
                        windowManager.takeScreenshot()
                    }

                    Button("Minimize All Apps") {
                        windowManager.minimizeAllActiveApps()
                    }

                    Button("Flatten Folder") {
                        windowManager.flattenCurrentDirectory()
                    }
                }

                contextInfoView
                quickActionsView

                if !windowManager.pinnedApps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(windowManager.pinnedApps) { pinned in
                                Button(pinned.name) {
                                    windowManager.activatePinnedApp(pinned)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Text("Clipboard History")
                    .font(.headline)

                VStack(spacing: 6) {
                    ForEach(Array(windowManager.clipboardItems.prefix(5))) { item in
                        HStack(spacing: 8) {
                            Text(item.displayText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button("Copy") {
                                windowManager.copyClipboardItemToPasteboard(item)
                            }
                            .buttonStyle(.bordered)

                            Button("Paste") {
                                windowManager.pasteClipboardItem(item)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canPaste(item))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.quaternary.opacity(0.25))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                if let lookup = windowManager.lookupResult {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Dictionary Lookup")
                                .font(.caption)
                                .fontWeight(.bold)
                            Spacer()
                            Button("Close") {
                                windowManager.clearLookup()
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                        ScrollView {
                            Text(lookup)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                    }
                    .padding(8)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                if !windowManager.statusMessage.isEmpty {
                    Text(windowManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                diagnosticsView
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 2)
        }
        .onAppear {
            windowManager.refreshDiagnostics()
        }
    }

    private var contextInfoView: some View {
        let context = windowManager.contextState
        return HStack(spacing: 8) {
            Text(context.frontmostAppName ?? "No App")
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary)
                .clipShape(Capsule())

            if let folder = context.directoryURL {
                Text("Folder: \(folder.lastPathComponent)")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Folder: Not detected")
                    .font(.caption)
            }

            Text("Selected: \(context.selectedCount)")
                .font(.caption)

            let targetDisplay = context.targetKind == .none ? "App Context" : context.targetKind.rawValue.capitalized
            Text("Target: \(targetDisplay)")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var quickActionsView: some View {
        let context = windowManager.contextState

        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Actions")
                .font(.caption)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                Menu("Format Text") {
                    Button("Copy as Plain Text") { windowManager.formatCurrentTextContext(style: .plainText) }
                    Button("Convert to UPPERCASE") { windowManager.formatCurrentTextContext(style: .uppercase) }
                    Button("lowercase") { windowManager.formatCurrentTextContext(style: .lowercase) }
                    Button("Title Case") { windowManager.formatCurrentTextContext(style: .titleCase) }
                }
                .fixedSize()

                Button("Lookup") {
                    windowManager.lookupCurrentTextContext()
                }
                .buttonStyle(.bordered)

                Button("OCR Text") {
                    windowManager.ocrImage()
                }
                .buttonStyle(.bordered)
            }

            switch context.targetKind {
            case .folder:
                HStack(spacing: 8) {
                    Button("New .md") { windowManager.createNewFile(.md) }
                        .buttonStyle(.bordered)
                    Button("Flatten This Folder") { windowManager.flattenCurrentDirectory() }
                        .buttonStyle(.bordered)
                    Button("Open Folder") { windowManager.openTargetInFinder() }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .image:
                HStack(spacing: 8) {
                    Button("Open Image") { windowManager.openTargetWithDefaultApp() }
                        .buttonStyle(.bordered)
                    Button("Reveal in Finder") { windowManager.openTargetInFinder() }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .text:
                HStack(spacing: 8) {
                    Button("Open Text File") { windowManager.openTargetWithDefaultApp() }
                        .buttonStyle(.bordered)
                    Button("New .txt Here") { windowManager.createNewFile(.txt) }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .file:
                HStack(spacing: 8) {
                    Button("Open") { windowManager.openTargetWithDefaultApp() }
                        .buttonStyle(.bordered)
                    Button("Reveal") { windowManager.openTargetInFinder() }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .none:
                Text("No file target detected under cursor.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diagnosticsView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Diagnostics")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Button("Copy Diagnostics") {
                    windowManager.copyDiagnosticsSnapshot()
                }
                .buttonStyle(.bordered)
            }

            Text("AX Trusted: \(windowManager.diagnosticsAXTrusted ? "Yes" : "No")")
                .font(.caption2)
            if !windowManager.diagnosticsAXTrusted {
                HStack(spacing: 8) {
                    Button("Grant Accessibility") {
                        windowManager.requestAccessibilityAccess()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Recheck") {
                        windowManager.refreshPermissionsAndContext()
                    }
                    .buttonStyle(.bordered)

                    Button("Reveal App") {
                        windowManager.revealThisAppInFinder()
                    }
                    .buttonStyle(.bordered)

                    Button("Copy App Path") {
                        windowManager.copyAppBundlePath()
                    }
                    .buttonStyle(.bordered)
                }
                Text("App Path: \(windowManager.diagnosticsAppBundlePath)")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Note: 'App Path' is this tool's location, not the Finder context folder.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("Automation (System Events): \(windowManager.diagnosticsAutomationOK ? "Yes" : "No")")
                .font(.caption2)
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
            Text("Apple Events Entitlement: \(windowManager.diagnosticsAppleEventsEntitled ? "Yes" : "No")")
                .font(.caption2)
            Text("Context Folder: \(windowManager.diagnosticsContextFolder)")
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Last Paste Path: \(windowManager.diagnosticsLastPastePath)")
                .font(.caption2)
        }
        .padding(8)
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func canPaste(_ item: ClipboardItem) -> Bool {
        // Context inference can be noisy while our panel is open.
        // If we have a valid paste payload, let the user attempt paste.
        item.canPaste
    }
}
