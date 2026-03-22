import AppKit
import SwiftUI

extension Notification.Name {
    static let panelKeyboardInput = Notification.Name("panelKeyboardInput")
    static let panelDidHide = Notification.Name("panelDidHide")
    static let panelSelectionMove = Notification.Name("panelSelectionMove")
    static let panelSelectionActivate = Notification.Name("panelSelectionActivate")
    static let panelCommandModifierChanged = Notification.Name("panelCommandModifierChanged")
    static let panelQuickSelect = Notification.Name("panelQuickSelect")
}

final class FloatingPanel: NSPanel, NSWindowDelegate {
    private let settings: SettingsManager
    private var isPresented = false
    private var isHiding = false
    private static let quickSelectKeys: [Character] = Array("1234567890abcdefghijklmnopqrstuvwxyz")
    var onDidHide: (() -> Void)?
    var statusButtonProvider: (() -> NSStatusBarButton?)?
    private let topBottomPanelHeight: CGFloat = 320
    private let sidePanelWidth: CGFloat = 520
    private let compactPanelWidth: CGFloat = CompactPanelLayout.width
    private let compactPanelMargin: CGFloat = CompactPanelLayout.margin
    private let travelDistance: CGFloat = 18
    private let panelCornerRadius: CGFloat = 18

    init(rootView: some View, settings: SettingsManager) {
        self.settings = settings
        super.init(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: compactPanelWidth,
                height: CompactPanelLayout.height(
                    for: NSScreen.main,
                    size: settings.compactPanelSize,
                    density: settings.compactDensity,
                    position: settings.compactPanelPosition
                )
            ),
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

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command),
           let quickIndex = quickSelectIndex(from: event) {
            NotificationCenter.default.post(
                name: .panelQuickSelect,
                object: nil,
                userInfo: ["index": quickIndex]
            )
            return
        }

