import Foundation
import AppKit
import Observation
import ServiceManagement

struct ExcludedApp: Codable, Identifiable, Hashable {
    let bundleIdentifier: String
    let name: String
    var id: String { bundleIdentifier }
}

enum PanelEdge: String, CaseIterable, Identifiable {
    case bottom
    case top
    case left
    case right

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bottom: return "底部"
        case .top: return "顶部"
        case .left: return "左侧"
        case .right: return "右侧"
        }
    }
}

enum CompactPanelSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }

    var heightRatio: CGFloat {
        switch self {
        case .small: return 0.45
        case .medium: return 0.60
        case .large: return 0.75
        }
    }
}

enum CompactDensity: String, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "宽松"
        case .medium: return "均衡"
        case .high: return "紧凑"
        }
    }
}

enum CompactPanelPosition: String, CaseIterable, Identifiable {
    case statusItem
    case followMouse
    case screenCenter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .statusItem: return "状态栏图标处"
        case .followMouse: return "跟随鼠标指针"
        case .screenCenter: return "始终屏幕中间"
        }
    }

    static func availablePositions(for density: CompactDensity) -> [CompactPanelPosition] {
        if density == .high {
            return Self.allCases
        }
        return [.statusItem, .screenCenter]
    }
}

@MainActor
@Observable
final class SettingsManager {
    var maxHistoryCount: Int {
        didSet { UserDefaults.standard.set(maxHistoryCount, forKey: "maxHistoryCount") }
    }

