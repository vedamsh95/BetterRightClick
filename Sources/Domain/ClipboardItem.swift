import AppKit

enum ClipboardItemKind: String {
    case text
    case file
    case image
    case pdf
    case unknown
}

struct ClipboardItem: Identifiable, Hashable {
    let id: UUID
    let kind: ClipboardItemKind
    let displayText: String
    let pasteValue: String?
    let pasteboardData: [NSPasteboard.PasteboardType: Data]?

    init(id: UUID = UUID(), kind: ClipboardItemKind, displayText: String, pasteValue: String?, pasteboardData: [NSPasteboard.PasteboardType: Data]? = nil) {
        self.id = id
        self.kind = kind
        self.displayText = displayText
        self.pasteValue = pasteValue
        self.pasteboardData = pasteboardData
    }

    var canPaste: Bool {
        pasteValue != nil || pasteboardData != nil
    }
}
