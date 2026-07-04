import UIKit
import SwiftUI
import UniformTypeIdentifiers

// Principal class for the share extension. The system shows this view
// controller in a sheet when the user picks Wishes from the share
// sheet. We pull the shared URL / text / page title out of the
// extensionContext, then host the SwiftUI confirm sheet (ShareComposeView).
final class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        extractSharedContent { [weak self] title, url in
            DispatchQueue.main.async { self?.showCompose(title: title, url: url) }
        }
    }

    // MARK: - Hosting the SwiftUI confirm sheet

    private func showCompose(title: String, url: String?) {
        let compose = ShareComposeView(
            initialTitle: title,
            url: url,
            onSave: { [weak self] in self?.complete() },
            onCancel: { [weak self] in self?.cancel() }
        )
        let host = UIHostingController(rootView: compose)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: "teratech.BucketList.ShareExtension", code: 0))
    }

    // MARK: - Extracting the shared payload

    // Resolves a best-effort (title, url) from the share. Safari/X/YouTube
    // hand us a URL; some apps also share selected text or a page title via
    // attributedContentText. Title falls back text → URL host so the field is
    // never empty.
    private func extractSharedContent(completion: @escaping (String, String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem else {
            completion("", nil); return
        }
        let pageTitle = item.attributedContentText?.string ?? ""
        var foundURL: String?
        var foundText = ""
        let group = DispatchGroup()

        for provider in item.attachments ?? [] {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.url.identifier) { data, _ in
                    if let u = data as? URL { foundURL = u.absoluteString }
                    else if let s = data as? String { foundURL = s }
                    group.leave()
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { data, _ in
                    if let t = data as? String { foundText = t }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            let host = foundURL.flatMap { URL(string: $0)?.host } ?? ""
            let title = !pageTitle.isEmpty ? pageTitle
                : (!foundText.isEmpty ? foundText : host)
            completion(title, foundURL)
        }
    }
}
