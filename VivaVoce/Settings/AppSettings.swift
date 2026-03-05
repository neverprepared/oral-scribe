import Foundation

// MARK: - Transcription Backend

enum TranscriptionBackend: String, CaseIterable, Codable {
    case appleSpeech = "appleSpeech"
    case openAIWhisper = "openAIWhisper"
    case whisperKit = "whisperKit"
    case whisperCpp = "whisperCpp"

    var displayName: String {
        switch self {
        case .appleSpeech: return "Apple Speech (Siri)"
        case .openAIWhisper: return "OpenAI Whisper"
        case .whisperKit: return "WhisperKit (Local)"
        case .whisperCpp: return "Whisper.cpp (Local)"
        }
    }
}

// MARK: - Processing Mode

enum ProcessingMode: String, CaseIterable, Codable {
    case passthrough = "passthrough"
    case cleanup = "cleanup"
    case summarize = "summarize"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .passthrough: return "None (pass-through)"
        case .cleanup: return "Clean up grammar"
        case .summarize: return "Summarize"
        case .custom: return "Custom prompt"
        }
    }

    var defaultPrompt: String? {
        switch self {
        case .passthrough: return nil
        case .cleanup: return "Fix grammar, punctuation, and spelling. Return only the corrected text."
        case .summarize: return "Summarize this text concisely. Return only the summary."
        case .custom: return nil
        }
    }
}

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording
    case transcribing
    case processing
    case translating
    case delivering
    case done(text: String)
    case error(message: String)

    var isActive: Bool {
        switch self {
        case .recording, .transcribing, .processing, .translating, .delivering:
            return true
        default:
            return false
        }
    }

    var statusText: String {
        switch self {
        case .idle: return "Ready"
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .processing: return "Processing..."
        case .translating: return "Translating..."
        case .delivering: return "Delivering..."
        case .done: return "Done"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Transcript Entry

struct TranscriptEntry: Identifiable, Codable {
    let id: UUID
    let text: String
    let timestamp: Date
    let duration: TimeInterval

    init(text: String, duration: TimeInterval) {
        id = UUID()
        self.text = text
        timestamp = Date()
        self.duration = duration
    }
}

// MARK: - Output Destinations

struct OutputDestinations: OptionSet {
    let rawValue: Int

    static let clipboard = OutputDestinations(rawValue: 1 << 0)
    static let activeField = OutputDestinations(rawValue: 1 << 1)
    static let appleNotes = OutputDestinations(rawValue: 1 << 2)
    static let file = OutputDestinations(rawValue: 1 << 3)
}
