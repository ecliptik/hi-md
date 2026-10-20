import Foundation

/// Drops request headers that the caller added when a redirect leaves the original origin.
///
/// URLSession removes `Authorization` on a cross-origin redirect but keeps every other header, so
/// reverse-proxy credentials such as Cloudflare Access tokens would reach whichever host the
/// server redirects to. Pass an instance as the per-task delegate of the requests that carry them.
nonisolated final class OriginScopedRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    /// Headers describing the representation wanted, not credentials. These survive a redirect.
    private static let harmless: Set<String> = [
        "accept", "accept-encoding", "accept-language", "user-agent", "range",
        "if-range", "if-none-match", "if-modified-since", "content-type"
    ]

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(Self.redirectedRequest(request, original: task.originalRequest))
    }

    static func redirectedRequest(_ request: URLRequest, original: URLRequest?) -> URLRequest {
        guard let from = original?.url, let to = request.url,
              !ServerConnection.isSameOrigin(from, to) else { return request }
        var scoped = request
        for name in original?.allHTTPHeaderFields?.keys ?? [:].keys where !harmless.contains(name.lowercased()) {
            scoped.setValue(nil, forHTTPHeaderField: name)
        }
        return scoped
    }
}
