import AppKit
import Foundation
import SwiftUI
import WebKit

private struct ActiveGroupPresetPayload: Encodable {
    let activeGroupPresetID: String?
}

struct OverCUEWebRootView: View {
    let serverReady: Bool
    let errorMessage: String?

    @EnvironmentObject private var groupPresetRuntimeCoordinator: GroupPresetRuntimeCoordinator

    var body: some View {
        Group {
            if serverReady {
                OverCUEWebView(
                    serverReady: true,
                    activeGroupPresetID: groupPresetRuntimeCoordinator.activeGroupPresetID
                )
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
    let activeGroupPresetID: String?

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
        context.coordinator.syncActiveGroupPreset(activeGroupPresetID, in: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let rootURL = URL(string: "http://127.0.0.1:4173/")!
        private var loadedRoot = false
        private var pageReady = false
        private var retryCount = 0
        private let maximumRetries = 12
        private var pendingActiveGroupPreset = ActiveGroupPresetPayload(activeGroupPresetID: nil)
        private var lastSentActiveGroupPresetJSON: String?

        func loadRootIfNeeded(in webView: WKWebView) {
            guard !loadedRoot else { return }
            loadedRoot = true
            retryCount = 0
            loadRoot(in: webView)
        }

        func syncActiveGroupPreset(_ activeGroupPresetID: String?, in webView: WKWebView) {
            pendingActiveGroupPreset = ActiveGroupPresetPayload(
                activeGroupPresetID: activeGroupPresetID
            )
            guard pageReady else { return }
            sendActiveGroupPreset(pendingActiveGroupPreset, to: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retryCount = 0
            pageReady = true
            lastSentActiveGroupPresetJSON = nil
            sendActiveGroupPreset(pendingActiveGroupPreset, to: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            pageReady = false
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
            pageReady = false
            lastSentActiveGroupPresetJSON = nil
            webView.load(
                URLRequest(
                    url: rootURL,
                    cachePolicy: .reloadIgnoringLocalCacheData,
                    timeoutInterval: 5
                )
            )
        }

        private func sendActiveGroupPreset(
            _ payload: ActiveGroupPresetPayload,
            to webView: WKWebView
        ) {
            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8),
                  json != lastSentActiveGroupPresetJSON
            else { return }

            let script = """
            window.dispatchEvent(new CustomEvent('overcue:active-group-preset-changed', { detail: \(json) }));
            """
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard error == nil else { return }
                self?.lastSentActiveGroupPresetJSON = json
            }
        }
    }
}
