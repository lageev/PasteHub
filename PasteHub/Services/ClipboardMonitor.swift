import AppKit

@MainActor
final class ClipboardMonitor {
    private var task: Task<Void, Never>?
    private var lastChangeCount: Int = 0
    private let store: ClipboardStore
    private let settings: SettingsManager
    private let pasteboard = NSPasteboard.general
    private let pollInterval: Duration = .milliseconds(400)

    init(store: ClipboardStore, settings: SettingsManager) {
        self.store = store
        self.settings = settings
        lastChangeCount = pasteboard.changeCount
    }
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.checkClipboard()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func syncChangeCount() {
        lastChangeCount = pasteboard.changeCount
    }

    // MARK: - Private

    private func checkClipboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let sourceBundleIdentifier = frontmostApp?.bundleIdentifier

        if settings.isAppExcluded(bundleIdentifier: sourceBundleIdentifier) { return }

        let sourceApp = frontmostApp?.localizedName
        let types = pasteboard.types ?? []

        // 1) 文件 URL
        if types.contains(.fileURL),
           let urls = pasteboard.readObjects(
               forClasses: [NSURL.self],
               options: [.urlReadingFileURLsOnly: true]
           ) as? [URL], !urls.isEmpty {
            for url in urls {
                store.add(
                    ClipboardItem(
                        type: .file,
                        content: url.absoluteString,
                        sourceApp: sourceApp,
                        sourceBundleIdentifier: sourceBundleIdentifier
                    )
                )
            }
            return
        }

        // 2) 图片
        if types.contains(.tiff) || types.contains(.png) {
            if let data = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
               let bitmap = NSBitmapImageRep(data: data),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
               let filename = UUID().uuidString + ".png"
                let fileURL = store.imagesDirectory.appendingPathComponent(filename)
                try? pngData.write(to: fileURL)
                store.add(
                    ClipboardItem(
                        type: .image,
                        content: fileURL.absoluteString,
                        sourceApp: sourceApp,
                        sourceBundleIdentifier: sourceBundleIdentifier
                    )
                )
                return
            }
        }

        // 3) 纯文本
        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            store.add(
                ClipboardItem(
                    type: .text,
                    content: string,
                    sourceApp: sourceApp,
                    sourceBundleIdentifier: sourceBundleIdentifier
                )
            )
        }
    }
}
