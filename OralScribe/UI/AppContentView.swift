import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AppKit

// MARK: - Visual Effect Blur (NSVisualEffectView wrapper)

struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Window Transparency Helper

/// Makes the hosting NSWindow and its SwiftUI content view fully transparent so
/// vibrancy effects with .behindWindow blending show through to the desktop.
struct WindowTransparencyHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(nsView) }
    }
    private static func configure(_ view: NSView) {
        guard let window = view.window else { return }
        window.backgroundColor = .clear
        window.isOpaque = false
        // Clear the SwiftUI NSHostingView layer so it doesn't fill with window background
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = CGColor.clear
    }
}

// MARK: - Sidebar Transparency Helper
//
// NavigationSplitView injects its own NSVisualEffectView for the sidebar column at the
// AppKit level. SwiftUI .background() / .glassEffect() modifiers sit beneath it and have
// no visible effect. This helper walks up the superview chain to find that injected view
// and replaces its material with a more transparent one.

struct SidebarTransparencyHelper: NSViewRepresentable {
    var alpha: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.configure(from: view, alpha: alpha) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.configure(from: nsView, alpha: alpha) }
    }

    private static func configure(from view: NSView, alpha: CGFloat) {
        var current = view.superview
        while let v = current {
            if let effect = v as? NSVisualEffectView {
                effect.material = .underWindowBackground
                effect.blendingMode = .behindWindow
                effect.state = .active
                effect.alphaValue = alpha
                return
            }
            current = v.superview
        }
    }
}

// MARK: - Sidebar Items

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case transcription
    case processing
    case translation
    case output
    case shortcut
    case voiceTrigger
    case history
    case startup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transcription:  return "Transcription"
        case .processing:     return "Processing"
        case .translation:    return "Translation"
        case .output:         return "Output"
        case .shortcut:       return "Shortcut"
        case .voiceTrigger:   return "Voice Trigger"
        case .history:        return "History"
        case .startup:        return "Startup"
        }
    }

    var icon: String {
        switch self {
        case .transcription:  return "waveform"
        case .processing:     return "cpu"
        case .translation:    return "globe"
        case .output:         return "tray.and.arrow.down"
        case .shortcut:       return "keyboard"
        case .voiceTrigger:   return "text.bubble"
        case .history:        return "clock"
        case .startup:        return "power"
        }
    }
}

// MARK: - Sidebar Sections

struct SidebarSection {
    let title: String
    let items: [SidebarItem]

    static let all: [SidebarSection] = [
        SidebarSection(title: "PIPELINE", items: [.transcription, .processing, .translation, .output]),
        SidebarSection(title: "ACTIVATION", items: [.shortcut, .voiceTrigger]),
        SidebarSection(title: "HISTORY", items: [.history]),
        SidebarSection(title: "SYSTEM", items: [.startup]),
    ]
}

// MARK: - App Content View

