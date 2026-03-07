import Foundation

enum NewFileType: String, CaseIterable, Identifiable {
    case txt
    case md
    case docx

    var id: String { rawValue }

    var label: String {
        switch self {
        case .txt: return ".txt"
        case .md: return ".md"
        case .docx: return ".docx"
        }
    }
}
