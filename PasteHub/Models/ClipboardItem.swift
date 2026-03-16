import Foundation

enum ClipboardContentType: String, Codable {
    case text
    case image
    case file

    var icon: String {
        switch self {
        case .text:  return "doc.text"
        case .image: return "photo"
        case .file:  return "doc"
        }
    }

    var label: String {
        switch self {
        case .text:  return "文本"
        case .image: return "图片"
        case .file:  return "文件"
        }
    }
}

struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    let type: ClipboardContentType
    let content: String
    let timestamp: Date
    let sourceApp: String?
    let sourceBundleIdentifier: String?
    let tags: [String]

    init(
        id: UUID = UUID(),
        type: ClipboardContentType,
        content: String,
        timestamp: Date = Date(),
        sourceApp: String? = nil,
        sourceBundleIdentifier: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.timestamp = timestamp
        self.sourceApp = sourceApp
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.tags = tags
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case content
        case timestamp
        case sourceApp
        case sourceBundleIdentifier
        case tags
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ClipboardContentType.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        sourceApp = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        sourceBundleIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceBundleIdentifier)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(sourceApp, forKey: .sourceApp)
        try container.encodeIfPresent(sourceBundleIdentifier, forKey: .sourceBundleIdentifier)
        try container.encode(tags, forKey: .tags)
    }

    var displayText: String {
        switch type {
        case .text:
            return String(content.prefix(200))
        case .image:
            return "[图片]"
        case .file:
            return contentURL?.lastPathComponent ?? content
        }
    }

    var contentURL: URL? {
        if let url = URL(string: content) {
            return url
        }
        if content.hasPrefix("/") {
            return URL(fileURLWithPath: content)
        }
        return nil
    }
}
