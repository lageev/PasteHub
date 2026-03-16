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
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var settingsWindow: NSWindow?
    private var lastHotKeyTriggerTime: TimeInterval = 0

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardownMonitors()
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

        statusItem.menu = menu
    }

    // MARK: - Floating Panel

    private func setupPanel() {
        panel = FloatingPanel(
            rootView: ClipboardListView(
                store: store,
                settings: settings,
                onOpenSettings: { [weak self] in
                    self?.showSettings()
                },
                onActivateItem: { [weak self] item in
                    self?.handleItemActivation(item)
                }
            ),
            settings: settings
        )
    }

    @objc func togglePanel() {
        if panel?.isVisible != true {
            pasteService.rememberFrontmostExternalApp()
        }
        panel?.toggle()
    }

    // MARK: - Settings

    @objc func showSettings() {
        if let w = settingsWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        w.title = "PasteHub 设置"
        w.contentViewController = NSHostingController(rootView: SettingsView(settings: settings))
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = w
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

    // MARK: - Global Hot Key

    private func setupHotKey() {
        registerHotKeyHandlerIfNeeded()
        registerHotKey()
    }

    private func handleHotKeyTrigger() {
        if let sw = settingsWindow, sw.isKeyWindow {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastHotKeyTriggerTime < 0.25 {
            return
        }
        lastHotKeyTriggerTime = now
        togglePanel()
    }

    private func reloadHotKey() {
        unregisterHotKey()
        registerHotKey()
    }

    private func registerHotKeyHandlerIfNeeded() {
        guard hotKeyHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in delegate.handleHotKeyTrigger() }
                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &hotKeyHandlerRef
        )
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }

        let hotKeyID = EventHotKeyID(signature: OSType(0x50544842), id: 1) // 'PTHB'
        let keyCode = UInt32(settings.hotkeyKeyCode)
        let modifiers = Self.carbonModifiers(from: settings.hotkeyModifiers)

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func teardownHotKeyMonitors() {
        unregisterHotKey()
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
