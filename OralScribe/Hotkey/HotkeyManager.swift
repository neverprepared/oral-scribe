import Foundation
import KeyboardShortcuts

// MARK: - Hotkey Name

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.option, .shift]))
}

// MARK: - Hotkey Manager

@MainActor
class HotkeyManager {
    static let shared = HotkeyManager()

    private init() {}

    func register() {
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) {
            Task { @MainActor in
                RecordingCoordinator.shared.toggle()
            }
        }
    }

    func unregister() {
        KeyboardShortcuts.disable(.toggleRecording)
    }
}
