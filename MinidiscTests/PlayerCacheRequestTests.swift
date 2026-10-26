import Foundation
import Testing
@testable import Minidisc

@Suite("Player cache requests")
struct PlayerCacheRequestTests {
    @Test func completeTranscodeDownloadDoesNotInheritEstimatedLength() throws {
        let url = try #require(URL(string: "https://music.example/rest/stream?id=a&format=mp3&maxBitRate=192&estimateContentLength=true&t=token%2Bvalue"))
        let request = PlayerService.cacheDownloadRequest(
            url: url, headers: ["Authorization": "Bearer fixture"], serviceType: .avStreaming
        )
        let requestURL = try #require(request.url)
        let components = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false))
        let query = components.queryItems ?? []
        #expect(query.filter { $0.name == "estimateContentLength" }.map(\.value) == ["false"])
        #expect(query.contains(URLQueryItem(name: "format", value: "mp3")))
        #expect(query.contains(URLQueryItem(name: "maxBitRate", value: "192")))
        #expect(query.contains(URLQueryItem(name: "t", value: "token+value")))
        #expect(components.percentEncodedQuery?.contains("t=token%2Bvalue") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture")
        #expect(request.networkServiceType == .avStreaming)
    }

    @Test func cacheDownloadsUseCellularButNeverLowDataMode() throws {
        let url = try #require(URL(string: "https://music.example/rest/stream?id=a"))
        let request = PlayerService.cacheDownloadRequest(url: url, headers: [:])
        #expect(request.allowsCellularAccess)
        #expect(request.allowsExpensiveNetworkAccess)
        #expect(!request.allowsConstrainedNetworkAccess)
        #expect(request.networkServiceType == .default)
    }

    @Test func onlyFailuresThatCanChangeAreRetried() {
        #expect(CacheDownloadRetry.isRetryable(URLError(.networkConnectionLost)))
        #expect(CacheDownloadRetry.isRetryable(URLError(.timedOut)))
        #expect(CacheDownloadRetry.isRetryable(CacheDownloadStatusError(statusCode: 503)))
        #expect(CacheDownloadRetry.isRetryable(AudioResponseRejection(check: "content-length", detail: "cut off")))
        #expect(!CacheDownloadRetry.isRetryable(URLError(.cancelled)))
        #expect(!CacheDownloadRetry.isRetryable(CancellationError()))
        #expect(!CacheDownloadRetry.isRetryable(CacheDownloadStatusError(statusCode: 404)))
        #expect(!CacheDownloadRetry.isRetryable(AudioResponseRejection(check: "body-sniff", detail: "envelope")))
    }

    @Test func backoffDoublesUpToItsCap() {
        #expect(CacheDownloadRetry.delay(afterAttempt: 1) == .seconds(2))
        #expect(CacheDownloadRetry.delay(afterAttempt: 2) == .seconds(4))
        #expect(CacheDownloadRetry.delay(afterAttempt: 3) == .seconds(8))
        #expect(CacheDownloadRetry.delay(afterAttempt: 9) == .seconds(30))
    }
}
