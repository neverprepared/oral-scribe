import Foundation
import Speech
import AVFoundation

// MARK: - Keyword Detector

/// Lightweight on-device speech recognizer that runs alongside the main audio recorder
/// to detect deliver/stop keywords during file-based recording sessions.
@MainActor
class KeywordDetector: ObservableObject {
    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var restartTimer: Timer?

    private var onDeliver: (() -> Void)?
    private var onStop: (() -> Void)?

    private var deliverPhrase = ""
    private var stopPhrase = ""
    private var isRunning = false
    /// Guard against double-firing while a delivery cycle is in progress.
    private var delivering = false

    // MARK: - Start

    func start(
        deliverPhrase: String,
        stopPhrase: String,
        onDeliver: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        guard !isRunning else { return }
        self.deliverPhrase = deliverPhrase.lowercased()
        self.stopPhrase = stopPhrase.lowercased()
        self.onDeliver = onDeliver
        self.onStop = onStop
        isRunning = true
        startRecognitionSession()
    }

    // MARK: - Stop

    func stop() {
        isRunning = false
        delivering = false
        teardownSession()
        restartTimer?.invalidate()
        restartTimer = nil
    }

    /// Temporarily pause detection during a deliver cycle (recorder is stopped).
    func pause() {
        delivering = true
        teardownSession()
        restartTimer?.invalidate()
        restartTimer = nil
    }

    /// Resume detection after a deliver cycle completes.
    func resume() {
        delivering = false
        guard isRunning else { return }
        startRecognitionSession()
    }

    // MARK: - Internal

    private func startRecognitionSession() {
        guard isRunning, !delivering else { return }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        guard let recognizer, recognizer.isAvailable else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        self.recognizer = recognizer
        self.recognitionRequest = request

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isRunning else { return }

                if let result {
                    self.scanForKeywords(in: result.bestTranscription.formattedString)
                }

                if error != nil || (result?.isFinal == true) {
                    // Session ended (silence or timeout) — restart if still running
                    self.teardownSession()
                    self.scheduleRestart()
                }
            }
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            print("KeywordDetector: failed to start audio engine: \(error)")
            teardownSession()
        }

        // Apple Speech has a ~60s limit — restart before that
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 55, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning, !self.delivering else { return }
                self.teardownSession()
                self.startRecognitionSession()
            }
        }
    }

    private func teardownSession() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        recognitionRequest = nil
        recognitionTask = nil
    }

    private func scheduleRestart() {
        guard isRunning, !delivering else { return }
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.startRecognitionSession()
            }
        }
    }

    private func scanForKeywords(in text: String) {
        guard !delivering else { return }
        let lowered = text.lowercased()

        // Check stop phrase first (it's more specific / longer)
        if lowered.hasSuffix(stopPhrase) || lowered.contains(stopPhrase) {
            delivering = true
            onStop?()
            return
        }

        if lowered.hasSuffix(deliverPhrase) || lowered.contains(deliverPhrase) {
            delivering = true
            onDeliver?()
        }
    }
}
