import AppKit
import AVFoundation
import Speech
import KeyboardShortcuts
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayWindow: RecordingOverlayWindow?
    private var stateCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request permissions
        requestMicrophonePermission()
        requestSpeechRecognitionPermission()

        // Request accessibility (needed for AX text injection and CGEvent.postToPid)
        if !AccessibilityOutput.isAccessibilityEnabled {
            AccessibilityOutput.requestAccessibilityPermission()
        }

        // Register global hotkey
        HotkeyManager.shared.register()

        // Auto-load the selected transcription model so the user doesn't have to press Load each launch
        autoLoadTranscriptionModel()

        // Observe recording state to show/hide floating overlay
        stateCancellable = RecordingCoordinator.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                switch state {
                case .recording, .transcribing, .processing, .translating, .delivering:
                    self?.showOverlay()
                default:
                    self?.hideOverlay()
                }
            }
    }

    private func showOverlay() {
        if overlayWindow == nil {
            overlayWindow = RecordingOverlayWindow()
        }
        overlayWindow?.showOverlay()
    }

    private func hideOverlay() {
        overlayWindow?.hideOverlay()
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return  // Already granted
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if !granted {
                    DispatchQueue.main.async {
                        self.showPermissionAlert(
                            title: "Microphone Access Required",
                            message: "Oral Scribe needs microphone access to record your voice. Please enable it in System Settings > Privacy & Security > Microphone."
                        )
                    }
                }
            }
        case .denied, .restricted:
            showPermissionAlert(
                title: "Microphone Access Required",
                message: "Oral Scribe needs microphone access to record your voice. Please enable it in System Settings > Privacy & Security > Microphone."
            )
        @unknown default:
            break
        }
    }

    private func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized {
                DispatchQueue.main.async {
                    self.showPermissionAlert(
                        title: "Speech Recognition Required",
                        message: "Oral Scribe needs speech recognition access. Please enable it in System Settings > Privacy & Security > Speech Recognition."
                    )
                }
            }
        }
    }

    private func autoLoadTranscriptionModel() {
        Task { @MainActor in
            let settings = SettingsManager.shared
            switch settings.transcriptionBackend {
            case .whisperCpp:
                let modelId = settings.whisperCppModel
                let model = SwiftWhisperManager.availableModels.first { $0.id == modelId }
                    ?? SwiftWhisperManager.availableModels[0]
                if SwiftWhisperManager.shared.isDownloaded(model) {
                    await SwiftWhisperManager.shared.downloadAndLoad(modelId: modelId)
                }
            case .whisperKit:
                let modelId = settings.whisperKitModel
                await WhisperKitManager.shared.downloadAndLoad(model: modelId)
            default:
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        ClipboardOutput.clearIfOurs()
    }

    private func showPermissionAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")!)
        }
    }
}
