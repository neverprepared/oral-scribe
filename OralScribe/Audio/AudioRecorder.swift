import AVFoundation
import Combine

// MARK: - AudioRecorder

@MainActor
class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var powerLevel: Float = -160  // dBFS, -160 = silence

    private let audioEngine = AVAudioEngine()
    private var bufferCallback: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private var recordingBuffers: [AVAudioPCMBuffer] = []
    private var recordingStartTime: Date?

    var recordingDuration: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Start

    func startRecording(bufferHandler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        guard !isRecording else { return }

        bufferCallback = bufferHandler
        recordingBuffers.removeAll()
        recordingStartTime = Date()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Install tap at native format, convert internally if needed
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }
            Task { @MainActor in
                self.processTap(buffer: buffer, time: time)
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
    }

    private func processTap(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Update power level for metering
        updatePowerLevel(from: buffer)

        // Collect for WAV export
        recordingBuffers.append(buffer)

        // Forward to live consumer (e.g., AppleSpeechEngine)
        bufferCallback?(buffer, time)
    }

    // MARK: - Buffer Callback

    /// Replace the live buffer callback (e.g. when AppleSpeechEngine restarts recognition).
    func setBufferCallback(_ handler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) {
        bufferCallback = handler
    }

    // MARK: - Stop

    func stopRecording() {
        guard isRecording else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        powerLevel = -160
    }

    // MARK: - WAV Export

    func exportToWAV() throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oralscribe_\(Date().timeIntervalSince1970).wav")

        guard !recordingBuffers.isEmpty,
              let firstBuffer = recordingBuffers.first else {
            throw AudioRecorderError.noAudioData
        }

        guard let sourceFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: firstBuffer.format.sampleRate,
            channels: firstBuffer.format.channelCount,
            interleaved: false
        ) else {
            throw AudioRecorderError.noAudioData
        }

        guard let outputFile = try? AVAudioFile(
            forWriting: tempURL,
            settings: AudioFormat.wavFormat.settings
        ) else {
            throw AudioRecorderError.fileCreationFailed
        }

        // AVAudioFile's processingFormat is always float32 non-interleaved —
        // buffers written via write(from:) must be in this format, NOT the file's
        // storage format (int16 interleaved). Convert to processingFormat so the
        // file's internal converter has nothing to do and won't abort.
        let processingFormat = outputFile.processingFormat

        guard let converter = AVAudioConverter(from: sourceFormat, to: processingFormat) else {
            throw AudioRecorderError.conversionFailed
        }

        for buffer in recordingBuffers {
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * processingFormat.sampleRate / buffer.format.sampleRate
            )
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: frameCapacity
            ) else { continue }

            var inputConsumed = false
            var error: NSError?
            converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return buffer
            }

            if error == nil && outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
        }

        return tempURL
    }

    // MARK: - Metering

    private func updatePowerLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(frameLength))
        let db = rms > 0 ? 20 * log10(rms) : -160
        powerLevel = max(-160, min(0, db))
    }
}

// MARK: - Errors

enum AudioRecorderError: LocalizedError {
    case noAudioData
    case fileCreationFailed
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .noAudioData: return "No audio data recorded"
        case .fileCreationFailed: return "Failed to create audio file"
        case .conversionFailed: return "Failed to convert audio format"
        }
    }
}
