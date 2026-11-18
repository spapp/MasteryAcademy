import SwiftUI
import WebKit

/// The original interactive course page (simulators, playgrounds), bundled with the app and shown offline.
struct InteractivePageView: View {
    let courseId: String
    @Environment(ContentRepository.self) private var repository

    var body: some View {
        Group {
            if let summary = repository.summary(courseId), let url = repository.webPageURL(for: summary) {
                WebPage(fileURL: url).ignoresSafeArea(edges: .bottom)
            } else {
                ContentUnavailableView("Not bundled", systemImage: "play.rectangle",
                                       description: Text("The interactive page for this course is not included in the app."))
            }
        }
        .navigationTitle("Simulators")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct WebPage: UIViewRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        /// The page stays inside the web view; links to other sites open in the browser.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
               url.scheme == "http" || url.scheme == "https" {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