struct AppContentView: View {
    @EnvironmentObject var coordinator: RecordingCoordinator
    @EnvironmentObject var settings: SettingsManager
    @State private var selectedItem: SidebarItem? = .transcription

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedItem) {
                    ForEach(SidebarSection.all, id: \.title) { section in
                        Section {
                            ForEach(section.items) { item in
                                Label(item.title, systemImage: item.icon)
                                    .tag(item)
                            }
                        } header: {
                            Text(section.title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)

                Divider()

                sidebarRecordButton
                    .padding(12)
            }
            .background(SidebarTransparencyHelper(alpha: 0.1))
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            detailPane
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(.clear)
        .background(WindowTransparencyHelper())
        .onReceive(NotificationCenter.default.publisher(for: .navigateToHistory)) { _ in
            selectedItem = .history
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
        case .voiceTrigger:
            AppVoiceTriggerPane()
                .environmentObject(settings)
        case .history:
            AppHistoryPane()
                .environmentObject(coordinator)
        case .startup:
            AppStartupPane()
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
                    SecureField("API Key", text: $settings.openAIAPIKey)
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

    private var currentModel: WhisperCppModel? {
        SwiftWhisperManager.availableModels.first { $0.id == settings.whisperCppModel }
    }

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

            if let model = currentModel, manager.isDownloaded(model) {
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

// MARK: - Ollama Status

enum OllamaStatus: Equatable {
    case idle
    case checking
    case connected(Int)
    case failed
}

// MARK: - Processing Pane

struct AppProcessingPane: View {
    @EnvironmentObject var settings: SettingsManager
    @State private var availableModels: [String] = []
    @State private var loadingModels = false
    @State private var ollamaStatus: OllamaStatus = .idle

    var body: some View {
        Form {
            Section("Ollama") {
                Toggle("Enable LLM Post-processing", isOn: $settings.ollamaEnabled)
                    .onChange(of: settings.ollamaEnabled) { enabled in
                        if enabled { refreshModels() }
                    }

                if settings.ollamaEnabled {
                    TextField("Ollama Host", text: $settings.ollamaHost)
                        .onChange(of: settings.ollamaHost) { _ in
                            refreshModels()
                        }

                    // Ollama connection status
                    HStack(spacing: 6) {
                        switch ollamaStatus {
                        case .idle:
                            EmptyView()
                        case .checking:
                            ProgressView()
                                .scaleEffect(0.6)
                            Text("Checking connection…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        case .connected(let count):
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected · \(count) model\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Connection failed")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("Retry") { refreshModels() }
                                .font(.caption)
                        }
                    }

                    HStack {
                        if availableModels.isEmpty {
                            TextField("Model", text: $settings.ollamaModel)
                        } else {
                            Picker("Model", selection: $settings.ollamaModel) {
                                ForEach(availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                                if !availableModels.contains(settings.ollamaModel) && !settings.ollamaModel.isEmpty {
                                    Text(settings.ollamaModel).tag(settings.ollamaModel)
                                }
                            }
                        }
                        if loadingModels {
                            ProgressView().scaleEffect(0.6)
                        } else {
                            Button {
                                refreshModels()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                    }

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
        .onAppear { refreshModels() }
    }

    private func refreshModels() {
        guard settings.ollamaEnabled else { return }
        loadingModels = true
        ollamaStatus = .checking
        let processor = OllamaProcessor(host: settings.ollamaHost)
        Task {
            let models = await processor.fetchModels()
            availableModels = models
            loadingModels = false
            if models.isEmpty {
                ollamaStatus = .failed
            } else {
                ollamaStatus = .connected(models.count)
            }
        }
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

    var body: some View {
        Form {
            Section("Destinations") {
                Toggle("Clipboard", isOn: $settings.outputToClipboard)
                Toggle("Active Text Field", isOn: $settings.outputToActiveField)
                Toggle("Apple Notes", isOn: $settings.outputToAppleNotes)
                Toggle("Append to File", isOn: $settings.outputToFile)
            }

            Section("Behavior") {
                Toggle("Auto-submit (press Return after inserting)", isOn: $settings.outputAutoSubmit)
            }

            if settings.outputToFile {
                Section("File Path") {
                    HStack {
                        TextField("File path", text: $settings.outputFilePath)
                        Button("Browse...") { browseForFile() }
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

// MARK: - Startup Pane

struct AppStartupPane: View {
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

// MARK: - Voice Trigger Pane

struct AppVoiceTriggerPane: View {
    @EnvironmentObject var settings: SettingsManager

    var body: some View {
        Form {
            Section {
                Toggle("Enable Voice Trigger", isOn: $settings.voiceTriggerEnabled)
                Text("Say a keyword during recording to deliver transcript to outputs without stopping.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if settings.voiceTriggerEnabled {
                Section("Keywords") {
                    TextField("Deliver phrase", text: $settings.deliverPhrase)
                    TextField("Stop phrase", text: $settings.stopPhrase)
                }

                Section("How it works") {
                    Text("Works with all backends. Hotkey and stop button still work.\n\nSay the deliver phrase to send the current transcript and keep recording. Say the stop phrase to deliver and end the session.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(coordinator.history) { entry in
                        HistoryEntryRow(entry: entry)
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button("Clear History") { coordinator.clearHistory() }
                        .foregroundColor(.red)
                        .padding(12)
                }
                .background(.bar)
            }
        }
    }
}

struct HistoryEntryRow: View {
    let entry: TranscriptEntry
    @State private var copied = false
    @State private var thinkExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let parsed = parseThinkTags(entry.text)

            // Think block (collapsible darker sub-card)
            if let thinking = parsed.thinking {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            thinkExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: thinkExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Image(systemName: "brain")
                                .font(.caption2)
                            Text("Thinking")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)

                    if thinkExpanded {
                        Text(thinking)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Main response
            if !parsed.response.isEmpty {
                Text(parsed.response)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }

            // Processing labels
            if entry.processingMode != nil || entry.processingModel != nil {
                HStack(spacing: 6) {
                    if let mode = entry.processingMode {
                        Text(mode)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if let model = entry.processingModel {
                        Text(model)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            HStack(spacing: 4) {
                Text(relativeDate(entry.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("·")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatDuration(entry.duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    ClipboardOutput.write(parsed.response)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundColor(copied ? .green : .secondary)
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func parseThinkTags(_ text: String) -> (thinking: String?, response: String) {
        guard let openRange = text.range(of: "<think>"),
              let closeRange = text.range(of: "</think>") else {
            return (nil, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let thinking = String(text[openRange.upperBound..<closeRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let response = String(text[closeRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (thinking.isEmpty ? nil : thinking, response)
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
