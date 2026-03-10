import SwiftUI
import AppKit
import Vision

@MainActor
class ActionManager: ObservableObject {
    private let windowManager: MenuWindowManager
    private let fileService: FileOperationsService
    
    init(windowManager: MenuWindowManager, fileService: FileOperationsService) {
        self.windowManager = windowManager
        self.fileService = fileService
    }
    
    enum PathStyle {
        case posix
        case terminalEscaped
        case fileURL
    }

    enum TextStyle {
        case plainText, uppercase, lowercase, titleCase
    }

    func createNewFile(_ template: FileTemplate) {
        windowManager.refreshContext(useFinderScript: false)

        let destinationDirectory = resolvedActionDirectory(preferFinderContext: true)
        let saveURL: URL?

        if let dir = destinationDirectory,
           fileService.isWritableDirectory(dir) {
            saveURL = nextUntitledURL(in: dir, template: template)
        } else {
            saveURL = presentSavePanelForNewFile(template: template)
        }

        guard let targetURL = saveURL else {
            windowManager.statusMessage = "Create file cancelled."
            return
        }

        do {
            try fileService.createFile(template: template, at: targetURL)
            windowManager.statusMessage = "Created \(targetURL.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([targetURL])
            windowManager.hidePanel()
        } catch {
            windowManager.statusMessage = "Create file failed: \(error.localizedDescription)"
        }
    }
    
