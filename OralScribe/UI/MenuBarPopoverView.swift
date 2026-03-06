import SwiftUI
import AppKit
import KeyboardShortcuts

extension Notification.Name {
    static let navigateToHistory = Notification.Name("navigateToHistory")
}

// MARK: - Menu Bar Popover View (slim)

struct MenuBarPopoverView: View {
    @EnvironmentObject var coordinator: RecordingCoordinator
    @EnvironmentObject var settings: SettingsManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Pipeline summary line + recording timer
            HStack {
                Text(pipelineSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if coordinator.state == .recording {
                    Text(formatDuration(coordinator.recordingDuration))
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()

            // Record button
            RecordButtonView()
                .environmentObject(coordinator)
                .padding(.vertical, 10)

            // Link to history when there's a transcript
            if !transcriptText.isEmpty {
                Button {
                    dismissPopover()
                    openMainWindow()
                    NotificationCenter.default.post(name: .navigateToHistory, object: nil)
                } label: {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text("View in History")
                            .font(.callout)
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }

            Divider()

            // Bottom row: hotkey chip + Open App + Quit
            HStack {
                if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleRecording) {
                    Text(shortcut.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                Spacer()

                Button("Open App") {
                    dismissPopover()
                    openMainWindow()
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)

                Text("·").foregroundColor(.secondary)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 280)
    }

    // MARK: - Computed

    private var pipelineSummary: String {
        var parts: [String] = [backendShortName]
        if settings.ollamaEnabled && settings.processingMode != .passthrough {
            parts.append(settings.processingMode.displayName)
        }
        parts.append(outputSummary)
        return parts.joined(separator: " → ")
    }

    private var backendShortName: String {
        switch settings.transcriptionBackend {
        case .appleSpeech:   return "Apple Speech"
        case .openAIWhisper: return "OpenAI Whisper"
        case .whisperKit:    return "WhisperKit"
        case .whisperCpp:    return "Whisper.cpp"
        }
    }

    private var outputSummary: String {
        var destinations: [String] = []
        if settings.outputToClipboard    { destinations.append("Clipboard") }
        if settings.outputToActiveField  { destinations.append("Active Field") }
        if settings.outputToAppleNotes   { destinations.append("Notes") }
        if settings.outputToFile         { destinations.append("File") }
        return destinations.isEmpty ? "No Output" : destinations.joined(separator: ", ")
    }

    private var transcriptText: String {
        coordinator.finalTranscript.isEmpty ? coordinator.liveTranscript : coordinator.finalTranscript
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }

    private func dismissPopover() {
        // The MenuBarExtra .window style popover is the current key window
        if let panel = NSApp.keyWindow, type(of: panel).description().contains("StatusBarWindow") || panel !== NSApp.windows.first(where: { $0.title == "Oral Scribe" }) {
            panel.close()
        }
    }

    private func openMainWindow() {
        if let window = NSApp.windows.first(where: { $0.title == "Oral Scribe" }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
