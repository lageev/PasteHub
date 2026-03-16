import SwiftUI
import AppKit

struct SettingsView: View {
    var settings: SettingsManager

    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("通用", systemImage: "gear") }
            HotkeyTab(settings: settings)
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            ExcludedAppsTab(settings: settings)
                .tabItem { Label("排除应用", systemImage: "hand.raised.slash") }
        }
        .frame(width: 480, height: 340)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @Bindable var settings: SettingsManager

    private let countOptions = [10, 20, 50, 100, 200, 500]

    var body: some View {
        Form {
            Section("历史记录") {
                Picker("最大保留条数", selection: $settings.maxHistoryCount) {
                    ForEach(countOptions, id: \.self) { n in
                        Text("\(n) 条").tag(n)
                    }
                }
            }
            Section("系统") {
                Toggle("开机自动启动", isOn: $settings.launchAtLogin)
            }
            Section("面板") {
                Picker("弹出位置", selection: $settings.panelEdge) {
                    ForEach(PanelEdge.allCases) { edge in
                        Text(edge.title).tag(edge)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hotkey

private struct HotkeyTab: View {
    var settings: SettingsManager

    var body: some View {
        Form {
            Section("全局快捷键") {
                HStack {
                    Text("显示 / 隐藏面板")
                    Spacer()
                    HotkeyRecorderButton(
                        displayString: settings.hotkeyDisplayString,
                        onRecorded: { code, mods in
                            settings.setHotkey(keyCode: code, modifiers: mods)
                        }
                    )
                }
            }
            Section("菜单快捷键") {
                ShortcutRow(label: "打开设置", shortcut: "\u{2318},")
                ShortcutRow(label: "退出应用", shortcut: "\u{2318}Q")
            }
            Section("面板操作") {
                ShortcutRow(label: "完成键入条目", shortcut: "单击卡片")
                ShortcutRow(label: "重新复制 / 标签 / 删除", shortcut: "卡片按钮或右键菜单")
            }
            Section {
                Text("点击全局快捷键区域后按下新的组合键即可修改，按 Esc 取消。单击卡片会先复制内容，再尝试自动键入。首次授予辅助功能权限后建议重启 PasteHub；若仍无效，请在系统设置中删除后重新添加 PasteHub 权限。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutRow: View {
    let label: String
    let shortcut: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcut)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

// MARK: - Excluded Apps

private struct ExcludedAppsTab: View {
    @Bindable var settings: SettingsManager

    private var availableApps: [(name: String, bundleID: String, icon: NSImage)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let name = app.localizedName,
                      let id = app.bundleIdentifier,
                      let icon = app.icon,
                      !settings.excludedApps.contains(where: { $0.bundleIdentifier == id })
                else { return nil }
                return (name, id, icon)
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            if settings.excludedApps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "hand.raised.slash")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("暂无排除应用")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("来自排除名单中应用的剪贴板内容将不会被记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(settings.excludedApps) { app in
                        HStack(spacing: 10) {
                            appIcon(for: app.bundleIdentifier)
                                .resizable()
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.system(size: 13, weight: .medium))
                                Text(app.bundleIdentifier)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                settings.excludedApps.removeAll { $0.id == app.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            HStack {
                Menu {
                    ForEach(availableApps, id: \.bundleID) { app in
                        Button {
                            settings.excludedApps.append(
                                ExcludedApp(bundleIdentifier: app.bundleID, name: app.name)
                            )
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: app.icon)
                            }
                        }
                    }

                    if availableApps.isEmpty {
                        Text("无可添加的运行中应用")
                    }
                } label: {
                    Label("添加正在运行的应用", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .fixedSize()

                Spacer()
            }
            .padding(10)
        }
    }

    private func appIcon(for bundleID: String) -> Image {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            return Image(nsImage: icon)
        }
        return Image(systemName: "app")
    }
}

// MARK: - Hotkey Recorder

private struct HotkeyRecorderButton: View {
    let displayString: String
    let onRecorded: (UInt16, UInt) -> Void
    @State private var isRecording = false

    var body: some View {
        ZStack {
            if isRecording {
                KeyCatcher(
                    onKey: { code, flags in
                        onRecorded(code, flags.rawValue)
                        isRecording = false
                    },
                    onCancel: { isRecording = false }
                )
                .frame(width: 0, height: 0)
            }

            Button { isRecording = true } label: {
                Text(isRecording ? "按下快捷键组合..." : displayString)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(minWidth: 120)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isRecording ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct KeyCatcher: NSViewRepresentable {
    let onKey: (UInt16, NSEvent.ModifierFlags) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let v = KeyCatcherView()
        v.onKey = onKey
        v.onCancel = onCancel
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {}

    class KeyCatcherView: NSView {
        var onKey: ((UInt16, NSEvent.ModifierFlags) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
            guard !modifierKeyCodes.contains(event.keyCode) else { return }

            if event.keyCode == 53 { onCancel?(); return }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .option, .control, .shift]).isEmpty else { return }

            onKey?(event.keyCode, flags)
        }
    }
}
