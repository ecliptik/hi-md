import Foundation
import Testing
import UIKit
@testable import Minidisc

nonisolated private let networkSafetyPNG = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVQI12NgAAAAAgAB4iG8MwAAAABJRU5ErkJggg=="
)!

@Suite("Credential handling in network requests")
@MainActor
struct NetworkSafetyTests {
    private func request(_ url: String, headers: [String: String]) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    // MARK: Redirects

    @Test("A cross-origin redirect drops custom headers but keeps representation headers")
    func crossOriginRedirectDropsCustomHeaders() {
        let original = request("https://music.example.com/rest/stream", headers: [
            "CF-Access-Client-Id": "id", "CF-Access-Client-Secret": "secret", "Accept": "audio/*"
        ])
        let redirected = request("https://cdn.other.net/file", headers: [
            "CF-Access-Client-Id": "id", "CF-Access-Client-Secret": "secret", "Accept": "audio/*"
        ])

        let result = OriginScopedRedirectDelegate.redirectedRequest(redirected, original: original)

        #expect(result.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
        #expect(result.value(forHTTPHeaderField: "CF-Access-Client-Secret") == nil)
        #expect(result.value(forHTTPHeaderField: "Accept") == "audio/*")
    }

    @Test("A same-origin redirect keeps every header")
    func sameOriginRedirectKeepsHeaders() {
        let original = request("https://music.example.com/a", headers: ["CF-Access-Client-Id": "id"])
        let redirected = request("https://music.example.com/b", headers: ["CF-Access-Client-Id": "id"])

        let result = OriginScopedRedirectDelegate.redirectedRequest(redirected, original: original)

        #expect(result.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id")
    }

    @Test("A scheme or port change counts as a different origin")
    func schemeChangeIsCrossOrigin() {
        let original = request("https://music.example.com/a", headers: ["X-Proxy-Key": "k"])
        let downgraded = request("http://music.example.com/a", headers: ["X-Proxy-Key": "k"])

        #expect(OriginScopedRedirectDelegate.redirectedRequest(downgraded, original: original)
            .value(forHTTPHeaderField: "X-Proxy-Key") == nil)
    }

    // MARK: Artwork

    @Test("Cover art requests carry the server's reverse-proxy headers")
    func artworkRequestsCarryHeaders() async {
        let recorded = RecordedRequests()
        let cache = ArtworkImageCache(
            coverArtURLProvider: { _, _ in URL(string: "https://music.example.com/rest/getCoverArt?id=1") },
            requestHeadersProvider: { _ in ["CF-Access-Client-Id": "abc"] },
            dataLoader: { request in
                await recorded.add(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (networkSafetyPNG, response)
            },
            imageDecoder: { data, _ in PlatformImage(data: data) }
        )
        cache.persistCoversEnabled = false

        #expect(await cache.load(coverArtId: "cover-1") != nil)

        let requests = await recorded.all()
        #expect(requests.first?.value(forHTTPHeaderField: "CF-Access-Client-Id") == "abc")
    }

    @Test("Logged artwork addresses never include the query string")
    func redactedArtworkURLHasNoCredentials() {
        let url = URL(string: "https://music.example.com/rest/getCoverArt?id=1&t=secrettoken&s=salt")!
        let text = ArtworkLoader.redacted(url)
        #expect(text.contains("music.example.com"))
        #expect(!text.contains("secrettoken"))
        #expect(!text.contains("salt"))
    }

    // MARK: Integration endpoints

    @Test("Only http and https addresses with a host are accepted")
    func integrationEndpointSchemes() {
        #expect(IntegrationEndpoint.validatedURL("https://api.listenbrainz.org") != nil)
        #expect(IntegrationEndpoint.validatedURL(" http://nas.local:8686 ") != nil)
        #expect(IntegrationEndpoint.validatedURL("ftp://example.com") == nil)
        #expect(IntegrationEndpoint.validatedURL("file:///etc/passwd") == nil)
        #expect(IntegrationEndpoint.validatedURL("nas.local:8686") == nil)
        #expect(IntegrationEndpoint.validatedURL("https://") == nil)
    }

    @Test("Cleartext addresses are flagged for a warning")
    func cleartextDetection() {
        #expect(IntegrationEndpoint.isCleartext("http://nas.local:8686"))
        #expect(IntegrationEndpoint.isCleartext("  HTTP://nas.local"))
        #expect(!IntegrationEndpoint.isCleartext("https://nas.local"))
        #expect(!IntegrationEndpoint.isCleartext(""))
    }

    @Test("Lidarr and AudioMuse refuse non-http addresses")
    func clientsRejectOtherSchemes() {
        #expect(LidarrClient(urlString: "ftp://nas.local", apiKey: "k") == nil)
        #expect(AudioMuseClient(urlString: "file:///tmp", token: nil) == nil)
        #expect(LidarrClient(urlString: "http://nas.local:8686", apiKey: "k") != nil)
    }
}

private actor RecordedRequests {
    private var requests: [URLRequest] = []
    func add(_ request: URLRequest) { requests.append(request) }
    func all() -> [URLRequest] { requests }
}
