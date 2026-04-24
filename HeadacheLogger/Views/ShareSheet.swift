import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // C10: UIActivityViewController asserts on iPad when presented without a popover anchor.
        // The app ships iPhone-only (TARGETED_DEVICE_FAMILY=1), but iPad compat mode can still
        // run it; set a defensive anchor centered on the key window so presentation never crashes.
        if let popover = controller.popoverPresentationController {
            let window = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first
            popover.sourceView = window
            if let bounds = window?.bounds {
                popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0)
            }
            popover.permittedArrowDirections = []
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
