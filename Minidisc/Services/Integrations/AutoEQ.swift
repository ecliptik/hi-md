import Foundation

// MARK: - Index

/// One measured headphone in AutoEQ's results index.
nonisolated struct AutoEQEntry: Identifiable, Hashable, Sendable {
    let name: String
    /// Who measured it, and on which rig when the index says: "crinacle on GRAS 43AG-7".
    let source: String
    /// Path components under `results/`, decoded: ["oratory1990", "over-ear", "Sennheiser HD 600"].
    let pathComponents: [String]

    var id: String { pathComponents.joined(separator: "/") }
    /// Profile files are named after the result's folder.
    var fileStem: String { pathComponents.last ?? name }
}

/// AutoEQ's `results/INDEX.md`, one Markdown list item per result:
/// `- [Name](./source/rig/Name) by source on rig`. Names may contain brackets and parentheses,
/// and links keep their parentheses unescaped, so the link ends at the last ") by ".
nonisolated enum AutoEQIndex {
    static func parse(_ text: String) -> [AutoEQEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { parseLine(String($0)) }
    }

    static func parseLine(_ line: String) -> AutoEQEntry? {
        guard line.hasPrefix("- ["), let linkStart = line.range(of: "](./") else { return nil }
        let name = String(line[line.index(line.startIndex, offsetBy: 3)..<linkStart.lowerBound])
        let afterLink = line[linkStart.upperBound...]
        let linkEnd = afterLink.range(of: ") by ", options: .backwards)
        let rawPath = linkEnd.map { afterLink[..<$0.lowerBound] } ?? afterLink.dropLast(afterLink.hasSuffix(")") ? 1 : 0)
        let source = linkEnd.map { String(afterLink[$0.upperBound...]).trimmingCharacters(in: .whitespaces) } ?? ""
        let components = rawPath.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        // The index is downloaded, so its paths are untrusted: no traversal, no empty parts.
        guard !name.isEmpty, components.count >= 2,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") })
        else { return nil }
        return AutoEQEntry(name: name, source: source, pathComponents: components)
    }

    /// Entries whose name contains every word of `query`, ignoring case and accents. Names that
    /// start with the query come first, then shorter names.
    static func search(_ entries: [AutoEQEntry], query: String, limit: Int = 60) -> [AutoEQEntry] {
        let words = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let foldedQuery = words.joined(separator: " ")
        let matches = entries.lazy.compactMap { entry -> (AutoEQEntry, Bool)? in
            let name = fold(entry.name)
            guard words.allSatisfy(name.contains) else { return nil }
            return (entry, name.hasPrefix(foldedQuery))
        }
        return matches
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 }
                if lhs.0.name.count != rhs.0.name.count { return lhs.0.name.count < rhs.0.name.count }
                return lhs.0.name.localizedStandardCompare(rhs.0.name) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

// MARK: - Profiles

/// An AutoEQ correction, as one of its text formats describes it.
nonisolated struct AutoEQProfile: Equatable, Sendable {
    enum FilterType: String, Sendable {
        case peaking = "PK"
        case lowShelf = "LSC"
        case highShelf = "HSC"
    }

    struct Filter: Equatable, Sendable {
        let type: FilterType
        let frequency: Float
        let gain: Float
        let q: Float
    }

    /// ParametricEQ.txt and FixedBandEQ.txt: a preamp and biquad filters.
    /// GraphicEQ.txt: gains at fixed frequencies, with its headroom already applied.
    enum Curve: Equatable, Sendable {
        case parametric(preamp: Float, filters: [Filter])
        case graphic(points: [(frequency: Float, gain: Float)])

        static func == (lhs: Curve, rhs: Curve) -> Bool {
            switch (lhs, rhs) {
            case let (.parametric(a, f), .parametric(b, g)): a == b && f == g
            case let (.graphic(p), .graphic(q)): p.count == q.count && zip(p, q).allSatisfy { $0 == $1 }
            default: false
            }
        }
    }

    let curve: Curve

    enum ParseError: Error, Equatable {
        case unrecognized
    }

    static func parse(_ text: String) throws -> AutoEQProfile {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("GraphicEQ:") {
            let points = trimmed.dropFirst("GraphicEQ:".count).split(separator: ";").compactMap { pair -> (Float, Float)? in
                let values = pair.split(whereSeparator: \.isWhitespace).compactMap { Float($0) }
                guard values.count == 2, values[0] > 0, values.allSatisfy(\.isFinite) else { return nil }
                return (values[0], values[1])
            }
            guard points.count >= 2 else { throw ParseError.unrecognized }
            return AutoEQProfile(curve: .graphic(points: points.sorted { $0.0 < $1.0 }.map { (frequency: $0.0, gain: $0.1) }))
        }
        var preamp: Float = 0
        var filters: [Filter] = []
        for line in trimmed.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            if words.first == "Preamp:", words.count >= 2, let value = Float(words[1]), value.isFinite {
                preamp = value
            } else if words.first == "Filter", let filter = parseFilter(words) {
                filters.append(filter)
            }
        }
        guard !filters.isEmpty else { throw ParseError.unrecognized }
        return AutoEQProfile(curve: .parametric(preamp: preamp, filters: filters))
    }

    /// `Filter 1: ON PK Fc 105 Hz Gain 6.5 dB Q 0.70`; filters that are OFF are skipped.
    private static func parseFilter(_ words: [String]) -> Filter? {
        guard words.count >= 4, words[2] == "ON", let type = FilterType(rawValue: words[3]) else { return nil }
        func value(after label: String) -> Float? {
            guard let index = words.firstIndex(of: label), index + 1 < words.count else { return nil }
            return Float(words[index + 1]).flatMap { $0.isFinite ? $0 : nil }
        }
        guard let frequency = value(after: "Fc"), frequency > 0, let gain = value(after: "Gain") else { return nil }
        let q = value(after: "Q") ?? 0.71
        guard q > 0 else { return nil }
        return Filter(type: type, frequency: frequency, gain: gain, q: q)
    }

    // MARK: Mapping onto the ten bands

    /// Ten band gains and a preamp for Minidisc's equalizer.
    ///
    /// AutoEQ's FixedBandEQ is fitted to these very bands, so its gains are used as they are.
    /// Anything else is sampled: the profile's combined response at each band centre becomes that
    /// band's gain. Ten one-octave bands can't follow a narrow parametric notch, so this keeps the
    /// broad tonal balance, which is what matters most. The preamp is the profile's own, or lower
    /// if the mapped bands boost more than it allows for.
    func bandGains(sampleRate: Float = 48000) -> (gains: [Float], preamp: Float) {
        let gains: [Float]
        let profilePreamp: Float
        switch curve {
        case .parametric(let preamp, let filters):
            profilePreamp = preamp
            if let fixed = Self.fixedBandGains(filters) {
                gains = fixed
            } else {
                gains = Equalizer.frequencies.map { frequency in
                    filters.reduce(0) { $0 + Self.response(of: $1, at: frequency, sampleRate: sampleRate) }
                }
            }
        case .graphic(let points):
            profilePreamp = 0
            gains = Equalizer.frequencies.map { Self.interpolate(points, at: $0) }
        }
        let clamped = gains.map(EqualizerSettings.clampedGain)
        let headroom = -max(0, clamped.max() ?? 0)
        return (clamped, EqualizerSettings.clampedPreamp(min(profilePreamp, headroom)))
    }

    /// The gains of ten peaking filters at the band centres with the bands' Q, in band order.
    private static func fixedBandGains(_ filters: [Filter]) -> [Float]? {
        guard filters.count == Equalizer.bandCount else { return nil }
        var gains = [Float](repeating: 0, count: Equalizer.bandCount)
        var seen = Set<Int>()
        for filter in filters {
            guard filter.type == .peaking, abs(filter.q - Equalizer.q) < 0.05,
                  let band = Equalizer.frequencies.firstIndex(where: { abs($0 - filter.frequency) / $0 < 0.03 }),
                  seen.insert(band).inserted else { return nil }
            gains[band] = filter.gain
        }
        return gains
    }

    static func response(of filter: Filter, at frequency: Float, sampleRate: Float) -> Float {
        guard filter.frequency < sampleRate * 0.49 else { return 0 }
        let c = coefficients(filter, sampleRate: sampleRate)
        return BiquadResponse.magnitudeDB(b0: c.b0, b1: c.b1, b2: c.b2, a1: c.a1, a2: c.a2,
                                          frequency: frequency, sampleRate: sampleRate)
    }

    /// RBJ Audio EQ Cookbook filters, normalised so a0 = 1; shelves use Q as AutoEQ does.
    private static func coefficients(_ filter: Filter, sampleRate: Float)
        -> (b0: Float, b1: Float, b2: Float, a1: Float, a2: Float) {
        switch filter.type {
        case .peaking:
            return EqualizerProcessor.peakingCoefficients(frequency: filter.frequency, gainDB: filter.gain,
                                                          q: filter.q, sampleRate: sampleRate)
        case .lowShelf, .highShelf:
            let a = pow(10, filter.gain / 40)
            let w0 = 2 * Float.pi * filter.frequency / sampleRate
            let alpha = sin(w0) / (2 * filter.q)
            let cosW0 = cos(w0)
            let root = 2 * sqrt(a) * alpha
            let sign: Float = filter.type == .lowShelf ? 1 : -1
            // Low shelf with sign = 1; the high shelf mirrors the cosine terms.
            let b0 = a * ((a + 1) - sign * (a - 1) * cosW0 + root)
            let b1 = sign * 2 * a * ((a - 1) - sign * (a + 1) * cosW0)
            let b2 = a * ((a + 1) - sign * (a - 1) * cosW0 - root)
            let a0 = (a + 1) + sign * (a - 1) * cosW0 + root
            let a1 = -sign * 2 * ((a - 1) + sign * (a + 1) * cosW0)
            let a2 = (a + 1) + sign * (a - 1) * cosW0 - root
            return (b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)
        }
    }

    /// Linear in log-frequency between the nearest points; flat beyond the ends.
    private static func interpolate(_ points: [(frequency: Float, gain: Float)], at frequency: Float) -> Float {
        guard let first = points.first, let last = points.last else { return 0 }
        if frequency <= first.frequency { return first.gain }
        if frequency >= last.frequency { return last.gain }
        guard let upper = points.firstIndex(where: { $0.frequency >= frequency }), upper > 0 else { return first.gain }
        let lo = points[upper - 1], hi = points[upper]
        let t = (log(frequency) - log(lo.frequency)) / (log(hi.frequency) - log(lo.frequency))
        return lo.gain + t * (hi.gain - lo.gain)
    }
}

