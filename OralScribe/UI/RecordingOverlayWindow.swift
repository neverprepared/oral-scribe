import AppKit
import SwiftUI

// MARK: - RecordingOverlayWindow

final class RecordingOverlayWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isMovableByWindowBackground = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let pillView = RecordingPillView()
            .environmentObject(RecordingCoordinator.shared)
            .environmentObject(SettingsManager.shared)
        let hostingView = NSHostingView(rootView: pillView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 350, height: 60)
        contentView = hostingView
    }

    func showOverlay() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 175
            let y = screenFrame.minY + 100
            setFrameOrigin(NSPoint(x: x, y: y))
        }
        orderFrontRegardless()
    }

    func hideOverlay() {
        orderOut(nil)
    }
}

// MARK: - RecordingPillView

struct RecordingPillView: View {
    @EnvironmentObject var coordinator: RecordingCoordinator
    @EnvironmentObject var settings: SettingsManager
    @State private var barHeights: [CGFloat] = Array(repeating: 0.15, count: 30)
    @State private var dotScale: CGFloat = 1.0

    private var isRecording: Bool {
        coordinator.state == .recording
    }

    var body: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )
            pillControls
        }
        .frame(width: 350, height: 60)
        .onChange(of: coordinator.powerLevel) { _ in
            updateBars()
        }
        .onAppear {
            updateBars()
        }
    }

    @ViewBuilder
    private var pillControls: some View {
        HStack(spacing: 12) {
            if isRecording {
                // Pulsing red dot
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .scaleEffect(dotScale)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                        value: dotScale
                    )
                    .onAppear { dotScale = 1.4 }
            } else {
                // Spinner for post-recording states
                ProgressView()
                    .controlSize(.small)
                    .colorScheme(.dark)
            }

            // Recording timer
            Text(formatDuration(coordinator.recordingDuration))
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .foregroundColor(.white.opacity(0.8))

            if isRecording {
                // Waveform bars
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<30, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color.white.opacity(0.85))
                            .frame(width: 3, height: barHeights[i] * 36 + 4)
                            .animation(.easeInOut(duration: 0.1), value: barHeights[i])
                    }
                }
                .frame(maxWidth: .infinity)

                // Auto-submit toggle
                Button {
                    settings.outputAutoSubmit.toggle()
                } label: {
                    Image(systemName: "return.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(settings.outputAutoSubmit ? .white : .white.opacity(0.35))
                        .frame(width: 24, height: 24)
                        .background(settings.outputAutoSubmit ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.08))
                        .clipShape(Circle())
                        .overlay(
                            settings.outputAutoSubmit ? nil :
                                Image(systemName: "line.diagonal")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                                    .rotationEffect(.degrees(90))
                        )
                }
                .buttonStyle(.plain)
                .help("Auto-submit (press Return after inserting)")

                // Stop button (finishes recording and runs pipeline)
                Button {
                    coordinator.toggle()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(width: 24, height: 24)
                        .background(Color.red.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // Cancel button (discards recording)
                Button {
                    coordinator.cancel()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else {
                // Status label for post-recording states
                Text(coordinator.state.statusText)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .animation(.easeInOut(duration: 0.2), value: isRecording)
    }

    private func updateBars() {
        let power = coordinator.powerLevel
        guard power > -155 else {
            // Silence — flatten without generating 30 random values
            if barHeights[0] != 0.05 { barHeights = Array(repeating: 0.05, count: 30) }
            return
        }
        let normalized = max(0, min(1, CGFloat(power + 60) / 60))
        for i in 0..<30 {
            barHeights[i] = max(0.05, min(1.0, normalized + CGFloat.random(in: -0.15...0.15)))
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
