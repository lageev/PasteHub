import AppKit
import SwiftUI

final class FloatingPanel: NSPanel, NSWindowDelegate {
    private let settings: SettingsManager
    private var isPresented = false
    private let topBottomPanelHeight: CGFloat = 320
    private let sidePanelWidth: CGFloat = 520
    private let travelDistance: CGFloat = 18
    private let panelCornerRadius: CGFloat = 18

    init(rootView: some View, settings: SettingsManager) {
        self.settings = settings
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )

        delegate = self
        isFloatingPanel = false
        level = .normal
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        contentViewController = NSHostingController(rootView: rootView)
        configureContainerAppearance()
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

    func updatePlacementIfVisible(animated: Bool = true) {
        guard isVisible, let screen = targetScreenForCurrentFrame() else { return }
        let frames = placementFrames(for: settings.panelEdge, on: screen)
        if animated {
            animate(to: frames.shown, duration: 0.16)
        } else {
            setFrame(frames.shown, display: true)
        }
    }

    private var shouldHideOnToggle: Bool {
        isPresented && isVisible && NSApp.isActive && isKeyWindow
    }

    private func show() {
        guard let screen = targetScreenForShow() else { return }
        isPresented = true
        let frames = placementFrames(for: settings.panelEdge, on: screen)

        if !isVisible {
            setFrame(frames.hidden, display: false)
        }

        level = .floating
        NSApp.activate(ignoringOtherApps: true)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)

        animate(to: frames.shown, duration: 0.18) { [weak self] in
            guard let self else { return }
            self.level = .normal
            self.makeKeyAndOrderFront(nil)
        }
    }

    private func hide() {
        isPresented = false
        guard isVisible, let screen = targetScreenForCurrentFrame() else {
            level = .normal
            orderOut(nil)
            return
        }
        let frames = placementFrames(for: settings.panelEdge, on: screen)
        animate(to: frames.hidden, duration: 0.14) { [weak self] in
            guard let self else { return }
            self.level = .normal
            self.orderOut(nil)
        }
    }

    private func animate(to targetFrame: NSRect, duration: TimeInterval, completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            animator().setFrame(targetFrame, display: true)
        } completionHandler: {
            completion?()
        }
    }

    private func placementFrames(for edge: PanelEdge, on screen: NSScreen) -> (shown: NSRect, hidden: NSRect) {
        let visible = screen.visibleFrame
        let shown = shownFrame(for: edge, in: visible)
        let hidden = hiddenFrame(from: shown, edge: edge, visibleFrame: visible)
        return (shown, hidden)
    }

    private func shownFrame(for edge: PanelEdge, in visibleFrame: NSRect) -> NSRect {
        let sideWidth = min(sidePanelWidth, visibleFrame.width)
        let topBottomHeight = min(topBottomPanelHeight, visibleFrame.height)

        switch edge {
        case .bottom:
            return NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: topBottomHeight
            )
        case .top:
            return NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.maxY - topBottomHeight,
                width: visibleFrame.width,
                height: topBottomHeight
            )
        case .left:
            return NSRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: sideWidth,
                height: visibleFrame.height
            )
        case .right:
            return NSRect(
                x: visibleFrame.maxX - sideWidth,
                y: visibleFrame.minY,
                width: sideWidth,
                height: visibleFrame.height
            )
        }
    }

    private func hiddenFrame(from shownFrame: NSRect, edge: PanelEdge, visibleFrame: NSRect) -> NSRect {
        switch edge {
        case .bottom:
            return NSRect(
                x: shownFrame.origin.x,
                y: visibleFrame.minY - shownFrame.height - travelDistance,
                width: shownFrame.width,
                height: shownFrame.height
            )
        case .top:
            return NSRect(
                x: shownFrame.origin.x,
                y: visibleFrame.maxY + travelDistance,
                width: shownFrame.width,
                height: shownFrame.height
            )
        case .left:
            return NSRect(
                x: visibleFrame.minX - shownFrame.width - travelDistance,
                y: shownFrame.origin.y,
                width: shownFrame.width,
                height: shownFrame.height
            )
        case .right:
            return NSRect(
                x: visibleFrame.maxX + travelDistance,
                y: shownFrame.origin.y,
                width: shownFrame.width,
                height: shownFrame.height
            )
        }
    }

    private func targetScreenForShow() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func targetScreenForCurrentFrame() -> NSScreen? {
        if let panelScreen = screen {
            return panelScreen
        }
        let centerPoint = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(centerPoint) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func configureContainerAppearance() {
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = panelCornerRadius
        contentView?.layer?.masksToBounds = true
    }
}
