import AppKit

@MainActor
final class ClipboardService: ObservableObject {
    @Published private(set) var history: [ClipboardItem] = []

    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let maxHistory = 25

    func startMonitoring() {
        stopMonitoring()
        lastChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func captureCurrentSnapshot() {
        if let item = extractItem(from: NSPasteboard.general) {
            insert(item)
        }
    }

    func currentText() -> String? {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func snapshotGeneralPasteboard() -> [[NSPasteboard.PasteboardType: Data]] {
        let pb = NSPasteboard.general
        guard let items = pb.pasteboardItems else { return [] }

        return items.map { item in
            var payload: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    payload[type] = data
                }
            }
            return payload
        }
    }

    @discardableResult
    func restoreGeneralPasteboard(from snapshot: [[NSPasteboard.PasteboardType: Data]]) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()

        guard !snapshot.isEmpty else {
            return true
        }

        let items: [NSPasteboardItem] = snapshot.map { payload in
            let item = NSPasteboardItem()
            for (type, data) in payload {
                item.setData(data, forType: type)
            }
            return item
        }

        return pb.writeObjects(items)
    }

    @discardableResult
    func copyToPasteboard(_ item: ClipboardItem) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()

        if let pbData = item.pasteboardData {
            var success = false
            for (type, data) in pbData {
                if pb.setData(data, forType: type) {
                    success = true
                }
            }
            return success
        }

        guard let value = item.pasteValue else { return false }

        switch item.kind {
        case .text:
            return pb.setString(value, forType: .string)
        case .file:
            let okFile = pb.setString(value, forType: .fileURL)
            let okText = pb.setString(value, forType: .string)
            return okFile || okText
        case .image, .pdf, .unknown:
            return pb.setString(value, forType: .string)
        }
    }

    private func pollPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        guard let item = extractItem(from: pb) else { return }
        insert(item)
    }

    private func extractItem(from pb: NSPasteboard) -> ClipboardItem? {
        var pbData: [NSPasteboard.PasteboardType: Data] = [:]
        if let firstItem = pb.pasteboardItems?.first {
            for type in firstItem.types {
                if let data = pb.data(forType: type) {
                    pbData[type] = data
                }
            }
        }

        if let text = pb.string(forType: .string) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return ClipboardItem(kind: .text, displayText: trimmed, pasteValue: trimmed, pasteboardData: pbData.isEmpty ? nil : pbData)
            }
        }

        if let fileURLString = pb.string(forType: .fileURL),
           let url = URL(string: fileURLString) {
            return ClipboardItem(kind: .file, displayText: "File: \(url.lastPathComponent)", pasteValue: fileURLString, pasteboardData: pbData.isEmpty ? nil : pbData)
        }

        if pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil {
            return ClipboardItem(kind: .image, displayText: "[Image]", pasteValue: nil, pasteboardData: pbData.isEmpty ? nil : pbData)
        }

        if pb.data(forType: .pdf) != nil {
            return ClipboardItem(kind: .pdf, displayText: "[PDF]", pasteValue: nil, pasteboardData: pbData.isEmpty ? nil : pbData)
        }

        return nil
    }

    private func insert(_ item: ClipboardItem) {
        if let first = history.first,
           first.displayText == item.displayText,
           first.pasteValue == item.pasteValue,
           first.kind == item.kind {
            return
        }

        history.removeAll {
            $0.displayText == item.displayText &&
            $0.pasteValue == item.pasteValue &&
            $0.kind == item.kind
        }

        history.insert(item, at: 0)

        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }
    }
}
