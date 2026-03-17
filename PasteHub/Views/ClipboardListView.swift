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
    @Bindable var settings: SettingsManager
    let onOpenSettings: (() -> Void)?
    let onActivateItem: ((ClipboardItem) -> Void)?
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var selectedTag: String?
    @State private var isSnippetMode = false
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var tagEditorItem: ClipboardItem?
    @State private var isSnippetEditorPresented = false
    @State private var editingSnippet: SnippetItem?

    init(
        store: ClipboardStore,
        settings: SettingsManager,
        onOpenSettings: (() -> Void)? = nil,
        onActivateItem: ((ClipboardItem) -> Void)? = nil
    ) {
        self.store = store
        self.settings = settings
        self.onOpenSettings = onOpenSettings
        self.onActivateItem = onActivateItem
    }

    private var useHorizontalWaterfall: Bool {
        settings.panelEdge == .top || settings.panelEdge == .bottom
    }

    private var chromeMaxWidth: CGFloat {
        useHorizontalWaterfall ? 1180 : .infinity
    }

    private var contentSpacing: CGFloat {
        useHorizontalWaterfall ? 12 : 14
    }

    private var verticalPadding: CGFloat {
        useHorizontalWaterfall ? 8 : 16
    }

    private let horizontalCardWidth: CGFloat = 260
    private let horizontalCardHeight: CGFloat = 170
    private let horizontalSnippetWidth: CGFloat = 300
    private let horizontalSnippetHeight: CGFloat = 170
    private let horizontalScrollerGap: CGFloat = 8
    private let panelCornerRadius: CGFloat = 18

    private var minPanelHeight: CGFloat {
        useHorizontalWaterfall ? 260 : 560
    }

    private var queryText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var availableTags: [String] {
        let historyTags = store.items.flatMap(\.tags)
        let snippetTags = store.snippets.flatMap(\.tags)
        return Array(Set(historyTags + snippetTags))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var filteredItems: [ClipboardItem] {
        return store.items.filter { item in
            selectedFilter.matches(item)
            && (selectedTag.map { item.tags.contains($0) } ?? true)
            && (
                queryText.isEmpty
                || item.displayText.localizedCaseInsensitiveContains(queryText)
                || (item.sourceApp?.localizedCaseInsensitiveContains(queryText) ?? false)
                || item.tags.contains(where: { $0.localizedCaseInsensitiveContains(queryText) })
            )
        }
    }

    private var filteredSnippets: [SnippetItem] {
        store.snippets.filter { snippet in
            (selectedTag.map { snippet.tags.contains($0) } ?? true)
            && (
                queryText.isEmpty
                || snippet.displayTitle.localizedCaseInsensitiveContains(queryText)
                || snippet.content.localizedCaseInsensitiveContains(queryText)
                || snippet.tags.contains(where: { $0.localizedCaseInsensitiveContains(queryText) })
            )
        }
    }

    var body: some View {
        ZStack {
            panelBackground

            VStack(spacing: contentSpacing) {
                controlArea
                contentArea
            }
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
        }
        .frame(minWidth: 480, minHeight: minPanelHeight)
        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        .sheet(item: $tagEditorItem) { item in
            TagEditorSheet(
                initialTags: item.tags,
                onSave: { tags in
                    store.setTags(for: item.id, tags: tags)
                }
            )
        }
        .sheet(isPresented: $isSnippetEditorPresented, onDismiss: {
            editingSnippet = nil
        }) {
            SnippetEditorSheet(
                title: editingSnippet == nil ? "新建常用片段" : "编辑常用片段",
                initialTitle: editingSnippet?.title ?? "",
                initialContent: editingSnippet?.content ?? "",
                initialTags: editingSnippet?.tags ?? [],
                onSave: { title, content, tags in
                    saveSnippet(title: title, content: content, tags: tags)
                    editingSnippet = nil
                    isSnippetEditorPresented = false
                }
            )
        }
        .onChange(of: availableTags) { _, tags in
            if let selectedTag, !tags.contains(selectedTag) {
                self.selectedTag = nil
            }
        }
    }

    private var panelBackground: some View {
        Rectangle()
            .fill(.clear)
            .glassEffect(.regular, in: Rectangle())
            .ignoresSafeArea()
    }

    private var contentArea: some View {
        Group {
            if isSnippetMode {
                snippetContentArea
            } else {
                historyContentArea
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isSnippetMode ? filteredSnippets.count : filteredItems.count)
    }

    private var historyContentArea: some View {
        Group {
            if filteredItems.isEmpty {
                EmptyStateCard()
                    .frame(maxHeight: .infinity)
            } else if useHorizontalWaterfall {
                horizontalWaterfallContent
            } else {
                verticalWaterfallContent
            }
        }
    }

    private var snippetContentArea: some View {
        Group {
            if filteredSnippets.isEmpty {
                EmptyStateCard(
                    icon: "bookmark",
                    title: "暂无常用片段",
                    subtitle: "可保存地址、账号、代码片段等，单击即可快速使用"
                )
                .frame(maxHeight: .infinity)
            } else if useHorizontalWaterfall {
                horizontalSnippetContent
            } else {
                verticalSnippetContent
            }
        }
    }

    private var controlArea: some View {
        VStack(spacing: useHorizontalWaterfall ? 6 : 10) {
            if useHorizontalWaterfall {
                horizontalControlRow
            } else {
                sideControlRows
            }
            if !availableTags.isEmpty {
                tagFilterRow
            }
        }
        .frame(maxWidth: chromeMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var horizontalControlRow: some View {
        HStack(spacing: 8) {
            searchControl
            modeToggleButton
            if isSnippetMode {
                snippetAddButton
            } else {
                filterChips
            }
            statusBadge
            if !isSnippetMode {
                clearButton
            }
            settingsButton
        }
    }

    private var sideControlRows: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                searchControl
                modeToggleButton
                if isSnippetMode {
                    snippetAddButton
                } else {
                    filterChips
                }
                Spacer(minLength: 6)
            }

            HStack(spacing: 10) {
                Spacer(minLength: 6)
                statusBadge
                if !isSnippetMode {
                    clearButton
                }
                settingsButton
            }
        }
    }

    private var searchControl: some View {
        Group {
            if isSearchExpanded || !searchText.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("搜索内容、标签或来源应用", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .focused($isSearchFocused)

                    Button {
                        if !searchText.isEmpty {
                            searchText = ""
                        } else {
                            withAnimation(.easeInOut(duration: 0.14)) {
                                isSearchExpanded = false
                            }
                            isSearchFocused = false
                        }
                    } label: {
                        Image(systemName: searchText.isEmpty ? "chevron.left.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, useHorizontalWaterfall ? 8 : 10)
                .frame(width: useHorizontalWaterfall ? 260 : 220)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.14)) {
                        isSearchExpanded = true
                    }
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: useHorizontalWaterfall ? 30 : 34, height: useHorizontalWaterfall ? 30 : 34)
                        .background(
                            Color(nsColor: .controlBackgroundColor).opacity(0.85),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isSearchExpanded)
    }

    private var verticalWaterfallContent: some View {
        ScrollView {
            let columns = waterfallColumns(from: filteredItems)
            HStack(alignment: .top, spacing: 10) {
                ForEach(0..<2, id: \.self) { col in
                    LazyVStack(spacing: 10) {
                        ForEach(columns[col]) { item in
                            ClipboardCard(
                                item: item,
                                onPrimaryAction: { activateClipboardItem(item) },
                                onCopy: { store.copyToClipboard(item) },
                                onDelete: { store.remove(item) },
                                onManageTags: { tagEditorItem = item },
                                onSaveAsSnippet: { quickSaveAsSnippet(item) }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var horizontalWaterfallContent: some View {
        HorizontalWheelScrollView(indicatorBottomInset: horizontalScrollerGap) {
            LazyHStack(alignment: .top, spacing: 8) {
                ForEach(filteredItems) { item in
                    ClipboardCard(
                        item: item,
                        onPrimaryAction: { activateClipboardItem(item) },
                        onCopy: { store.copyToClipboard(item) },
                        onDelete: { store.remove(item) },
                        onManageTags: { tagEditorItem = item },
                        onSaveAsSnippet: { quickSaveAsSnippet(item) },
                        preferredWidth: horizontalCardWidth,
                        preferredHeight: horizontalCardHeight,
                        compactStyle: true
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: horizontalCardHeight + horizontalScrollerGap + 8)
    }

    private var verticalSnippetContent: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(filteredSnippets) { snippet in
                    SnippetCard(
                        snippet: snippet,
                        onPrimaryAction: { activateSnippet(snippet) },
                        onCopy: { store.copySnippetToClipboard(snippet) },
                        onEdit: { beginEditSnippet(snippet) },
                        onDelete: { store.removeSnippet(snippet) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var horizontalSnippetContent: some View {
        HorizontalWheelScrollView(indicatorBottomInset: horizontalScrollerGap) {
            LazyHStack(alignment: .top, spacing: 8) {
                ForEach(filteredSnippets) { snippet in
                    SnippetCard(
                        snippet: snippet,
                        onPrimaryAction: { activateSnippet(snippet) },
                        onCopy: { store.copySnippetToClipboard(snippet) },
                        onEdit: { beginEditSnippet(snippet) },
                        onDelete: { store.removeSnippet(snippet) },
                        preferredWidth: horizontalSnippetWidth,
                        preferredHeight: horizontalSnippetHeight,
                        compactStyle: true
                    )
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: horizontalSnippetHeight + horizontalScrollerGap + 8)
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

    private var filterChips: some View {
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
        }
    }

    private var modeToggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                isSnippetMode.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bookmark")
                    .font(.system(size: 12, weight: .semibold))
                Text("常用片段")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSnippetMode ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                isSnippetMode ? Color.accentColor : Color.secondary.opacity(0.12),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    selectedTag = nil
                } label: {
                    Text("全部标签")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selectedTag == nil ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            selectedTag == nil ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)

                ForEach(availableTags, id: \.self) { tag in
                    Button {
                        selectedTag = selectedTag == tag ? nil : tag
                    } label: {
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedTag == tag ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                selectedTag == tag ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var statusBadge: some View {
        Text(isSnippetMode ? "\(store.snippets.count) 条片段" : "\(store.items.count) 条")
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.18), in: Capsule())
    }

    private var snippetAddButton: some View {
        Button {
            beginAddSnippet()
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("新增常用片段")
    }

    private var clearButton: some View {
        Button("清空", role: .destructive) {
            store.clearAll()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private func beginAddSnippet() {
        editingSnippet = nil
        isSnippetEditorPresented = true
    }

    private func beginEditSnippet(_ snippet: SnippetItem) {
        editingSnippet = snippet
        isSnippetEditorPresented = true
    }

    private func saveSnippet(title: String, content: String, tags: [String]) {
        if let editingSnippet {
            store.updateSnippet(
                SnippetItem(
                    id: editingSnippet.id,
                    title: title,
                    content: content,
                    tags: tags,
                    timestamp: editingSnippet.timestamp
                )
            )
            return
        }
        store.addSnippet(title: title, content: content, tags: tags)
    }

    private func quickSaveAsSnippet(_ item: ClipboardItem) {
        guard item.type == .text else { return }
        store.addSnippet(title: "", content: item.content, tags: item.tags)
        isSnippetMode = true
    }

    private func activateClipboardItem(_ item: ClipboardItem) {
        if let onActivateItem {
            onActivateItem(item)
            return
        }
        store.copyToClipboard(item)
    }

    private func activateSnippet(_ snippet: SnippetItem) {
        if let onActivateItem {
            onActivateItem(
                ClipboardItem(
                    type: .text,
                    content: snippet.content,
                    tags: snippet.tags
                )
            )
            return
        }
        store.copySnippetToClipboard(snippet)
    }

    private var settingsButton: some View {
        Button {
            onOpenSettings?()
        } label: {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("打开设置")
    }
}

private struct HorizontalWheelScrollView<Content: View>: NSViewRepresentable {
    let indicatorBottomInset: CGFloat
    let content: Content

    init(
        indicatorBottomInset: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.indicatorBottomInset = indicatorBottomInset
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rootView: content)
    }

    func makeNSView(context: Context) -> WheelEnabledHorizontalScrollView {
        let scrollView = WheelEnabledHorizontalScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: indicatorBottomInset,
            right: 0
        )

        let hostingView = context.coordinator.hostingView
        scrollView.documentView = hostingView
        scrollView.onLayout = { [weak scrollView, weak hostingView] in
            guard let scrollView, let hostingView else { return }
            Self.syncDocumentFrame(scrollView: scrollView, hostingView: hostingView)
        }
        Self.syncDocumentFrame(scrollView: scrollView, hostingView: hostingView)
        return scrollView
    }

    func updateNSView(_ scrollView: WheelEnabledHorizontalScrollView, context: Context) {
        let hostingView = context.coordinator.hostingView
        hostingView.rootView = content
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: indicatorBottomInset,
            right: 0
        )
        Self.syncDocumentFrame(scrollView: scrollView, hostingView: hostingView)
    }

    private static func syncDocumentFrame(
        scrollView: NSScrollView,
        hostingView: NSHostingView<Content>
    ) {
        let fit = hostingView.fittingSize
        let clipBounds = scrollView.contentView.bounds
        let targetSize = NSSize(
            width: max(fit.width, clipBounds.width),
            height: max(fit.height, clipBounds.height)
        )
        if hostingView.frame.size != targetSize {
            hostingView.frame = NSRect(origin: .zero, size: targetSize)
        }
    }

    final class Coordinator {
        let hostingView: NSHostingView<Content>

        init(rootView: Content) {
            hostingView = NSHostingView(rootView: rootView)
        }
    }
}

private final class WheelEnabledHorizontalScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    private var isLayoutCallbackScheduled = false

    override func layout() {
        super.layout()
        guard !isLayoutCallbackScheduled else { return }
        isLayoutCallbackScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLayoutCallbackScheduled = false
            self.onLayout?()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontalDelta = abs(event.scrollingDeltaX)
        let verticalDelta = abs(event.scrollingDeltaY)

        if horizontalDelta < 0.1, verticalDelta > 0.1 {
            guard let documentView else {
                super.scrollWheel(with: event)
                return
            }
            let maxOffsetX = max(documentView.frame.width - contentView.bounds.width, 0)
            guard maxOffsetX > 0 else {
                super.scrollWheel(with: event)
                return
            }

            let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
            let delta = event.scrollingDeltaY * multiplier
            let targetOffsetX = min(max(contentView.bounds.origin.x - delta, 0), maxOffsetX)
            contentView.scroll(to: NSPoint(x: targetOffsetX, y: 0))
            reflectScrolledClipView(contentView)
            return
        }

        super.scrollWheel(with: event)
    }
}

private struct EmptyStateCard: View {
    let icon: String
    let title: String
    let subtitle: String

    init(
        icon: String = "tray",
        title: String = "暂无匹配记录",
        subtitle: String = "复制文本、图片或文件后会自动出现在这里"
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(subtitle)
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
    let onPrimaryAction: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onManageTags: () -> Void
    let onSaveAsSnippet: () -> Void
    let preferredWidth: CGFloat?
    let preferredHeight: CGFloat?
    let compactStyle: Bool
    @State private var isHovering = false
    @State private var isPressing = false

    init(
        item: ClipboardItem,
        onPrimaryAction: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onManageTags: @escaping () -> Void,
        onSaveAsSnippet: @escaping () -> Void,
        preferredWidth: CGFloat? = nil,
        preferredHeight: CGFloat? = nil,
        compactStyle: Bool = false
    ) {
        self.item = item
        self.onPrimaryAction = onPrimaryAction
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.onManageTags = onManageTags
        self.onSaveAsSnippet = onSaveAsSnippet
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.compactStyle = compactStyle
    }

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
                if compactStyle {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            Text(item.displayText)
                .lineLimit(item.type == .text ? (compactStyle ? 3 : 6) : 2)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            if !item.tags.isEmpty {
                TagStripView(tags: item.tags, compactStyle: compactStyle)
            }

            if compactStyle {
                Spacer(minLength: 0)
            }

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
        .padding(compactStyle ? 8 : 10)
        .frame(width: preferredWidth, height: preferredHeight, alignment: .topLeading)
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
        .onTapGesture(perform: onPrimaryAction)
        .contextMenu {
            Button("完成键入", action: onPrimaryAction)
            Button("重新复制", action: onCopy)
            Button("编辑标签", action: onManageTags)
            if item.type == .text {
                Button("添加到常用片段", action: onSaveAsSnippet)
            }
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

private struct SnippetCard: View {
    let snippet: SnippetItem
    let onPrimaryAction: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let preferredWidth: CGFloat?
    let preferredHeight: CGFloat?
    let compactStyle: Bool
    @State private var isHovering = false
    @State private var isPressing = false

    init(
        snippet: SnippetItem,
        onPrimaryAction: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        preferredWidth: CGFloat? = nil,
        preferredHeight: CGFloat? = nil,
        compactStyle: Bool = false
    ) {
        self.snippet = snippet
        self.onPrimaryAction = onPrimaryAction
        self.onCopy = onCopy
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.compactStyle = compactStyle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("片段", systemImage: "bookmark.fill")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())

                Spacer()

                HStack(spacing: 6) {
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(CardIconButtonStyle(tint: Color.accentColor))

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(CardIconButtonStyle(tint: .orange))

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(CardIconButtonStyle(tint: .pink))
                }
                .opacity(isHovering ? 1 : 0)
            }

            Text(snippet.displayTitle)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(snippet.displayText)
                .lineLimit(compactStyle ? 5 : 8)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            if !snippet.tags.isEmpty {
                TagStripView(tags: snippet.tags, compactStyle: compactStyle)
            }

            if compactStyle {
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(ClipboardTimeFormatter.shared.string(from: snippet.timestamp))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
        }
        .padding(compactStyle ? 8 : 10)
        .frame(width: preferredWidth, height: preferredHeight, alignment: .topLeading)
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
        .onTapGesture(perform: onPrimaryAction)
        .contextMenu {
            Button("完成键入", action: onPrimaryAction)
            Button("重新复制", action: onCopy)
            Button("编辑片段", action: onEdit)
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

private struct TagStripView: View {
    let tags: [String]
    let compactStyle: Bool

    var body: some View {
        let limit = compactStyle ? 2 : 4
        let visibleTags = Array(tags.prefix(limit))
        HStack(spacing: 5) {
            ForEach(visibleTags, id: \.self) { tag in
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.14), in: Capsule())
            }
            if tags.count > limit {
                Text("+\(tags.count - limit)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TagEditorSheet: View {
    let initialTags: [String]
    let onSave: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tagsInput: String

    init(initialTags: [String], onSave: @escaping ([String]) -> Void) {
        self.initialTags = initialTags
        self.onSave = onSave
        _tagsInput = State(initialValue: TagParser.format(initialTags))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("编辑标签")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            TextField("多个标签可用逗号分隔", text: $tagsInput)
                .textFieldStyle(.roundedBorder)

            Text("示例：账号, 公司, 常用")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(TagParser.parse(tagsInput))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

private struct SnippetEditorSheet: View {
    let title: String
    let initialTitle: String
    let initialContent: String
    let initialTags: [String]
    let onSave: (String, String, [String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var titleInput: String
    @State private var contentInput: String
    @State private var tagsInput: String

    init(
        title: String,
        initialTitle: String,
        initialContent: String,
        initialTags: [String],
        onSave: @escaping (String, String, [String]) -> Void
    ) {
        self.title = title
        self.initialTitle = initialTitle
        self.initialContent = initialContent
        self.initialTags = initialTags
        self.onSave = onSave
        _titleInput = State(initialValue: initialTitle)
        _contentInput = State(initialValue: initialContent)
        _tagsInput = State(initialValue: TagParser.format(initialTags))
    }

    private var canSave: Bool {
        !contentInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            TextField("标题（可选）", text: $titleInput)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $contentInput)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .frame(height: 180)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
                )

            TextField("标签（可选，逗号分隔）", text: $tagsInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    onSave(titleInput, contentInput, TagParser.parse(tagsInput))
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

private enum TagParser {
    static func parse(_ raw: String) -> [String] {
        var set = Set<String>()
        var result: [String] = []
        let parts = raw.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
        for part in parts {
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if !set.contains(value) {
                set.insert(value)
                result.append(value)
            }
        }
        return result
    }

    static func format(_ tags: [String]) -> String {
        tags.joined(separator: ", ")
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
