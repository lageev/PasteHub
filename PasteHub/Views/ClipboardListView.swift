import AppKit
import SwiftUI

private enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case file

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .file: return "文件"
        }
    }

    var icon: String {
        switch self {
        case .all: return "square.stack.3d.up"
        case .text: return "doc.text"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return item.type == .text
        case .image: return item.type == .image
        case .file: return item.type == .file
        }
    }
}

struct ClipboardListView: View {
    let store: ClipboardStore
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardFilter = .all

    private var filteredItems: [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.items.filter {
            selectedFilter.matches($0)
            && (
                query.isEmpty
                || $0.displayText.localizedCaseInsensitiveContains(query)
                || ($0.sourceApp?.localizedCaseInsensitiveContains(query) ?? false)
            )
        }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                headerBar
                searchBar
                filterBar
                contentArea
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 560)
    }

    private var contentArea: some View {
        Group {
            if filteredItems.isEmpty {
                EmptyStateCard()
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    let columns = waterfallColumns(from: filteredItems)
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0..<2, id: \.self) { col in
                            LazyVStack(spacing: 10) {
                                ForEach(columns[col]) { item in
                                    ClipboardCard(
                                        item: item,
                                        onCopy: { store.copyToClipboard(item) },
                                        onDelete: { store.remove(item) }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .animation(.easeInOut(duration: 0.16), value: filteredItems.count)
    }

    private func waterfallColumns(from items: [ClipboardItem]) -> [[ClipboardItem]] {
        var columns: [[ClipboardItem]] = [[], []]
        var heights: [CGFloat] = [0, 0]
        for item in items {
            let col = heights[0] <= heights[1] ? 0 : 1
            columns[col].append(item)
            heights[col] += estimatedHeight(for: item)
        }
        return columns
    }

    private func estimatedHeight(for item: ClipboardItem) -> CGFloat {
        switch item.type {
        case .image: return 200
        case .file: return 100
        case .text:
            let len = item.displayText.count
            if len > 100 { return 150 }
            if len > 40 { return 120 }
            return 90
        }
    }

    private var headerBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PASTEHUB")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text("Clipboard Flow")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            Spacer()

            HStack(spacing: 10) {
                Text("\(store.items.count) 条")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.18), in: Capsule())

                Button("清空", role: .destructive) {
                    store.clearAll()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索内容或来源应用", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.85),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(ClipboardFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(filter.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(selectedFilter == filter ? .white : .primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        selectedFilter == filter ? Color.accentColor : Color.secondary.opacity(0.12),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }
}

private struct EmptyStateCard: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text("暂无匹配记录")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("复制文本、图片或文件后会自动出现在这里")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(28)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.72),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct ClipboardCard: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onDelete: () -> Void
    @State private var isHovering = false
    @State private var isPressing = false

    private var accent: Color {
        switch item.type {
        case .text: return Color(red: 0.20, green: 0.78, blue: 0.76)
        case .image: return Color(red: 0.34, green: 0.68, blue: 1.00)
        case .file: return Color(red: 0.96, green: 0.69, blue: 0.26)
        }
    }

    private var previewImage: NSImage? {
        guard item.type == .image, let url = item.contentURL else { return nil }
        let key = url as NSURL
        if let cached = ImagePreviewCache.shared.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        ImagePreviewCache.shared.setObject(image, forKey: key)
        return image
    }

    private var sourceAppIcon: NSImage? {
        guard let appName = item.sourceApp, !appName.isEmpty else { return nil }
        let key = appName as NSString
        if let cached = AppIconCache.shared.object(forKey: key) {
            return cached
        }

        if let bundleID = item.sourceBundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: appURL.path)
            icon.size = NSSize(width: 14, height: 14)
            AppIconCache.shared.setObject(icon, forKey: key)
            return icon
        }

        if let runningIcon = NSWorkspace.shared.runningApplications.first(where: { app in
            app.localizedName == appName
        })?.icon {
            runningIcon.size = NSSize(width: 14, height: 14)
            AppIconCache.shared.setObject(runningIcon, forKey: key)
            return runningIcon
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: item.type.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(item.type.label)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accent.opacity(0.15), in: Capsule())

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(CardIconButtonStyle(tint: accent))

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(CardIconButtonStyle(tint: .pink))
                }
                .opacity(isHovering ? 1 : 0)
            }

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            Text(item.displayText)
                .lineLimit(item.type == .text ? 6 : 2)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(ClipboardTimeFormatter.shared.string(from: item.timestamp))
                    .font(.system(size: 10, weight: .medium, design: .rounded))

                if let app = item.sourceApp, !app.isEmpty {
                    Spacer()
                    HStack(spacing: 4) {
                        if let sourceAppIcon {
                            Image(nsImage: sourceAppIcon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        }
                        Text(app)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(isPressing ? 0.08 : 0))
        )
        .scaleEffect(isPressing ? 0.988 : 1)
        .onTapGesture(count: 2, perform: onCopy)
        .contextMenu {
            Button("重新复制", action: onCopy)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 14, pressing: { pressing in
            withAnimation(.easeOut(duration: 0.12)) {
                isPressing = pressing
            }
        }, perform: {})
    }
}

private struct CardIconButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(tint.opacity(configuration.isPressed ? 0.95 : 0.78), in: Circle())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}

private enum ImagePreviewCache {
    static let shared: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 120
        return cache
    }()
}

private enum AppIconCache {
    static let shared: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 80
        return cache
    }()
}

private enum ClipboardTimeFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
