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
    private let maxSearchDepth = 7
    private let maxChildrenPerNode = 80
    private let searchFieldRole = "AXSearchField"
    private let editableAttribute = "AXEditable"

    func rememberFrontmostExternalApp() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return }
        guard frontmost.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        targetBundleIdentifier = frontmost.bundleIdentifier
        targetProcessIdentifier = frontmost.processIdentifier
    }

    func pasteIntoRememberedAppIfPossible() {
        guard ensureAccessibilityPermission() else { return }
        guard let targetApp = resolveTargetApplication() else { return }

        targetApp.activate(options: [])
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else { return }
            focusEditableElementIfNeeded(in: targetApp)
            try? await Task.sleep(for: .milliseconds(40))
            postPasteShortcut()
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

    private func focusEditableElementIfNeeded(in app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        if let focusedElement = copyElementValue(from: appElement, attribute: kAXFocusedUIElementAttribute as CFString),
           isEditableElement(focusedElement) {
            focus(element: focusedElement)
            return
        }

        if let focusedWindow = copyElementValue(from: appElement, attribute: kAXFocusedWindowAttribute as CFString),
           let found = findEditableElement(in: focusedWindow, depth: 0) {
            focus(element: found)
            return
        }

        if let mainWindow = copyElementValue(from: appElement, attribute: kAXMainWindowAttribute as CFString),
           let found = findEditableElement(in: mainWindow, depth: 0) {
            focus(element: found)
            return
        }

        if let found = findEditableElement(in: appElement, depth: 0) {
            focus(element: found)
        }
    }

    private func findEditableElement(in root: AXUIElement, depth: Int) -> AXUIElement? {
        guard depth <= maxSearchDepth else { return nil }
        if isEditableElement(root) {
            return root
        }

        let childAttributes: [CFString] = [
            kAXChildrenAttribute as CFString,
            kAXVisibleChildrenAttribute as CFString,
            kAXContentsAttribute as CFString
        ]

        for attribute in childAttributes {
            let children = copyElementArray(from: root, attribute: attribute)
            for child in children {
                if let found = findEditableElement(in: child, depth: depth + 1) {
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
        _ = AXUIElementSetAttributeValue(
            element,
            kAXFocusedAttribute as CFString,
            kCFBooleanTrue
        )
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

    private func postPasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
