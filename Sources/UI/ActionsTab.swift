import SwiftUI

struct ActionsTab: View {
    @ObservedObject var windowManager: MenuWindowManager

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    let analysis = FileContextAnalyzer.analyze(at: windowManager.contextState.directoryURL)
                    
                    Menu {
                        // Section 1: Recommended
                        Section("Recommended for this folder") {
                            ForEach(analysis.recommended) { template in
                                Button {
                                    windowManager.createNewFile(template)
                                } label: {
                                    Label(template.title, systemImage: template.icon)
                                }
                            }
                        }
                        
                        Divider()
                        
                        // Section 2: All Types grouped by category
                        ForEach(FileContextAnalyzer.categorizedTemplates, id: \.category) { group in
                            Section(group.category) {
                                ForEach(group.templates) { template in
                                    Button {
                                        windowManager.createNewFile(template)
                                    } label: {
                                        Label(template.title, systemImage: template.icon)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("New File", systemImage: "doc.badge.plus")
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

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 2)
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
                    Menu("Copy Path As") {
                        Button("POSIX Path")        { windowManager.copyPathAs(.posix) }
                        Button("Terminal Escaped")  { windowManager.copyPathAs(.terminalEscaped) }
                        Button("File URL")          { windowManager.copyPathAs(.fileURL) }
                    }
                    .fixedSize()
                    
                    Button("New .md") { windowManager.createNewFile(FileContextAnalyzer.mdTemplate) }
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
                    Menu("Copy Path As") {
                        Button("POSIX Path")        { windowManager.copyPathAs(.posix) }
                        Button("Terminal Escaped")  { windowManager.copyPathAs(.terminalEscaped) }
                        Button("File URL")          { windowManager.copyPathAs(.fileURL) }
                    }
                    .fixedSize()
                    
                    Button("Open Image") { windowManager.openTargetWithDefaultApp() }
                        .buttonStyle(.bordered)
                    Button("Reveal in Finder") { windowManager.openTargetInFinder() }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .text:
                HStack(spacing: 8) {
                    Menu("Copy Path As") {
                        Button("POSIX Path")        { windowManager.copyPathAs(.posix) }
                        Button("Terminal Escaped")  { windowManager.copyPathAs(.terminalEscaped) }
                        Button("File URL")          { windowManager.copyPathAs(.fileURL) }
                    }
                    .fixedSize()
                    
                    Button("Open Text File") { windowManager.openTargetWithDefaultApp() }
                        .buttonStyle(.bordered)
                    Button("New .txt Here") { windowManager.createNewFile(FileContextAnalyzer.txtTemplate) }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .file:
                HStack(spacing: 8) {
                    Menu("Copy Path As") {
                        Button("POSIX Path")        { windowManager.copyPathAs(.posix) }
                        Button("Terminal Escaped")  { windowManager.copyPathAs(.terminalEscaped) }
                        Button("File URL")          { windowManager.copyPathAs(.fileURL) }
                    }
                    .fixedSize()
                    
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

    private func canPaste(_ item: ClipboardItem) -> Bool {
        // Context inference can be noisy while our panel is open.
        // If we have a valid paste payload, let the user attempt paste.
        item.canPaste
    }
}
