import SwiftUI
import WatchConnectivity

struct WatchRootView: View {
    @StateObject private var session = WatchConnectivityController()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                logButton

                if let message = session.statusMessage {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .transition(.opacity)
                }

                if let lastDate = session.lastLoggedDate, !session.showConfirmation {
                    lastLoggedLabel(date: lastDate)
                }
            }
            .padding(.horizontal, 4)
            .animation(.easeInOut(duration: 0.25), value: session.showConfirmation)
            .animation(.easeInOut(duration: 0.25), value: session.isSending)
        }
        .onAppear {
            session.activate()
        }
    }

    private var logButton: some View {
        Button {
            session.requestLogFromPhone()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 28, weight: .bold))
                Text(buttonLabel)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(buttonTint)
        .disabled(session.isSending)
    }

    private var buttonIcon: String {
        if session.showConfirmation { return "checkmark.circle.fill" }
        if session.isSending { return "arrow.up.circle" }
        return "brain.head.profile"
    }

    private var buttonLabel: String {
        if session.showConfirmation { return "Logged" }
        if session.isSending { return "Sending…" }
        return "Headache"
    }

    private var buttonTint: Color {
        if session.showConfirmation { return .green }
        if session.isSending { return .orange }
        return Color(red: 0.95, green: 0.25, blue: 0.43)
    }

    private func lastLoggedLabel(date: Date) -> some View {
        VStack(spacing: 2) {
            Text("Last logged")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(date, style: .relative)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            + Text(" ago")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
