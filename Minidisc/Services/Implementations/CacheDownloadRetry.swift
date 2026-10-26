import Foundation

/// A stream-cache download the server answered with a non-success status.
nonisolated struct CacheDownloadStatusError: Error, Sendable {
    let statusCode: Int
}

/// When a failed stream-cache download is worth repeating, and how long to wait first. A car on
/// cellular drops connections often; giving up on the first failure left later songs to stream.
nonisolated enum CacheDownloadRetry {
    /// Connection problems, server errors and a cut-off body are worth retrying. A missing song,
    /// a refused request or an error envelope in place of audio will not change.
    static func isRetryable(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        if let error = error as? URLError {
            switch error.code {
            case .cancelled, .badURL, .unsupportedURL, .userAuthenticationRequired, .fileDoesNotExist:
                return false
            default:
                return true
            }
        }
        if let error = error as? CacheDownloadStatusError {
            return error.statusCode >= 500 || error.statusCode == 408 || error.statusCode == 429
        }
        if let rejection = error as? AudioResponseRejection {
            return rejection.check == "content-length"
        }
        return false
    }

    /// Exponential backoff: `base`, then twice as long each time, up to `cap`.
    static func delay(afterAttempt attempt: Int, base: Duration = .seconds(2), cap: Duration = .seconds(30)) -> Duration {
        let factor = 1 << min(max(attempt - 1, 0), 10)
        return min(base * factor, cap)
    }
}
