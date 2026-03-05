import SwiftUI
import KeyboardShortcuts
import ServiceManagement

// MARK: - Sidebar Items

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case transcription
    case processing
    case translation
    case output
    case shortcut
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcription: return "Transcription"
        case .processing:    return "Processing"
        case .translation:   return "Translation"
        case .output:        return "Output"
        case .shortcut:      return "Shortcut"
        case .history:       return "History"
        }
    }

    var icon: String {
        switch self {
        case .transcription: return "waveform"
        case .processing:    return "cpu"
        case .translation:   return "globe"
        case .output:        return "tray.and.arrow.down"
        case .shortcut:      return "keyboard"
        case .history:       return "clock"
        }
    }
}

// MARK: - App Content View

struct AppContentView: View {
    @EnvironmentObject var coordinator: RecordingCoordinator
    @EnvironmentObject var settings: SettingsManager
    @State private var selectedItem: SidebarItem? = .transcription

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SidebarItem.allCases, id: \.self, selection: $selectedItem) { item in
                    Label(item.title, systemImage: item.icon)
                }
                .listStyle(.sidebar)

                Divider()

                sidebarRecordButton
                    .padding(12)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailPane
        }
    }

    // MARK: - Sidebar Record Button

    private var sidebarRecordButton: some View {
        RecordButtonView()
            .environmentObject(coordinator)
    }

    // MARK: - Detail Pane

    @ViewBuilder
    private var detailPane: some View {
        switch selectedItem {
        case .transcription:
            AppTranscriptionPane()
                .environmentObject(settings)
        case .processing:
            AppProcessingPane()
                .environmentObject(settings)
        case .translation:
            AppTranslationPane()
                .environmentObject(settings)
        case .output:
            AppOutputPane()
                .environmentObject(settings)
        case .shortcut:
            AppShortcutPane()
        case .history:
            AppHistoryPane()
                .environmentObject(coordinator)
        case nil:
            Text("Select an item from the sidebar.")
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }


}

// MARK: - Transcription Pane

