import AVFoundation

// MARK: - Audio Format Constants

enum AudioFormat {
    /// Sample rate optimized for speech recognition (16kHz mono PCM)
    static let sampleRate: Double = 16000
    static let channelCount: AVAudioChannelCount = 1
    static let bitDepth: UInt32 = 16

    static var speechOptimizedFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: false
        )!
    }

    static var wavFormat: AVAudioFormat {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: sampleRate,
            channels: channelCount,
            interleaved: true
        )!
    }
}
