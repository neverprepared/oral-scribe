import AppKit
import ApplicationServices

// MARK: - Accessibility Output

struct AccessibilityOutput {

    static func inject(_ text: String, into targetApp: NSRunningApplication?) {
        // Note: skip AXIsProcessTrustedWithOptions — it returns false for ad-hoc signed builds
        // even when TCC has granted the permission. Just attempt the calls directly.

        guard let targetApp else {
            pasteFromClipboard(text, activating: nil)
            return
        }

        if targetApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            return
        }

        // Try direct AX insert at cursor first (no focus change required)
        let pid = targetApp.processIdentifier
        if tryAXInsert(text, pid: pid) {
            return
        }

        // Fallback: activate the target app and send Cmd+V to the global HID tap.
        pasteFromClipboard(text, activating: targetApp)
    }

    // MARK: - AXUIElement insert at cursor

    private static func tryAXInsert(_ text: String, pid: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(pid)
        var focusedRef: CFTypeRef?

        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success else { return false }

        let focused = focusedRef as! AXUIElement  // swiftlint:disable:this force_cast

        // Only attempt if the attribute is actually settable — some apps accept
        // the AX call and return .success but silently ignore it (false positive).
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(
            focused,
            kAXSelectedTextAttribute as CFString,
            &settable
        ) == .success, settable.boolValue else { return false }

        return AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    // MARK: - Activate + Cmd+V

    private static func pasteFromClipboard(_ text: String, activating targetApp: NSRunningApplication?) {
        // Write text to clipboard now — required for Cmd+V to paste the transcript
        // regardless of whether the user has "Output to Clipboard" enabled.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        if let targetApp {
            targetApp.activate(options: .activateIgnoringOtherApps)
        }

        // Brief delay to let activation settle before posting the keystroke
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let source = CGEventSource(stateID: .hidSystemState)
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
                let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            else { return }

            keyDown.flags = .maskCommand
            keyUp.flags   = .maskCommand

            if let pid = targetApp?.processIdentifier {
                // postToPid is more reliable than the global HID tap for apps
                // that don't handle synthesized HID events (e.g. terminal emulators)
                keyDown.postToPid(pid)
                keyUp.postToPid(pid)
            } else {
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Auto-submit (Return keystroke)

    static func sendReturn(to pid: pid_t?) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
            let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        else { return }

        if let pid {
            keyDown.postToPid(pid)
            keyUp.postToPid(pid)
        } else {
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Permission

    static var isAccessibilityEnabled: Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
        )
    }

    static func requestAccessibilityPermission() {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
        )
    }
}
