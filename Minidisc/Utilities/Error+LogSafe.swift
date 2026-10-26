import Foundation
import SwiftSonic

extension Error {
    /// A description that is safe to log publicly. A URL loading error's description includes the
    /// failing URL, which carries the Subsonic `u`, `t` and `s` parameters, so only its domain and
    /// code are kept, as ServerService does for a failed connection test.
    nonisolated var logSafe: String {
        if let sonic = self as? SwiftSonicError, case .network(let urlError) = sonic {
            return "SwiftSonicError.network(\(urlError.logSafe))"
        }
        if let error = self as? MinidiscError {
            switch error {
            case .connectionFailed(let underlying):
                return "connectionFailed(\(underlying.logSafe))"
            case .cacheStorageFailed(let underlying):
                return "cacheStorageFailed(\(underlying.logSafe))"
            case .downloadFailed(let songId, let underlying):
                return "downloadFailed(songId: \(songId), underlying: \(underlying.logSafe))"
            default:
                return String(describing: error)
            }
        }
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain
            || nsError.userInfo[NSURLErrorFailingURLErrorKey] != nil
            // The deprecated NSURLErrorFailingURLStringErrorKey; older code still sets it.
            || nsError.userInfo["NSErrorFailingURLStringKey"] != nil {
            return "domain=\(nsError.domain) code=\(nsError.code)"
        }
        return String(describing: self)
    }
}
