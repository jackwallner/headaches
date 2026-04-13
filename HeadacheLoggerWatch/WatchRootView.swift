import SwiftUI
import WatchConnectivity

struct WatchRootView: View {
    @StateObject private var session = WatchConnectivityController()

    var body: some View {
        logView
            .onAppear {
                session.activate()
            }
    }

    private var logView: some View {
        VStack(spacing: 12) {
            Text("Headache")
                .font(.headline)
            Button {
                session.requestLogFromPhone()
            } label: {
                Label(session.showConfirmation ? "Logged" : "Log headache",
                      systemImage: session.showConfirmation ? "checkmark.circle.fill" : "brain.head.profile")
            }
            .buttonStyle(.borderedProminent)
            .tint(session.showConfirmation ? .green : Color(red: 0.95, green: 0.25, blue: 0.43))
            .animation(.easeInOut(duration: 0.25), value: session.showConfirmation)

            if let message = session.statusMessage, !session.showConfirmation {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 4)
    }
}
