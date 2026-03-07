import SwiftUI
import KeyboardShortcuts

// MARK: - Onboarding View

struct OnboardingView: View {
    @EnvironmentObject var settings: SettingsManager
    @Binding var isPresented: Bool
    @State private var currentStep = 0

    private let totalSteps = 4

    var body: some View {
        VStack(spacing: 0) {
            // Content
            ScrollView {
                Group {
                    switch currentStep {
                    case 0: welcomeStep
                    case 1: outputStep
                    case 2: hotkeyStep
                    case 3: finishStep
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Divider()

            // Footer: progress dots + navigation
            HStack {
                if currentStep > 0 {
                    Button("Back") { withAnimation { currentStep -= 1 } }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                } else {
                    Spacer().frame(width: 40)
                }

                Spacer()

                progressDots

                Spacer()

                if currentStep < totalSteps - 1 {
                    Button("Next") { withAnimation { currentStep += 1 } }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentStep == 1 && !hasAtLeastOneOutput)
                } else {
                    Button("Start Dictating") { completeOnboarding() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 460)
    }

    // MARK: - Step 1: Welcome / Engine Picker

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.and.mic")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Welcome to Oral Scribe")
                .font(.title)
                .fontWeight(.semibold)

            Text("Choose your transcription engine to get started.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(TranscriptionBackend.allCases, id: \.self) { backend in
                    engineRow(backend)
                }
            }
            .padding(.horizontal, 40)
        }
        .padding()
    }

    private func engineRow(_ backend: TranscriptionBackend) -> some View {
        Button {
            settings.transcriptionBackend = backend
        } label: {
            HStack(spacing: 12) {
                Image(systemName: settings.transcriptionBackend == backend ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(settings.transcriptionBackend == backend ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(backend.displayName)
                        .fontWeight(.medium)
                    Text(engineDescription(backend))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(settings.transcriptionBackend == backend
                          ? Color.accentColor.opacity(0.1)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func engineDescription(_ backend: TranscriptionBackend) -> String {
        switch backend {
        case .appleSpeech:  return "Built-in, on-device. No setup needed."
        case .openAIWhisper: return "Cloud-based, high accuracy. Requires API key."
        case .whisperKit:   return "On-device with WhisperKit. Downloads model locally."
        case .whisperCpp:   return "On-device with Whisper.cpp. Downloads model locally."
        }
    }

    // MARK: - Step 2: Output Destinations

    private var outputStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Where should transcripts go?")
                .font(.title)
                .fontWeight(.semibold)

            Text("Select at least one destination.")
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $settings.outputToClipboard) {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
                Toggle(isOn: $settings.outputToActiveField) {
                    Label("Active Text Field", systemImage: "character.cursor.ibeam")
                }
                Toggle(isOn: $settings.outputToAppleNotes) {
                    Label("Apple Notes", systemImage: "note.text")
                }
                Toggle(isOn: $settings.outputToFile) {
                    Label("File", systemImage: "doc.text")
                }
            }
            .toggleStyle(.checkbox)
            .padding(.horizontal, 60)

            if !hasAtLeastOneOutput {
                Text("Please select at least one output destination.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    private var hasAtLeastOneOutput: Bool {
        settings.outputToClipboard
        || settings.outputToActiveField
        || settings.outputToAppleNotes
        || settings.outputToFile
    }

    // MARK: - Step 3: Hotkey

    private var hotkeyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "keyboard")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Set your hotkey")
                .font(.title)
                .fontWeight(.semibold)

            Text("Record a global shortcut to start and stop dictation.")
                .foregroundColor(.secondary)

            HStack {
                Text("Record / Stop Hotkey")
                Spacer()
                KeyboardShortcuts.Recorder("", name: .toggleRecording)
            }
            .padding(.horizontal, 60)

            Button("Skip") { withAnimation { currentStep += 1 } }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
    }

    // MARK: - Step 4: Finish

    private var finishStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("You're all set!")
                .font(.title)
                .fontWeight(.semibold)

            // Summary checklist
            VStack(alignment: .leading, spacing: 8) {
                summaryRow(icon: "waveform", label: "Engine", value: settings.transcriptionBackend.displayName)
                summaryRow(icon: "tray.and.arrow.down", label: "Output", value: outputSummary)
                summaryRow(icon: "keyboard", label: "Hotkey", value: hotkeySummary)
            }
            .padding(.horizontal, 40)

            // Accessibility permission
            if !AccessibilityOutput.isAccessibilityEnabled {
                Button {
                    AccessibilityOutput.requestAccessibilityPermission()
                } label: {
                    Label("Request Accessibility Permission", systemImage: "lock.shield")
                }
                .buttonStyle(.bordered)
            } else {
                Label("Accessibility Permission Granted", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
        }
        .padding()
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.accentColor)
            Text(label)
                .fontWeight(.medium)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    private var outputSummary: String {
        var destinations: [String] = []
        if settings.outputToClipboard { destinations.append("Clipboard") }
        if settings.outputToActiveField { destinations.append("Active Field") }
        if settings.outputToAppleNotes { destinations.append("Apple Notes") }
        if settings.outputToFile { destinations.append("File") }
        return destinations.joined(separator: ", ")
    }

    private var hotkeySummary: String {
        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleRecording) {
            return "\(shortcut)"
        }
        return "Not set"
    }

    // MARK: - Progress Dots

    private var progressDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { step in
                Circle()
                    .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
            }
        }
    }

    // MARK: - Actions

    private func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        isPresented = false
    }
}
