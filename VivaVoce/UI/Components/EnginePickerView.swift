import SwiftUI

// MARK: - Engine Picker View

struct EnginePickerView: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Picker("Transcription Engine", selection: $settings.transcriptionBackend) {
            ForEach(TranscriptionBackend.allCases, id: \.self) { backend in
                Text(backend.displayName).tag(backend)
            }
        }
        .pickerStyle(.menu)
    }
}
