import AppKit

@MainActor
final class FileOperationsService {
    private var cutBuffer: [URL] = []

    var cutItemCount: Int {
        cutBuffer.count
    }

    @discardableResult
    func createFile(type: NewFileType, in directory: URL) throws -> URL {
        let fm = FileManager.default
        let baseName = "Untitled"
        let ext = type.rawValue

        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }

        try createFile(type: type, at: candidate)

        return candidate
    }

    @discardableResult
    func createFile(template: FileTemplate, in directory: URL) throws -> URL {
        let fm = FileManager.default
        let baseName = template.defaultName
        let ext = template.extensionString

        var candidate = directory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 1
        while fm.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(counter).\(ext)")
            counter += 1
        }

        try createFile(template: template, at: candidate)

        return candidate
    }

    func createFile(type: NewFileType, at url: URL) throws {
        let fm = FileManager.default

        switch type {
        case .txt, .md:
            try "".write(to: url, atomically: true, encoding: .utf8)
        case .docx:
            let tempTXT = fm.temporaryDirectory
                .appendingPathComponent("better-right-click-")
                .appendingPathExtension("txt")

            try "".write(to: tempTXT, atomically: true, encoding: .utf8)
            defer { try? fm.removeItem(at: tempTXT) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
            process.arguments = ["-convert", "docx", tempTXT.path, "-output", url.path]
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                throw NSError(
                    domain: "FileOperationsService",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create .docx file"]
                )
            }
        }
    }

    func createFile(template: FileTemplate, at url: URL) throws {
        try template.content.write(to: url, atomically: true, encoding: .utf8)
    }

    func isWritableDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue && FileManager.default.isWritableFile(atPath: url.path)
    }

    func stageCutItems(_ urls: [URL]) {
        cutBuffer = urls
    }

    @discardableResult
    func pasteCutItems(into destinationDirectory: URL) throws -> Int {
        guard !cutBuffer.isEmpty else { return 0 }

        let fm = FileManager.default
        var movedCount = 0
        var remaining: [URL] = []

        for source in cutBuffer {
            let destination = uniqueDestination(for: source, in: destinationDirectory)
            do {
                if fm.fileExists(atPath: source.path) {
                    try moveUsingShell(source: source, destination: destination)
                    movedCount += 1
                }
            } catch {
                remaining.append(source)
            }
        }

        cutBuffer = remaining
        return movedCount
    }

    @discardableResult
    func flattenDirectory(root: URL) throws -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var movedCount = 0

        for case let fileURL as URL in enumerator {
            if fileURL.deletingLastPathComponent() == root {
                continue
            }

            let values = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                continue
            }

            let destination = uniqueDestination(for: fileURL, in: root)
            do {
                try fm.moveItem(at: fileURL, to: destination)
                movedCount += 1
            } catch {
                continue
            }
        }

        return movedCount
    }

    private func uniqueDestination(for sourceURL: URL, in directory: URL) -> URL {
        let fm = FileManager.default
        let ext = sourceURL.pathExtension
        let stem = sourceURL.deletingPathExtension().lastPathComponent

        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var index = 1

        while fm.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
            candidate = directory.appendingPathComponent(name)
            index += 1
        }

        return candidate
    }

    private func moveUsingShell(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/mv")
        process.arguments = [source.path, destination.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(
                domain: "FileOperationsService",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Failed to move \(source.lastPathComponent)"]
            )
        }
    }
}
