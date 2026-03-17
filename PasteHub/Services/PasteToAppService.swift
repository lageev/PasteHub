import AppKit
import ApplicationServices

@MainActor
final class PasteToAppService {
    private static let accessibilityPromptedKey = "accessibilityPromptedOnce"

    static func resetAccessibilityPromptCache() {
        UserDefaults.standard.removeObject(forKey: accessibilityPromptedKey)
    }

    private var targetBundleIdentifier: String?
    private var targetProcessIdentifier: pid_t?
    private var targetFocusedElement: AXUIElement?
    private var targetFocusedElementProcessIdentifier: pid_t?
    private let maxSearchDepth = 8
    private let maxChildrenPerNode = 80
    private let searchFieldRole = "AXSearchField"
    private let webAreaRole = "AXWebArea"
    private let editableAttribute = "AXEditable"
    private let selectedTextAttribute = "AXSelectedText"
    private let traversalAttributes: [CFString] = [
        kAXContentsAttribute as CFString,
        kAXVisibleChildrenAttribute as CFString,
        kAXChildrenAttribute as CFString
    ]

    func rememberFrontmostExternalApp() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        guard frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else {
            targetBundleIdentifier = nil
            targetProcessIdentifier = nil
            targetFocusedElement = nil
            targetFocusedElementProcessIdentifier = nil
            return
        }
        targetBundleIdentifier = frontmost.bundleIdentifier
        targetProcessIdentifier = frontmost.processIdentifier

