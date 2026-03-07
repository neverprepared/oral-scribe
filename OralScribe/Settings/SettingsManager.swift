import Foundation
import Security

// MARK: - Keychain Helper

enum Keychain {
    static func save(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Settings Manager

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // Transcription
    @Published var transcriptionBackend: TranscriptionBackend {
        didSet { UserDefaults.standard.set(transcriptionBackend.rawValue, forKey: Keys.transcriptionBackend) }
    }
    @Published var speechLocale: String {
        didSet { UserDefaults.standard.set(speechLocale, forKey: Keys.speechLocale) }
    }
    @Published var onDeviceRecognition: Bool {
        didSet { UserDefaults.standard.set(onDeviceRecognition, forKey: Keys.onDeviceRecognition) }
    }
    @Published var whisperKitModel: String {
        didSet { UserDefaults.standard.set(whisperKitModel, forKey: Keys.whisperKitModel) }
    }
    @Published var whisperCppModel: String {
        didSet { UserDefaults.standard.set(whisperCppModel, forKey: Keys.whisperCppModel) }
    }
    @Published var openAIModel: String {
        didSet { UserDefaults.standard.set(openAIModel, forKey: Keys.openAIModel) }
    }
    @Published var whisperTranslateMode: Bool {
        didSet { UserDefaults.standard.set(whisperTranslateMode, forKey: Keys.whisperTranslateMode) }
    }

    // OpenAI API Key (Keychain) — cached in memory after the single init-time read
    private var _openAIAPIKey: String = ""

    var openAIAPIKey: String {
        get { _openAIAPIKey }
        set {
            _openAIAPIKey = newValue
            if newValue.isEmpty {
                Keychain.delete(key: Keys.openAIAPIKey)
            } else {
                Keychain.save(key: Keys.openAIAPIKey, value: newValue)
            }
            objectWillChange.send()
        }
    }

    // LLM Processing
    @Published var ollamaEnabled: Bool {
        didSet { UserDefaults.standard.set(ollamaEnabled, forKey: Keys.ollamaEnabled) }
    }
    @Published var ollamaHost: String {
        didSet { UserDefaults.standard.set(ollamaHost, forKey: Keys.ollamaHost) }
    }
    @Published var ollamaModel: String {
        didSet { UserDefaults.standard.set(ollamaModel, forKey: Keys.ollamaModel) }
    }
    @Published var processingMode: ProcessingMode {
        didSet { UserDefaults.standard.set(processingMode.rawValue, forKey: Keys.processingMode) }
    }
    @Published var customPrompt: String {
        didSet { UserDefaults.standard.set(customPrompt, forKey: Keys.customPrompt) }
    }

    // Translation
    @Published var translationEnabled: Bool {
        didSet { UserDefaults.standard.set(translationEnabled, forKey: Keys.translationEnabled) }
    }
    @Published var translationTargetLanguage: String {
        didSet { UserDefaults.standard.set(translationTargetLanguage, forKey: Keys.translationTargetLanguage) }
    }

    // Voice Trigger
    @Published var voiceTriggerEnabled: Bool {
        didSet { UserDefaults.standard.set(voiceTriggerEnabled, forKey: Keys.voiceTriggerEnabled) }
    }
    @Published var deliverPhrase: String {
        didSet { UserDefaults.standard.set(deliverPhrase, forKey: Keys.deliverPhrase) }
    }
    @Published var stopPhrase: String {
        didSet { UserDefaults.standard.set(stopPhrase, forKey: Keys.stopPhrase) }
    }

    // Output
    @Published var outputToClipboard: Bool {
        didSet { UserDefaults.standard.set(outputToClipboard, forKey: Keys.outputToClipboard) }
    }
    @Published var outputToActiveField: Bool {
        didSet { UserDefaults.standard.set(outputToActiveField, forKey: Keys.outputToActiveField) }
    }
    @Published var outputToAppleNotes: Bool {
        didSet { UserDefaults.standard.set(outputToAppleNotes, forKey: Keys.outputToAppleNotes) }
    }
    @Published var outputToFile: Bool {
        didSet { UserDefaults.standard.set(outputToFile, forKey: Keys.outputToFile) }
    }
    @Published var outputFilePath: String {
        didSet { UserDefaults.standard.set(outputFilePath, forKey: Keys.outputFilePath) }
    }

    private enum Keys {
        static let transcriptionBackend = "transcriptionBackend"
        static let speechLocale = "speechLocale"
        static let openAIModel = "openAIModel"
        static let whisperTranslateMode = "whisperTranslateMode"
        static let onDeviceRecognition = "onDeviceRecognition"
        static let whisperKitModel = "whisperKitModel"
        static let whisperCppModel = "whisperCppModel"
        static let openAIAPIKey = "com.oralscribe.openai-api-key"
        static let ollamaEnabled = "ollamaEnabled"
        static let ollamaHost = "ollamaHost"
        static let ollamaModel = "ollamaModel"
        static let processingMode = "processingMode"
        static let customPrompt = "customPrompt"
        static let translationEnabled = "translationEnabled"
        static let translationTargetLanguage = "translationTargetLanguage"
        static let voiceTriggerEnabled = "voiceTriggerEnabled"
        static let deliverPhrase = "deliverPhrase"
        static let stopPhrase = "stopPhrase"
        static let outputToClipboard = "outputToClipboard"
        static let outputToActiveField = "outputToActiveField"
        static let outputToAppleNotes = "outputToAppleNotes"
        static let outputToFile = "outputToFile"
        static let outputFilePath = "outputFilePath"
    }

    private init() {
        let defaults = UserDefaults.standard

        _openAIAPIKey = Keychain.load(key: Keys.openAIAPIKey) ?? ""

        transcriptionBackend = TranscriptionBackend(
            rawValue: defaults.string(forKey: Keys.transcriptionBackend) ?? ""
        ) ?? .appleSpeech

        speechLocale = defaults.string(forKey: Keys.speechLocale) ?? "en-US"
        onDeviceRecognition = defaults.object(forKey: Keys.onDeviceRecognition) as? Bool ?? true
        whisperKitModel = defaults.string(forKey: Keys.whisperKitModel) ?? "large-v3-turbo"
        let storedCppModel = defaults.string(forKey: Keys.whisperCppModel) ?? "small"
        let validCppIds = SwiftWhisperManager.availableModels.map(\.id)
        whisperCppModel = validCppIds.contains(storedCppModel) ? storedCppModel : "small"
        openAIModel = defaults.string(forKey: Keys.openAIModel) ?? "whisper-1"
        whisperTranslateMode = defaults.bool(forKey: Keys.whisperTranslateMode)

        ollamaEnabled = defaults.bool(forKey: Keys.ollamaEnabled)
        ollamaHost = defaults.string(forKey: Keys.ollamaHost) ?? "http://localhost:11434"
        ollamaModel = defaults.string(forKey: Keys.ollamaModel) ?? "llama3.2:1b"
        processingMode = ProcessingMode(
            rawValue: defaults.string(forKey: Keys.processingMode) ?? ""
        ) ?? .passthrough
        customPrompt = defaults.string(forKey: Keys.customPrompt) ?? ""

        translationEnabled = defaults.bool(forKey: Keys.translationEnabled)
        translationTargetLanguage = defaults.string(forKey: Keys.translationTargetLanguage) ?? "en"

        voiceTriggerEnabled = defaults.bool(forKey: Keys.voiceTriggerEnabled)
        deliverPhrase = defaults.string(forKey: Keys.deliverPhrase) ?? "deliver"
        stopPhrase = defaults.string(forKey: Keys.stopPhrase) ?? "stop listening"

        outputToClipboard = defaults.object(forKey: Keys.outputToClipboard) as? Bool ?? false
        outputToActiveField = defaults.object(forKey: Keys.outputToActiveField) as? Bool ?? true
        outputToAppleNotes = defaults.bool(forKey: Keys.outputToAppleNotes)
        outputToFile = defaults.bool(forKey: Keys.outputToFile)
        outputFilePath = defaults.string(forKey: Keys.outputFilePath) ?? ""
    }
}
