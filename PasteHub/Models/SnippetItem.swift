import Foundation

struct SnippetItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var content: String
    var tags: [String]
    var timestamp: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        content: String,
        tags: [String] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.tags = tags
        self.timestamp = timestamp
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        let fallback = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if fallback.isEmpty {
            return "未命名片段"
        }
        return String(fallback.prefix(24))
    }

    var displayText: String {
        String(content.prefix(240))
    }
}