        if modifiers.intersection([.command, .control, .option]).isEmpty {
            if let direction = selectionDirection(for: event.keyCode) {
                NotificationCenter.default.post(
                    name: .panelSelectionMove,
                    object: nil,
                    userInfo: ["direction": direction]
                )
                return
            }

            if event.keyCode == 36 || event.keyCode == 76 {
                NotificationCenter.default.post(name: .panelSelectionActivate, object: nil)
                return
            }

            if let characters = event.characters,
               !characters.isEmpty,
               characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) {
                NotificationCenter.default.post(
                    name: .panelKeyboardInput,
                    object: nil,
                    userInfo: ["characters": characters]
                )
                return
            }
        }
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        NotificationCenter.default.post(
            name: .panelCommandModifierChanged,
            object: nil,
            userInfo: ["isPressed": modifiers.contains(.command)]
        )
        super.flagsChanged(with: event)
    }

    override func close() {
        hide()
    }

    func windowWillClose(_ notification: Notification) {
        isPresented = false
    }

    func windowDidResignKey(_ notification: Notification) {
        guard isPresented, isVisible else { return }
        guard attachedSheet == nil, sheets.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isPresented, self.isVisible else { return }
            guard self.attachedSheet == nil, self.sheets.isEmpty else { return }
            guard !NSApp.isActive else { return }
            self.hide()
        }
    }

    func toggle() {
        if shouldHideOnToggle {
            hide()
        } else {
            show()
        }
    }

    func updatePlacementIfVisible(animated: Bool = true) {
        guard isVisible else { return }
        let targetScreen: NSScreen?
        if settings.compactModeEnabled && settings.compactPanelPosition == .followMouse {
            targetScreen = screenContainingMouse() ?? targetScreenForCurrentFrame()
        } else {
            targetScreen = targetScreenForCurrentFrame()
        }
        guard let screen = targetScreen else { return }
        let frames = placementFrames(for: settings.panelEdge, on: screen)
        if animated {
            animate(to: frames.shown, duration: 0.16)
        } else {
            setFrame(frames.shown, display: true)
        }
    }

    private var shouldHideOnToggle: Bool {
        isVisible
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
            self.makeKeyAndOrderFront(nil)
        }
    }

    private func hide() {
        guard !isHiding else { return }
        isHiding = true
        isPresented = false
        NotificationCenter.default.post(name: .panelDidHide, object: nil)
        guard isVisible, let screen = targetScreenForCurrentFrame() else {
            level = .normal
            orderOut(nil)
            onDidHide?()
            isHiding = false
            return
        }
        let hiddenTargetFrame: NSRect
        if settings.compactModeEnabled && settings.compactPanelPosition == .followMouse {
            // 关闭时沿当前可见位置做位移，不再重新跟随鼠标重算锚点，避免出现先跳位再淡出的感觉。
            hiddenTargetFrame = NSRect(
                x: frame.origin.x,
                y: frame.origin.y + travelDistance,
                width: frame.width,
                height: frame.height
            )
        } else {
            let frames = placementFrames(for: settings.panelEdge, on: screen)
            hiddenTargetFrame = frames.hidden
        }
        level = .floating
        animate(to: hiddenTargetFrame, duration: 0.14) { [weak self] in
            guard let self else { return }
            self.level = .normal
            self.orderOut(nil)
            self.onDidHide?()
            self.isHiding = false
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
        if settings.compactModeEnabled {
            return compactPlacementFrames(on: screen)
        }

        let visible = screen.visibleFrame
        let shown = shownFrame(for: edge, in: visible)
        let hidden = hiddenFrame(from: shown, edge: edge, visibleFrame: visible)
        return (shown, hidden)
    }

    private func compactPlacementFrames(on screen: NSScreen) -> (shown: NSRect, hidden: NSRect) {
        let visible = screen.visibleFrame
        let shown = compactShownFrame(
            on: screen,
            visibleFrame: visible,
            position: settings.compactPanelPosition
        )
        let hidden = NSRect(
            x: shown.origin.x,
            y: shown.origin.y + travelDistance,
            width: shown.width,
            height: shown.height
        )
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

    private func compactShownFrame(
        on screen: NSScreen,
        visibleFrame: NSRect,
        position: CompactPanelPosition
    ) -> NSRect {
        let width = min(compactPanelWidth, visibleFrame.width - compactPanelMargin * 2)
        let height = CompactPanelLayout.height(
            for: screen,
            size: settings.compactPanelSize,
            density: settings.compactDensity,
            position: settings.compactPanelPosition
        )
        let maxX = visibleFrame.maxX - width - compactPanelMargin
        let maxY = visibleFrame.maxY - height - compactPanelMargin
        let minX = visibleFrame.minX + compactPanelMargin
        let minY = visibleFrame.minY + compactPanelMargin

        switch position {
        case .statusItem:
            let anchorFrame = statusButtonFrameOnScreen() ?? fallbackAnchorFrame(in: screen.frame)
            let preferredX = anchorFrame.midX - width / 2
            let preferredY = anchorFrame.minY - height - compactPanelMargin
            let x = min(max(preferredX, minX), maxX)
            let y = max(minY, min(preferredY, maxY))
            return NSRect(x: x, y: y, width: width, height: height)
        case .followMouse:
            let mouseLocation = NSEvent.mouseLocation
            let preferredX = mouseLocation.x - width / 2
            let preferredY = mouseLocation.y - height - compactPanelMargin
            let x = min(max(preferredX, minX), maxX)
            let y = max(minY, min(preferredY, maxY))
            return NSRect(x: x, y: y, width: width, height: height)
        case .screenCenter:
            let x = visibleFrame.minX + (visibleFrame.width - width) / 2
            let y = visibleFrame.minY + (visibleFrame.height - height) / 2
            return NSRect(x: x, y: y, width: width, height: height)
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
        if settings.compactModeEnabled {
            switch settings.compactPanelPosition {
            case .statusItem:
                if let buttonScreen = statusButtonProvider?()?.window?.screen {
                    return buttonScreen
                }
                return screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
            case .followMouse, .screenCenter:
                return screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
            }
        }
        return screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
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

    private func statusButtonFrameOnScreen() -> NSRect? {
        guard let button = statusButtonProvider?(),
              let window = button.window else {
            return nil
        }

        let frameInWindow = button.convert(button.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    private func fallbackAnchorFrame(in screenFrame: NSRect) -> NSRect {
        NSRect(
            x: screenFrame.midX - 10,
            y: screenFrame.maxY - 24,
            width: 20,
            height: 20
        )
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
    }

    private func selectionDirection(for keyCode: UInt16) -> String? {
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
              chars.count == 1,
              let key = chars.first else {
            return nil
        }
        return Self.quickSelectKeys.firstIndex(of: key)
    }
}
