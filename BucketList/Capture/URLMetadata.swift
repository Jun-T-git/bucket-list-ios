import Foundation
import Darwin

// MARK: - Source type

// Where a shared/pasted URL came from. Drives copy and the rule-based fallback's
// category/tag choice (e.g. a YouTube link → a leisure/video subject).
enum SourceType: String, Sendable {
    case googleMaps, instagram, tiktok, x, youtube, web, unknown

    static func detect(from url: URL?) -> SourceType {
        guard let url, let host = url.host?.lowercased() else { return .unknown }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let isGoogleHost = h == "google.com" || h.hasSuffix(".google.com")
        // A Knowledge-Graph id (kgmid) marks a shared place/entity: Google's
        // newer "share.google" place links resolve to a /search URL carrying it
        // (the place name sits in the q= param, which GoogleMapsURL reads).
        let hasKGMID = (URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "kgmid" }) ?? false
        switch true {
        case h == "maps.google.com",
             isGoogleHost && url.path.contains("/maps"),
             isGoogleHost && hasKGMID,
             h == "goo.gl" && url.path.hasPrefix("/maps"),
             h == "maps.app.goo.gl",
             h == "share.google":
            return .googleMaps
        case h == "instagram.com", h.hasSuffix(".instagram.com"):
            return .instagram
        case h == "tiktok.com", h.hasSuffix(".tiktok.com"), h == "vm.tiktok.com":
            return .tiktok
        case h == "x.com", h == "twitter.com", h.hasSuffix(".twitter.com"):
            return .x
        case h == "youtube.com", h.hasSuffix(".youtube.com"), h == "youtu.be":
            return .youtube
        default:
            return .web
        }
    }
}

// MARK: - URL safety (best-effort SSRF guard)

// Keeps fetching to public http(s) endpoints. This is a best-effort check on
// the literal host — it intentionally does not do DNS resolution (rebinding is
// out of scope for an on-device convenience fetcher), but it blocks the obvious
// localhost / private-IP / link-local cases the spec calls out.
enum URLSafety {
    static func normalized(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Allow a bare "example.com/…" paste by assuming https.
        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: candidate) else { return nil }
        return isSafe(url) ? url : nil
    }

    // "Looks like a real web link" — stricter than `normalized`, used to decide
    // whether to bother fetching. Requires a dotted host so stray words like
    // "hello" (which normalize to https://hello) and free-text notes don't
    // trigger a doomed read or get saved as a broken link. Not a safety check —
    // `isSafe` still gates the actual fetch.
    static func looksLikeWebURL(_ raw: String) -> Bool {
        guard let url = normalized(raw), let host = url.host else { return false }
        return host.contains(".")
    }

    static func isSafe(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard var host = url.host?.lowercased(), !host.isEmpty else { return false }
        // Foundation returns bracketed IPv6 hosts. DNS's final root dot must not
        // hide a local hostname or change the interpretation of an IP literal.
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.contains("%") else { return false }
        if ["localhost", "local", "internal"].contains(where: {
            host == $0 || host.hasSuffix("." + $0)
        }) { return false }

        if host.contains(":") {
            var address = in6_addr()
            guard inet_pton(AF_INET6, host, &address) == 1 else { return false }
            let bytes = withUnsafeBytes(of: address) { Array($0) }
            // IPv4-mapped addresses must pass the same IPv4 policy.
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
                return isPublicIPv4(Array(bytes.suffix(4)))
            }
            // Only global-unicast literals; excludes loopback, unspecified,
            // unique/site/link-local, multicast, and IPv4-compatible addresses.
            return bytes[0] & 0xe0 == 0x20
        }
        var address = in_addr()
        if inet_aton(host, &address) == 1 {
            let parts = host.split(separator: ".", omittingEmptySubsequences: false)
            let octets = parts.compactMap { UInt8($0) }
            // Reject shorthand, integer, hexadecimal and octal spellings rather
            // than letting URLSession interpret them differently from our guard.
            guard parts.count == 4, octets.count == 4,
                  zip(parts, octets).allSatisfy({ String($0.0) == String($0.1) }) else { return false }
            return isPublicIPv4(octets)
        }
        // Invalid numeric-looking hosts must not fall through as DNS names.
        if host.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        return true
    }

    private static func isPublicIPv4(_ octets: [UInt8]) -> Bool {
        switch (octets[0], octets[1]) {
        case (0, _), (10, _), (127, _), (169, 254), (192, 168): return false
        case (172, let b) where (16...31).contains(b): return false
        case (100, let b) where (64...127).contains(b): return false
        case (let a, _) where a >= 224: return false
        default: return true
        }
    }
}

