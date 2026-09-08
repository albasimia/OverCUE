import AppKit
import SwiftUI
import WebKit

struct OverCUEWebRootView: View {
    let serverReady: Bool
    let errorMessage: String?

    var body: some View {
        Group {
            if serverReady {
                OverCUEWebView(serverReady: true)
            } else {
                VStack(spacing: 14) {
                    ProgressView()
                    Text("Starting OverCUE Web UI…")
                        .font(.headline)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
    }
}

private struct OverCUEWebView: NSViewRepresentable {
    let serverReady: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard serverReady else { return }
        context.coordinator.loadRootIfNeeded(in: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let rootURL = URL(string: "http://127.0.0.1:4173/")!
        private var loadedRoot = false
        private var retryCount = 0
        private let maximumRetries = 12

        func loadRootIfNeeded(in webView: WKWebView) {
            guard !loadedRoot else { return }
            loadedRoot = true
            retryCount = 0
            loadRoot(in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retryCount = 0
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            guard retryCount < maximumRetries else { return }
            retryCount += 1
            Task { @MainActor [weak webView] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let webView else { return }
                self.loadRoot(in: webView)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if url.scheme == "about" {
                decisionHandler(.allow)
                return
            }

            let isLocalOverCUE = (url.host == "127.0.0.1" || url.host == "localhost")
                && (url.port == nil || url.port == 4_173)
            if isLocalOverCUE {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "http" || url.scheme == "https" {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        private func loadRoot(in webView: WKWebView) {
            webView.load(
                URLRequest(
                    url: rootURL,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 5
                )
            )
        }
    }
}
