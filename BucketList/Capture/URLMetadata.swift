import Foundation
import LinkPresentation

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
        guard let host = url.host?.lowercased() else { return false }
        if host == "localhost" || host.hasSuffix(".local") || host.hasSuffix(".internal") {
            return false
        }
        if isPrivateIP(host) { return false }
        return true
    }

    private static func isPrivateIP(_ host: String) -> Bool {
        // IPv6 loopback / unique-local.
        if host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") { return true }
        // IPv4 literal in a private / loopback / link-local range. Parse exactly
        // four octets, each 0...255 — a non-numeric part is dropped by compactMap
        // (→ count != 4), an out-of-range one fails allSatisfy; both → not-private
        // path returns false, same as before.
        let parts = host.split(separator: ".")
        let octets = parts.compactMap { Int($0) }
        guard parts.count == 4, octets.count == 4,
              octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, let b) where (16...31).contains(b): return true
        default: return false
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

// LinkPresentation first (standard, gives a clean title + preview image); a
// size-capped HTML/OGP read only fills the gaps. Every failure is a normal
// outcome — callers always get a LinkMetadata they can fall back from.
enum MetadataFetcher {
    static let requestTimeout: TimeInterval = 6
    static let maxRedirects = 5
    static let maxHTMLBytes = 256 * 1024

    static func fetch(_ url: URL) async -> LinkMetadata {
        // Only shorteners need a redirect round-trip; skip it for normal URLs so
        // we don't pay an extra request. LinkPresentation follows redirects itself.
        let host = url.host?.lowercased() ?? ""
        let resolved = isShortener(host) ? await resolveRedirects(url) : url
        let sourceType = SourceType.detect(from: resolved)
        var meta = LinkMetadata(resolvedURL: resolved, sourceType: sourceType)
        // For maps, the place name in the URL beats any page title.
        if sourceType == .googleMaps { meta.placeName = GoogleMapsURL.placeName(from: resolved) }

        // 1) LinkPresentation — a clean title.
        if let title = await fetchLinkPresentation(resolved) {
            meta.title = title
        }

        // 2) HTML only when it can add something LP/maps didn't. Maps already has
        //    the place name; YouTube's LP title is the video — skip HTML for both.
        let titleWeak = GenericTitle.isGeneric(meta.title)
        let skipHTML = sourceType == .googleMaps || sourceType == .youtube
        if !skipHTML, titleWeak || meta.description == nil {
            if let html = await fetchHTMLHead(resolved) {
                if titleWeak, let t = html.title, !GenericTitle.isGeneric(t) { meta.title = t }
                meta.siteName = html.siteName
                meta.description = meta.description ?? html.description
                meta.canonical = html.canonical
            }
        }
        return meta
    }

    private static let shortenerHosts: Set<String> = [
        "goo.gl", "maps.app.goo.gl", "vm.tiktok.com", "youtu.be", "t.co",
        "bit.ly", "tinyurl.com", "amzn.to", "g.co", "lnkd.in", "buff.ly",
        // Google's universal share wrapper (Maps "share place", search results,
        // etc.) — must be expanded to reach the real destination.
        "share.google",
    ]
    private static func isShortener(_ host: String) -> Bool {
        shortenerHosts.contains(host) || shortenerHosts.contains { host.hasSuffix("." + $0) }
    }

    // MARK: redirects

    private static func resolveRedirects(_ url: URL) async -> URL {
        guard URLSafety.isSafe(url) else { return url }
        var req = URLRequest(url: url, timeoutInterval: requestTimeout)
        req.httpMethod = "GET"   // GET follows shortener redirects more reliably than HEAD
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let guardDelegate = RedirectGuard(maxRedirects: maxRedirects)
        do {
            let (bytes, response) = try await URLSession.shared.bytes(for: req, delegate: guardDelegate)
            // We only need the resolved URL — stop immediately, don't drain the body.
            for try await _ in bytes { break }
            return response.url ?? url
        } catch {
            return url
        }
    }

    // A desktop-ish UA stops some sites (incl. Google) from serving an empty or
    // consent interstitial that yields a useless title.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    // MARK: LinkPresentation

    private static func fetchLinkPresentation(_ url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = requestTimeout
        guard let metadata = try? await provider.startFetchingMetadata(for: url) else { return nil }
        return metadata.title
    }

    // MARK: HTML / OGP (capped)

    private struct HTMLHead { var title: String?; var description: String?; var siteName: String?; var canonical: URL? }

    private static func fetchHTMLHead(_ url: URL) async -> HTMLHead? {
        guard URLSafety.isSafe(url) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: requestTimeout)
        req.setValue("text/html", forHTTPHeaderField: "Accept")
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Ask for just the head of the document; servers that honour Range save us
        // the full download. We cap again locally for servers that ignore it.
        req.setValue("bytes=0-\(maxHTMLBytes - 1)", forHTTPHeaderField: "Range")
        let guardDelegate = RedirectGuard(maxRedirects: maxRedirects)
        do {
            // Bulk download (fast) rather than byte-by-byte; parse only the first
            // chunk where <head> lives.
            let (data, response) = try await URLSession.shared.data(for: req, delegate: guardDelegate)
            if let mime = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               !mime.contains("html") { return nil }
            let html = String(decoding: data.prefix(maxHTMLBytes), as: UTF8.self)
            return parseHead(html, baseURL: url)
        } catch {
            return nil
        }
    }

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
            head.canonical = URL(string: canon, relativeTo: baseURL)?.absoluteURL
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

// Per-request redirect policy: cap the hops and re-validate every Location so a
// shortener can't bounce us onto a private address.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    let maxRedirects: Int
    private var count = 0
    init(maxRedirects: Int) { self.maxRedirects = maxRedirects }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        count += 1
        guard count <= maxRedirects, let url = request.url, URLSafety.isSafe(url) else { return nil }
        return request
    }
}