// MARK: - Fetched metadata

// On-device-collected facts about a URL. Only these values (never page bodies)
// are handed to the on-device model.
struct LinkMetadata: Sendable {
    var resolvedURL: URL
    var sourceType: SourceType
    var title: String?
    var description: String?
    var siteName: String?     // og:site_name — often the real business/brand name
    var placeName: String?    // extracted from a Google Maps URL path/query
    var canonical: URL?

    var bestURL: URL { canonical ?? resolvedURL }
}

// Titles that carry no real meaning ("Home", "Google Maps", a bare site name).
// Used to reject junk before it becomes a "ホーム"-style meaningless title.
enum GenericTitle {
    private static let blocked: Set<String> = [
        "google", "google maps", "google マップ", "グーグルマップ", "google search",
        "google検索", "マップ", "maps", "home", "ホーム", "top", "トップ", "トップページ",
        "menu", "メニュー", "index", "トップ ページ", "page", "ページ", "loading", "読み込み中",
        "untitled", "no title", "ログイン", "login", "sign in",
    ]
    static func isGeneric(_ name: String?) -> Bool {
        guard let n = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !n.isEmpty else {
            return true
        }
        return n.count < 2 || blocked.contains(n)
    }
}

// Pulls a place name out of a Google Maps URL — far more reliable than the page
// title, which LinkPresentation often reports as "Google Maps"/"Google Search".
enum GoogleMapsURL {
    static func placeName(from url: URL) -> String? {
        let segments = url.path.split(separator: "/").map(String.init)
        if let i = segments.firstIndex(of: "place"), i + 1 < segments.count {
            let raw = segments[i + 1]
            if !raw.hasPrefix("@"), !raw.hasPrefix("data=") { return decode(raw) }
        }
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for key in ["q", "query", "destination"] {
                if let v = items.first(where: { $0.name == key })?.value,
                   !v.isEmpty, !v.contains(",") || !v.allSatisfy({ "0123456789.,- ".contains($0) }) {
                    return decode(v)
                }
            }
        }
        return nil
    }
    private static func decode(_ s: String) -> String {
        (s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? s)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Metadata fetcher

// One bounded HTML request owns redirects, timeout and cancellation. There is
// no second metadata provider with an independent, opaque network policy.
enum MetadataFetcher {
    static let requestTimeout: TimeInterval = 6
    static let maxRedirects = 5
    static let maxHTMLBytes = 256 * 1024

    static func fetch(_ url: URL, configuration: URLSessionConfiguration = .ephemeral,
                      timeout: TimeInterval = requestTimeout) async -> LinkMetadata {
        var meta = LinkMetadata(resolvedURL: url, sourceType: SourceType.detect(from: url))
        if meta.sourceType == .googleMaps { meta.placeName = GoogleMapsURL.placeName(from: url) }
        guard URLSafety.isSafe(url), !Task.isCancelled else { return meta }
        let reader = BoundedHTMLRequest(configuration: configuration, timeout: timeout)
        guard let result = await reader.fetch(url) else { return meta }
        meta.resolvedURL = result.url
        meta.sourceType = SourceType.detect(from: result.url)
        meta.placeName = meta.sourceType == .googleMaps ? GoogleMapsURL.placeName(from: result.url) : nil
        guard let data = result.data else { return meta }
        let head = parseHead(String(decoding: data, as: UTF8.self), baseURL: result.url)
        if !GenericTitle.isGeneric(head.title) { meta.title = head.title }
        meta.siteName = head.siteName
        meta.description = head.description
        meta.canonical = head.canonical
        return meta
    }

    private struct HTMLHead { var title: String?; var description: String?; var siteName: String?; var canonical: URL? }

    private static func parseHead(_ html: String, baseURL: URL) -> HTMLHead {
        var head = HTMLHead()
        head.title = firstMatch(html, #"<title[^>]*>([\s\S]*?)</title>"#)
            .map { decodeEntities($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let og = metaContent(html, property: "og:title") { head.title = og }
        head.siteName = metaContent(html, property: "og:site_name")
        head.description = metaContent(html, property: "og:description")
            ?? metaContent(html, name: "description")
        if let canon = firstMatch(html, #"<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']+)["']"#)
            ?? firstMatch(html, #"<link[^>]+href=["']([^"']+)["'][^>]+rel=["']canonical["']"#) {
            if let url = URL(string: decodeEntities(canon), relativeTo: baseURL)?.absoluteURL,
               URLSafety.isSafe(url) { head.canonical = url }
        }
        return head
    }

    private static func metaContent(_ html: String, property: String) -> String? {
        firstMatch(html, "<meta[^>]+property=[\"']\(property)[\"'][^>]+content=[\"']([^\"']*)[\"']")
            ?? firstMatch(html, "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+property=[\"']\(property)[\"']")
    }
    private static func metaContent(_ html: String, name: String) -> String? {
        firstMatch(html, "<meta[^>]+name=[\"']\(name)[\"'][^>]+content=[\"']([^\"']*)[\"']")
            ?? firstMatch(html, "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+name=[\"']\(name)[\"']")
    }

    private static func firstMatch(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        let v = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

// Delegate callbacks use a serial URLSession queue. The lock also coordinates
// cancellation/deadline callbacks so every continuation completes exactly once.
private final class BoundedHTMLRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Result { let url: URL; let data: Data? }
    private let lock = NSLock()
    private let configuration: URLSessionConfiguration
    private let timeout: TimeInterval
    private var continuation: CheckedContinuation<Result?, Never>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var deadline: DispatchWorkItem?
    private var finished = false
    private var redirects = 0
    private var responseURL: URL?
    private var data = Data()

    init(configuration: URLSessionConfiguration, timeout: TimeInterval) {
        self.configuration = configuration.copy() as! URLSessionConfiguration
        self.timeout = timeout
    }

    func fetch(_ url: URL) async -> Result? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    continuation.resume(returning: nil)
                    return
                }
                self.continuation = continuation
                configuration.timeoutIntervalForRequest = timeout
                configuration.timeoutIntervalForResource = timeout
                configuration.httpCookieStorage = nil
                configuration.urlCredentialStorage = nil
                configuration.urlCache = nil
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                self.session = session
                var request = URLRequest(url: url, timeoutInterval: timeout)
                request.setValue("text/html", forHTTPHeaderField: "Accept")
                request.setValue("bytes=0-\(MetadataFetcher.maxHTMLBytes - 1)", forHTTPHeaderField: "Range")
                request.setValue("Mozilla/5.0 AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
                let task = session.dataTask(with: request)
                self.task = task
                let deadline = DispatchWorkItem { [weak self] in self?.finish(nil) }
                self.deadline = deadline
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
                task.resume()
                lock.unlock()
            }
        } onCancel: {
            self.finish(nil)
        }
    }

    private func finish(_ result: Result?) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let result = result ?? responseURL.map { Result(url: $0, data: nil) }
        let continuation = self.continuation
        let session = self.session
        self.continuation = nil
        self.session = nil
        task = nil
        deadline?.cancel()
        deadline = nil
        lock.unlock()
        session?.invalidateAndCancel()
        continuation?.resume(returning: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse,
              let url = http.url, URLSafety.isSafe(url) else {
            completionHandler(.cancel)
            finish(nil)
            return
        }
        lock.withLock { responseURL = url }
        guard (200...299).contains(http.statusCode),
              http.mimeType == nil || http.mimeType?.lowercased() == "text/html"
                  || http.mimeType?.lowercased() == "application/xhtml+xml" else {
            completionHandler(.cancel)
            finish(Result(url: url, data: nil))
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        // Retain at most the cap even when the server ignores Range or has no
        // Content-Length. Cancel immediately at the cap or end of the head.
        data.append(chunk.prefix(MetadataFetcher.maxHTMLBytes - data.count))
        if data.count == MetadataFetcher.maxHTMLBytes ||
            String(decoding: data, as: UTF8.self).range(of: "</head>", options: .caseInsensitive) != nil {
            finish(responseURL.map { Result(url: $0, data: data) })
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error == nil ? responseURL.map { Result(url: $0, data: data) } : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        guard redirects <= MetadataFetcher.maxRedirects, let url = request.url, URLSafety.isSafe(url) else {
            completionHandler(nil)
            finish(nil)
            return
        }
        completionHandler(request)
    }
}
