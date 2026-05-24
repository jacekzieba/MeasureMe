import SwiftUI
import MessageUI

struct MailComposerSheet: UIViewControllerRepresentable {
    let toRecipient: String
    let subject: String
    let body: String
    let attachmentData: Data?
    let attachmentFileName: String
    var onDismiss: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([toRecipient])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        if let data = attachmentData {
            vc.addAttachmentData(data, mimeType: "application/json", fileName: attachmentFileName)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true)
            onDismiss()
        }
    }
}
