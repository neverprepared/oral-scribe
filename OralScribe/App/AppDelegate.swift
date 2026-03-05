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

        // Observe recording state to show/hide floating overlay
        stateCancellable = RecordingCoordinator.shared.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                switch state {
                case .recording:
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