// MARK: - Client

nonisolated enum AutoEQError: Error, Equatable, Sendable {
    /// The index or profile can't be fetched and nothing is cached.
    case offline
    case notFound
    case tooLarge
    case unreadable
}

nonisolated protocol AutoEQTransport: Sendable {
    /// Fetches `url`, failing with `AutoEQError.tooLarge` past `limit` bytes. Returns the HTTP status.
    func data(from url: URL, limit: Int) async throws -> (Data, Int)
}

nonisolated struct URLSessionAutoEQTransport: AutoEQTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(from url: URL, limit: Int) async throws -> (Data, Int) {
        // Plain HTTP is never followed, even through a redirect.
        guard url.scheme?.lowercased() == "https" else { throw AutoEQError.unreadable }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("text/plain", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSOnlyRedirectDelegate())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if response.expectedContentLength > Int64(limit) { throw AutoEQError.tooLarge }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit { throw AutoEQError.tooLarge }
        }
        return (data, status)
    }
}

/// Refuses redirects that leave HTTPS.
private nonisolated final class HTTPSOnlyRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}

/// Finds headphone corrections in the public AutoEQ results (github.com/jaakkopasanen/AutoEq).
/// The index is kept in Caches for a week and used past that while offline.
actor AutoEQClient {
    static let shared = AutoEQClient()
    static let resultsURL = URL(string: "https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/")!
    /// The real index is under 1 MB; anything far larger isn't it.
    static let indexLimit = 4 * 1024 * 1024
    static let profileLimit = 64 * 1024
    static let indexLifetime: TimeInterval = 7 * 24 * 60 * 60

    private let transport: any AutoEQTransport
    private let cacheURL: URL
    private let now: @Sendable () -> Date
    private var entries: [AutoEQEntry]?

    init(
        transport: any AutoEQTransport = URLSessionAutoEQTransport(),
        cacheURL: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.minidisc/autoeq-index.md"),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.cacheURL = cacheURL
        self.now = now
    }

    /// The index: from memory, a fresh cache, the network, or a stale cache when offline.
    func index() async throws -> [AutoEQEntry] {
        if let entries { return entries }
        let cached = cachedIndex()
        if let cached, now().timeIntervalSince(cached.modified) < Self.indexLifetime {
            entries = cached.entries
            return cached.entries
        }
        do {
            let (data, status) = try await transport.data(from: Self.resultsURL.appending(path: "INDEX.md"), limit: Self.indexLimit)
            guard status == 200, let text = String(data: data, encoding: .utf8) else { throw AutoEQError.unreadable }
            let parsed = AutoEQIndex.parse(text)
            guard !parsed.isEmpty else { throw AutoEQError.unreadable }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
            entries = parsed
            return parsed
        } catch {
            if let cached {
                entries = cached.entries
                return cached.entries
            }
            if let error = error as? AutoEQError { throw error }
            throw AutoEQError.offline
        }
    }

    func search(_ query: String) async throws -> [AutoEQEntry] {
        AutoEQIndex.search(try await index(), query: query)
    }

    /// The best profile for ten bands: FixedBandEQ, then ParametricEQ, then GraphicEQ.
    func profile(for entry: AutoEQEntry) async throws -> AutoEQProfile {
        var directory = Self.resultsURL
        for component in entry.pathComponents { directory = directory.appending(path: component) }
        var lastError = AutoEQError.notFound
        for kind in ["FixedBandEQ", "ParametricEQ", "GraphicEQ"] {
            let url = directory.appending(path: "\(entry.fileStem) \(kind).txt")
            do {
                let (data, status) = try await transport.data(from: url, limit: Self.profileLimit)
                if status == 404 { continue }
                guard status == 200, let text = String(data: data, encoding: .utf8) else {
                    lastError = .unreadable
                    continue
                }
                return try AutoEQProfile.parse(text)
            } catch let error as AutoEQError {
                lastError = error
            } catch is AutoEQProfile.ParseError {
                lastError = .unreadable
            } catch {
                throw AutoEQError.offline
            }
        }
        throw lastError
    }

    private func cachedIndex() -> (entries: [AutoEQEntry], modified: Date)? {
        guard let values = try? cacheURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let size = values.fileSize, size <= Self.indexLimit,
              let data = try? Data(contentsOf: cacheURL), let text = String(data: data, encoding: .utf8) else { return nil }
        let parsed = AutoEQIndex.parse(text)
        guard !parsed.isEmpty else { return nil }
        return (parsed, values.contentModificationDate ?? .distantPast)
    }
}
