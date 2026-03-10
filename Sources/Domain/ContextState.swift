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

struct FileTemplate: Equatable, Identifiable {
    let id = UUID()
    let title: String
    let extensionString: String
    let defaultName: String
    let content: String
    let icon: String       // SF Symbol name
    let category: String
    
    init(title: String, ext: String, defaultName: String = "Untitled", content: String = "", icon: String = "doc", category: String = "General") {
        self.title = title
        self.extensionString = ext
        self.defaultName = defaultName
        self.content = content
        self.icon = icon
        self.category = category
    }
}

class FileContextAnalyzer {
    
    // MARK: - The Master Template Arsenal
    
    // Web Dev
    static let htmlTemplate = FileTemplate(title: "HTML Page", ext: "html", defaultName: "index", content: "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n    <meta charset=\"UTF-8\">\n    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n    <title>Document</title>\n</head>\n<body>\n\n</body>\n</html>", icon: "globe", category: "Web Dev")
    static let cssTemplate = FileTemplate(title: "CSS Stylesheet", ext: "css", defaultName: "styles", content: "/* Styles */\n", icon: "paintbrush", category: "Web Dev")
    static let jsTemplate = FileTemplate(title: "JavaScript File", ext: "js", defaultName: "script", content: "'use strict';\n\n", icon: "curlybraces", category: "Web Dev")
    static let tsTemplate = FileTemplate(title: "TypeScript File", ext: "ts", defaultName: "index", content: "// TypeScript\n\n", icon: "curlybraces", category: "Web Dev")
    static let jsxTemplate = FileTemplate(title: "React JSX", ext: "jsx", defaultName: "Component", content: "import React from 'react';\n\nexport default function Component() {\n    return (\n        <div>\n\n        </div>\n    );\n}\n", icon: "atom", category: "Web Dev")
    static let tsxTemplate = FileTemplate(title: "React TSX", ext: "tsx", defaultName: "Component", content: "import React from 'react';\n\nexport default function Component(): JSX.Element {\n    return (\n        <div>\n\n        </div>\n    );\n}\n", icon: "atom", category: "Web Dev")
    
    // Backend / Script
    static let pythonTemplate = FileTemplate(title: "Python Script", ext: "py", defaultName: "main", content: "#!/usr/bin/env python3\n\n\ndef main():\n    pass\n\n\nif __name__ == '__main__':\n    main()\n", icon: "text.word.spacing", category: "Backend")
    static let swiftTemplate = FileTemplate(title: "Swift File", ext: "swift", defaultName: "NewFile", content: "import Foundation\n\n", icon: "swift", category: "Backend")
    static let shellTemplate = FileTemplate(title: "Shell Script", ext: "sh", defaultName: "script", content: "#!/bin/bash\nset -euo pipefail\n\n", icon: "terminal", category: "Backend")
    static let rubyTemplate = FileTemplate(title: "Ruby Script", ext: "rb", defaultName: "script", content: "#!/usr/bin/env ruby\n\n", icon: "diamond", category: "Backend")
    
