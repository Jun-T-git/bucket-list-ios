import Foundation
import Testing
@testable import Wishes

// Pure-logic tests for the URL→candidate pipeline's honesty guarantees.
// See docs/architecture/capture-pipeline.md and 設計原則 §7/§8.

struct TagValidatorTests {
    // Only keys that exist in the app survive, matched by key or Japanese label.
    @Test func matchesByKeyAndByJapaneseLabel() {
        let tags = Tags.defaults
        #expect(TagValidator.validate(["food"], against: tags) == ["food"])
        #expect(TagValidator.validate(["飲食"], against: tags) == ["food"])
    }

    @Test func dropsUnknownTags() {
        #expect(TagValidator.validate(["不明", "food"], against: Tags.defaults) == ["food"])
        #expect(TagValidator.validate(["nonsense"], against: Tags.defaults) == [])
    }

    @Test func deduplicates() {
        let out = TagValidator.validate(["food", "飲食", "food"], against: Tags.defaults)
        #expect(out == ["food"])
    }

    // Never returns more than the limit (default 3) — keeps tagging light.
    @Test func capsAtLimit() {
        let raw = ["food", "travel", "leisure", "shopping"]
        #expect(TagValidator.validate(raw, against: Tags.defaults).count == 3)
        #expect(TagValidator.validate(raw, against: Tags.defaults, limit: 2).count == 2)
    }

    @Test func ignoresEmptyAndWhitespace() {
        #expect(TagValidator.validate(["", "  ", "food"], against: Tags.defaults) == ["food"])
    }
}

struct ItemCandidateTests {
    private func candidate(confidence: Double, needsConfirm: Bool) -> ItemCandidate {
        ItemCandidate(title: "t", tags: [], seasons: [.any], priority: .maybe,
                      confidence: confidence, needsUserConfirmation: needsConfirm,
                      sourceURL: nil, canonical: nil)
    }

    @Test func shouldConfirmWhenLowConfidence() {
        #expect(candidate(confidence: 0.2, needsConfirm: false).shouldConfirm)
        #expect(!candidate(confidence: 0.9, needsConfirm: false).shouldConfirm)
    }

    @Test func shouldConfirmWhenFlagged() {
        #expect(candidate(confidence: 0.9, needsConfirm: true).shouldConfirm)
    }

    // The fallback placeholder marks the link as unreadable so callers can tell
    // "couldn't read at all" from "read something but unsure".
    @Test func fallbackIsUnreadableAndNeedsConfirm() {
        let f = ItemCandidate.fallback(url: nil)
        #expect(f.readable == false)
        #expect(f.shouldConfirm)
    }

    @Test func titleCapIsThirty() {
        #expect(ItemCandidate.titleMaxLength == 30)
    }
}

struct URLSafetyTests {
    @Test func rejectsLocalAndAmbiguousAddresses() {
        let hosts = ["localhost", "localhost.", "a.localhost", "a.localhost.", "a.local", "a.internal",
                     "127.0.0.1", "127.0.0.1.", "10.2.3.4", "172.16.0.1", "172.31.255.255",
                     "192.168.1.1", "169.254.169.254", "0.0.0.0", "100.64.0.1", "224.0.0.1",
                     "127.1", "2130706433", "0x7f000001", "0177.0.0.1", "127.000.0.1",
                     "999.1.1.1", "[::1]", "[::]", "[fc00::1]", "[fd12::1]", "[fe80::1]",
                     "[fe90::1]", "[fec0::1]", "[ff02::1]", "[::ffff:127.0.0.1]",
                     "[::ffff:192.168.1.1]", "[::ffff:7f00:1]", "[fe80::1%25en0]"]
        for host in hosts {
            #expect(URLSafety.normalized("https://\(host)/") == nil, "Must reject \(host)")
        }
        #expect(URLSafety.normalized("file:///etc/passwd") == nil)
    }

    @Test func permitsPublicAddressesAndOrdinaryFCFDHosts() {
        for host in ["example.com", "fc.example.com", "fd.example.com", "fda.gov", "example.com.",
                     "8.8.8.8", "172.15.1.1", "172.32.1.1", "[2606:4700:4700::1111]",
                     "[::ffff:8.8.8.8]"] {
            #expect(URLSafety.normalized("https://\(host)/") != nil, "Must allow \(host)")
        }
    }
}

