import Foundation
import AppKit
import AVFoundation
import Combine

// MARK: - Recording Coordinator

@MainActor
class RecordingCoordinator: ObservableObject {
    static let shared = RecordingCoordinator()

    @Published var state: RecordingState = .idle
    @Published var liveTranscript: String = ""
    @Published var finalTranscript: String = ""
    @Published var powerLevel: Float = -160
    @Published var recordingDuration: TimeInterval = 0
    @Published var history: [TranscriptEntry] = []

    private let audioRecorder = AudioRecorder()
    private let settings = SettingsManager.shared

    /// The app that was frontmost when recording started — we restore focus here before injecting text.
    private var targetApp: NSRunningApplication?

    // Engines (initialized lazily with current settings values)
    private lazy var appleSpeechEngine = AppleSpeechEngine(locale: settings.speechLocale)
    private lazy var openAIWhisperEngine = OpenAIWhisperEngine(
        apiKey: settings.openAIAPIKey,
        model: settings.openAIModel,
        translateMode: settings.whisperTranslateMode
    )
    private lazy var ollamaProcessor = OllamaProcessor(
        host: settings.ollamaHost,
        model: settings.ollamaModel
    )

    private var liveStreamTask: Task<Void, Never>?
    private var powerLevelObserver: AnyCancellable?
    private var recordingTimer: Timer?
    private var recordingStartTime: Date?

    private static let historyKey = "transcriptHistory"
    private static let maxHistoryCount = 50

    private init() {
        // Mirror audio recorder's power level
        powerLevelObserver = audioRecorder.$powerLevel
            .receive(on: RunLoop.main)
            .assign(to: \.powerLevel, on: self)

        // Load persisted history
        if let data = UserDefaults.standard.data(forKey: Self.historyKey),
           let entries = try? JSONDecoder().decode([TranscriptEntry].self, from: data) {
            history = entries
        }
    }

    // MARK: - Toggle

    func toggle() {
        switch state {
        case .recording:
            stopRecording()
        default:
            if !state.isActive {
                startRecording()
            }
        }
    }

    // MARK: - Start Recording

    private func startRecording() {
        // Capture target app before the popover can steal focus
        targetApp = NSWorkspace.shared.frontmostApplication

        state = .recording
        liveTranscript = ""
        finalTranscript = ""

        startRecordingTimer()
        NSSound(named: .init("Tink"))?.play()

        switch settings.transcriptionBackend {
        case .appleSpeech:
            startAppleSpeechRecording()
        case .openAIWhisper:
            startFileBasedRecording()
        case .whisperKit:
            guard WhisperKitManager.shared.loadState.isReady else {
                state = .error(message: "WhisperKit model not loaded. Open Settings → Transcription to download it.")
                return
            }
            startFileBasedRecording()
        case .whisperCpp:
            guard SwiftWhisperManager.shared.loadState.isReady else {
                state = .error(message: "Whisper.cpp model not loaded. Open Settings → Transcription to download it.")
                return
            }
            startFileBasedRecording()
        }
    }

    // MARK: - Apple Speech (live streaming)

