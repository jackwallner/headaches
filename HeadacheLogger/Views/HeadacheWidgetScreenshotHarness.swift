#if DEBUG
import SwiftUI

struct HeadacheWidgetScreenshotHarness: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            HeadacheWidgetLogLabel()
                .frame(width: 158, height: 158)
                .background(Color(red: 0.35, green: 0.12, blue: 0.16))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
#endif
