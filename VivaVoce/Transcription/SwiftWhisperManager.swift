import Foundation
import SwiftWhisper

// MARK: - Model Definition

struct WhisperCppModel {
    let id: String
    let filename: String
    let displayName: String
    let sizeNote: String

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    // CoreML encoder zip (enables ANE/GPU acceleration via WHISPER_USE_COREML)
    var coremlZipFilename: String { "ggml-\(id)-encoder.mlmodelc.zip" }
    var coremlZipURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(coremlZipFilename)")!
    }
    // The unzipped directory name that whisper.cpp looks for alongside the .bin
    var coremlDirName: String { "ggml-\(id)-encoder.mlmodelc" }
}

// MARK: - Manager

@MainActor
class SwiftWhisperManager: ObservableObject {
    static let shared = SwiftWhisperManager()

    enum LoadState: Equatable {
        case notDownloaded
        case downloading(String, Double)  // label, 0.0–1.0
        case loading
        case ready(String)        // loaded model id
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

    @Published var loadState: LoadState = .notDownloaded
    private(set) var whisper: Whisper?

    // Models compatible with whisper.cpp v1.4.2 (bundled in SwiftWhisper).
    // large-v3 and large-v3-turbo require v1.5+ and will crash on encode.
    static let availableModels: [WhisperCppModel] = [
        .init(id: "tiny",     filename: "ggml-tiny.bin",     displayName: "Tiny",     sizeNote: "~75 MB"),
        .init(id: "base",     filename: "ggml-base.bin",     displayName: "Base",     sizeNote: "~148 MB"),
        .init(id: "small",    filename: "ggml-small.bin",    displayName: "Small",    sizeNote: "~488 MB"),
        .init(id: "medium",   filename: "ggml-medium.bin",   displayName: "Medium",   sizeNote: "~1.5 GB"),
        .init(id: "large-v2", filename: "ggml-large-v2.bin", displayName: "Large v2", sizeNote: "~3.1 GB"),
    ]

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("VivaVoce/WhisperCpp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func displayName(for modelId: String) -> String {
        availableModels.first { $0.id == modelId }?.displayName ?? modelId
    }

    private init() {}

    func modelURL(for model: WhisperCppModel) -> URL {
        Self.modelsDirectory.appendingPathComponent(model.filename)
    }

    func coremlDirURL(for model: WhisperCppModel) -> URL {
        Self.modelsDirectory.appendingPathComponent(model.coremlDirName, isDirectory: true)
    }

    func isDownloaded(_ model: WhisperCppModel) -> Bool {
        let url = modelURL(for: model)
        guard FileManager.default.fileExists(atPath: url.path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size > 50_000_000 else {
            // Missing or partial file — clean up so we re-download
            try? FileManager.default.removeItem(at: url)
            return false
        }
        return true
    }

    func isCoreMLDownloaded(_ model: WhisperCppModel) -> Bool {
        let dirURL = coremlDirURL(for: model)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dirURL.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - Download & Load

    func downloadAndLoad(modelId: String) async {
        guard !loadState.isBusy else { return }
        guard let model = Self.availableModels.first(where: { $0.id == modelId }) else {
            loadState = .failed("Unknown model: \(modelId)")
            return
        }

        whisper = nil
        let destURL = modelURL(for: model)

        // 1. Download .bin weights if needed
        if !isDownloaded(model) {
            do {
                loadState = .downloading("Downloading weights…", 0)
                try await downloadFile(from: model.downloadURL, to: destURL) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.loadState = .downloading("Downloading weights…", progress)
                    }
                }
            } catch {
                loadState = .failed(error.localizedDescription)
                return
            }
        }

        // Validate weights file size before passing to Whisper.init (which crashes on bad files)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
              let fileSize = attrs[.size] as? Int64,
              fileSize > 50_000_000 else {
            try? FileManager.default.removeItem(at: destURL)
            loadState = .failed("Downloaded file appears incomplete. Please try again.")
            return
        }

        // 2. Download CoreML encoder if needed (enables ANE/GPU via WHISPER_USE_COREML)
        if !isCoreMLDownloaded(model) {
            let zipURL = Self.modelsDirectory.appendingPathComponent(model.coremlZipFilename)
            do {
                loadState = .downloading("Downloading CoreML encoder…", 0)
                try await downloadFile(from: model.coremlZipURL, to: zipURL) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.loadState = .downloading("Downloading CoreML encoder…", progress)
                    }
                }
                // Unzip into models directory
                loadState = .downloading("Extracting CoreML encoder…", 1.0)
                try unzip(zipURL, into: Self.modelsDirectory)
                try? FileManager.default.removeItem(at: zipURL)
            } catch {
                // CoreML is optional — log and continue with CPU fallback
                try? FileManager.default.removeItem(at: zipURL)
                print("[SwiftWhisperManager] CoreML encoder download/unzip failed (will use CPU): \(error)")
            }
        }

        // 3. Load model
        loadState = .loading
        let whisperInstance = await Task.detached(priority: .userInitiated) {
            // Set language explicitly to avoid whisper_lang_auto_detect_with_state,
            // which asserts inside whisper_encode_internal on some model/platform combos.
            let params = WhisperParams.default
            params.language = .english
            params.suppress_blank = true
            params.suppress_non_speech_tokens = true
            return Whisper(fromFileURL: destURL, withParams: params)
        }.value
        whisper = whisperInstance
        loadState = .ready(modelId)
    }

    // MARK: - File Download

    private func downloadFile(from url: URL, to destURL: URL, onProgress: @escaping (Double) -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let delegate = ModelDownloadDelegate(destURL: destURL, onProgress: onProgress) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    // MARK: - Unzip

    private func unzip(_ zipURL: URL, into directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        // -o: overwrite, -q: quiet, -d: destination
        process.arguments = ["-o", "-q", zipURL.path, "-d", directory.path]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw NSError(domain: "SwiftWhisperManager", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "unzip exited with status \(process.terminationStatus)"])
        }
    }

    // MARK: - Unload / Delete

    func unload() {
        whisper = nil
        loadState = .notDownloaded
    }

    func deleteModel(modelId: String) {
        guard let model = Self.availableModels.first(where: { $0.id == modelId }) else { return }
        try? FileManager.default.removeItem(at: modelURL(for: model))
        try? FileManager.default.removeItem(at: coremlDirURL(for: model))
        if case .ready(let loaded) = loadState, loaded == modelId {
            whisper = nil
            loadState = .notDownloaded
        }
    }
}

// MARK: - Download Delegate

private class ModelDownloadDelegate: NSObject, URLSessionDownloadDelegate {
    private let destURL: URL
    private let onProgress: (Double) -> Void
    private let onComplete: (Error?) -> Void
    private var completed = false

    init(destURL: URL, onProgress: @escaping (Double) -> Void, onComplete: @escaping (Error?) -> Void) {
        self.destURL = destURL
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: location, to: destURL)
            finish(error: nil)
        } catch {
            finish(error: error)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error { finish(error: error) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.99))
    }

    private func finish(error: Error?) {
        guard !completed else { return }
        completed = true
        onComplete(error)
    }
}