    private func startAppleSpeechRecording() {
        // Recreate engine with current settings
        appleSpeechEngine = AppleSpeechEngine(locale: settings.speechLocale, onDevice: settings.onDeviceRecognition)

        liveStreamTask = Task {
            do {
                let stream = try await appleSpeechEngine.transcribeLive(recorder: audioRecorder)
                for try await partial in stream {
                    if Task.isCancelled { break }
                    liveTranscript = partial
                }
                // Stream ended naturally (Apple Speech sent isFinal after silence).
                // Auto-trigger the pipeline — don't wait for a second hotkey press.
                if !Task.isCancelled && state == .recording {
                    audioRecorder.stopRecording()
                    let transcript = liveTranscript
                    if !transcript.isEmpty {
                        await runPostProcessingPipeline(transcript: transcript)
                    } else {
                        state = .idle
                    }
                }
            } catch {
                if !Task.isCancelled {
                    state = .error(message: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - File-based recording (Whisper)

    private func startFileBasedRecording() {
        do {
            try audioRecorder.startRecording { _, _ in
                // Buffers collected internally for WAV export
            }
        } catch {
            state = .error(message: "Failed to start recording: \(error.localizedDescription)")
        }
    }

    // MARK: - Stop Recording

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func startRecordingTimer() {
        recordingStartTime = Date()
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.recordingDuration = Date().timeIntervalSince(start)
        }
    }

    private func stopRecording() {
        switch settings.transcriptionBackend {
        case .appleSpeech:
            stopAppleSpeech()
        case .openAIWhisper, .whisperKit, .whisperCpp:
            stopFileBasedAndTranscribe()
        }
    }

    private func stopAppleSpeech() {
        // If the stream already auto-completed and ran the pipeline, just cancel.
        guard state == .recording else {
            liveStreamTask?.cancel()
            liveStreamTask = nil
            return
        }

        stopRecordingTimer()
        appleSpeechEngine.stopLiveTranscription()
        audioRecorder.stopRecording()
        liveStreamTask?.cancel()
        liveStreamTask = nil

        let transcript = liveTranscript
        guard !transcript.isEmpty else {
            state = .idle
            return
        }

        Task {
            await runPostProcessingPipeline(transcript: transcript)
        }
    }

    private func stopFileBasedAndTranscribe() {
        stopRecordingTimer()
        audioRecorder.stopRecording()
        state = .transcribing

        // Refresh Whisper engine with latest settings
        openAIWhisperEngine.apiKey = settings.openAIAPIKey
        openAIWhisperEngine.model = settings.openAIModel
        openAIWhisperEngine.translateMode = settings.whisperTranslateMode
        ollamaProcessor.host = settings.ollamaHost
        ollamaProcessor.model = settings.ollamaModel

        Task {
            do {
                let wavURL = try audioRecorder.exportToWAV()
                defer { try? FileManager.default.removeItem(at: wavURL) }

                let result: TranscriptionResult
                switch settings.transcriptionBackend {
                case .openAIWhisper:
                    result = try await openAIWhisperEngine.transcribeFile(at: wavURL)
                case .whisperKit:
                    guard let pipe = WhisperKitManager.shared.pipe else {
                        throw TranscriptionError.notAvailable
                    }
                    result = try await WhisperKitEngine(pipe: pipe).transcribeFile(at: wavURL)
                case .whisperCpp:
                    guard let whisper = SwiftWhisperManager.shared.whisper else {
                        throw TranscriptionError.notAvailable
                    }
                    result = try await SwiftWhisperEngine(whisper: whisper).transcribeFile(at: wavURL)
                default:
                    throw TranscriptionError.notAvailable
                }

                await runPostProcessingPipeline(transcript: result.text)
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Post-Processing Pipeline

    private func runPostProcessingPipeline(transcript: String) async {
        var text = transcript
        finalTranscript = text

        // LLM Processing
        if settings.ollamaEnabled && settings.processingMode != .passthrough {
            state = .processing
            ollamaProcessor.host = settings.ollamaHost
            ollamaProcessor.model = settings.ollamaModel
            do {
                text = try await ollamaProcessor.process(
                    text: text,
                    mode: settings.processingMode,
                    customPrompt: settings.customPrompt.isEmpty ? nil : settings.customPrompt
                )
                finalTranscript = text
            } catch {
                print("LLM processing failed: \(error.localizedDescription)")
                // Continue with original transcript
            }
        }

        // Translation
        if settings.translationEnabled {
            state = .translating
            do {
                text = try await TranslationManager.shared.translate(
                    text: text,
                    targetLanguage: settings.translationTargetLanguage
                )
                finalTranscript = text
            } catch {
                print("Translation failed: \(error.localizedDescription)")
                // Continue without translation
            }
        }

        // Output delivery
        state = .delivering
        await OutputManager.shared.deliver(text, settings: settings, targetApp: targetApp)
        targetApp = nil

        // Append to history
        let entry = TranscriptEntry(text: text, duration: recordingDuration)
        history.insert(entry, at: 0)
        if history.count > Self.maxHistoryCount {
            history = Array(history.prefix(Self.maxHistoryCount))
        }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: Self.historyKey)
        }

        // Done
        NSSound(named: .init("Glass"))?.play()
        state = .done(text: text)

        // Reset to idle after a brief moment
        try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds
        if case .done = state {
            state = .idle
            liveTranscript = ""
        }
    }

    // MARK: - Cancel

    func cancel() {
        stopRecordingTimer()
        liveStreamTask?.cancel()
        appleSpeechEngine.stopLiveTranscription()
        audioRecorder.stopRecording()
        state = .idle
        liveTranscript = ""
    }

    func clearHistory() {
        history = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }
}
