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

    // Voice trigger
    private var keywordDetector: KeywordDetector?
    /// Tracks the last partial text we already scanned for keywords, to avoid re-triggering.
    private var lastDeliveredPartialLength: Int = 0
    /// Lowercased phrase cache — set once per recording session, reused on every partial result.
    private var stopPhraseLower = ""
    private var deliverPhraseLower = ""

    private static let maxHistoryCount = 50

    private init() {
        // Mirror audio recorder's power level
        powerLevelObserver = audioRecorder.$powerLevel
            .receive(on: RunLoop.main)
            .assign(to: \.powerLevel, on: self)

        // Load persisted history
        history = HistoryStore.load()
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
        lastDeliveredPartialLength = 0
        stopPhraseLower = settings.stopPhrase.lowercased()
        deliverPhraseLower = settings.deliverPhrase.lowercased()

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
                var stream = try await appleSpeechEngine.transcribeLive(recorder: audioRecorder)
                try await consumeAppleSpeechStream(&stream)
            } catch {
                if !Task.isCancelled {
                    state = .error(message: error.localizedDescription)
                }
            }
        }
    }

    /// Iterates an Apple Speech stream, handling voice-trigger keywords and isFinal restarts.
    private func consumeAppleSpeechStream(_ stream: inout AsyncThrowingStream<String, Error>) async throws {
        for try await partial in stream {
            if Task.isCancelled { return }
            liveTranscript = partial

            // Voice trigger keyword scanning
            if settings.voiceTriggerEnabled {
                let lowered = partial.lowercased()

                // Check stop phrase first (more specific)
                if lowered.hasSuffix(stopPhraseLower) {
                    let cleaned = stripPhrase(settings.stopPhrase, from: partial)
                    appleSpeechEngine.stopLiveTranscription()
                    audioRecorder.stopRecording()
                    stopRecordingTimer()
                    if !cleaned.isEmpty {
                        await deliverAndContinue(transcript: cleaned)
                    }
                    state = .idle
                    liveTranscript = ""
                    return
                }

                // Check deliver phrase
                if lowered.hasSuffix(deliverPhraseLower) {
                    let cleaned = stripPhrase(settings.deliverPhrase, from: partial)
                    if !cleaned.isEmpty {
                        await deliverAndContinue(transcript: cleaned)
                    }
                    // Restart recognition to continue listening
                    liveTranscript = ""
                    lastDeliveredPartialLength = 0
                    var newStream = appleSpeechEngine.restartRecognition(recorder: audioRecorder)
                    try await consumeAppleSpeechStream(&newStream)
                    return
                }
            }
        }

        // Stream ended naturally (isFinal after silence)
        if Task.isCancelled { return }

        if settings.voiceTriggerEnabled && state == .recording {
            // In voice trigger mode: restart recognizer instead of auto-triggering pipeline
            liveTranscript = ""
            lastDeliveredPartialLength = 0
            var newStream = appleSpeechEngine.restartRecognition(recorder: audioRecorder)
            try await consumeAppleSpeechStream(&newStream)
        } else if state == .recording {
            // Normal mode: auto-trigger pipeline on silence
            audioRecorder.stopRecording()
            stopRecordingTimer()
            let transcript = liveTranscript
            if !transcript.isEmpty {
                await runPostProcessingPipeline(transcript: transcript)
            } else {
                state = .idle
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
            return
        }

        // Start keyword detector for voice trigger mode
        if settings.voiceTriggerEnabled {
            let detector = KeywordDetector()
            keywordDetector = detector
            detector.start(
                deliverPhrase: settings.deliverPhrase,
                stopPhrase: settings.stopPhrase,
                onDeliver: { [weak self] in
                    Task { @MainActor in
                        self?.handleFileBasedDeliver()
                    }
                },
                onStop: { [weak self] in
                    Task { @MainActor in
                        self?.handleFileBasedStop()
                    }
                }
            )
        }
    }

    /// Voice trigger: deliver current file-based recording segment and restart.
    private func handleFileBasedDeliver() {
        guard state == .recording else { return }

        // Pause keyword detector while we process
        keywordDetector?.pause()
        audioRecorder.stopRecording()

        Task {
            do {
                let wavURL = try audioRecorder.exportToWAV()
                defer { try? FileManager.default.removeItem(at: wavURL) }

                let result = try await transcribeFileBasedWAV(at: wavURL)
                let cleaned = stripPhrase(settings.deliverPhrase, from: result.text)
                if !cleaned.isEmpty {
                    await deliverAndContinue(transcript: cleaned)
                }

                // Restart recording
                state = .recording
                try audioRecorder.startRecording { _, _ in }
                keywordDetector?.resume()
            } catch {
                state = .error(message: error.localizedDescription)
                keywordDetector?.stop()
                keywordDetector = nil
            }
        }
    }

    /// Voice trigger: deliver final file-based segment and end session.
    private func handleFileBasedStop() {
        guard state == .recording else { return }

        keywordDetector?.stop()
        keywordDetector = nil
        audioRecorder.stopRecording()
        stopRecordingTimer()

        Task {
            do {
                let wavURL = try audioRecorder.exportToWAV()
                defer { try? FileManager.default.removeItem(at: wavURL) }

                let result = try await transcribeFileBasedWAV(at: wavURL)
                let cleaned = stripPhrase(settings.stopPhrase, from: result.text)
                if !cleaned.isEmpty {
                    await runPostProcessingPipeline(transcript: cleaned)
                } else {
                    state = .idle
                }
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }

    /// Shared helper to transcribe a WAV file with the current file-based backend.
    private func transcribeFileBasedWAV(at wavURL: URL) async throws -> TranscriptionResult {
        openAIWhisperEngine.apiKey = settings.openAIAPIKey
        openAIWhisperEngine.model = settings.openAIModel
        openAIWhisperEngine.translateMode = settings.whisperTranslateMode

        switch settings.transcriptionBackend {
        case .openAIWhisper:
            return try await openAIWhisperEngine.transcribeFile(at: wavURL)
        case .whisperKit:
            guard let pipe = WhisperKitManager.shared.pipe else {
                throw TranscriptionError.notAvailable
            }
            return try await WhisperKitEngine(pipe: pipe).transcribeFile(at: wavURL)
        case .whisperCpp:
            guard let whisper = SwiftWhisperManager.shared.whisper else {
                throw TranscriptionError.notAvailable
            }
            return try await SwiftWhisperEngine(whisper: whisper).transcribeFile(at: wavURL)
        default:
            throw TranscriptionError.notAvailable
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
        // Clean up keyword detector if active
        keywordDetector?.stop()
        keywordDetector = nil

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

        let transcript: String
        if settings.voiceTriggerEnabled {
            transcript = stripPhrase(settings.stopPhrase, from: liveTranscript)
        } else {
            transcript = liveTranscript
        }

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

        Task {
            do {
                let wavURL = try audioRecorder.exportToWAV()
                defer { try? FileManager.default.removeItem(at: wavURL) }

                let result = try await transcribeFileBasedWAV(at: wavURL)
                await runPostProcessingPipeline(transcript: result.text)
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }

    // MARK: - Voice Trigger Helpers

    /// Remove a keyword phrase from the end of transcribed text (case-insensitive).
    private func stripPhrase(_ phrase: String, from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = trimmed.lowercased()
        let phraseLower = phrase.lowercased()

        if lowered.hasSuffix(phraseLower) {
            return String(trimmed.dropLast(phraseLower.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// Deliver transcript to outputs without changing state to idle (for continuous mode).
    private func deliverAndContinue(transcript: String) async {
        var text = transcript
        finalTranscript = text

        // LLM Processing
        if settings.ollamaEnabled && settings.processingMode != .passthrough {
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
            }
        }

        // Translation
        if settings.translationEnabled {
            do {
                text = try await TranslationManager.shared.translate(
                    text: text,
                    targetLanguage: settings.translationTargetLanguage
                )
                finalTranscript = text
            } catch {
                print("Translation failed: \(error.localizedDescription)")
            }
        }

        // Output delivery
        await OutputManager.shared.deliver(text, settings: settings, targetApp: targetApp)

        // Append to history
        let info = processingInfo
        let entry = TranscriptEntry(
            text: text,
            duration: recordingDuration,
            processingMode: info?.mode,
            processingModel: info?.model
        )
        history.insert(entry, at: 0)
        if history.count > Self.maxHistoryCount {
            history.removeLast()
        }
        HistoryStore.save(history)

        NSSound(named: .init("Glass"))?.play()
    }

    /// Processing mode + model name if LLM post-processing is active — reads settings once.
    private var processingInfo: (mode: String, model: String)? {
        guard settings.ollamaEnabled, settings.processingMode != .passthrough else { return nil }
        return (settings.processingMode.displayName, settings.ollamaModel)
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
        let info = processingInfo
        let entry = TranscriptEntry(
            text: text,
            duration: recordingDuration,
            processingMode: info?.mode,
            processingModel: info?.model
        )
        history.insert(entry, at: 0)
        if history.count > Self.maxHistoryCount {
            history.removeLast()
        }
        HistoryStore.save(history)

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
        keywordDetector?.stop()
        keywordDetector = nil
        liveStreamTask?.cancel()
        appleSpeechEngine.stopLiveTranscription()
        audioRecorder.stopRecording()
        state = .idle
        liveTranscript = ""
    }

    func clearHistory() {
        history = []
        HistoryStore.clear()
    }
}
