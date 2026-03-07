import Foundation

enum ContextTargetKind: String {
    case none
    case folder
    case image
    case text
    case file
}

struct ContextState {
    var frontmostBundleID: String?
    var frontmostAppName: String?
    var directoryURL: URL?
    var selectedFileURLs: [URL]
    var targetURL: URL?
    var targetKind: ContextTargetKind
    var selectedText: String?
    var selectedTextSource: String?

    init(
        frontmostBundleID: String? = nil,
        frontmostAppName: String? = nil,
        directoryURL: URL? = nil,
        selectedFileURLs: [URL] = [],
        targetURL: URL? = nil,
        targetKind: ContextTargetKind = .none,
        selectedText: String? = nil,
        selectedTextSource: String? = nil
    ) {
        self.frontmostBundleID = frontmostBundleID
        self.frontmostAppName = frontmostAppName
        self.directoryURL = directoryURL
        self.selectedFileURLs = selectedFileURLs
        self.targetURL = targetURL
        self.targetKind = targetKind
        self.selectedText = selectedText
        self.selectedTextSource = selectedTextSource
    }

    var primaryExtension: String? {
        targetURL?.pathExtension.lowercased() ?? selectedFileURLs.first?.pathExtension.lowercased()
    }

    var selectedCount: Int {
        selectedFileURLs.count
    }

    var isFinder: Bool {
        frontmostBundleID == "com.apple.finder"
    }
}
