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
        case .image: return item.isImageLikeItem
        case .file: return item.type == .file
        }
    }
}

struct ClipboardListView: View {
    private enum SelectionDirection: String {
        case left
        case right
        case up
        case down

        var sequentialStep: Int {
            switch self {
            case .left, .up:
                return -1
            case .right, .down:
                return 1
            }
        }
    }

    let store: ClipboardStore
    @Bindable var settings: SettingsManager
    let onOpenSettings: (() -> Void)?
    let onActivateItem: ((ClipboardItem) -> Void)?
    @State private var searchText = ""
    @State private var selectedFilter: ClipboardFilter = .all
    @State private var selectedHistoryTag: String?
    @State private var selectedSnippetTag: String?
    @State private var isSnippetMode = false
    @State private var isSearchExpanded = false
    @FocusState private var isSearchFocused: Bool
    @State private var tagEditorItem: ClipboardItem?
    @State private var isSnippetEditorPresented = false
    @State private var editingSnippet: SnippetItem?
    @State private var tokenSelectionItem: ClipboardItem?
    @State private var isClearConfirmationPresented = false
    @State private var selectedHistoryItemID: UUID?
    @State private var selectedSnippetItemID: UUID?
    @State private var isCommandModifierPressed = false
    @State private var visibleHistoryItemIDs: Set<UUID> = []
    @State private var visibleSnippetItemIDs: Set<UUID> = []
    @State private var horizontalHistoryViewportRangeX: ClosedRange<CGFloat>?
    @State private var horizontalSnippetViewportRangeX: ClosedRange<CGFloat>?
    @State private var localKeyDownMonitor: Any?
    @State private var localFlagsChangedMonitor: Any?

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

    private var isCompactMode: Bool {
        settings.compactModeEnabled
    }

    private var useHorizontalWaterfall: Bool {
        !isCompactMode && (settings.panelEdge == .top || settings.panelEdge == .bottom)
    }