// All requests are intercepted; these integration tests never resolve DNS or
// contact a website. Serial execution keeps cancellation observations isolated.
@Suite(.serialized)
struct MetadataFetcherTests {
    private func fetch(_ path: String, timeout: TimeInterval = 1) async -> LinkMetadata {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MetadataURLProtocol.self]
        return await MetadataFetcher.fetch(URL(string: "https://metadata.example\(path)")!,
                                           configuration: config, timeout: timeout)
    }

    private func expectStopped() async {
        let deadline = Date().addingTimeInterval(1)
        while MetadataURLProtocol.stoppedCount == 0, Date() < deadline { await Task.yield() }
        #expect(MetadataURLProtocol.stoppedCount > 0)
    }

    @Test func parsesOGPAndResolvesCanonicalAgainstFinalURL() async {
        let meta = await fetch("/redirect/0")
        #expect(meta.resolvedURL.path == "/page/final")
        #expect(meta.title == "海辺のカフェ")
        #expect(meta.description == "海の見えるお店")
        #expect(meta.siteName == "Cafe")
        #expect(meta.canonical?.absoluteString == "https://metadata.example/page/canonical")
    }

    @Test func rejectsUnsafeCanonicalWithoutLosingTitle() async {
        let meta = await fetch("/unsafe-canonical")
        #expect(meta.title == "Public page")
        #expect(meta.canonical == nil)
    }

    @Test func preservesResolvedMapsPlaceWhenFinalPageIsNotHTML() async {
        let meta = await fetch("/maps-binary-redirect")
        #expect(meta.sourceType == .googleMaps)
        #expect(meta.placeName == "ResolvedCafe")
        #expect(meta.resolvedURL.host == "www.google.com")
        #expect(meta.title == nil)
    }

    @Test func retainsMapsAndYouTubeMetadata() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MetadataURLProtocol.self]
        let maps = await MetadataFetcher.fetch(URL(string: "https://www.google.com/maps/place/Cafe")!, configuration: config)
        #expect(maps.sourceType == .googleMaps)
        #expect(maps.placeName == "Cafe")
        let youtube = await MetadataFetcher.fetch(URL(string: "https://www.youtube.com/watch?v=test")!, configuration: config)
        #expect(youtube.sourceType == .youtube)
        #expect(youtube.title == "海辺のカフェ")
    }

    @Test func blocksUnsafeRedirectsForOrdinaryURLs() async {
        MetadataURLProtocol.reset()
        for path in ["/private-redirect", "/ipv6-redirect", "/scheme-redirect"] {
            let meta = await fetch(path)
            #expect(meta.title == nil)
            #expect(meta.resolvedURL.path == path)
        }
        #expect(MetadataURLProtocol.requestedURLs.allSatisfy(URLSafety.isSafe))
        #expect(MetadataURLProtocol.requestedURLs.count == 3)
    }

    @Test func permitsFiveRedirectsAndRejectsTheSixth() async {
        MetadataURLProtocol.reset()
        let five = await fetch("/hops/5")
        #expect(five.title == "海辺のカフェ")
        #expect(MetadataURLProtocol.requestedURLs.count == 6)
        MetadataURLProtocol.reset()
        let six = await fetch("/hops/6")
        #expect(six.title == nil)
        #expect(MetadataURLProtocol.requestedURLs.count == 6)
    }

    @Test func capsRetainedHTMLWhenRangeIsIgnored() async {
        let meta = await fetch("/oversized")
        #expect(meta.title == "Bounded page")
        #expect(meta.canonical == nil) // The canonical tag lies beyond the cap.
        #expect(MetadataFetcher.maxHTMLBytes == 256 * 1024)
    }

    @Test func stopsAtHeadAndDoesNotWaitForBody() async {
        MetadataURLProtocol.reset()
        let meta = await fetch("/endless-body", timeout: 0.2)
        #expect(meta.title == "Head complete")
        await expectStopped()
    }

    @Test func deadlineStopsAnActiveStreamAndReturnsFallback() async {
        MetadataURLProtocol.reset()
        let start = Date()
        let meta = await fetch("/slow-stream", timeout: 0.12)
        #expect(meta.title == nil)
        #expect(Date().timeIntervalSince(start) < 1)
        await expectStopped()
        #expect(MetadataFetcher.requestTimeout == 6)
    }

    @Test func cancellationStopsTheUnderlyingRequest() async {
        MetadataURLProtocol.reset()
        let task = Task { await fetch("/slow-stream", timeout: 3) }
        let deadline = Date().addingTimeInterval(1)
        while MetadataURLProtocol.requestedURLs.isEmpty, Date() < deadline { await Task.yield() }
        #expect(!MetadataURLProtocol.requestedURLs.isEmpty)
        task.cancel()
        let meta = await task.value
        #expect(meta.title == nil)
        await expectStopped()
    }

    @Test func unsafeInputMakesNoRequestAndFailuresKeepOriginalURL() async {
        MetadataURLProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MetadataURLProtocol.self]
        let unsafe = URL(string: "http://[::1]/")!
        let meta = await MetadataFetcher.fetch(unsafe, configuration: config)
        #expect(meta.resolvedURL == unsafe)
        #expect(meta.title == nil)
        #expect(MetadataURLProtocol.requestedURLs.isEmpty)
        for path in ["/binary", "/error", "/network-error"] {
            let failed = await fetch(path)
            #expect(failed.title == nil)
            #expect(failed.resolvedURL.path == path)
        }
    }
}