        let appElement = AXUIElementCreateApplication(frontmost.processIdentifier)
        if let focusedElement = copyElementValue(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString) {
            targetFocusedElement = deepestFocusedElement(startingFrom: focusedElement)
            targetFocusedElementProcessIdentifier = frontmost.processIdentifier
        } else {
            targetFocusedElement = nil
            targetFocusedElementProcessIdentifier = nil
        }
    }

    func pasteIntoRememberedAppIfPossible() {
        guard ensureAccessibilityPermission() else { return }
        guard let targetApp = resolveTargetApplication() else { return }

        targetApp.activate(options: [])
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard let self else { return }
            let focusedElement = focusEditableElementIfNeeded(in: targetApp)
            try? await Task.sleep(for: .milliseconds(40))
            if !insertClipboardTextIfPossible(into: focusedElement, for: targetApp) {
                postPasteShortcut(to: targetApp)
            }
        }
    }

    private func resolveTargetApplication() -> NSRunningApplication? {
        let selfBundleID = Bundle.main.bundleIdentifier

        if let pid = targetProcessIdentifier,
           let app = NSRunningApplication(processIdentifier: pid),
           !app.isTerminated,
           app.bundleIdentifier != selfBundleID {
            return app
        }

        if let bundleID = targetBundleIdentifier {
            let matched = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { !$0.isTerminated })
            if let matched, matched.bundleIdentifier != selfBundleID {
                return matched
            }
        }

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != selfBundleID {
            return frontmost
        }

        return NSWorkspace.shared.runningApplications.first(where: { app in
            app.activationPolicy == .regular
            && !app.isTerminated
            && app.bundleIdentifier != selfBundleID
        })
    }

    private func ensureAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        if !UserDefaults.standard.bool(forKey: Self.accessibilityPromptedKey) {
            let options = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            UserDefaults.standard.set(true, forKey: Self.accessibilityPromptedKey)
        }
        return false
    }

    private func focusEditableElementIfNeeded(in app: NSRunningApplication) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let skipDeepTraversal = isBrowserApp(app)

        if app.processIdentifier == targetFocusedElementProcessIdentifier,
           let rememberedFocusedElement = targetFocusedElement {
            if isEditableElement(rememberedFocusedElement) {
                focus(element: rememberedFocusedElement)
                return rememberedFocusedElement
            }

            if !skipDeepTraversal,
               let found = findEditableElement(in: rememberedFocusedElement, depth: 0) {
                focus(element: found)
                return found
            }
        }

        if let focusedElement = copyElementValue(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString) {
            let deepestFocused = deepestFocusedElement(startingFrom: focusedElement)
            if isEditableElement(deepestFocused) {
                focus(element: deepestFocused)
                return deepestFocused
            }

            if !skipDeepTraversal,
               let found = findEditableElement(in: deepestFocused, depth: 0) {
                focus(element: found)
                return found
            }
        }

        if skipDeepTraversal {
            return nil
        }

        if let focusedWindow = copyElementValue(from: appElement, attribute: kAXFocusedWindowAttribute as CFString),
           let found = findEditableElementPreferringWebArea(in: focusedWindow) {
            focus(element: found)
            return found
        }

        if let mainWindow = copyElementValue(from: appElement, attribute: kAXMainWindowAttribute as CFString),
           let found = findEditableElementPreferringWebArea(in: mainWindow) {
            focus(element: found)
            return found
        }

        if let found = findEditableElement(in: appElement, depth: 0) {
            focus(element: found)
            return found
        }

        return nil
    }

    private func deepestFocusedElement(startingFrom element: AXUIElement) -> AXUIElement {
        var current = element
        for _ in 0..<maxSearchDepth {
            guard let next = copyElementValue(from: current, attribute: kAXFocusedUIElementAttribute as CFString) else {
                break
            }
            if CFEqual(next, current) {
                break
            }
            current = next
        }
        return current
    }

    private func findEditableElement(in root: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= maxSearchDepth else { return nil }
        if isEditableElement(root) {
            return root
        }

        for attribute in traversalAttributes {
            let children = copyElementArray(from: root, attribute: attribute)
            for child in children {
                if let found = findEditableElement(in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private func findEditableElementPreferringWebArea(in root: AXUIElement) -> AXUIElement? {
        if let webArea = findElement(withRole: webAreaRole, in: root, depth: 0),
           let found = findEditableElement(in: webArea, depth: 0) {
            return found
        }
        return findEditableElement(in: root, depth: 0)
    }

    private func findElement(withRole role: String, in root: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= maxSearchDepth else { return nil }

        if copyStringValue(from: root, attribute: kAXRoleAttribute as CFString) == role {
            return root
        }

        for attribute in traversalAttributes {
            let children = copyElementArray(from: root, attribute: attribute)
            for child in children {
                if let found = findElement(withRole: role, in: child, depth: depth + 1) {
                    return found
                }
            }
        }

        return nil
    }

    private func isEditableElement(_ element: AXUIElement) -> Bool {
        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            searchFieldRole
        ]

        if let role = copyStringValue(from: element, attribute: kAXRoleAttribute as CFString),
           textRoles.contains(role) {
            return true
        }

        if let editable = copyBoolValue(from: element, attribute: editableAttribute as CFString), editable {
            return true
        }

        var isSettable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(
            element,
            kAXValueAttribute as CFString,
            &isSettable
        )
        return result == .success && isSettable.boolValue
    }

    private func focus(element: AXUIElement) {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
        if result != .success {
            _ = AXUIElementPerformAction(element, kAXPressAction as CFString)
        }
    }

    private func insertClipboardTextIfPossible(into element: AXUIElement?, for app: NSRunningApplication) -> Bool {
        guard isBrowserApp(app),
              let element,
              let text = NSPasteboard.general.string(forType: .string),
              !text.isEmpty else {
            return false
        }

        let result = AXUIElementSetAttributeValue(
            element,
            selectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    private func isBrowserApp(_ app: NSRunningApplication) -> Bool {
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        let browserBundlePrefixes = [
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.google.Chrome",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "com.operasoftware.Opera",
            "com.vivaldi.Vivaldi",
            "company.thebrowser.Browser"
        ]
        return browserBundlePrefixes.contains(where: { bundleIdentifier.hasPrefix($0) })
    }

    private func copyElementValue(from element: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let value else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyElementArray(from element: AXUIElement, attribute: CFString) -> [AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let array = value as? [AXUIElement] else { return [] }
        return Array(array.prefix(maxChildrenPerNode))
    }

    private func copyStringValue(from element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? String
    }

    private func copyBoolValue(from element: AXUIElement, attribute: CFString) -> Bool? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else { return nil }
        return value as? Bool
    }

    private func postPasteShortcut(to app: NSRunningApplication) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(app.processIdentifier)
        keyUp.postToPid(app.processIdentifier)
    }
}
