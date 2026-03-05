import SwiftUI
import KeyboardShortcuts

// MARK: - Hotkey Recorder View

struct HotkeyRecorderView: View {
    var body: some View {
        HStack {
            Text("Record / Stop Hotkey")
            Spacer()
            KeyboardShortcuts.Recorder("", name: .toggleRecording)
        }
    }
}