private final class MetadataURLProtocol: URLProtocol, @unchecked Sendable {
    private static let stateLock = NSLock()
    private static var urls: [URL] = []
    private static var stops = 0
    static var requestedURLs: [URL] { stateLock.withLock { urls } }
    static var stoppedCount: Int { stateLock.withLock { stops } }
    static func reset() { stateLock.withLock { urls = []; stops = 0 } }
    private let cancellationLock = NSLock()
    private var cancelled = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        Self.stateLock.withLock { Self.urls.append(url) }
        let path = url.path
        var location: String?
        if path == "/redirect/0" { location = "https://metadata.example/page/final" }
        if path == "/maps-binary-redirect" { location = "https://www.google.com/maps/place/ResolvedCafe" }
        if path == "/private-redirect" { location = "http://127.0.0.1/secret" }
        if path == "/ipv6-redirect" { location = "http://[fe80::1]/secret" }
        if path == "/scheme-redirect" { location = "file:///etc/passwd" }
        if path.hasPrefix("/hops/"), let hops = Int(path.split(separator: "/").last!), hops > 0 {
            location = "https://metadata.example/hops/\(hops - 1)"
        }
        if let location {
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": location])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: URL(string: location)!), redirectResponse: response)
            return
        }
        if path == "/network-error" {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: path == "/error" ? 503 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: [
                                        "Content-Type": (path == "/binary" || path.hasSuffix("/ResolvedCafe")) ? "application/octet-stream" : "text/html"
                                       ])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if path == "/slow-stream" {
            sendStream()
            return
        }
        let html: String
        switch path {
        case "/unsafe-canonical": html = "<head><title>Public page</title><link rel='canonical' href='http://[::1]/'></head>"
        case "/oversized": html = "<head><title>Bounded page</title>" + String(repeating: " ", count: MetadataFetcher.maxHTMLBytes) + "<link rel='canonical' href='/too-late'></head>"
        case "/endless-body": html = "<head><title>Head complete</title></head>"
        default: html = "<head><title>Title</title><meta property='og:title' content='海辺のカフェ'><meta property='og:description' content='海の見えるお店'><meta property='og:site_name' content='Cafe'><link rel='canonical' href='canonical'></head>"
        }
        client?.urlProtocol(self, didLoad: Data(html.utf8))
        if path != "/endless-body" { client?.urlProtocolDidFinishLoading(self) }
    }

    private func sendStream() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, !self.cancellationLock.withLock({ self.cancelled }) else { return }
            self.client?.urlProtocol(self, didLoad: Data("<title>Unfinished".utf8))
            self.sendStream()
        }
    }

    override func stopLoading() {
        cancellationLock.withLock { cancelled = true }
        Self.stateLock.withLock { Self.stops += 1 }
    }
}
