import AVFoundation
import Combine

// MARK: - AudioRecorder

@MainActor
class AudioRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var powerLevel: Float = -160  // dBFS, -160 = silence

    private let audioEngine = AVAudioEngine()
    private var bufferCallback: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private var recordingFile: AVAudioFile?
    private var recordingConverter: AVAudioConverter?
    private var recordingURL: URL?

    // MARK: - Start

    func startRecording(bufferHandler: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void) throws {
        guard !isRecording else { return }

        bufferCallback = bufferHandler

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("oralscribe_\(UUID().uuidString).wav")

        let outputFile: AVAudioFile
        do {
            outputFile = try AVAudioFile(forWriting: tempURL, settings: AudioFormat.wavFormat.settings)
        } catch {
            throw AudioRecorderError.fileCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFile.processingFormat) else {
            throw AudioRecorderError.conversionFailed
        }

        recordingFile = outputFile
        recordingConverter = converter
        recordingURL = tempURL

        // Install tap at native format, convert and stream to disk
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }
            DispatchQueue.main.async {
                self.processTap(buffer: buffer, time: time)
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            recordingFile = nil
            recordingConverter = nil
            recordingURL = nil
            throw error
        }
        isRecording = true
    }

    private func processTap(buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        // Update power level for metering
        updatePowerLevel(from: buffer)

        // Stream buffer to disk
        writeBufferToDisk(buffer)

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
        guard let url = recordingURL else {
            throw AudioRecorderError.noAudioData
        }

        // Nilling recordingFile triggers AVAudioFile.deinit → flushes and closes the file
        recordingFile = nil
        recordingConverter = nil
        recordingURL = nil

        return url
    }

    // MARK: - Disk Streaming

    private func writeBufferToDisk(_ buffer: AVAudioPCMBuffer) {
        guard let converter = recordingConverter, let file = recordingFile else { return }

        let processingFormat = file.processingFormat
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * processingFormat.sampleRate / buffer.format.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: max(frameCapacity, 1)
        ) else { return }

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
            try? file.write(from: outputBuffer)
        }
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
