import Foundation
import WhisperKit

// MARK: - Model Load State

enum WKLoadState: Equatable {
    case notLoaded
    case downloading(Double)  // 0.0–1.0
    case loading
    case ready(String)        // loaded model name
    case failed(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .downloading, .loading: return true
        default: return false
        }
    }

}

// MARK: - WhisperKit Model Options

struct WhisperKitModel {
    let id: String        // e.g. "openai/whisper-large-v3-turbo"
    let displayName: String
    let sizeNote: String
}

// MARK: - Manager

@MainActor
class WhisperKitManager: ObservableObject {
    static let shared = WhisperKitManager()

    @Published var loadState: WKLoadState = .notLoaded

    private(set) var pipe: WhisperKit?

    static let availableModels: [WhisperKitModel] = [
        .init(id: "tiny",            displayName: "Tiny",           sizeNote: "~150 MB"),
        .init(id: "base",            displayName: "Base",           sizeNote: "~300 MB"),
        .init(id: "small",           displayName: "Small",          sizeNote: "~500 MB"),
        .init(id: "large-v3-turbo",  displayName: "Large v3 Turbo", sizeNote: "~1.6 GB"),
        .init(id: "large-v3",        displayName: "Large v3",       sizeNote: "~3 GB"),
    ]

    static func displayName(for modelId: String) -> String {
        availableModels.first { $0.id == modelId }?.displayName ?? modelId
    }

    private init() {}

    // MARK: - Load

    func downloadAndLoad(model: String) async {
        guard !loadState.isBusy else { return }
        pipe = nil
        loadState = .loading  // indeterminate — WhisperKit downloads + loads in one step

        do {
            let whisperKit = try await WhisperKit(model: model)
            pipe = whisperKit
            loadState = .ready(model)
        } catch {
            print("[WhisperKit] load failed: \(error)")
            loadState = .failed(error.localizedDescription)
            pipe = nil
        }
    }

    func unload() {
        pipe = nil
        loadState = .notLoaded
    }
}
