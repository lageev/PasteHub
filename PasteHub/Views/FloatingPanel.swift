import AppKit
import SwiftUI

final class FloatingPanel: NSPanel, NSWindowDelegate {
    private var isPresented = false

    init(rootView: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )

        delegate = self
        isFloatingPanel = false
        level = .normal
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titlebarSeparatorStyle = .none
        titleVisibility = .hidden
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        isOpaque = true
        backgroundColor = .windowBackgroundColor
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentViewController = NSHostingController(rootView: rootView)

        center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func close() {
        hide()
    }

    func windowWillClose(_ notification: Notification) {
        isPresented = false
    }

    func toggle() {
        if shouldHideOnToggle {
            hide()
        } else {
            show()
        }
    }

    private var shouldHideOnToggle: Bool {
        isPresented && isVisible && NSApp.isActive && isKeyWindow
    }

    private func show() {
        isPresented = true
        if !isVisible { center() }
        level = .floating
        NSApp.activate(ignoringOtherApps: true)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.level = .normal
            self.makeKeyAndOrderFront(nil)
        }
    }

    private func hide() {
        isPresented = false
        level = .normal
        orderOut(nil)
    }
}
