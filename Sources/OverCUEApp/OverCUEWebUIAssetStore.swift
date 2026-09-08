import Foundation

struct OverCUEWebUIAssetStore: Sendable {
    private let rootURL: URL?

    init() {
        rootURL = Self.resolveRootURL()
    }

    func response(for requestPath: String) -> OverCUELocalHTTPResponse {
        guard let rootURL else {
            return htmlResponse(
                statusCode: 503,
                reason: "Service Unavailable",
                html: Self.missingBuildHTML
            )
        }

        guard let relativeComponents = safeRelativeComponents(from: requestPath) else {
            return htmlResponse(
                statusCode: 400,
                reason: "Bad Request",
                html: "<h1>Bad Request</h1>"
            )
        }

        let candidate = relativeComponents.reduce(rootURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }.standardizedFileURL

        let rootPath = rootURL.standardizedFileURL.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            return htmlResponse(
                statusCode: 403,
                reason: "Forbidden",
                html: "<h1>Forbidden</h1>"
            )
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) {
            if isDirectory.boolValue {
                let directoryIndex = candidate.appendingPathComponent("index.html")
                if FileManager.default.fileExists(atPath: directoryIndex.path) {
                    return fileResponse(at: directoryIndex)
                }
            } else {
                return fileResponse(at: candidate)
            }
        }

        // Vue Router uses history mode. Requests such as /presets or /devices
        // must resolve to index.html so the client-side router can take over.
        if candidate.pathExtension.isEmpty {
            return fileResponse(at: rootURL.appendingPathComponent("index.html"))
        }

        return htmlResponse(
            statusCode: 404,
            reason: "Not Found",
            html: "<h1>Not Found</h1>"
        )
    }

    private func safeRelativeComponents(from requestPath: String) -> [String]? {
        let decoded = requestPath.removingPercentEncoding ?? requestPath
        let components = decoded
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !components.contains(where: {
            $0 == "." || $0 == ".." || $0.contains("\0")
        }) else { return nil }

        return components
    }

    private func fileResponse(at url: URL) -> OverCUELocalHTTPResponse {
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            return OverCUELocalHTTPResponse(
                statusCode: 200,
                reason: "OK",
                headers: [
                    "Content-Type": Self.contentType(for: url.pathExtension),
                    "Cache-Control": "no-store",
                    "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'none'",
                    "Referrer-Policy": "no-referrer",
                    "X-Content-Type-Options": "nosniff",
                ],
                body: data
            )
        } catch {
            return htmlResponse(
                statusCode: 500,
                reason: "Internal Server Error",
                html: "<h1>Web UI asset could not be read.</h1>"
            )
        }
    }

    private func htmlResponse(
        statusCode: Int,
        reason: String,
        html: String
    ) -> OverCUELocalHTTPResponse {
        OverCUELocalHTTPResponse(
            statusCode: statusCode,
            reason: reason,
            headers: [
                "Content-Type": "text/html; charset=utf-8",
                "Cache-Control": "no-store",
                "X-Content-Type-Options": "nosniff",
            ],
            body: Data(html.utf8)
        )
    }

    private static func resolveRootURL() -> URL? {
        let fileManager = FileManager.default

        if let override = ProcessInfo.processInfo.environment["OVERCUE_WEB_UI_ROOT"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
            if fileManager.fileExists(atPath: url.appendingPathComponent("index.html").path) {
                return url
            }
        }

        if let resourceURL = Bundle.main.resourceURL {
            let packaged = resourceURL.appendingPathComponent("WebUI", isDirectory: true)
            if fileManager.fileExists(atPath: packaged.appendingPathComponent("index.html").path) {
                return packaged
            }
        }

        var candidate = URL(
            fileURLWithPath: fileManager.currentDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        for _ in 0..<8 {
            let development = candidate
                .appendingPathComponent("WebUI", isDirectory: true)
                .appendingPathComponent("dist", isDirectory: true)
            if fileManager.fileExists(atPath: development.appendingPathComponent("index.html").path) {
                return development
            }
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { break }
            candidate = parent
        }

        return nil
    }

    private static func contentType(for rawExtension: String) -> String {
        switch rawExtension.lowercased() {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "json", "map": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "ico": "image/x-icon"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }

    private static let missingBuildHTML = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>OverCUE</title>
        <style>
          body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0a0b0d; color: #f4f4f5; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
          main { max-width: 560px; padding: 32px; border: 1px solid #2a2e38; border-radius: 14px; background: #111318; }
          p { color: #9298a5; line-height: 1.6; }
          code { color: #f4f4f5; }
        </style>
      </head>
      <body>
        <main>
          <h1>OverCUE Web UI is not built.</h1>
          <p>Run <code>cd WebUI &amp;&amp; npm run build</code>, then reopen OverCUE.</p>
        </main>
      </body>
    </html>
    """
}