    func takeScreenshot() {
        windowManager.hidePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "BRC_Screenshot_\(formatter.string(from: Date())).png"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", tempURL.path]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0,
               FileManager.default.fileExists(atPath: tempURL.path) {
                NSApp.activate(ignoringOtherApps: true)

                let panel = NSSavePanel()
                panel.canCreateDirectories = true
                panel.nameFieldStringValue = filename
                panel.allowedContentTypes = [.png]
                panel.isExtensionHidden = false
                panel.title = "Save Screenshot"
                panel.message = "Choose where to save your screenshot."

                if panel.runModal() == .OK, let destination = panel.url {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try? FileManager.default.removeItem(at: destination)
                    }

                    do {
                        try FileManager.default.moveItem(at: tempURL, to: destination)
                        windowManager.statusMessage = "Screenshot saved to \(destination.lastPathComponent)."
                        windowManager.diagnosticsLastPastePath = "screenshot: saved-via-save-panel"
                    } catch {
                        windowManager.statusMessage = "Failed to save screenshot: \(error.localizedDescription)"
                        windowManager.diagnosticsLastPastePath = "screenshot: save-failed"
                        try? FileManager.default.removeItem(at: tempURL)
                    }
                } else {
                    windowManager.statusMessage = "Screenshot captured, but save was cancelled."
                    windowManager.diagnosticsLastPastePath = "screenshot: save-cancelled"
                    try? FileManager.default.removeItem(at: tempURL)
                }
            } else {
                windowManager.statusMessage = "Screenshot cancelled or blocked by Screen Recording permission."
                windowManager.diagnosticsLastPastePath = "screenshot: cancelled-or-blocked"
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch {
            windowManager.statusMessage = "Failed to start screenshot tool: \(error.localizedDescription)"
            windowManager.diagnosticsLastPastePath = "screenshot: failed-to-start"
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
    
    func flattenCurrentDirectory() {
        windowManager.refreshContext(useFinderScript: false)
        let directory = resolvedActionDirectory(preferFinderContext: true) ??
            presentDirectoryPicker(title: "Choose Folder To Flatten")

        guard let directory = directory else {
            windowManager.statusMessage = "Flatten cancelled."
            return
        }

        do {
            let moved = try fileService.flattenDirectory(root: directory)
            windowManager.statusMessage = "Flatten complete: moved \(moved) file(s)."
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
            windowManager.hidePanel()
        } catch {
            windowManager.statusMessage = "Flatten failed: \(error.localizedDescription)"
        }
    }
    
    func copyPathAs(_ style: PathStyle) {
        let raw = windowManager.contextState.targetURL?.path
            ?? windowManager.contextState.selectedFileURLs.first?.path
            ?? windowManager.contextState.directoryURL?.path

        guard let path = raw else {
            windowManager.statusMessage = "No file or folder selected."
            return
        }

        let formatted: String
        switch style {
        case .posix:
            formatted = path
        case .terminalEscaped:
            formatted = path.replacingOccurrences(of: " ", with: "\\ ")
                           .replacingOccurrences(of: "(", with: "\\(")
                           .replacingOccurrences(of: ")", with: "\\)")
                           .replacingOccurrences(of: "[", with: "\\[")
                           .replacingOccurrences(of: "]", with: "\\]")
                           .replacingOccurrences(of: "&", with: "\\&")
                           .replacingOccurrences(of: ";", with: ";")
        case .fileURL:
            formatted = URL(fileURLWithPath: path).absoluteString
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formatted, forType: .string)
        windowManager.statusMessage = "Copied path to clipboard."
    }
    
    func formatCurrentTextContext(style: TextStyle) {
        guard let text = resolveSelectedTextForTools() else {
            windowManager.statusMessage = "No selected text detected for formatting."
            return
        }

        let formattedText: String
        switch style {
        case .plainText: formattedText = text
        case .uppercase: formattedText = text.uppercased()
        case .lowercase: formattedText = text.lowercased()
        case .titleCase: formattedText = text.capitalized
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(formattedText, forType: .string)
        windowManager.statusMessage = "Formatted selected text pasted."
        windowManager.hidePanel()
        
        // Post paste
        windowManager.postPasteCommandToFrontmostApp(preferMatchStyle: false)
    }
    
    func ocrImage() {
        guard let url = windowManager.contextState.targetURL else {
            windowManager.statusMessage = "No image found for OCR."
            return
        }

        windowManager.statusMessage = "OCR Processing..."
        windowManager.diagnosticsOCRState = "processing"

        let requestHandler = VNImageRequestHandler(url: url)
        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self, let observations = request.results as? [VNRecognizedTextObservation] else { return }
            
            let recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            
            DispatchQueue.main.async {
                if recognizedText.isEmpty {
                    self.windowManager.statusMessage = "No text found in image."
                    self.windowManager.diagnosticsOCRState = "complete: empty"
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(recognizedText, forType: .string)
                    self.windowManager.statusMessage = "OCR complete. Text copied."
                    self.windowManager.diagnosticsOCRState = "complete: success"
                    self.windowManager.diagnosticsOCRDestination = "pasteboard"
                }
            }
        }
        
        request.recognitionLevel = .accurate
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.windowManager.statusMessage = "OCR failed: \(error.localizedDescription)"
                    self?.windowManager.diagnosticsOCRState = "failed"
                }
            }
        }
    }
    
    func lookupCurrentTextContext() {
        guard let text = resolveSelectedTextForTools() else {
            windowManager.statusMessage = "No selected text detected for lookup."
            return
        }
        windowManager.lookupResult = "Looking up '\(text)'..."
        // In a real app, this would trigger a Dictionary lookup or separate AI agent
    }
    
    func openTargetInFinder() {
        if let target = windowManager.contextState.targetURL {
            NSWorkspace.shared.activateFileViewerSelecting([target])
            windowManager.statusMessage = "Revealed target in Finder."
            return
        }

        if let directory = windowManager.contextState.directoryURL {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
            windowManager.statusMessage = "Opened folder in Finder."
            return
        }

        windowManager.statusMessage = "No target item under cursor."
    }
    
    func openTargetWithDefaultApp() {
        guard let target = windowManager.contextState.targetURL else {
            windowManager.statusMessage = "No target item under cursor."
            return
        }

        NSWorkspace.shared.open(target)
        windowManager.statusMessage = "Opened target with default app."
        windowManager.hidePanel()
    }
    
    func deleteTargetPermanently() {
        guard let url = windowManager.contextState.targetURL else { return }
        do {
            try FileManager.default.removeItem(at: url)
            windowManager.hidePanel()
            windowManager.statusMessage = "Deleted permanently."
        } catch {
            windowManager.statusMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func resolvedActionDirectory(preferFinderContext: Bool) -> URL? {
        if preferFinderContext,
           windowManager.contextState.frontmostBundleID == "com.apple.finder",
           let dir = windowManager.contextState.directoryURL {
            return dir
        }

        if let dir = windowManager.contextState.directoryURL {
            return dir
        }

        if let target = windowManager.contextState.targetURL {
            return windowManager.contextState.targetKind == .folder ? target : target.deletingLastPathComponent()
        }

        return nil
    }

    private func nextUntitledURL(in directory: URL, template: FileTemplate) -> URL {
        let fm = FileManager.default
        var index = 0

        while true {
            let name = index == 0 ? template.defaultName : "\(template.defaultName) \(index)"
            let candidate = directory.appendingPathComponent(name).appendingPathExtension(template.extensionString)
            if !fm.fileExists(atPath: candidate.path) {
                return candidate
            }
            index += 1
        }
    }

    private func presentSavePanelForNewFile(template: FileTemplate) -> URL? {
        windowManager.hidePanel()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = "\(template.defaultName).\(template.extensionString)"
        panel.title = "Create New \(template.title)"

        let response = panel.runModal()
        guard response == .OK, let selected = panel.url else { return nil }

        if selected.pathExtension.lowercased() == template.extensionString {
            return selected
        }

        return selected.appendingPathExtension(template.extensionString)
    }

    private func presentDirectoryPicker(title: String) -> URL? {
        windowManager.hidePanel()
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = title

        let response = panel.runModal()
        guard response == .OK else { return nil }
        return panel.url
    }

    private func resolveSelectedTextForTools() -> String? {
        if let current = windowManager.contextState.selectedText?.trimmingCharacters(in: .whitespacesAndNewlines), !current.isEmpty {
            return current
        }

        // Active probe
        if let probed = windowManager.probeSelectedTextFromActiveApp()?.trimmingCharacters(in: .whitespacesAndNewlines), !probed.isEmpty {
            return probed
        }

        return nil
    }
}


