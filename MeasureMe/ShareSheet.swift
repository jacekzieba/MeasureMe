import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var subject: String? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let subject {
            controller.setValue(subject, forKey: "subject")
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // no-op
    }
}