    var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            updateLoginItem()
        }
    }

    private(set) var hotkeyKeyCode: UInt16 {
        didSet { UserDefaults.standard.set(Int(hotkeyKeyCode), forKey: "hotkeyKeyCode") }
    }

    private(set) var hotkeyModifiers: UInt {
        didSet { UserDefaults.standard.set(Int(hotkeyModifiers), forKey: "hotkeyModifiers") }
    }

    var excludedApps: [ExcludedApp] {
        didSet {
            guard let data = try? JSONEncoder().encode(excludedApps) else { return }
            UserDefaults.standard.set(data, forKey: "excludedApps")
        }
    }

    var panelEdge: PanelEdge {
        didSet {
            UserDefaults.standard.set(panelEdge.rawValue, forKey: "panelEdge")
            onPanelEdgeChanged?()
        }
    }

    var compactModeEnabled: Bool {
        didSet {
            UserDefaults.standard.set(compactModeEnabled, forKey: "compactModeEnabled")
            onCompactModeChanged?()
        }
    }

    var compactPanelSize: CompactPanelSize {
        didSet {
            UserDefaults.standard.set(compactPanelSize.rawValue, forKey: "compactPanelSize")
            onCompactPanelSizeChanged?()
        }
    }

    var compactDensity: CompactDensity {
        didSet {
            UserDefaults.standard.set(compactDensity.rawValue, forKey: "compactDensity")
            let normalizedPosition = Self.normalizedCompactPanelPosition(
                for: compactDensity,
                requested: compactPanelPosition
            )
            if compactPanelPosition != normalizedPosition {
                compactPanelPosition = normalizedPosition
            }
            onCompactDensityChanged?()
        }
    }

    var compactPanelPosition: CompactPanelPosition {
        didSet {
            let normalizedPosition = Self.normalizedCompactPanelPosition(
                for: compactDensity,
                requested: compactPanelPosition
            )
            if compactPanelPosition != normalizedPosition {
                compactPanelPosition = normalizedPosition
                return
            }
            UserDefaults.standard.set(compactPanelPosition.rawValue, forKey: "compactPanelPosition")
            onCompactPanelPositionChanged?()
        }
    }

    var onHotkeyChanged: (() -> Void)?
    var onPanelEdgeChanged: (() -> Void)?
    var onCompactModeChanged: (() -> Void)?
    var onCompactPanelSizeChanged: (() -> Void)?
    var onCompactDensityChanged: (() -> Void)?
    var onCompactPanelPositionChanged: (() -> Void)?

    init() {
        let d = UserDefaults.standard

        if let v = d.object(forKey: "maxHistoryCount") as? Int, v > 0 {
            maxHistoryCount = v
        } else {
            maxHistoryCount = 50
        }

        launchAtLogin = d.bool(forKey: "launchAtLogin")

        if let v = d.object(forKey: "hotkeyKeyCode") as? Int {
            hotkeyKeyCode = UInt16(v)
        } else {
            hotkeyKeyCode = 9
        }

        if let v = d.object(forKey: "hotkeyModifiers") as? Int, v > 0 {
            hotkeyModifiers = UInt(v)
        } else {
            hotkeyModifiers = NSEvent.ModifierFlags([.command, .shift]).rawValue
        }

        if let data = d.data(forKey: "excludedApps"),
           let decoded = try? JSONDecoder().decode([ExcludedApp].self, from: data) {
            excludedApps = decoded
        } else {
            excludedApps = []
        }

        if let raw = d.string(forKey: "panelEdge"),
           let edge = PanelEdge(rawValue: raw) {
            panelEdge = edge
        } else {
            panelEdge = .bottom
        }

        compactModeEnabled = d.bool(forKey: "compactModeEnabled")

        if let raw = d.string(forKey: "compactPanelSize"),
           let size = CompactPanelSize(rawValue: raw) {
            compactPanelSize = size
        } else {
            compactPanelSize = .medium
        }

        let initialDensity: CompactDensity
        if let raw = d.string(forKey: "compactDensity"),
           let density = CompactDensity(rawValue: raw) {
            initialDensity = density
        } else {
            initialDensity = .low
        }
        compactDensity = initialDensity

        let initialPosition: CompactPanelPosition
        if let raw = d.string(forKey: "compactPanelPosition"),
           let position = CompactPanelPosition(rawValue: raw) {
            initialPosition = position
        } else {
            initialPosition = .statusItem
        }
        compactPanelPosition = Self.normalizedCompactPanelPosition(
            for: initialDensity,
            requested: initialPosition
        )
    }

    func setHotkey(keyCode: UInt16, modifiers: UInt) {
        hotkeyKeyCode = keyCode
        hotkeyModifiers = modifiers
        onHotkeyChanged?()
    }

    func isAppExcluded(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return excludedApps.contains { $0.bundleIdentifier == id }
    }

    var hotkeyDisplayString: String {
        var s = ""
        let flags = NSEvent.ModifierFlags(rawValue: hotkeyModifiers)
        if flags.contains(.control) { s += "\u{2303}" }
        if flags.contains(.option) { s += "\u{2325}" }
        if flags.contains(.shift) { s += "\u{21E7}" }
        if flags.contains(.command) { s += "\u{2318}" }
        s += Self.keyName(for: hotkeyKeyCode)
        return s
    }

    nonisolated static func keyName(for keyCode: UInt16) -> String {
        let map: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
            32: "U", 33: "[", 34: "I", 35: "P", 36: "\u{23CE}", 37: "L", 38: "J",
            39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
            47: ".", 48: "\u{21E5}", 49: "\u{2423}", 50: "`", 51: "\u{232B}", 53: "\u{238B}",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F11", 105: "F13", 107: "F14",
            109: "F10", 111: "F12", 113: "F15",
            118: "F4", 120: "F2", 122: "F1",
            123: "\u{2190}", 124: "\u{2192}", 125: "\u{2193}", 126: "\u{2191}",
        ]
        return map[keyCode] ?? "Key\(keyCode)"
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {}
    }

    private static func normalizedCompactPanelPosition(
        for density: CompactDensity,
        requested position: CompactPanelPosition
    ) -> CompactPanelPosition {
        CompactPanelPosition.availablePositions(for: density).contains(position) ? position : .statusItem
    }
}
