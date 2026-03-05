import SwiftUI

// MARK: - Circular Record Button

struct RecordButtonView: View {
    @EnvironmentObject var coordinator: RecordingCoordinator
    var size: CGFloat = 56

    @State private var pulseAnimation = false

    var body: some View {
        VStack(spacing: 6) {
        Button(action: { coordinator.toggle() }) {
            ZStack {
                Circle()
                    .fill(buttonColor.opacity(0.15))
                    .frame(width: size + 8, height: size + 8)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .animation(
                        coordinator.state == .recording
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: pulseAnimation
                    )

                Circle()
                    .fill(buttonColor)
                    .frame(width: size, height: size)

                Image(systemName: micIcon)
                    .font(.system(size: size * 0.43, weight: .medium))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(coordinator.state.isActive && coordinator.state != .recording)
        .onAppear { pulseAnimation = coordinator.state == .recording }
        .onChange(of: coordinator.state) { newState in
            pulseAnimation = newState == .recording
        }

        Text(coordinator.state.statusText)
            .font(.caption)
            .foregroundColor(.secondary)
        } // end VStack
    }

    private var buttonColor: Color {
        switch coordinator.state {
        case .recording:                                             return .red
        case .transcribing, .processing, .translating, .delivering: return .orange
        case .done:                                                  return .green
        case .error:                                                 return .red
        default:                                                     return .accentColor
        }
    }

    private var micIcon: String {
        switch coordinator.state {
        case .recording:                                             return "stop.fill"
        case .transcribing, .processing, .translating, .delivering: return "ellipsis"
        case .error:                                                 return "exclamationmark.triangle.fill"
        default:                                                     return "mic.fill"
        }
    }
}