    private var isHistoryWaterfallLayout: Bool {
        !isSnippetMode && !useHorizontalWaterfall && !(isCompactMode && usesCompactLinearList)
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
    private let compactPanelWidth: CGFloat = CompactPanelLayout.width
    private var compactDensity: CompactDensity {
        settings.compactDensity
    }

    private var compactGridSpacing: CGFloat {
        switch compactDensity {
        case .low: return 8
        case .medium: return 7
        case .high: return 6
        }
    }

    private var compactColumnWidth: CGFloat {
        switch compactDensity {
        case .low: return 172
        case .medium: return 168
        case .high: return 162
        }
    }

    private var compactImageCardSize: CGFloat {
        switch compactDensity {
        case .low: return 172
        case .medium: return 154
        case .high: return 138
        }
    }

    private var compactBodySpacing: CGFloat {
        switch compactDensity {
        case .low: return 12
        case .medium: return 10
        case .high: return 8
        }
    }

    private var compactHeaderSpacing: CGFloat {
        switch compactDensity {
        case .low: return 10
        case .medium: return 8
        case .high: return 6
        }
    }

    private var compactPanelHorizontalPadding: CGFloat {
        switch compactDensity {
        case .low: return 14
        case .medium: return 12
        case .high: return 10
        }
    }

    private var compactPanelVerticalPadding: CGFloat {
        switch compactDensity {
        case .low: return 14
        case .medium: return 12
        case .high: return 10
        }
    }

    private var compactControlFontSize: CGFloat {
        switch compactDensity {
        case .low: return 10
        case .medium: return 9.5
        case .high: return 9
        }
    }

    private var compactSearchFieldWidth: CGFloat {
        switch compactDensity {
        case .low: return 142
        case .medium: return 132
        case .high: return 122
        }
    }

    private var compactSearchIconSide: CGFloat {
        switch compactDensity {
        case .low: return 30
        case .medium: return 28
        case .high: return 26
        }
    }
    private static let quickShortcutKeys: [String] = {
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        let letters = (0..<26).compactMap { index in
            UnicodeScalar(65 + index).map { String(Character($0)) }
        }
        return digits + letters
    }()
    private var compactSnippetCardWidth: CGFloat { compactPanelWidth - compactPanelHorizontalPadding * 2 }
    private var usesCompactLinearList: Bool { compactDensity != .low }
    private var isHighDensityPointerCompactMode: Bool {
        isCompactMode
        && compactDensity == .high
        && settings.compactPanelPosition == .followMouse
    }
    private let highDensityPointerPageLimit = CompactPanelLayout.highDensityPointerRowsPerPage

    private var compactDisplayedHistoryItems: [ClipboardItem] {
        if isHighDensityPointerCompactMode {
            return Array(filteredItems.prefix(highDensityPointerPageLimit))
        }
        return filteredItems
    }

    private var compactDisplayedSnippets: [SnippetItem] {
        if isHighDensityPointerCompactMode {
            return Array(filteredSnippets.prefix(highDensityPointerPageLimit))
        }
        return filteredSnippets
    }

    private var horizontalHistoryContentHeight: CGFloat {
        horizontalCardHeight + horizontalScrollerGap + 8
    }

    private var horizontalSnippetContentHeight: CGFloat {
        horizontalSnippetHeight + horizontalScrollerGap + 8
    }

    private var minPanelHeight: CGFloat {
        useHorizontalWaterfall ? 260 : 560
    }

    private var queryText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var availableHistoryTags: [String] {
        let tags = store.items.flatMap(\.tags)
        return Array(Set(tags))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var availableSnippetTags: [String] {
        let tags = store.snippets.flatMap(\.tags)
        return Array(Set(tags))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var availableTags: [String] {
        isSnippetMode ? availableSnippetTags : availableHistoryTags
    }

    private var filteredItems: [ClipboardItem] {
        return store.items.filter { item in
            selectedFilter.matches(item)
            && (selectedHistoryTag.map { item.tags.contains($0) } ?? true)
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
            (selectedSnippetTag.map { snippet.tags.contains($0) } ?? true)
            && (
                queryText.isEmpty
                || snippet.displayTitle.localizedCaseInsensitiveContains(queryText)
                || snippet.content.localizedCaseInsensitiveContains(queryText)
                || snippet.tags.contains(where: { $0.localizedCaseInsensitiveContains(queryText) })
            )
        }
    }

    private var visibleHistoryItems: [ClipboardItem] {
        filteredItems.filter { visibleHistoryItemIDs.contains($0.id) }
    }

    private var visibleSnippetItems: [SnippetItem] {
        filteredSnippets.filter { visibleSnippetItemIDs.contains($0.id) }
    }

    private var horizontalVisibleHistoryItems: [ClipboardItem] {
        guard let visibleRange = horizontalHistoryViewportRangeX else { return [] }
        let itemStride = horizontalCardWidth + 8
        return filteredItems.enumerated().compactMap { index, item in
            let minX = CGFloat(index) * itemStride
            let maxX = minX + horizontalCardWidth
            return maxX > visibleRange.lowerBound && minX < visibleRange.upperBound ? item : nil
        }
    }

    private var horizontalVisibleSnippetItems: [SnippetItem] {
        guard let visibleRange = horizontalSnippetViewportRangeX else { return [] }
        let itemStride = horizontalSnippetWidth + 8
        return filteredSnippets.enumerated().compactMap { index, snippet in
            let minX = CGFloat(index) * itemStride
            let maxX = minX + horizontalSnippetWidth
            return maxX > visibleRange.lowerBound && minX < visibleRange.upperBound ? snippet : nil
        }
    }

    private var quickShortcutCapacity: Int {
        Self.quickShortcutKeys.count
    }

    private var quickSelectableHistoryItems: [ClipboardItem] {
        let sourceItems: [ClipboardItem]
        if useHorizontalWaterfall {
            sourceItems = horizontalVisibleHistoryItems
        } else if isHighDensityPointerCompactMode {
            sourceItems = compactDisplayedHistoryItems
        } else if isCompactMode && usesCompactLinearList {
            sourceItems = visibleHistoryItems.isEmpty ? compactDisplayedHistoryItems : visibleHistoryItems
        } else {
            sourceItems = visibleHistoryItems.isEmpty ? filteredItems : visibleHistoryItems
        }
        return Array(sourceItems.prefix(quickShortcutCapacity))
    }

    private var quickSelectableSnippets: [SnippetItem] {
        let sourceSnippets: [SnippetItem]
        if useHorizontalWaterfall {
            sourceSnippets = horizontalVisibleSnippetItems
        } else if isHighDensityPointerCompactMode {
            sourceSnippets = compactDisplayedSnippets
        } else if isCompactMode && usesCompactLinearList {
            sourceSnippets = visibleSnippetItems.isEmpty ? compactDisplayedSnippets : visibleSnippetItems
        } else {
            sourceSnippets = visibleSnippetItems.isEmpty ? filteredSnippets : visibleSnippetItems
        }
        return Array(sourceSnippets.prefix(quickShortcutCapacity))
    }

    private var firstVisibleHistoryItemID: UUID? {
        if useHorizontalWaterfall {
            return horizontalVisibleHistoryItems.first?.id
        }
        if isHighDensityPointerCompactMode {
            return compactDisplayedHistoryItems.first?.id
        }
        if isCompactMode && usesCompactLinearList {
            return (visibleHistoryItems.isEmpty ? compactDisplayedHistoryItems : visibleHistoryItems).first?.id
        }
        return (visibleHistoryItems.isEmpty ? filteredItems : visibleHistoryItems).first?.id
    }

    private var firstVisibleSnippetItemID: UUID? {
        if useHorizontalWaterfall {
            return horizontalVisibleSnippetItems.first?.id
        }
        if isHighDensityPointerCompactMode {
            return compactDisplayedSnippets.first?.id
        }
        if isCompactMode && usesCompactLinearList {
            return (visibleSnippetItems.isEmpty ? compactDisplayedSnippets : visibleSnippetItems).first?.id
        }
        return (visibleSnippetItems.isEmpty ? filteredSnippets : visibleSnippetItems).first?.id
    }

    private var historyQuickLabelsByID: [UUID: String] {
        guard isCommandModifierPressed else { return [:] }
        var labels: [UUID: String] = [:]
        for (index, item) in quickSelectableHistoryItems.enumerated() {
            labels[item.id] = "⌘\(Self.quickShortcutKeys[index])"
        }
        return labels
    }

    private var snippetQuickLabelsByID: [UUID: String] {
        guard isCommandModifierPressed else { return [:] }
        var labels: [UUID: String] = [:]
        for (index, snippet) in quickSelectableSnippets.enumerated() {
            labels[snippet.id] = "⌘\(Self.quickShortcutKeys[index])"
        }
        return labels
    }

    private var selectedHistoryIndex: Int? {
        guard let selectedHistoryItemID else { return nil }
        return filteredItems.firstIndex(where: { $0.id == selectedHistoryItemID })
    }

    private var selectedSnippetIndex: Int? {
        guard let selectedSnippetItemID else { return nil }
        return filteredSnippets.firstIndex(where: { $0.id == selectedSnippetItemID })
    }

    private var horizontalHistoryVisibleRangeX: ClosedRange<CGFloat>? {
        guard let selectedHistoryIndex else { return nil }
        let itemStride = horizontalCardWidth + 8
        let minX = CGFloat(selectedHistoryIndex) * itemStride
        return minX...(minX + horizontalCardWidth)
    }

    private var horizontalSnippetVisibleRangeX: ClosedRange<CGFloat>? {
        guard let selectedSnippetIndex else { return nil }
        let itemStride = horizontalSnippetWidth + 8
        let minX = CGFloat(selectedSnippetIndex) * itemStride
        return minX...(minX + horizontalSnippetWidth)
    }

    var body: some View {
        Group {
            if isCompactMode {
                compactModeBody
            } else {
                regularModeBody
            }
        }
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
        .sheet(item: $tokenSelectionItem) { item in
            TokenSelectionSheet(
                sourceText: item.content,
                onSubmit: { selectedText in
                    activateClipboardItem(
                        ClipboardItem(
                            type: .text,
                            content: selectedText,
                            sourceApp: item.sourceApp,
                            sourceBundleIdentifier: item.sourceBundleIdentifier,
                            tags: item.tags
                        )
                    )
                }
            )
        }
        .alert("确认清空历史记录？", isPresented: $isClearConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                store.clearAll()
            }
        } message: {
            Text("清空后不可恢复。")
        }
        .onChange(of: availableHistoryTags) { _, tags in
            if let selectedHistoryTag, !tags.contains(selectedHistoryTag) {
                self.selectedHistoryTag = nil
            }
        }
        .onChange(of: availableSnippetTags) { _, tags in
            if let selectedSnippetTag, !tags.contains(selectedSnippetTag) {
                self.selectedSnippetTag = nil
            }
        }
        .onChange(of: settings.compactModeEnabled) { _, isEnabled in
            if isEnabled {
                isSnippetMode = false
                selectedFilter = .all
                selectedHistoryTag = nil
                selectedSnippetTag = nil
                isSearchExpanded = false
            }
        }
        .onChange(of: isHighDensityPointerCompactMode) { _, isEnabled in
            if isEnabled {
                isSnippetMode = false
                selectedFilter = .all
                selectedHistoryTag = nil
                selectedSnippetTag = nil
                selectedHistoryItemID = nil
                selectedSnippetItemID = nil
                syncHighDensitySearchModeIfNeeded()
            }
        }
        .onChange(of: searchText) { _, _ in
            syncHighDensitySearchModeIfNeeded()
        }
        .onChange(of: filteredItems.map(\.id)) { _, _ in
            syncHighDensitySearchModeIfNeeded()
            syncSelectionIfNeeded()
            syncVisibleItemsIfNeeded()
        }
        .onChange(of: filteredSnippets.map(\.id)) { _, _ in
            syncHighDensitySearchModeIfNeeded()
            syncSelectionIfNeeded()
            syncVisibleItemsIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelDidHide)) { _ in
            searchText = ""
            isSearchExpanded = false
            isSearchFocused = false
            selectedHistoryItemID = nil
            selectedSnippetItemID = nil
            isCommandModifierPressed = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelSelectionMove)) { notification in
            guard let directionRaw = notification.userInfo?["direction"] as? String,
                  let direction = SelectionDirection(rawValue: directionRaw) else { return }
            moveSelection(direction: direction)
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelSelectionActivate)) { _ in
            activateSelectedItem()
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelCommandModifierChanged)) { notification in
            guard let isPressed = notification.userInfo?["isPressed"] as? Bool else { return }
            isCommandModifierPressed = isPressed
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelQuickSelect)) { notification in
            guard let index = notification.userInfo?["index"] as? Int else { return }
            quickSelectAndActivate(index: index)
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelKeyboardInput)) { notification in
            guard let characters = notification.userInfo?["characters"] as? String else { return }
            if !isSearchExpanded {
                withAnimation(.easeInOut(duration: 0.14)) {
                    isSearchExpanded = true
                }
            }
            let shouldFocusSearch = !isSearchFocused
            searchText += characters
            if shouldFocusSearch {
                focusSearchFieldForTyping()
            }
        }
        .onAppear {
            installLocalKeyboardBridgingIfNeeded()
        }
        .onDisappear {
            removeLocalKeyboardBridging()
        }
    }

    private var regularModeBody: some View {
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
    }

    private var compactModeBody: some View {
        GeometryReader { _ in
            ZStack {
                panelBackground

                VStack(spacing: compactBodySpacing) {
                    if !isHighDensityPointerCompactMode {
                        compactHeader
                    }
                    if isHighDensityPointerCompactMode && (isSearchExpanded || !searchText.isEmpty) {
                        compactInlineSearchControl
                    }
                    compactContentArea
                }
                .padding(.horizontal, compactPanelHorizontalPadding)
                .padding(.vertical, compactPanelVerticalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                collapseSearchIfNeeded()
            }
            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
        }
        .frame(width: compactPanelWidth)
    }

    private var panelBackground: some View {
        Rectangle()
            .fill(.clear)
            .glassEffect(.regular, in: Rectangle())
            .ignoresSafeArea()
    }

    private var compactHeader: some View {
        VStack(spacing: compactHeaderSpacing) {
            HStack(spacing: 8) {
                compactModeTabs
                compactHeaderActions
            }

            if !isSnippetMode {
                compactHistoryFilterRow
            }

            compactTagFilterRow
        }
    }

    private var compactModeTabs: some View {
        HStack(spacing: compactDensity == .high ? 4 : 6) {
            compactModeTab(
                title: "历史",
                systemImage: "clock.arrow.circlepath",
                count: store.items.count,
                isActive: !isSnippetMode
            ) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isSnippetMode = false
                }
            }

            compactModeTab(
                title: "常用片段",
                systemImage: "bookmark.fill",
                count: store.snippets.count,
                isActive: isSnippetMode
            ) {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isSnippetMode = true
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(compactDensity == .low ? 4 : 3)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.82),
            in: RoundedRectangle(cornerRadius: compactDensity == .high ? 12 : 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: compactDensity == .high ? 12 : 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactHeaderActions: some View {
        HStack(spacing: 8) {
            compactSearchControl
            if !(isSearchExpanded || !searchText.isEmpty) {
                if isSnippetMode {
                    compactSnippetAddButton
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    compactClearButton
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                settingsButton
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isSearchExpanded || !searchText.isEmpty)
    }

    private var compactContentArea: some View {
        Group {
            if isSnippetMode {
                compactSnippetList
            } else {
                compactHistoryList
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isSnippetMode ? filteredSnippets.count : filteredItems.count)
    }

    private var compactHistoryList: some View {
        Group {
            if compactDisplayedHistoryItems.isEmpty {
                EmptyStateCard(
                    icon: "list.bullet.rectangle",
                    title: "暂无记录",
                    subtitle: queryText.isEmpty
                        ? "复制文本、图片或文件后会按时间顺序出现在这里"
                        : "没有匹配当前搜索条件的结果"
                )
            } else {
                if usesCompactLinearList {
                    compactLinearHistoryContent
                } else {
                    compactWaterfallContent
                }
            }
        }
    }

    private var compactSnippetList: some View {
        Group {
            if compactDisplayedSnippets.isEmpty {
                EmptyStateCard(
                    icon: "bookmark",
                    title: "暂无常用片段",
                    subtitle: queryText.isEmpty
                        ? "可保存地址、账号、代码片段等，单击即可快速使用"
                        : "没有匹配当前搜索条件的片段"
                )
            } else {
                if usesCompactLinearList {
                    compactLinearSnippetContent
                } else {
                    compactSnippetContent
                }
            }
        }
    }

    private var compactSearchControl: some View {
        Group {
            if isHighDensityPointerCompactMode && !isSearchExpanded && searchText.isEmpty {
                EmptyView()
            } else
            if isSearchExpanded || !searchText.isEmpty {
                HStack(spacing: compactDensity == .high ? 4 : 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)

                    TextField("搜索", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: compactDensity == .high ? 11 : 12, weight: .medium, design: .rounded))
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
                .padding(.horizontal, compactDensity == .high ? 8 : 10)
                .padding(.vertical, compactDensity == .low ? 7 : 6)
                .frame(width: compactSearchFieldWidth)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.82),
                    in: RoundedRectangle(cornerRadius: compactDensity == .low ? 11 : 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: compactDensity == .low ? 11 : 10, style: .continuous)
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
                        .frame(width: compactSearchIconSide, height: compactSearchIconSide)
                        .background(
                            Color(nsColor: .controlBackgroundColor).opacity(0.82),
                            in: RoundedRectangle(cornerRadius: compactDensity == .high ? 9 : 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: compactDensity == .high ? 9 : 10, style: .continuous)
                                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isSearchExpanded)
    }

    private var compactInlineSearchControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("搜索", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11, weight: .medium, design: .rounded))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.82),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var compactHistoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: compactDensity == .high ? 4 : 6) {
                ForEach(ClipboardFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(.system(size: compactControlFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(selectedFilter == filter ? .white : .primary)
                            .padding(.horizontal, compactDensity == .high ? 8 : 9)
                            .padding(.vertical, compactDensity == .low ? 5 : 4)
                            .background(
                                selectedFilter == filter ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactTagFilterRow: some View {
        Group {
            if availableTags.isEmpty {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: compactDensity == .high ? 4 : 6) {
                        Button {
                            if isSnippetMode {
                                selectedSnippetTag = nil
                            } else {
                                selectedHistoryTag = nil
                            }
                        } label: {
                            Text("全部")
                                .font(.system(size: compactControlFontSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(compactSelectedTag == nil ? .white : .primary)
                                .padding(.horizontal, compactDensity == .high ? 8 : 9)
                                .padding(.vertical, compactDensity == .low ? 5 : 4)
                                .background(
                                    compactSelectedTag == nil ? Color.accentColor : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)

                        ForEach(availableTags, id: \.self) { tag in
                            Button {
                                if isSnippetMode {
                                    selectedSnippetTag = selectedSnippetTag == tag ? nil : tag
                                } else {
                                    selectedHistoryTag = selectedHistoryTag == tag ? nil : tag
                                }
                            } label: {
                                Text("#\(tag)")
                                    .font(.system(size: compactControlFontSize, weight: .semibold, design: .rounded))
                                    .foregroundStyle(compactSelectedTag == tag ? .white : .primary)
                                    .padding(.horizontal, compactDensity == .high ? 8 : 9)
                                    .padding(.vertical, compactDensity == .low ? 5 : 4)
                                    .background(
                                        compactSelectedTag == tag ? Color.accentColor : Color.secondary.opacity(0.12),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var compactSelectedTag: String? {
        isSnippetMode ? selectedSnippetTag : selectedHistoryTag
    }

    private var compactWaterfallContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                let columns = compactWaterfallColumns(from: filteredItems)
                HStack(alignment: .top, spacing: compactGridSpacing) {
                    ForEach(0..<2, id: \.self) { col in
                        LazyVStack(spacing: compactGridSpacing) {
                            ForEach(columns[col]) { item in
                                CompactClipboardCard(
                                    item: item,
                                    cardWidth: compactColumnWidth,
                                    imageCardSize: compactImageCardSize,
                                    density: compactDensity,
                                    onPrimaryAction: {
                                        selectedHistoryItemID = item.id
                                        activateClipboardItem(item)
                                    },
                                    onCopy: { store.copyToClipboard(item) },
                                    onDelete: { store.remove(item) },
                                    onManageTags: { tagEditorItem = item },
                                    onSaveAsSnippet: { quickSaveAsSnippet(item) },
                                    onTokenSelect: { tokenSelectionItem = item },
                                    isSelected: selectedHistoryItemID == item.id,
                                    quickShortcutLabel: historyQuickLabelsByID[item.id]
                                )
                                .onAppear {
                                    trackHistoryVisibility(item.id, isVisible: true)
                                }
                                .onDisappear {
                                    trackHistoryVisibility(item.id, isVisible: false)
                                }
                            }
                        }
                        .frame(width: compactColumnWidth, alignment: .top)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 2)
                .background(
                    ScrollWheelInterventionObserver {
                        if selectedHistoryItemID != nil {
                            selectedHistoryItemID = nil
                        }
                    }
                    .frame(width: 0, height: 0)
                )
            }
            .onChange(of: selectedHistoryItemID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private var compactSnippetContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: compactGridSpacing) {
                    ForEach(filteredSnippets) { snippet in
                        SnippetCard(
                            snippet: snippet,
                            onPrimaryAction: {
                                selectedSnippetItemID = snippet.id
                                activateSnippet(snippet)
                            },
                            onCopy: { store.copySnippetToClipboard(snippet) },
                            onEdit: { beginEditSnippet(snippet) },
                            onDelete: { store.removeSnippet(snippet) },
                            preferredWidth: compactSnippetCardWidth,
                            compactStyle: true,
                            compactDensity: compactDensity,
                            isSelected: selectedSnippetItemID == snippet.id,
                            quickShortcutLabel: snippetQuickLabelsByID[snippet.id]
                        )
                        .onAppear {
                            trackSnippetVisibility(snippet.id, isVisible: true)
                        }
                        .onDisappear {
                            trackSnippetVisibility(snippet.id, isVisible: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
                .background(
                    ScrollWheelInterventionObserver {
                        if selectedSnippetItemID != nil {
                            selectedSnippetItemID = nil
                        }
                    }
                    .frame(width: 0, height: 0)
                )
            }
            .onChange(of: selectedSnippetItemID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private var compactLinearHistoryContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: compactDensity == .high ? 3 : 4) {
                    ForEach(compactDisplayedHistoryItems) { item in
                        CompactLinearHistoryRow(
                            item: item,
                            density: compactDensity,
                            isSelected: selectedHistoryItemID == item.id,
                            quickShortcutLabel: historyQuickLabelsByID[item.id],
                            onPrimaryAction: {
                                selectedHistoryItemID = item.id
                                activateClipboardItem(item)
                            },
                            onCopy: { store.copyToClipboard(item) },
                            onDelete: { store.remove(item) },
                            onManageTags: { tagEditorItem = item },
                            onSaveAsSnippet: { quickSaveAsSnippet(item) },
                            onTokenSelect: { tokenSelectionItem = item }
                        )
                        .id(item.id)
                        .onAppear {
                            trackHistoryVisibility(item.id, isVisible: true)
                        }
                        .onDisappear {
                            trackHistoryVisibility(item.id, isVisible: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .background(
                    ScrollWheelInterventionObserver {
                        if selectedHistoryItemID != nil {
                            selectedHistoryItemID = nil
                        }
                    }
                    .frame(width: 0, height: 0)
                )
            }
            .onChange(of: selectedHistoryItemID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private var compactLinearSnippetContent: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: compactDensity == .high ? 3 : 4) {
                    ForEach(compactDisplayedSnippets) { snippet in
                        CompactLinearSnippetRow(
                            snippet: snippet,
                            density: compactDensity,
                            isSelected: selectedSnippetItemID == snippet.id,
                            quickShortcutLabel: snippetQuickLabelsByID[snippet.id],
                            onPrimaryAction: {
                                selectedSnippetItemID = snippet.id
                                activateSnippet(snippet)
                            },
                            onCopy: { store.copySnippetToClipboard(snippet) },
                            onEdit: { beginEditSnippet(snippet) },
                            onDelete: { store.removeSnippet(snippet) }
                        )
                        .id(snippet.id)
                        .onAppear {
                            trackSnippetVisibility(snippet.id, isVisible: true)
                        }
                        .onDisappear {
                            trackSnippetVisibility(snippet.id, isVisible: false)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 1)
                .background(
                    ScrollWheelInterventionObserver {
                        if selectedSnippetItemID != nil {
                            selectedSnippetItemID = nil
                        }
                    }
                    .frame(width: 0, height: 0)
                )
            }
            .onChange(of: selectedSnippetItemID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
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
                    .frame(maxHeight: useHorizontalWaterfall ? horizontalHistoryContentHeight : .infinity)
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
                .frame(maxHeight: useHorizontalWaterfall ? horizontalSnippetContentHeight : .infinity)
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
        ScrollViewReader { proxy in
            GeometryReader { geometry in
                ScrollView {
                    let columns = waterfallColumns(from: filteredItems)
                    let columnWidth = max((geometry.size.width - 10) / 2, 220)
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(0..<2, id: \.self) { col in
                            LazyVStack(spacing: 10) {
                                ForEach(columns[col]) { item in
                                    ClipboardCard(
                                        item: item,
                                        onPrimaryAction: {
                                            selectedHistoryItemID = item.id
                                            activateClipboardItem(item)
                                        },
                                        onCopy: { store.copyToClipboard(item) },
                                        onDelete: { store.remove(item) },
                                        onManageTags: { tagEditorItem = item },
                                        onSaveAsSnippet: { quickSaveAsSnippet(item) },
                                        onTokenSelect: { tokenSelectionItem = item },
                                        preferredWidth: columnWidth,
                                        isSelected: selectedHistoryItemID == item.id,
                                        quickShortcutLabel: historyQuickLabelsByID[item.id]
                                    )
                                    .onAppear {
                                        trackHistoryVisibility(item.id, isVisible: true)
                                    }
                                    .onDisappear {
                                        trackHistoryVisibility(item.id, isVisible: false)
                                    }
                                }
                            }
                            .frame(width: columnWidth, alignment: .top)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                    .background(
                        ScrollWheelInterventionObserver {
                            if selectedHistoryItemID != nil {
                                selectedHistoryItemID = nil
                            }
                        }
                        .frame(width: 0, height: 0)
                    )
                }
            }
            .onChange(of: selectedHistoryItemID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private var horizontalWaterfallContent: some View {
        HorizontalWheelScrollView(
            indicatorBottomInset: horizontalScrollerGap,
            targetVisibleRangeX: horizontalHistoryVisibleRangeX,
            onVisibleRangeChange: { rangeX in
                if horizontalHistoryViewportRangeX != rangeX {
                    horizontalHistoryViewportRangeX = rangeX
                }
            },
            onUserScrollIntervention: {
                if selectedHistoryItemID != nil {
                    selectedHistoryItemID = nil
                }
            }
        ) {
            LazyHStack(alignment: .top, spacing: 8) {
                ForEach(filteredItems) { item in
                    ClipboardCard(
                        item: item,
                        onPrimaryAction: {
                            selectedHistoryItemID = item.id
                            activateClipboardItem(item)
                        },
                        onCopy: { store.copyToClipboard(item) },
                        onDelete: { store.remove(item) },
                        onManageTags: { tagEditorItem = item },
                        onSaveAsSnippet: { quickSaveAsSnippet(item) },
                        onTokenSelect: { tokenSelectionItem = item },
                        preferredWidth: horizontalCardWidth,
                        preferredHeight: horizontalCardHeight,
                        compactStyle: true,
                        isSelected: selectedHistoryItemID == item.id,
                        quickShortcutLabel: historyQuickLabelsByID[item.id]
                    )
                    .onAppear {
                        trackHistoryVisibility(item.id, isVisible: true)
                    }
                    .onDisappear {
                        trackHistoryVisibility(item.id, isVisible: false)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: horizontalHistoryContentHeight)
    }

    private var verticalSnippetContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(filteredSnippets) { snippet in
                        SnippetCard(
                            snippet: snippet,
                            onPrimaryAction: {
                                selectedSnippetItemID = snippet.id
                                activateSnippet(snippet)
                            },
                            onCopy: { store.copySnippetToClipboard(snippet) },
                            onEdit: { beginEditSnippet(snippet) },
                            onDelete: { store.removeSnippet(snippet) },
                            isSelected: selectedSnippetItemID == snippet.id,
                            quickShortcutLabel: snippetQuickLabelsByID[snippet.id]
                        )
                        .onAppear {
                            trackSnippetVisibility(snippet.id, isVisible: true)
                        }
                        .onDisappear {
                            trackSnippetVisibility(snippet.id, isVisible: false)
                        }
                    }
                }
                .padding(.vertical, 4)
                .background(
                    ScrollWheelInterventionObserver {
                        if selectedSnippetItemID != nil {
                            selectedSnippetItemID = nil
                        }
                    }
                    .frame(width: 0, height: 0)
                )
            }
            .onChange(of: selectedSnippetItemID) { _, selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.14)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private var horizontalSnippetContent: some View {
        HorizontalWheelScrollView(
            indicatorBottomInset: horizontalScrollerGap,
            targetVisibleRangeX: horizontalSnippetVisibleRangeX,
            onVisibleRangeChange: { rangeX in
                if horizontalSnippetViewportRangeX != rangeX {
                    horizontalSnippetViewportRangeX = rangeX
                }
            },
            onUserScrollIntervention: {
                if selectedSnippetItemID != nil {
                    selectedSnippetItemID = nil
                }
            }
        ) {
            LazyHStack(alignment: .top, spacing: 8) {
                ForEach(filteredSnippets) { snippet in
                    SnippetCard(
                        snippet: snippet,
                        onPrimaryAction: {
                            selectedSnippetItemID = snippet.id
                            activateSnippet(snippet)
                        },
                        onCopy: { store.copySnippetToClipboard(snippet) },
                        onEdit: { beginEditSnippet(snippet) },
                        onDelete: { store.removeSnippet(snippet) },
                        preferredWidth: horizontalSnippetWidth,
                        preferredHeight: horizontalSnippetHeight,
                        compactStyle: true,
                        isSelected: selectedSnippetItemID == snippet.id,
                        quickShortcutLabel: snippetQuickLabelsByID[snippet.id]
                    )
                    .onAppear {
                        trackSnippetVisibility(snippet.id, isVisible: true)
                    }
                    .onDisappear {
                        trackSnippetVisibility(snippet.id, isVisible: false)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(height: horizontalSnippetContentHeight)
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

    private func compactWaterfallColumns(from items: [ClipboardItem]) -> [[ClipboardItem]] {
        var columns: [[ClipboardItem]] = [[], []]
        var heights: [CGFloat] = [0, 0]

        for item in items {
            let column = heights[0] <= heights[1] ? 0 : 1
            columns[column].append(item)
            heights[column] += compactEstimatedHeight(for: item)
        }

        return columns
    }

    private func estimatedHeight(for item: ClipboardItem) -> CGFloat {
        switch item.type {
        case .image: return 200
        case .file: return item.isImageLikeItem ? 200 : 100
        case .text:
            let len = item.displayText.count
            if len > 100 { return 150 }
            if len > 40 { return 120 }
            return 90
        }
    }

    private func compactEstimatedHeight(for item: ClipboardItem) -> CGFloat {
        switch item.type {
        case .image:
            return compactImageCardSize
        case .file:
            if item.isImageLikeItem {
                return compactImageCardSize
            }
            switch compactDensity {
            case .low: return 110
            case .medium: return 100
            case .high: return 90
            }
        case .text:
            let len = item.displayText.count
            switch compactDensity {
            case .low:
                if len > 120 { return 160 }
                if len > 60 { return 136 }
                return 112
            case .medium:
                if len > 120 { return 142 }
                if len > 60 { return 124 }
                return 102
            case .high:
                if len > 120 { return 128 }
                if len > 60 { return 112 }
                return 92
            }
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
                let activeSelectedTag = isSnippetMode ? selectedSnippetTag : selectedHistoryTag
                Button {
                    if isSnippetMode {
                        selectedSnippetTag = nil
                    } else {
                        selectedHistoryTag = nil
                    }
                } label: {
                    Text("全部标签")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(activeSelectedTag == nil ? .white : .primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            activeSelectedTag == nil ? Color.accentColor : Color.secondary.opacity(0.12),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)

                ForEach(availableTags, id: \.self) { tag in
                    Button {
                        if isSnippetMode {
                            selectedSnippetTag = selectedSnippetTag == tag ? nil : tag
                        } else {
                            selectedHistoryTag = selectedHistoryTag == tag ? nil : tag
                        }
                    } label: {
                        Text("#\(tag)")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(activeSelectedTag == tag ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                activeSelectedTag == tag ? Color.accentColor : Color.secondary.opacity(0.12),
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
            isClearConfirmationPresented = true
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var compactClearButton: some View {
        Button {
            isClearConfirmationPresented = true
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("清空历史")
        .disabled(store.items.isEmpty)
    }

    private var compactSnippetAddButton: some View {
        Button {
            beginAddSnippet()
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("新增常用片段")
    }

    private func compactModeTab(
        title: String,
        systemImage: String,
        count: Int,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: compactDensity == .high ? 4 : 6) {
                Image(systemName: systemImage)
                    .font(.system(size: compactDensity == .high ? 10 : 11, weight: .semibold))

                Text(title)
                    .font(.system(size: compactDensity == .high ? 10 : 11, weight: .semibold, design: .rounded))
                    .lineLimit(1)

                Text("\(count)")
                    .font(.system(size: compactDensity == .high ? 9 : 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, compactDensity == .high ? 5 : 6)
                    .padding(.vertical, compactDensity == .high ? 1.5 : 2)
                    .background(
                        isActive ? Color.white.opacity(0.18) : Color.secondary.opacity(0.12),
                        in: Capsule()
                    )
            }
            .foregroundStyle(isActive ? .white : .primary)
            .padding(.horizontal, compactDensity == .high ? 8 : 10)
            .padding(.vertical, compactDensity == .low ? 8 : 6)
            .frame(maxWidth: .infinity, minHeight: compactDensity == .low ? 34 : 30)
            .background(
                isActive ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: compactDensity == .high ? 8 : 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func collapseSearchIfNeeded() {
        guard isSearchExpanded, searchText.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.14)) {
            isSearchExpanded = false
        }
        isSearchFocused = false
    }

    private func syncHighDensitySearchModeIfNeeded() {
        guard isHighDensityPointerCompactMode else { return }

        if queryText.isEmpty {
            if isSnippetMode {
                isSnippetMode = false
                selectedSnippetItemID = nil
            }
            return
        }

        let hasHistoryMatch = !filteredItems.isEmpty
        let hasSnippetMatch = !filteredSnippets.isEmpty

        if hasSnippetMatch && !hasHistoryMatch {
            if !isSnippetMode {
                isSnippetMode = true
                selectedHistoryItemID = nil
            }
        } else {
            if isSnippetMode {
                isSnippetMode = false
                selectedSnippetItemID = nil
            }
        }
    }

    private func focusSearchFieldForTyping() {
        DispatchQueue.main.async {
            isSearchFocused = true
            moveSearchCaretToEnd(retryCount: 6)
        }
    }

    private func moveSearchCaretToEnd(retryCount: Int) {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else {
            guard retryCount > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                moveSearchCaretToEnd(retryCount: retryCount - 1)
            }
            return
        }
        let end = textView.string.count
        textView.setSelectedRange(NSRange(location: end, length: 0))
    }

    private func syncSelectionIfNeeded() {
        if let selectedHistoryItemID,
           !filteredItems.contains(where: { $0.id == selectedHistoryItemID }) {
            self.selectedHistoryItemID = nil
        }
        if let selectedSnippetItemID,
           !filteredSnippets.contains(where: { $0.id == selectedSnippetItemID }) {
            self.selectedSnippetItemID = nil
        }
    }

    private func syncVisibleItemsIfNeeded() {
        let validHistoryIDs = Set(filteredItems.map(\.id))
        visibleHistoryItemIDs = visibleHistoryItemIDs.intersection(validHistoryIDs)

        let validSnippetIDs = Set(filteredSnippets.map(\.id))
        visibleSnippetItemIDs = visibleSnippetItemIDs.intersection(validSnippetIDs)
    }

    private func trackHistoryVisibility(_ itemID: UUID, isVisible: Bool) {
        if isVisible {
            visibleHistoryItemIDs.insert(itemID)
        } else {
            visibleHistoryItemIDs.remove(itemID)
        }
    }

    private func trackSnippetVisibility(_ snippetID: UUID, isVisible: Bool) {
        if isVisible {
            visibleSnippetItemIDs.insert(snippetID)
        } else {
            visibleSnippetItemIDs.remove(snippetID)
        }
    }

    private func moveSelection(direction: SelectionDirection) {
        if isSnippetMode {
            let sourceSnippets = isHighDensityPointerCompactMode ? compactDisplayedSnippets : filteredSnippets
            let ids = sourceSnippets.map(\.id)
            let currentID = selectedSnippetItemID

            if useHorizontalWaterfall, let currentID {
                let visibleSnippetIDSet = Set(horizontalVisibleSnippetItems.map(\.id))
                if !visibleSnippetIDSet.contains(currentID) {
                    self.selectedSnippetItemID = firstVisibleSnippetItemID
                    return
                }
            }

            selectedSnippetItemID = advancedSelectionID(
                currentID: currentID,
                allIDs: ids,
                step: direction.sequentialStep,
                startID: firstVisibleSnippetItemID
            )
            return
        }

        if isHistoryWaterfallLayout, direction == .up || direction == .down {
            moveHistorySelectionInSameColumn(direction: direction)
            return
        }

        let sourceItems = isHighDensityPointerCompactMode ? compactDisplayedHistoryItems : filteredItems
        let ids = sourceItems.map(\.id)
        let currentID = selectedHistoryItemID

        if useHorizontalWaterfall, let currentID {
            let visibleHistoryIDSet = Set(horizontalVisibleHistoryItems.map(\.id))
            if !visibleHistoryIDSet.contains(currentID) {
                self.selectedHistoryItemID = firstVisibleHistoryItemID
                return
            }
        }

        selectedHistoryItemID = advancedSelectionID(
            currentID: currentID,
            allIDs: ids,
            step: direction.sequentialStep,
            startID: firstVisibleHistoryItemID
        )
    }

    private func moveHistorySelectionInSameColumn(direction: SelectionDirection) {
        guard !filteredItems.isEmpty else {
            selectedHistoryItemID = nil
            return
        }

        guard let selectedHistoryItemID else {
            self.selectedHistoryItemID = firstVisibleHistoryItemID ?? filteredItems[0].id
            return
        }

        let columns = isCompactMode
            ? compactWaterfallColumns(from: filteredItems)
            : waterfallColumns(from: filteredItems)
        for column in columns {
            guard let currentIndex = column.firstIndex(where: { $0.id == selectedHistoryItemID }) else { continue }
            let targetIndex = direction == .down ? currentIndex + 1 : currentIndex - 1
            guard column.indices.contains(targetIndex) else { return }
            self.selectedHistoryItemID = column[targetIndex].id
            return
        }

        self.selectedHistoryItemID = firstVisibleHistoryItemID ?? filteredItems[0].id
    }

    private func advancedSelectionID(currentID: UUID?, allIDs: [UUID], step: Int, startID: UUID?) -> UUID? {
        guard !allIDs.isEmpty else { return nil }
        guard let currentID,
              let currentIndex = allIDs.firstIndex(of: currentID) else {
            if let startID, allIDs.contains(startID) {
                return startID
            }
            return allIDs[0]
        }
        let next = min(max(currentIndex + step, 0), allIDs.count - 1)
        return allIDs[next]
    }

    private func activateSelectedItem() {
        if isSnippetMode {
            let sourceSnippets = isHighDensityPointerCompactMode ? compactDisplayedSnippets : filteredSnippets
            guard let selectedSnippetItemID,
                  let snippet = sourceSnippets.first(where: { $0.id == selectedSnippetItemID }) else {
                return
            }
            activateSnippet(snippet)
            return
        }

        let sourceItems = isHighDensityPointerCompactMode ? compactDisplayedHistoryItems : filteredItems
        guard let selectedHistoryItemID,
              let item = sourceItems.first(where: { $0.id == selectedHistoryItemID }) else {
            return
        }
        activateClipboardItem(item)
    }

    private func quickSelectAndActivate(index: Int) {
        guard index >= 0 else { return }
        if isSnippetMode {
            let quickSnippets = quickSelectableSnippets
            guard quickSnippets.indices.contains(index) else { return }
            let snippet = quickSnippets[index]
            selectedSnippetItemID = snippet.id
            activateSnippet(snippet)
            return
        }

        let quickItems = quickSelectableHistoryItems
        guard quickItems.indices.contains(index) else { return }
        let item = quickItems[index]
        selectedHistoryItemID = item.id
        activateClipboardItem(item)
    }

    private var shouldBridgeSearchFocusedKeys: Bool {
        isSearchFocused
        && (NSApp.keyWindow is FloatingPanel)
    }

    private var isSearchInputComposing: Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return textView.hasMarkedText()
    }

    private func installLocalKeyboardBridgingIfNeeded() {
        if localKeyDownMonitor == nil {
            localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard shouldBridgeSearchFocusedKeys else { return event }
                guard !isSearchInputComposing else { return event }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if modifiers.contains(.command), let quickIndex = quickSelectIndex(from: event) {
                    NotificationCenter.default.post(
                        name: .panelQuickSelect,
                        object: nil,
                        userInfo: ["index": quickIndex]
                    )
                    return nil
                }

                if modifiers.intersection([.command, .control, .option]).isEmpty {
                    if let direction = selectionDirectionRaw(for: event.keyCode) {
                        // 方向键进入结果导航时让搜索框失焦，后续回车由列表处理。
                        isSearchFocused = false
                        NotificationCenter.default.post(
                            name: .panelSelectionMove,
                            object: nil,
                            userInfo: ["direction": direction]
                        )
                        return nil
                    }
                }

                return event
            }
        }

        if localFlagsChangedMonitor == nil {
            localFlagsChangedMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                guard shouldBridgeSearchFocusedKeys else { return event }
                guard !isSearchInputComposing else { return event }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                NotificationCenter.default.post(
                    name: .panelCommandModifierChanged,
                    object: nil,
                    userInfo: ["isPressed": modifiers.contains(.command)]
                )
                return event
            }
        }
    }

    private func removeLocalKeyboardBridging() {
        if let localKeyDownMonitor {
            NSEvent.removeMonitor(localKeyDownMonitor)
            self.localKeyDownMonitor = nil
        }

        if let localFlagsChangedMonitor {
            NSEvent.removeMonitor(localFlagsChangedMonitor)
            self.localFlagsChangedMonitor = nil
        }
    }

    private func selectionDirectionRaw(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 123:
            return "left"
        case 124:
            return "right"
        case 125:
            return "down"
        case 126:
            return "up"
        default:
            return nil
        }
    }

    private func quickSelectIndex(from event: NSEvent) -> Int? {
        guard let chars = event.charactersIgnoringModifiers?.lowercased(),
              chars.count == 1 else {
            return nil
        }
        return Self.quickShortcutKeys.firstIndex(where: { $0.lowercased() == chars })
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

private struct CompactLinearHistoryRow: View {
    let item: ClipboardItem
    let density: CompactDensity
    let isSelected: Bool
    let quickShortcutLabel: String?
    let onPrimaryAction: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onManageTags: () -> Void
    let onSaveAsSnippet: () -> Void
    let onTokenSelect: () -> Void

    private var previewImage: NSImage? {
        guard item.isImageLikeItem, let url = item.contentURL else { return nil }
        let key = url as NSURL
        if let cached = ImagePreviewCache.shared.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        ImagePreviewCache.shared.setObject(image, forKey: key)
        return image
    }

    private var rowHorizontalPadding: CGFloat {
        density == .high ? 4 : 6
    }

    private var rowVerticalPadding: CGFloat {
        density == .high ? 3 : 5
    }

    private var titleFontSize: CGFloat {
        density == .high ? 12 : 12.5
    }

    private var metaFontSize: CGFloat {
        density == .high ? 9 : 10
    }

    private var typeLabel: String {
        item.isImageLikeItem ? ClipboardContentType.image.label : item.type.label
    }

    private var titleText: String {
        item.displayText
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var metaText: String {
        var parts = [typeLabel]
        if let app = item.sourceApp?.trimmingCharacters(in: .whitespacesAndNewlines),
           !app.isEmpty {
            parts.append(app)
        }
        parts.append(ClipboardTimeFormatter.shared.string(from: item.timestamp))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var logo: some View {
        if item.isImageLikeItem, let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: item.isImageLikeItem ? ClipboardContentType.image.icon : item.type.icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 14)
        }
    }

    var body: some View {
        HStack(spacing: density == .high ? 6 : 8) {
            logo

            VStack(alignment: .leading, spacing: density == .high ? 0 : 2) {
                Text(titleText.isEmpty ? "空内容" : titleText)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if density == .medium {
                    Text(metaText)
                        .font(.system(size: metaFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if let quickShortcutLabel {
                Text(quickShortcutLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: density == .high ? 24 : 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: density == .high ? 7 : 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: density == .high ? 7 : 9, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPrimaryAction)
        .contextMenu {
            Button("完成键入", action: onPrimaryAction)
            Button("重新复制", action: onCopy)
            Button("编辑标签", action: onManageTags)
            if item.type == .text {
                Button("分词选择", action: onTokenSelect)
                Button("添加到常用片段", action: onSaveAsSnippet)
            }
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}

private struct CompactLinearSnippetRow: View {
    let snippet: SnippetItem
    let density: CompactDensity
    let isSelected: Bool
    let quickShortcutLabel: String?
    let onPrimaryAction: () -> Void
    let onCopy: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var rowHorizontalPadding: CGFloat {
        density == .high ? 4 : 6
    }

    private var rowVerticalPadding: CGFloat {
        density == .high ? 3 : 5
    }

    private var titleFontSize: CGFloat {
        density == .high ? 12 : 12.5
    }

    private var metaFontSize: CGFloat {
        density == .high ? 9 : 10
    }

    private var contentText: String {
        let text = snippet.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "空内容" : text
    }

    var body: some View {
        HStack(spacing: density == .high ? 6 : 8) {
            Image(systemName: "bookmark.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 14, height: 14)

            VStack(alignment: .leading, spacing: density == .high ? 0 : 2) {
                Text(snippet.displayTitle)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(contentText)
                    .font(.system(size: metaFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let quickShortcutLabel {
                Text(quickShortcutLabel)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, rowHorizontalPadding)
        .padding(.vertical, rowVerticalPadding)
        .frame(maxWidth: .infinity, minHeight: density == .high ? 24 : 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: density == .high ? 7 : 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: density == .high ? 7 : 9, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onPrimaryAction)
        .contextMenu {
            Button("完成键入", action: onPrimaryAction)
            Button("重新复制", action: onCopy)
            Button("编辑片段", action: onEdit)
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
    }
}

private struct CompactClipboardCard: View {
    let item: ClipboardItem
    let cardWidth: CGFloat
    let imageCardSize: CGFloat
    let density: CompactDensity
    let onPrimaryAction: () -> Void
    let onCopy: () -> Void
    let onDelete: () -> Void
    let onManageTags: () -> Void
    let onSaveAsSnippet: () -> Void
    let onTokenSelect: () -> Void
    let isSelected: Bool
    let quickShortcutLabel: String?
    @State private var isHovering = false

    private var accent: Color {
        if item.isImageLikeItem {
            return Color(red: 0.34, green: 0.68, blue: 1.00)
        }
        switch item.type {
        case .text: return Color(red: 0.20, green: 0.78, blue: 0.76)
        case .image: return Color(red: 0.34, green: 0.68, blue: 1.00)
        case .file: return Color(red: 0.96, green: 0.69, blue: 0.26)
        }
    }

    private var previewImage: NSImage? {
        guard item.isImageLikeItem, let url = item.contentURL else { return nil }
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

    private var isImageCard: Bool {
        item.isImageLikeItem
    }

    private var textLineLimit: Int {
        switch density {
        case .low: return item.type == .text ? 5 : 3
        case .medium: return item.type == .text ? 4 : 2
        case .high: return item.type == .text ? 3 : 2
        }
    }

    private var cardPadding: CGFloat {
        switch density {
        case .low: return 10
        case .medium: return 9
        case .high: return 8
        }
    }

    private var titleFontSize: CGFloat {
        switch density {
        case .low: return 13
        case .medium: return 12
        case .high: return 11
        }
    }

    private var helperFontSize: CGFloat {
        switch density {
        case .low, .medium: return 10
        case .high: return 9
        }
    }

    private var shouldShowHoverHint: Bool {
        density != .high
    }

    var body: some View {
        Group {
            if isImageCard {
                imageCardBody
            } else {
                regularCardBody
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if let quickShortcutLabel {
                QuickShortcutBadge(label: quickShortcutLabel)
                    .padding(8)
            }
        }
        .contextMenu {
            Button("完成键入", action: onPrimaryAction)
            Button("重新复制", action: onCopy)
            Button("编辑标签", action: onManageTags)
            if item.type == .text {
                Button("分词选择", action: onTokenSelect)
                Button("添加到常用片段", action: onSaveAsSnippet)
            }
            Divider()
            Button("删除", role: .destructive, action: onDelete)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
    }

    private var imageCardBody: some View {
        Button(action: onPrimaryAction) {
            ZStack(alignment: .topLeading) {
                imageCardBackground

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [.black.opacity(0.52), .black.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 78)

                    Spacer(minLength: 0)
                }

                compactMetaRow(foreground: .white.opacity(0.96), secondary: .white.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.top, 9)
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)

                VStack(spacing: 0) {
                    Spacer()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.58)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 54)
                    .overlay(alignment: .bottomLeading) {
                        compactFooterRow(foreground: .white.opacity(0.92))
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                    }
                }
            }
            .frame(width: cardWidth, height: imageCardSize)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.86 : 0.72))
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var imageCardBackground: some View {
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: cardWidth, height: imageCardSize)
                .clipped()
        } else {
            Rectangle()
                .fill(accent.opacity(0.18))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(accent)
                }
        }
    }

    private var regularCardBody: some View {
        Button(action: onPrimaryAction) {
            VStack(alignment: .leading, spacing: 8) {
                compactMetaRow(foreground: accent, secondary: .secondary)

                Text(item.displayText)
                    .font(.system(size: titleFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(textLineLimit)
                    .frame(maxWidth: .infinity, alignment: .leading)

                compactFooterRow(foreground: .secondary)

                if isHovering && shouldShowHoverHint {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                        Text("单击回填，右键更多")
                            .lineLimit(1)
                    }
                    .font(.system(size: helperFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(cardPadding)
            .frame(width: cardWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.86 : 0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func compactMetaRow(foreground: Color, secondary: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: item.isImageLikeItem ? ClipboardContentType.image.icon : item.type.icon)
                .font(.system(size: helperFontSize, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: 16, height: 16)
                .background(foreground.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("·")
                .foregroundStyle(secondary)
            Text(ClipboardTimeFormatter.shared.string(from: item.timestamp))
                .foregroundStyle(secondary)
            Spacer(minLength: 0)
        }
        .font(.system(size: helperFontSize, weight: .semibold, design: .rounded))
        .lineLimit(1)
    }

    private func compactFooterRow(foreground: Color) -> some View {
        HStack(spacing: 6) {
            if let app = item.sourceApp, !app.isEmpty {
                HStack(spacing: 4) {
                    if let sourceAppIcon {
                        Image(nsImage: sourceAppIcon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 12, height: 12)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    Text(app)
                        .lineLimit(1)
                }
            }

            if !item.tags.isEmpty {
                Text(item.tags.prefix(1).map { "#\($0)" }.joined())
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .font(.system(size: helperFontSize, weight: .medium, design: .rounded))
        .foregroundStyle(foreground)
    }
}

private struct ScrollWheelInterventionObserver: NSViewRepresentable {
    let onUserScrollIntervention: () -> Void

    func makeNSView(context: Context) -> ScrollWheelObservationView {
        let view = ScrollWheelObservationView()
        view.onUserScrollIntervention = onUserScrollIntervention
        return view
    }

    func updateNSView(_ nsView: ScrollWheelObservationView, context: Context) {
        nsView.onUserScrollIntervention = onUserScrollIntervention
        nsView.attachIfNeeded()
    }
}

private final class ScrollWheelObservationView: NSView {
    var onUserScrollIntervention: (() -> Void)?
    private weak var observedClipView: NSClipView?
    private var boundsObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfNeeded()
    }

    deinit {
        detach()
    }

    func attachIfNeeded() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        guard observedClipView !== clipView else { return }
        detach()
        observedClipView = clipView
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard NSApp.currentEvent?.type == .scrollWheel else { return }
            self.onUserScrollIntervention?()
        }
    }

    private func detach() {
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        observedClipView = nil
    }
}

private struct HorizontalWheelScrollView<Content: View>: NSViewRepresentable {
    let indicatorBottomInset: CGFloat
    let targetVisibleRangeX: ClosedRange<CGFloat>?
    let onVisibleRangeChange: ((ClosedRange<CGFloat>) -> Void)?
    let onUserScrollIntervention: (() -> Void)?
    let content: Content

    init(
        indicatorBottomInset: CGFloat = 0,
        targetVisibleRangeX: ClosedRange<CGFloat>? = nil,
        onVisibleRangeChange: ((ClosedRange<CGFloat>) -> Void)? = nil,
        onUserScrollIntervention: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.indicatorBottomInset = indicatorBottomInset
        self.targetVisibleRangeX = targetVisibleRangeX
        self.onVisibleRangeChange = onVisibleRangeChange
        self.onUserScrollIntervention = onUserScrollIntervention
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
        context.coordinator.targetVisibleRangeX = targetVisibleRangeX
        context.coordinator.onVisibleRangeChange = onVisibleRangeChange
        scrollView.documentView = hostingView
        scrollView.onVisibleRangeChange = { [weak coordinator = context.coordinator] range in
            coordinator?.onVisibleRangeChange?(range)
        }
        scrollView.onUserScrollIntervention = onUserScrollIntervention
        scrollView.onLayout = { [weak scrollView, weak hostingView, weak coordinator = context.coordinator] in
            guard let scrollView, let hostingView else { return }
            Self.syncDocumentFrame(scrollView: scrollView, hostingView: hostingView)
            Self.ensureVisibleRange(
                targetRangeX: coordinator?.targetVisibleRangeX,
                scrollView: scrollView,
                animated: false
            )
            scrollView.reportVisibleRange(force: true)
        }
        Self.syncDocumentFrame(scrollView: scrollView, hostingView: hostingView)
        Self.ensureVisibleRange(targetRangeX: targetVisibleRangeX, scrollView: scrollView, animated: false)
        return scrollView
    }

    func updateNSView(_ scrollView: WheelEnabledHorizontalScrollView, context: Context) {
        let hostingView = context.coordinator.hostingView
        context.coordinator.targetVisibleRangeX = targetVisibleRangeX
        context.coordinator.onVisibleRangeChange = onVisibleRangeChange
        hostingView.rootView = content
        scrollView.onVisibleRangeChange = { [weak coordinator = context.coordinator] range in
            coordinator?.onVisibleRangeChange?(range)
        }
        scrollView.onUserScrollIntervention = onUserScrollIntervention
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: indicatorBottomInset,
            right: 0
        )
        Self.syncDocumentFrame(scrollView: scrollView, hostingView: hostingView)
        Self.ensureVisibleRange(targetRangeX: targetVisibleRangeX, scrollView: scrollView, animated: true)
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

    private static func ensureVisibleRange(
        targetRangeX: ClosedRange<CGFloat>?,
        scrollView: NSScrollView,
        animated: Bool
    ) {
        guard let targetRangeX, let documentView = scrollView.documentView else { return }
        let visibleMinX = scrollView.contentView.bounds.minX
        let visibleMaxX = visibleMinX + scrollView.contentView.bounds.width

        let targetX: CGFloat
        if targetRangeX.lowerBound < visibleMinX {
            targetX = targetRangeX.lowerBound
        } else if targetRangeX.upperBound > visibleMaxX {
            targetX = targetRangeX.upperBound - scrollView.contentView.bounds.width
        } else {
            return
        }

        let maxOffsetX = max(documentView.frame.width - scrollView.contentView.bounds.width, 0)
        let clampedX = min(max(targetX, 0), maxOffsetX)
        let currentX = scrollView.contentView.bounds.origin.x
        guard abs(currentX - clampedX) > 1 else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                scrollView.contentView.animator().setBoundsOrigin(NSPoint(x: clampedX, y: 0))
            } completionHandler: {
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }
        } else {
            scrollView.contentView.scroll(to: NSPoint(x: clampedX, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    final class Coordinator {
        let hostingView: NSHostingView<Content>
        var targetVisibleRangeX: ClosedRange<CGFloat>?
        var onVisibleRangeChange: ((ClosedRange<CGFloat>) -> Void)?

        init(rootView: Content) {
            hostingView = NSHostingView(rootView: rootView)
        }
    }
}

private final class WheelEnabledHorizontalScrollView: NSScrollView {
    var onLayout: (() -> Void)?
    var onVisibleRangeChange: ((ClosedRange<CGFloat>) -> Void)?
    var onUserScrollIntervention: (() -> Void)?
    private var isLayoutCallbackScheduled = false
    private var lastReportedVisibleRangeX: ClosedRange<CGFloat>?

    override func layout() {
        super.layout()
        guard !isLayoutCallbackScheduled else { return }
        isLayoutCallbackScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLayoutCallbackScheduled = false
            self.onLayout?()
            self.reportVisibleRange(force: true)
        }
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        reportVisibleRange()
    }

    func reportVisibleRange(force: Bool = false) {
        let minX = contentView.bounds.minX
        let maxX = minX + contentView.bounds.width
        let currentRange = minX...maxX

        if !force, let lastRange = lastReportedVisibleRangeX,
           abs(lastRange.lowerBound - currentRange.lowerBound) < 0.5,
           abs(lastRange.upperBound - currentRange.upperBound) < 0.5 {
            return
        }

        lastReportedVisibleRangeX = currentRange
        onVisibleRangeChange?(currentRange)
    }

    override func scrollWheel(with event: NSEvent) {
        let horizontalDelta = abs(event.scrollingDeltaX)
        let verticalDelta = abs(event.scrollingDeltaY)
        if horizontalDelta > 0.1 || verticalDelta > 0.1 {
            onUserScrollIntervention?()
        }

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
    let onTokenSelect: () -> Void
    let preferredWidth: CGFloat?
    let preferredHeight: CGFloat?
    let compactStyle: Bool
    let isSelected: Bool
    let quickShortcutLabel: String?
    @State private var isHovering = false
    @State private var isPressing = false

    init(
        item: ClipboardItem,
        onPrimaryAction: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onManageTags: @escaping () -> Void,
        onSaveAsSnippet: @escaping () -> Void,
        onTokenSelect: @escaping () -> Void,
        preferredWidth: CGFloat? = nil,
        preferredHeight: CGFloat? = nil,
        compactStyle: Bool = false,
        isSelected: Bool = false,
        quickShortcutLabel: String? = nil
    ) {
        self.item = item
        self.onPrimaryAction = onPrimaryAction
        self.onCopy = onCopy
        self.onDelete = onDelete
        self.onManageTags = onManageTags
        self.onSaveAsSnippet = onSaveAsSnippet
        self.onTokenSelect = onTokenSelect
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.compactStyle = compactStyle
        self.isSelected = isSelected
        self.quickShortcutLabel = quickShortcutLabel
    }

    private var accent: Color {
        if item.isImageLikeItem {
            return Color(red: 0.34, green: 0.68, blue: 1.00)
        }
        switch item.type {
        case .text: return Color(red: 0.20, green: 0.78, blue: 0.76)
        case .image: return Color(red: 0.34, green: 0.68, blue: 1.00)
        case .file: return Color(red: 0.96, green: 0.69, blue: 0.26)
        }
    }

    private var previewImage: NSImage? {
        guard item.isImageLikeItem, let url = item.contentURL else { return nil }
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

    /// 与紧凑模式大图卡片一致：含顶/底边横向列表（`compactStyle == true`）时的图片项。
    private var usesFullBleedImageLayout: Bool {
        item.isImageLikeItem
    }

    private static let verticalImageCardHeight: CGFloat = 200

    private var fullBleedImageHeight: CGFloat {
        preferredHeight ?? Self.verticalImageCardHeight
    }

    @ViewBuilder
    private var nonCompactImageFillBackground: some View {
        if let previewImage {
            Image(nsImage: previewImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Rectangle()
                .fill(accent.opacity(0.18))
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(accent)
                }
        }
    }

    private var nonCompactImageMetaRow: some View {
        HStack(spacing: 4) {
            Image(systemName: ClipboardContentType.image.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(ClipboardContentType.image.label)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white.opacity(0.96))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.34), in: Capsule())
    }

    private var nonCompactImageFooterRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            if item.type == .file {
                Text(item.displayText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                Text(ClipboardTimeFormatter.shared.string(from: item.timestamp))
                    .font(.system(size: 10, weight: .medium, design: .rounded))

                if !item.tags.isEmpty {
                    Text(item.tags.prefix(1).map { "#\($0)" }.joined())
                        .lineLimit(1)
                }

                if let app = item.sourceApp, !app.isEmpty {
                    Spacer()
                    HStack(spacing: 4) {
                        if let sourceAppIcon {
                            Image(nsImage: sourceAppIcon)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 12, height: 12)
                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        }
                        Text(app)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.26), in: Capsule())
                }
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var fullBleedImageCardBody: some View {
        ZStack {
            nonCompactImageFillBackground
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: preferredWidth, height: fullBleedImageHeight)
        .frame(maxWidth: preferredWidth == nil ? .infinity : nil)
            .overlay {
                LinearGradient(
                    colors: [.black.opacity(0.16), .clear, .black.opacity(0.12)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .overlay(alignment: .top) {
                LinearGradient(
                    colors: [.black.opacity(0.72), .black.opacity(0.36), .black.opacity(0.1), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 98)
            }
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.46), .black.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
            }
            .overlay(alignment: .topLeading) {
                HStack(alignment: .top, spacing: 8) {
                    nonCompactImageMetaRow
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)
                    Spacer(minLength: 0)
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
                    .shadow(color: .black.opacity(0.24), radius: 6, x: 0, y: 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.top, 9)
            }
            .overlay(alignment: .bottomLeading) {
                nonCompactImageFooterRow
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 0.86 : 0.72))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private var standardCardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: item.isImageLikeItem ? ClipboardContentType.image.icon : item.type.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(item.isImageLikeItem ? ClipboardContentType.image.label : item.type.label)
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
    }

    var body: some View {
        Group {
            if usesFullBleedImageLayout {
                fullBleedImageCardBody
            } else {
                standardCardContent
                    .padding(compactStyle ? 8 : 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
            }
        }
        .frame(maxWidth: usesFullBleedImageLayout && preferredWidth == nil ? .infinity : nil)
        .frame(width: preferredWidth, height: preferredHeight, alignment: .topLeading)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(isPressing ? 0.08 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if let quickShortcutLabel {
                QuickShortcutBadge(label: quickShortcutLabel)
                    .padding(8)
            }
        }
        .scaleEffect(isPressing ? 0.988 : 1)
        .onTapGesture(perform: onPrimaryAction)
        .contextMenu {
            Button("完成键入", action: onPrimaryAction)
            Button("重新复制", action: onCopy)
            Button("编辑标签", action: onManageTags)
            if item.type == .text {
                Button("分词选择", action: onTokenSelect)
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
    let compactDensity: CompactDensity
    let isSelected: Bool
    let quickShortcutLabel: String?
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
        compactStyle: Bool = false,
        compactDensity: CompactDensity = .low,
        isSelected: Bool = false,
        quickShortcutLabel: String? = nil
    ) {
        self.snippet = snippet
        self.onPrimaryAction = onPrimaryAction
        self.onCopy = onCopy
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.preferredWidth = preferredWidth
        self.preferredHeight = preferredHeight
        self.compactStyle = compactStyle
        self.compactDensity = compactDensity
        self.isSelected = isSelected
        self.quickShortcutLabel = quickShortcutLabel
    }

    private var compactContentLineLimit: Int {
        guard compactStyle else { return 8 }
        switch compactDensity {
        case .low: return 5
        case .medium: return 4
        case .high: return 3
        }
    }

    private var compactTitleFontSize: CGFloat {
        guard compactStyle else { return 14 }
        switch compactDensity {
        case .low: return 14
        case .medium: return 13
        case .high: return 12
        }
    }

    private var compactBodyFontSize: CGFloat {
        guard compactStyle else { return 13 }
        switch compactDensity {
        case .low: return 13
        case .medium: return 12
        case .high: return 11
        }
    }

    private var compactFooterFontSize: CGFloat {
        guard compactStyle else { return 10 }
        switch compactDensity {
        case .low, .medium: return 10
        case .high: return 9
        }
    }

    private var compactPadding: CGFloat {
        guard compactStyle else { return 10 }
        switch compactDensity {
        case .low: return 8
        case .medium: return 7
        case .high: return 6
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if compactStyle {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 16, height: 16)
                        .background(
                            Color.accentColor.opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                } else {
                    Label("片段", systemImage: "bookmark.fill")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }

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
                .font(.system(size: compactTitleFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(snippet.displayText)
                .lineLimit(compactContentLineLimit)
                .font(.system(size: compactBodyFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)

            if !snippet.tags.isEmpty {
                TagStripView(tags: snippet.tags, compactStyle: compactStyle)
            }

            if compactStyle {
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: compactFooterFontSize))
                Text(ClipboardTimeFormatter.shared.string(from: snippet.timestamp))
                    .font(.system(size: compactFooterFontSize, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.secondary)
        }
        .padding(compactPadding)
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
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .overlay(alignment: .topTrailing) {
            if let quickShortcutLabel {
                QuickShortcutBadge(label: quickShortcutLabel)
                    .padding(8)
            }
        }
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

private struct QuickShortcutBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.68), in: Capsule())
            .allowsHitTesting(false)
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

private struct TokenSelectionSheet: View {
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    private let characters: [Character]
    private let tokenCellSize: CGFloat = 28
    private let tokenCellSpacing: CGFloat = 6
    @State private var selectedIndices: Set<Int> = []
    @State private var rangeAnchorIndex: Int?

    init(sourceText: String, onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
        self.characters = Array(sourceText)
    }

    private var selectedText: String {
        selectedIndices
            .sorted()
            .map { String(characters[$0]) }
            .joined()
    }

    private var canSubmit: Bool {
        !selectedIndices.isEmpty
    }

    private var allIndices: Set<Int> {
        Set(characters.indices)
    }

    private var selectionAreaHeight: CGFloat {
        tokenCellSize * 5 + tokenCellSpacing * 4 + 8
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分词选择")
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Text("点选方块选择字符，按原顺序拼接后完成键入")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("支持 Shift + 点击做连续选择；快捷按钮会直接替换当前选择")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("全选") {
                        selectedIndices = allIndices
                    }
                    Button("反选") {
                        selectedIndices = allIndices.subtracting(selectedIndices)
                    }
                    Button("仅数字") {
                        selectOnly(where: isDigit)
                    }
                    Button("手机号段") {
                        selectPhoneNumberLikeDigits()
                    }
                    Button("仅字母") {
                        selectOnly(where: isASCIIAlpha)
                    }
                    Button("仅空白") {
                        selectOnly(where: isWhitespace)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if characters.isEmpty {
                Text("当前文本为空")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: selectionAreaHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: tokenCellSize, maximum: tokenCellSize), spacing: tokenCellSpacing)],
                        spacing: tokenCellSpacing
                    ) {
                        ForEach(characters.indices, id: \.self) { index in
                            let isSelected = selectedIndices.contains(index)
                            Button {
                                handleCellTap(at: index)
                            } label: {
                                Text(displayText(for: characters[index]))
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(isSelected ? .white : .primary)
                                    .frame(width: tokenCellSize, height: tokenCellSize)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.14))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: selectionAreaHeight)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("已选择 \(selectedIndices.count) 个字符")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(selectedText.isEmpty ? "（尚未选择）" : selectedText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    )
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("清空选择") { selectedIndices.removeAll() }
                    .disabled(selectedIndices.isEmpty)
                Button("完成键入") {
                    guard canSubmit else { return }
                    onSubmit(selectedText)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(16)
        .frame(width: 520)
    }

    private func displayText(for character: Character) -> String {
        switch character {
        case " ":
            return "SP"
        case "\n":
            return "\\n"
        case "\t":
            return "\\t"
        default:
            return String(character)
        }
    }

    private func handleCellTap(at index: Int) {
        let isRangeSelection = NSEvent.modifierFlags.contains(.shift)
        if isRangeSelection, let anchor = rangeAnchorIndex {
            let lower = min(anchor, index)
            let upper = max(anchor, index)
            selectedIndices.formUnion(lower...upper)
        } else {
            selectedIndices.formSymmetricDifference([index])
        }
        rangeAnchorIndex = index
    }

    private func selectOnly(where predicate: (Character) -> Bool) {
        selectedIndices = Set(characters.indices.filter { predicate(characters[$0]) })
    }

    private func selectPhoneNumberLikeDigits() {
        var result = Set<Int>()
        var runStart: Int?

        for index in characters.indices {
            if isDigit(characters[index]) {
                if runStart == nil {
                    runStart = index
                }
            } else if let start = runStart {
                if index - start >= 11 {
                    result.formUnion(start..<index)
                }
                runStart = nil
            }
        }

        if let start = runStart, characters.count - start >= 11 {
            result.formUnion(start..<characters.count)
        }

        selectedIndices = result.isEmpty
            ? Set(characters.indices.filter { isDigit(characters[$0]) })
            : result
    }

    private func isDigit(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.decimalDigits.contains)
    }

    private func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }

    private func isASCIIAlpha(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        return (scalar.value >= 65 && scalar.value <= 90)
            || (scalar.value >= 97 && scalar.value <= 122)
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
