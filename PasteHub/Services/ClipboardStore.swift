import Foundation
import AppKit
import Observation

@MainActor
@Observable
final class ClipboardStore {
    private(set) var items: [ClipboardItem] = []

    var maxItems: Int {
        let v = UserDefaults.standard.integer(forKey: "maxHistoryCount")
        return v > 0 ? v : 50
    }

    let imagesDirectory: URL
    var onClipboardWrite: (() -> Void)?

    private let storageURL: URL
    private let maxTextLength = 20_000

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("PasteHub")
        storageURL = appDir.appendingPathComponent("history.json")
        imagesDirectory = appDir.appendingPathComponent("Images")

        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        load()
        pruneOrphanedImages()
    }

    // MARK: - Public

    func add(_ item: ClipboardItem) {
        let normalized = normalizedItem(item)

        if let first = items.first,
           first.type == normalized.type,
           first.content == normalized.content {
            return
        }

        if let existingIndex = items.firstIndex(where: {
            $0.type == normalized.type && $0.content == normalized.content
        }) {
            items.remove(at: existingIndex)
        }

        items.insert(normalized, at: 0)
        trimExcessItems()
        save()
    }

    func remove(_ item: ClipboardItem) {
        let removed = items.filter { $0.id == item.id }
        items.removeAll { $0.id == item.id }
        cleanupImages(for: removed)
        save()
    }

    func clearAll() {
        cleanupImages(for: items)
        items.removeAll()
        save()
    }

    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case .text:
            pasteboard.setString(item.content, forType: .string)
        case .image:
            if let url = item.contentURL,
               let image = NSImage(contentsOf: url) {
                pasteboard.writeObjects([image])
            }
        case .file:
            if let url = item.contentURL {
                pasteboard.writeObjects([url as NSURL])
            }
        }

        onClipboardWrite?()
    }

    // MARK: - Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? decoder.decode([ClipboardItem].self, from: data) else { return }
        items = Array(decoded.prefix(maxItems))
    }

    private func cleanupImages(for removedItems: [ClipboardItem]) {
        for item in removedItems where item.type == .image {
            if let url = item.contentURL,
               url.isFileURL,
               url.path.hasPrefix(imagesDirectory.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func trimExcessItems() {
        guard items.count > maxItems else { return }
        let removed = Array(items[maxItems...])
        items = Array(items.prefix(maxItems))
        cleanupImages(for: removed)
    }

    private func normalizedItem(_ item: ClipboardItem) -> ClipboardItem {
        guard item.type == .text, item.content.count > maxTextLength else { return item }
        let shortened = String(item.content.prefix(maxTextLength))
        return ClipboardItem(
            id: item.id,
            type: item.type,
            content: shortened,
            timestamp: item.timestamp,
            sourceApp: item.sourceApp,
            sourceBundleIdentifier: item.sourceBundleIdentifier
        )
    }

    private func pruneOrphanedImages() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        let referenced = Set(
            items.compactMap { item -> URL? in
                guard item.type == .image,
                      let url = item.contentURL,
                      url.isFileURL,
                      url.path.hasPrefix(imagesDirectory.path) else {
                    return nil
                }
                return url.standardizedFileURL
            }
        )

        for file in files {
            let normalized = file.standardizedFileURL
            if !referenced.contains(normalized) {
                try? FileManager.default.removeItem(at: normalized)
            }
        }
    }
}
