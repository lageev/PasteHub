import AppKit
import Carbon
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var store = ClipboardStore()
    private(set) var settings = SettingsManager()
    private let pasteService = PasteToAppService()
    private var monitor: ClipboardMonitor!
    private var panel: FloatingPanel!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var hotKeyHandlerRef: EventHandlerRef?
    private var settingsWindow: NSWindow?
    private var shouldPresentSettingsAfterPanelHides = false
    private var lastHotKeyTriggerTime: TimeInterval = 0
    private enum HotKeyActionID: UInt32 {
        case togglePanel = 1
        case showSettings = 2
        case clearHistory = 3
    }

    private let hotKeySignature = OSType(0x50544842) // 'PTHB'

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = ClipboardMonitor(store: store, settings: settings)
        monitor.start()

        store.onClipboardWrite = { [weak self] in
            self?.monitor.syncChangeCount()
        }

        setupStatusItem()
        setupPanel()
        setupHotKey()

        settings.onHotkeyChanged = { [weak self] in
            self?.reloadHotKey()
        }
        settings.onPanelEdgeChanged = { [weak self] in
            self?.panel?.updatePlacementIfVisible()
        }
        settings.onCompactModeChanged = { [weak self] in
            self?.configureStatusItemInteraction()
            self?.panel?.updatePlacementIfVisible()
        }
        settings.onCompactPanelSizeChanged = { [weak self] in
            self?.panel?.updatePlacementIfVisible()
        }
        settings.onCompactDensityChanged = { [weak self] in
            self?.panel?.updatePlacementIfVisible()
        }
        settings.onCompactPanelPositionChanged = { [weak self] in
            self?.panel?.updatePlacementIfVisible()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardownMonitors()
    }

    func applicationDidResignActive(_ notification: Notification) {
        panel?.close()
        settingsWindow?.close()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "PasteHub"
        )

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "显示 / 隐藏面板", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "清空记录", action: #selector(clearHistory), keyEquivalent: ""))

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "退出 PasteHub", action: #selector(quitApp), keyEquivalent: "q"))

        statusMenu = menu
        configureStatusItemInteraction()
    }

    private func configureStatusItemInteraction() {
        guard let button = statusItem.button else { return }

        if settings.compactModeEnabled {
            statusItem.menu = nil
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        } else {
            button.sendAction(on: [])
            button.action = nil
            button.target = nil
            statusItem.menu = statusMenu
        }
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePanel()
            return
        }

        switch event.type {
        case .rightMouseUp:
            showStatusMenu(relativeTo: sender)
        default:
            togglePanel()
        }
    }

    private func showStatusMenu(relativeTo _: NSStatusBarButton) {
        guard let statusMenu else { return }
        let previousMenu = statusItem.menu
        let previousAction = statusItem.button?.action
        let previousTarget = statusItem.button?.target

        statusItem.button?.action = nil
        statusItem.button?.target = nil
        statusItem.menu = statusMenu
        statusItem.button?.performClick(nil)
        statusItem.menu = previousMenu
        statusItem.button?.action = previousAction
        statusItem.button?.target = previousTarget
    }

    // MARK: - Floating Panel

    private func setupPanel() {
        panel = FloatingPanel(
            rootView: ClipboardListView(
                store: store,
                settings: settings,
                onOpenSettings: { [weak self] in
                    self?.openSettingsFromPanel()
                },
                onActivateItem: { [weak self] item in
                    self?.handleItemActivation(item)
                }
            ),
            settings: settings
        )
        panel.statusButtonProvider = { [weak self] in
            self?.statusItem.button
        }
        panel.onDidHide = { [weak self] in
            guard let self else { return }

            if self.shouldPresentSettingsAfterPanelHides {
                self.shouldPresentSettingsAfterPanelHides = false
                self.presentSettingsWindow(centerBeforeShowing: false)
                return
            }

            self.settingsWindow?.close()
        }
    }

    @objc func togglePanel() {
        if panel?.isVisible != true {
            pasteService.rememberFrontmostExternalApp()
        }
        panel?.toggle()
    }

    // MARK: - Settings

    @objc func showSettings() {
        presentSettingsWindow(centerBeforeShowing: false)
    }

    private func openSettingsFromPanel() {
        guard panel?.isVisible == true else {
            presentSettingsWindow(centerBeforeShowing: false)
            return
        }

        shouldPresentSettingsAfterPanelHides = true
        panel?.close()
    }

    private func presentSettingsWindow(centerBeforeShowing: Bool) {
        if let w = settingsWindow {
            w.level = panel.level
            if centerBeforeShowing {
                centerWindowOnActiveScreen(w)
            }
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { [weak self, weak w] in
                guard let self, let w, self.settingsWindow === w else { return }
                if !centerBeforeShowing {
                    self.centerWindowOnActiveScreen(w)
                }
                self.focusSettingsSidebar(in: w)
            }
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: !centerBeforeShowing
        )
        w.title = "PasteHub 设置"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.toolbarStyle = .unified
        w.isMovableByWindowBackground = true
        w.contentViewController = NSHostingController(rootView: SettingsView(settings: settings))
        w.minSize = NSSize(width: 820, height: 560)
        w.isReleasedWhenClosed = false
        w.level = panel.level
        if centerBeforeShowing {
            settingsWindow = w
            centerWindowOnActiveScreen(w)
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !centerBeforeShowing {
            settingsWindow = w
        }
        DispatchQueue.main.async { [weak self, weak w] in
            guard let self, let w, self.settingsWindow === w else { return }
            if !centerBeforeShowing {
                self.centerWindowOnActiveScreen(w)
            }
            self.focusSettingsSidebar(in: w)
        }
    }

    @objc private func clearHistory() {
        store.clearAll()
    }

    private func handleItemActivation(_ item: ClipboardItem) {
        store.copyToClipboard(item)
        if panel?.isVisible == true {
            panel?.toggle()
        }
        pasteService.pasteIntoRememberedAppIfPossible()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func centerWindowOnActiveScreen(_ window: NSWindow) {
        let targetScreen = NSScreen.main ?? NSScreen.screens.first

        guard let screen = targetScreen else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visibleFrame.minX + (visibleFrame.width - size.width) / 2,
            y: visibleFrame.minY + (visibleFrame.height - size.height) / 2
        )
        window.setFrameOrigin(origin)
    }

    private func focusSettingsSidebar(in window: NSWindow) {
        guard let contentView = window.contentView,
              let outlineView = firstSubview(ofType: NSOutlineView.self, in: contentView)
        else { return }

        window.makeFirstResponder(outlineView)
    }

    private func firstSubview<T: NSView>(ofType type: T.Type, in view: NSView) -> T? {
        if let match = view as? T {
            return match
        }

        for subview in view.subviews {
            if let match = firstSubview(ofType: type, in: subview) {
                return match
            }
        }

        return nil
    }

    // MARK: - Global Hot Key

    private func setupHotKey() {
        registerHotKeyHandlerIfNeeded()
        registerHotKeys()
    }

    private func handleHotKeyEvent(actionID: HotKeyActionID?) {
        guard let actionID else { return }
        if let sw = settingsWindow, sw.isKeyWindow {
            return
        }

        switch actionID {
        case .togglePanel:
            handleTogglePanelHotKeyTrigger()
        case .showSettings:
            showSettings()
        case .clearHistory:
            clearHistory()
        }
    }

    private func handleTogglePanelHotKeyTrigger() {
        if let sw = settingsWindow, sw.isKeyWindow {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastHotKeyTriggerTime < 0.4 {
            return
        }
        lastHotKeyTriggerTime = now
        togglePanel()
    }

    private func reloadHotKey() {
        unregisterHotKeys()
        registerHotKeys()
    }

    private func registerHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                let actionID: HotKeyActionID?
                if let event {
                    var hotKeyID = EventHotKeyID()
                    let status = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    actionID = status == noErr ? HotKeyActionID(rawValue: hotKeyID.id) : nil
                } else {
                    actionID = nil
                }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in delegate.handleHotKeyEvent(actionID: actionID) }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandlerRef
        )
    }

    private func registerHotKeys() {
        registerHotKey(
            id: .togglePanel,
            keyCode: settings.hotkeyKeyCode,
            modifiers: settings.hotkeyModifiers
        )

        if let showSettingsHotkey = settings.showSettingsHotkey {
            registerHotKey(
                id: .showSettings,
                keyCode: showSettingsHotkey.keyCode,
                modifiers: showSettingsHotkey.modifiers
            )
        }

        if let clearHistoryHotkey = settings.clearHistoryHotkey {
            registerHotKey(
                id: .clearHistory,
                keyCode: clearHistoryHotkey.keyCode,
                modifiers: clearHistoryHotkey.modifiers
            )
        }
    }

    private func registerHotKey(id: HotKeyActionID, keyCode: UInt16, modifiers: UInt) {
        guard hotKeyRefs[id.rawValue] == nil else { return }
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id.rawValue)

        let status = RegisterEventHotKey(
            UInt32(keyCode),
            Self.carbonModifiers(from: modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else { return }
        hotKeyRefs[id.rawValue] = hotKeyRef
    }

    private func unregisterHotKeys() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
    }

    private func teardownHotKeyMonitors() {
        unregisterHotKeys()
        if let hotKeyHandlerRef {
            RemoveEventHandler(hotKeyHandlerRef)
            self.hotKeyHandlerRef = nil
        }
    }

    private func teardownMonitors() {
        monitor?.stop()
        teardownHotKeyMonitors()
    }

    private nonisolated static func carbonModifiers(from rawFlags: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: rawFlags)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}
