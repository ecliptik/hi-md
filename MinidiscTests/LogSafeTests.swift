import Foundation
import SwiftSonic
import Testing
@testable import Minidisc

@Suite("Error.logSafe")
struct LogSafeTests {
    private let failingURL = URL(string: "https://music.example/rest/stream?u=alice&t=secret-token&s=secret-salt&id=1")!

    private var urlError: URLError {
        URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: failingURL])
    }

    @Test func urlErrorKeepsOnlyItsDomainAndCode() {
        #expect(String(describing: urlError).contains("secret"))
        #expect(urlError.logSafe == "domain=\(NSURLErrorDomain) code=\(URLError.Code.timedOut.rawValue)")
    }

    @Test func wrappedURLErrorsAreRedactedToo() {
        let errors: [any Error] = [
            MinidiscError.downloadFailed(songId: "s1", underlying: urlError),
            MinidiscError.connectionFailed(underlying: urlError),
            SwiftSonicError.network(urlError),
            NSError(domain: "Other", code: 7, userInfo: ["NSErrorFailingURLStringKey": failingURL.absoluteString]),
            NSError(domain: "Other", code: 8, userInfo: [NSURLErrorFailingURLErrorKey: failingURL]),
        ]
        for error in errors {
            #expect(!error.logSafe.contains("secret"), "\(error.logSafe)")
            #expect(!error.logSafe.contains("music.example"))
        }
    }

    @Test func otherErrorsKeepTheirDescription() {
        #expect(MinidiscError.mediaNotFound(songId: "s1").logSafe == String(describing: MinidiscError.mediaNotFound(songId: "s1")))
        #expect(CocoaError(.fileWriteNoPermission).logSafe == String(describing: CocoaError(.fileWriteNoPermission)))
    }
}
