import AppKit
import SwiftUI

// MARK: - RecordingOverlayWindow

final class RecordingOverlayWindow: NSPanel {

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 60),
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
        let hostingView = NSHostingView(rootView: pillView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 60)
        contentView = hostingView
    }

    func showOverlay() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 140
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
    @State private var barHeights: [CGFloat] = Array(repeating: 0.15, count: 30)
    @State private var dotScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                )

            HStack(spacing: 12) {
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

                // Recording timer
                Text(formatDuration(coordinator.recordingDuration))
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundColor(.white.opacity(0.8))

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

                // Cancel button
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
            }
            .padding(.horizontal, 14)
        }
        .frame(width: 280, height: 60)
        .onChange(of: coordinator.powerLevel) { _ in
            updateBars()
        }
        .onAppear {
            updateBars()
        }
    }

    private func updateBars() {
        let normalized = max(0, min(1, CGFloat(coordinator.powerLevel + 60) / 60))
        for i in 0..<30 {
            let jitter = CGFloat.random(in: -0.15...0.15)
            barHeights[i] = max(0.05, min(1.0, normalized + jitter))
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let s = Int(t)
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}
