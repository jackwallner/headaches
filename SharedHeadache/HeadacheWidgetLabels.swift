import SwiftUI

struct HeadacheWidgetLogLabel: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 32))
                .symbolRenderingMode(.hierarchical)
            Text("Log headache")
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
}

struct HeadacheWidgetLoggedLabel: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text("Logged")
                .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
}
