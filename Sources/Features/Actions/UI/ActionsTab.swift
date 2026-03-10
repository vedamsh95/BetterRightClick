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
                                    windowManager.actions.createNewFile(template)
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
                                        windowManager.actions.createNewFile(template)
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
                        windowManager.actions.takeScreenshot()
                    }

                    Button("Minimize All Apps") {
                        windowManager.switcher.minimizeAllActiveApps()
                    }

                    Button("Flatten Folder") {
                        windowManager.actions.flattenCurrentDirectory()
                    }
                }

                contextInfoView
                quickActionsView

                if !windowManager.pinnedApps.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(windowManager.pinnedApps) { pinned in
                                Button(pinned.name) {
                                    windowManager.switcher.activatePinnedApp(pinned)
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
                                windowManager.switcher.copyClipboardItemToPasteboard(item)
                            }
                            .buttonStyle(.bordered)

                            Button("Paste") {
                                windowManager.switcher.pasteClipboardItem(item)
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
                                windowManager.settings.clearLookup()
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
                    Button("Copy as Plain Text") { windowManager.actions.formatCurrentTextContext(style: .plainText) }
                    Button("Convert to UPPERCASE") { windowManager.actions.formatCurrentTextContext(style: .uppercase) }
                    Button("lowercase") { windowManager.actions.formatCurrentTextContext(style: .lowercase) }
                    Button("Title Case") { windowManager.actions.formatCurrentTextContext(style: .titleCase) }
                }
                .fixedSize()

                Button("Lookup") {
                    windowManager.actions.lookupCurrentTextContext()
                }
                .buttonStyle(.bordered)

                Button("OCR Text") {
                    windowManager.actions.ocrImage()
                }
                .buttonStyle(.bordered)
            }

            switch context.targetKind {
            case .folder:
                HStack(spacing: 8) {
                    Menu("Copy Path As") {
                        Button("POSIX Path")        { windowManager.actions.copyPathAs(.posix) }
                        Button("Terminal Escaped")  { windowManager.actions.copyPathAs(.terminalEscaped) }
                        Button("File URL")          { windowManager.actions.copyPathAs(.fileURL) }
                    }
                    .fixedSize()
                    
                    Button("New .md") { windowManager.actions.createNewFile(FileContextAnalyzer.mdTemplate) }
                        .buttonStyle(.bordered)
                    Button("Flatten This Folder") { windowManager.actions.flattenCurrentDirectory() }
                        .buttonStyle(.bordered)
                    Button("Open Folder") { windowManager.actions.openTargetInFinder() }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.actions.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .image:
                HStack(spacing: 8) {
                    Menu("Copy Path As") {
                        Button("POSIX Path")        { windowManager.actions.copyPathAs(.posix) }
                        Button("Terminal Escaped")  { windowManager.actions.copyPathAs(.terminalEscaped) }
                        Button("File URL")          { windowManager.actions.copyPathAs(.fileURL) }
                    }
                    .fixedSize()
                    
                    Button("Open Image") { windowManager.actions.openTargetWithDefaultApp() }
                        .buttonStyle(.bordered)
                    Button("Reveal in Finder") { windowManager.actions.openTargetInFinder() }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.actions.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .text:
                HStack(spacing: 8) {
                    Menu("Copy Path As") {
                        Button("POSIX Path")        { windowManager.actions.copyPathAs(.posix) }
                        Button("Terminal Escaped")  { windowManager.actions.copyPathAs(.terminalEscaped) }
                        Button("File URL")          { windowManager.actions.copyPathAs(.fileURL) }
                    }
                    .fixedSize()
                    
                    Button("Open Text File") { windowManager.actions.openTargetWithDefaultApp() }
                        .buttonStyle(.bordered)
                    Button("New .txt Here") { windowManager.actions.createNewFile(FileContextAnalyzer.txtTemplate) }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.actions.deleteTargetPermanently() }
                        .buttonStyle(.bordered)
                }
            case .file:
                HStack(spacing: 8) {
                    Menu("Copy Path As") {
                        Button("POSIX Path")        { windowManager.actions.copyPathAs(.posix) }
                        Button("Terminal Escaped")  { windowManager.actions.copyPathAs(.terminalEscaped) }
                        Button("File URL")          { windowManager.actions.copyPathAs(.fileURL) }
                    }
                    .fixedSize()
                    
                    Button("Open") { windowManager.actions.openTargetWithDefaultApp() }
                        .buttonStyle(.bordered)
                    Button("Reveal") { windowManager.actions.openTargetInFinder() }
                        .buttonStyle(.bordered)
                    Button("Delete Permanently") { windowManager.actions.deleteTargetPermanently() }
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