struct AppTranscriptionPane: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Engine") {
                EnginePickerView()
                    .environmentObject(settings)
            }

            if settings.transcriptionBackend == .appleSpeech {
                Section("Apple Speech") {
                    Toggle("On-Device Only (no audio sent to Apple)", isOn: $settings.onDeviceRecognition)
                    TextField("Locale (e.g. en-US)", text: $settings.speechLocale)
                        .foregroundColor(settings.onDeviceRecognition ? .primary : .secondary)
                }
            }

            if settings.transcriptionBackend == .whisperKit {
                AppWhisperKitSection()
                    .environmentObject(settings)
            }

            if settings.transcriptionBackend == .whisperCpp {
                AppWhisperCppSection()
                    .environmentObject(settings)
            }

            if settings.transcriptionBackend == .openAIWhisper {
                Section("OpenAI Whisper") {
                    SecureField("API Key", text: Binding(
                        get: { settings.openAIAPIKey },
                        set: { settings.openAIAPIKey = $0 }
                    ))
                    TextField("Model", text: $settings.openAIModel)
                    Toggle("Translation Mode (transcribe to English)", isOn: $settings.whisperTranslateMode)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - WhisperKit Section

struct AppWhisperKitSection: View {
    @EnvironmentObject var settings: SettingsManager
    @StateObject private var wk = WhisperKitManager.shared

    var body: some View {
        Section("WhisperKit (On-Device)") {
            Picker("Model", selection: $settings.whisperKitModel) {
                ForEach(WhisperKitManager.availableModels, id: \.id) { model in
                    Text("\(model.displayName)  \(model.sizeNote)")
                        .tag(model.id)
                }
            }
            .disabled(wk.loadState.isBusy)

            HStack {
                switch wk.loadState {
                case .notLoaded:
                    Image(systemName: "arrow.down.circle").foregroundColor(.secondary)
                    Text("Not downloaded").foregroundColor(.secondary)
                case .downloading, .loading:
                    ProgressView().scaleEffect(0.7)
                    Text("Downloading & loading… (may take a few minutes)")
                        .foregroundColor(.secondary).font(.caption)
                case .ready(let name):
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Ready · \(WhisperKitManager.displayName(for: name))")
                case .failed(let msg):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(msg).foregroundColor(.orange).font(.caption).lineLimit(2)
                }

                Spacer()

                switch wk.loadState {
                case .notLoaded, .failed:
                    Button("Download & Load") {
                        Task { await wk.downloadAndLoad(model: settings.whisperKitModel) }
                    }
                case .ready:
                    Button("Unload") { wk.unload() }.foregroundColor(.secondary)
                default:
                    EmptyView()
                }
            }

            if case .ready(let loaded) = wk.loadState, loaded != settings.whisperKitModel {
                HStack {
                    Image(systemName: "info.circle").foregroundColor(.blue)
                    Text("Model changed. Reload to apply.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Reload") {
                        Task { await wk.downloadAndLoad(model: settings.whisperKitModel) }
                    }.font(.caption)
                }
            }
        }
    }
}

// MARK: - WhisperCpp Section

struct AppWhisperCppSection: View {
    @EnvironmentObject var settings: SettingsManager
    @ObservedObject private var manager = SwiftWhisperManager.shared

    var body: some View {
        Section("Whisper.cpp (On-Device)") {
            Picker("Model", selection: $settings.whisperCppModel) {
                ForEach(SwiftWhisperManager.availableModels, id: \.id) { model in
                    Text("\(model.displayName)  \(model.sizeNote)").tag(model.id)
                }
            }
            .disabled(manager.loadState.isBusy)

            HStack {
                switch manager.loadState {
                case .notDownloaded:
                    Image(systemName: "arrow.down.circle").foregroundColor(.secondary)
                    Text("Not downloaded").foregroundColor(.secondary)
                case .downloading(let label, let progress):
                    ProgressView(value: progress).frame(width: 80).scaleEffect(y: 0.7)
                    Text("\(label) \(Int(progress * 100))%").foregroundColor(.secondary).font(.caption)
                case .loading:
                    ProgressView().scaleEffect(0.7)
                    Text("Loading model…").foregroundColor(.secondary).font(.caption)
                case .ready(let name):
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Ready · \(SwiftWhisperManager.displayName(for: name))")
                case .failed(let msg):
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(msg).foregroundColor(.orange).font(.caption).lineLimit(2)
                }

                Spacer()

                switch manager.loadState {
                case .notDownloaded, .failed:
                    Button("Download & Load") {
                        Task { await manager.downloadAndLoad(modelId: settings.whisperCppModel) }
                    }
                case .ready:
                    Button("Unload") { manager.unload() }.foregroundColor(.secondary)
                default:
                    EmptyView()
                }
            }

            if case .ready(let loaded) = manager.loadState, loaded != settings.whisperCppModel {
                HStack {
                    Image(systemName: "info.circle").foregroundColor(.blue)
                    Text("Model changed. Reload to apply.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Reload") {
                        Task { await manager.downloadAndLoad(modelId: settings.whisperCppModel) }
                    }.font(.caption)
                }
            }

            if let model = SwiftWhisperManager.availableModels.first(where: { $0.id == settings.whisperCppModel }),
               manager.isDownloaded(model) {
                HStack {
                    Image(systemName: "internaldrive").foregroundColor(.secondary)
                    Text("Downloaded · \(model.sizeNote)").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Delete") { manager.deleteModel(modelId: settings.whisperCppModel) }
                        .foregroundColor(.red).font(.caption)
                }
            }
        }
    }
}

// MARK: - Processing Pane

struct AppProcessingPane: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Ollama") {
                Toggle("Enable LLM Post-processing", isOn: $settings.ollamaEnabled)

                if settings.ollamaEnabled {
                    TextField("Ollama Host", text: $settings.ollamaHost)
                    TextField("Model", text: $settings.ollamaModel)

                    Picker("Processing Mode", selection: $settings.processingMode) {
                        ForEach(ProcessingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    if settings.processingMode == .custom {
                        VStack(alignment: .leading) {
                            Text("Custom Prompt")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextEditor(text: $settings.customPrompt)
                                .frame(height: 100)
                                .font(.body)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Translation Pane

struct AppTranslationPane: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            Section("Translation") {
                if #available(macOS 15.0, *) {
                    Toggle("Enable Translation", isOn: $settings.translationEnabled)
                    if settings.translationEnabled {
                        TextField("Target Language Code (e.g. en, fr, de)", text: $settings.translationTargetLanguage)
                    }
                } else {
                    Text("Translation requires macOS 15 or later.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Output Pane

struct AppOutputPane: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }
            }
            Section("Destinations") {
                Toggle("Clipboard (always on)", isOn: .constant(true))
                    .disabled(true)
                Toggle("Active Text Field", isOn: $settings.outputToActiveField)
                Toggle("Apple Notes", isOn: $settings.outputToAppleNotes)
                Toggle("Append to File", isOn: $settings.outputToFile)
            }

            if settings.outputToFile {
                Section("File Path") {
                    HStack {
                        TextField("File path", text: $settings.outputFilePath)
                        Button("Browse...") { browseForFile() }
                    }
                }
            }

            Section("Accessibility") {
                HStack {
                    Text("Accessibility Permission")
                    Spacer()
                    if AccessibilityOutput.isAccessibilityEnabled {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Request Permission") {
                            AccessibilityOutput.requestAccessibilityPermission()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func browseForFile() {
        let panel = NSSavePanel()
        panel.title = "Choose output file"
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "viva-voce-transcript.txt"
        if panel.runModal() == .OK, let url = panel.url {
            settings.outputFilePath = url.path
        }
    }
}

// MARK: - Shortcut Pane

struct AppShortcutPane: View {
    var body: some View {
        Form {
            Section("Global Shortcut") {
                HotkeyRecorderView()
            }

            Section("Tips") {
                Text("Press the hotkey once to start recording, press it again to stop and transcribe.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - History Pane

struct AppHistoryPane: View {
    @EnvironmentObject var coordinator: RecordingCoordinator

    var body: some View {
        if coordinator.history.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                Text("No transcriptions yet")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(coordinator.history) { entry in
                HistoryEntryRow(entry: entry)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button("Clear History") { coordinator.clearHistory() }
                        .foregroundColor(.red)
                        .padding(12)
                }
            }
        }
    }
}

struct HistoryEntryRow: View {
    let entry: TranscriptEntry
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.text)
                .font(.body)
                .lineLimit(3)
                .textSelection(.enabled)

            HStack(spacing: 4) {
                Text(relativeDate(entry.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("·")
                    .foregroundColor(.secondary)
                Text(formatDuration(entry.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    ClipboardOutput.write(entry.text)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(copied ? .green : .accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