    // Data
    static let jsonTemplate = FileTemplate(title: "JSON File", ext: "json", defaultName: "data", content: "{\n\n}\n", icon: "curlybraces", category: "Data")
    static let csvTemplate = FileTemplate(title: "CSV Spreadsheet", ext: "csv", defaultName: "data", content: "column_a,column_b,column_c\n", icon: "tablecells", category: "Data")
    static let yamlTemplate = FileTemplate(title: "YAML Config", ext: "yaml", defaultName: "config", content: "# Configuration\n\n", icon: "list.bullet.indent", category: "Data")
    static let xmlTemplate = FileTemplate(title: "XML File", ext: "xml", defaultName: "data", content: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root>\n\n</root>\n", icon: "chevron.left.forwardslash.chevron.right", category: "Data")
    
    // Config / DevOps
    static let envTemplate = FileTemplate(title: ".env File", ext: "env", defaultName: ".env", content: "# Environment Variables\n\n", icon: "lock.shield", category: "Config")
    static let gitignoreTemplate = FileTemplate(title: ".gitignore", ext: "gitignore", defaultName: ".gitignore", content: "# Compiled\n*.o\n*.pyc\n__pycache__/\n\n# Dependencies\nnode_modules/\n\n# OS\n.DS_Store\nThumbs.db\n", icon: "eye.slash", category: "Config")
    static let dockerfileTemplate = FileTemplate(title: "Dockerfile", ext: "", defaultName: "Dockerfile", content: "FROM alpine:latest\n\nWORKDIR /app\n\nCOPY . .\n\nCMD [\"sh\"]\n", icon: "shippingbox", category: "Config")
    static let requirementsTemplate = FileTemplate(title: "requirements.txt", ext: "txt", defaultName: "requirements", content: "# Python dependencies\n\n", icon: "list.clipboard", category: "Config")
    
    // Writer / General
    static let txtTemplate = FileTemplate(title: "Plain Text", ext: "txt", defaultName: "Untitled", icon: "doc.text", category: "General")
    static let mdTemplate = FileTemplate(title: "Markdown", ext: "md", defaultName: "README", content: "# Title\n\n", icon: "text.justify.left", category: "General")
    static let rtfTemplate = FileTemplate(title: "Rich Text", ext: "rtf", defaultName: "Document", content: "{\\rtf1\\ansi\\deftab720 }\n", icon: "doc.richtext", category: "General")
    
    // All templates in display order
    static let allTemplates: [FileTemplate] = [
        // Web Dev
        htmlTemplate, cssTemplate, jsTemplate, tsTemplate, jsxTemplate, tsxTemplate,
        // Backend
        pythonTemplate, swiftTemplate, shellTemplate, rubyTemplate,
        // Data
        jsonTemplate, csvTemplate, yamlTemplate, xmlTemplate,
        // Config
        envTemplate, gitignoreTemplate, dockerfileTemplate, requirementsTemplate,
        // General
        txtTemplate, mdTemplate, rtfTemplate
    ]
    
    // MARK: - The Context Sniffer
    
    struct AnalysisResult {
        let recommended: [FileTemplate]
        let other: [FileTemplate]
    }
    
    static func analyze(at url: URL?) -> AnalysisResult {
        let recommended = sniffRecommendations(at: url)
        let recommendedExts = Set(recommended.map { $0.extensionString })
        let other = allTemplates.filter { !recommendedExts.contains($0.extensionString) }
        return AnalysisResult(recommended: recommended, other: other)
    }
    
    private static func sniffRecommendations(at url: URL?) -> [FileTemplate] {
        guard let url = url else {
            return [txtTemplate, mdTemplate, jsonTemplate]
        }
        
        // Desktop fallback
        let path = url.path.lowercased()
        if path.contains("/desktop") {
            return [txtTemplate, mdTemplate, rtfTemplate, csvTemplate]
        }
        
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return [txtTemplate, mdTemplate, jsonTemplate]
        }
        
        let capped = Array(items.prefix(80))
        var jsCount = 0, pyCount = 0, swiftCount = 0, imageCount = 0
        var hasPackageJson = false, hasXcodeProj = false, hasPackageSwift = false
        var hasRequirementsTxt = false, hasGemfile = false
        
        for item in capped {
            let name = item.lastPathComponent.lowercased()
            let ext = item.pathExtension.lowercased()
            
            // Signal files
            if name == "package.json" { hasPackageJson = true }
            if name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcworkspace") { hasXcodeProj = true }
            if name == "package.swift" { hasPackageSwift = true }
            if name == "requirements.txt" || name == "pyproject.toml" || name == "pipfile" { hasRequirementsTxt = true }
            if name == "gemfile" { hasGemfile = true }
            
            // Extension counts
            switch ext {
            case "js", "ts", "jsx", "tsx": jsCount += 1
            case "py": pyCount += 1
            case "swift": swiftCount += 1
            case "jpg", "jpeg", "png", "gif", "svg", "webp", "heic": imageCount += 1
            default: break
            }
        }
        
        let total = max(capped.count, 1)
        
        // Decision tree
        if hasPackageJson || (Double(jsCount) / Double(total)) > 0.3 {
            return [tsTemplate, jsTemplate, jsxTemplate, tsxTemplate, htmlTemplate, cssTemplate, jsonTemplate, envTemplate]
        }
        
        if hasXcodeProj || hasPackageSwift || swiftCount > 2 {
            return [swiftTemplate, mdTemplate, jsonTemplate, shellTemplate]
        }
        
        if hasRequirementsTxt || pyCount > 2 {
            return [pythonTemplate, requirementsTemplate, jsonTemplate, csvTemplate, envTemplate, shellTemplate]
        }
        
        if hasGemfile {
            return [rubyTemplate, yamlTemplate, envTemplate, shellTemplate, mdTemplate]
        }
        
        // Image-heavy folder → probably assets, suggest readme/notes
        if (Double(imageCount) / Double(total)) > 0.5 && imageCount > 3 {
            return [mdTemplate, txtTemplate, csvTemplate]
        }
        
        // Generic fallback
        return [txtTemplate, mdTemplate, jsonTemplate, csvTemplate]
    }
    
    // MARK: - Category Grouping Helper
    static var categorizedTemplates: [(category: String, templates: [FileTemplate])] {
        let grouped = Dictionary(grouping: allTemplates, by: { $0.category })
        let order = ["Web Dev", "Backend", "Data", "Config", "General"]
        return order.compactMap { cat in
            guard let templates = grouped[cat] else { return nil }
            return (category: cat, templates: templates)
        }
    }
}

