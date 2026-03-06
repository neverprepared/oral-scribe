import SwiftUI
import KeyboardShortcuts

@main
struct OralScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = RecordingCoordinator.shared
    @StateObject private var settings = SettingsManager.shared

    var body: some Scene {
        Window("Oral Scribe", id: "main") {
            AppContentView()
                .environmentObject(coordinator)
                .environmentObject(settings)
        }
        .defaultSize(width: 820, height: 540)

        MenuBarExtra {
            MenuBarPopoverView()
                .environmentObject(coordinator)
                .environmentObject(settings)
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarIcon: String {
        switch coordinator.state {
        case .idle:                                                  return "waveform.and.mic"
        case .recording:                                             return "mic.fill"
        case .transcribing, .processing, .translating, .delivering: return "waveform"
        case .done:                                                  return "checkmark"
        case .error:                                                 return "exclamationmark.triangle"
        }
    }
}
