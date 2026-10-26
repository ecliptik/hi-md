import Foundation
import Synchronization
import Testing
@testable import Minidisc

private final class FixtureBundleToken {}

private func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle(for: FixtureBundleToken.self).url(forResource: name, withExtension: nil))
    return try String(contentsOf: url, encoding: .utf8)
}

@Suite("AutoEQ index")
struct AutoEQIndexTests {
    @Test("The index fixture parses into entries with decoded paths")
    func parsesFixture() throws {
        let entries = AutoEQIndex.parse(try fixture("autoeq-index.md"))
        #expect(entries.count == 15)
        let hd600 = try #require(entries.first { $0.name == "Sennheiser HD 600" })
        #expect(hd600.source == "oratory1990")
        #expect(hd600.pathComponents == ["oratory1990", "over-ear", "Sennheiser HD 600"])
        #expect(hd600.fileStem == "Sennheiser HD 600")
    }

    @Test("Parentheses, accents and rigs survive")
    func awkwardNames() throws {
        let entries = AutoEQIndex.parse(try fixture("autoeq-index.md"))
        let aero = try #require(entries.first { $0.name == "1MORE Aero (ANC Off)" })
        #expect(aero.pathComponents.last == "1MORE Aero (ANC Off)")
        #expect(aero.source == "HypetheSonics on GRAS RA0045")
        let ecoute = try #require(entries.first { $0.name.hasPrefix("écoute") && $0.name.hasSuffix("(passive)") })
        #expect(ecoute.pathComponents.last == "écoute Audio TH1 (passive)")
        let rtings = try #require(entries.first { $0.source.hasPrefix("Rtings") })
        #expect(rtings.pathComponents[1] == "Bruel & Kjaer 5128 over-ear")
    }

    @Test("Lines that aren't results, or that try to leave the results folder, are dropped")
    func rejectsBadLines() {
        #expect(AutoEQIndex.parseLine("# Index") == nil)
        #expect(AutoEQIndex.parseLine("This is a list of all equalization profiles.") == nil)
        #expect(AutoEQIndex.parseLine("- [Evil](./../../etc/passwd) by nobody") == nil)
        #expect(AutoEQIndex.parseLine("- [Evil](./a/%2E%2E/b) by nobody") == nil)
        #expect(AutoEQIndex.parseLine("- [Evil](./a/b%2Fc) by nobody") == nil)
        #expect(AutoEQIndex.parseLine("- [](./a/b) by nobody") == nil)
        #expect(AutoEQIndex.parseLine("- [Short](./single) by nobody") == nil)
    }

    @Test("Search matches every word, ignoring case and accents, best matches first")
    func search() throws {
        let entries = AutoEQIndex.parse(try fixture("autoeq-index.md"))
        let hd = AutoEQIndex.search(entries, query: "hd 6")
        #expect(hd.map(\.name).sorted() == ["Sennheiser HD 600", "Sennheiser HD 600", "Sennheiser HD 600", "Sennheiser HD 650", "Sennheiser HD 6XX"])
        #expect(AutoEQIndex.search(entries, query: "ECOUTE passive").count == 1)
        #expect(AutoEQIndex.search(entries, query: "sony").first?.name == "Sony WH-1000XM4")
        #expect(AutoEQIndex.search(entries, query: "   ").isEmpty)
        #expect(AutoEQIndex.search(entries, query: "zzz").isEmpty)
        // A name that starts with the query outranks one that only contains it.
        let ranked = AutoEQIndex.search(entries, query: "1more")
        #expect(ranked.first?.name == "1MORE Aero (ANC On)")
    }
}

@Suite("AutoEQ profiles")
struct AutoEQProfileTests {
    @Test("FixedBandEQ maps band for band with its own preamp")
    func fixedBand() throws {
        let profile = try AutoEQProfile.parse(try fixture("autoeq-hd600-fixedband.txt"))
        let mapped = profile.bandGains()
        #expect(mapped.gains == [6.9, 3.3, -1.1, -1.6, 0.6, -0.8, 0.1, -1.0, 3.9, -6.5])
        #expect(mapped.preamp == -7.5)
    }

    @Test("ParametricEQ is sampled at the band centres")
    func parametric() throws {
        let profile = try AutoEQProfile.parse(try fixture("autoeq-hd600-parametric.txt"))
        guard case .parametric(let preamp, let filters) = profile.curve else {
            Issue.record("expected a parametric profile")
            return
        }
        #expect(preamp == -6.3)
        #expect(filters.count == 10)
        #expect(filters[0] == .init(type: .lowShelf, frequency: 105, gain: 6.5, q: 0.70))
        #expect(filters[5] == .init(type: .highShelf, frequency: 10000, gain: -3.1, q: 0.70))

        let mapped = profile.bandGains()
        #expect(mapped.gains.count == Equalizer.bandCount)
        // Each band equals the sum of the filters' responses at its centre.
        for (band, frequency) in Equalizer.frequencies.enumerated() {
            let expected = filters.reduce(Float(0)) { $0 + AutoEQProfile.response(of: $1, at: frequency, sampleRate: 48000) }
            #expect(abs(mapped.gains[band] - expected) < 1e-4)
        }
        // The low shelf lifts the bass well above the treble, which the high shelf lowers.
        #expect(mapped.gains[0] > 5)
        #expect(mapped.gains[9] < -2)
        // The profile's preamp covers the biggest mapped boost.
        #expect(mapped.preamp <= -(mapped.gains.max() ?? 0))
        #expect(mapped.preamp <= -6.3)
    }

    @Test("The sampled ParametricEQ lands close to AutoEQ's own fixed-band fit")
    func parametricAgreesWithFixedBand() throws {
        let sampled = try AutoEQProfile.parse(try fixture("autoeq-hd600-parametric.txt")).bandGains().gains
        let fitted = try AutoEQProfile.parse(try fixture("autoeq-hd600-fixedband.txt")).bandGains().gains
        // Sampling and fitting differ in detail, but the tonal balance matches.
        let sampledCurve = Equalizer.frequencies.map { Equalizer.response(at: $0, gains: sampled) }
        let fittedCurve = Equalizer.frequencies.map { Equalizer.response(at: $0, gains: fitted) }
        let averageDifference = zip(sampledCurve, fittedCurve).map { abs($0 - $1) }.reduce(0, +) / Float(sampledCurve.count)
        #expect(averageDifference < 4)
        #expect(sampled[0] > 0 && fitted[0] > 0)
    }

    @Test("GraphicEQ is interpolated at the band centres")
    func graphic() throws {
        let profile = try AutoEQProfile.parse(try fixture("autoeq-hd600-graphic.txt"))
        let mapped = profile.bandGains()
        // The fixture reads -0.2 dB at 30 and 32 Hz.
        #expect(abs(mapped.gains[0] - (-0.2)) < 0.05)
        #expect(mapped.gains.allSatisfy { Equalizer.gainRange.contains($0) })
        #expect(mapped.preamp == -max(0, mapped.gains.max() ?? 0))
    }

    @Test("Out-of-range values clamp and junk is refused")
    func clampingAndJunk() throws {
        let loud = try AutoEQProfile.parse("Preamp: -30 dB\nFilter 1: ON PK Fc 1000 Hz Gain 20 dB Q 1.41\nFilter 2: OFF PK Fc 100 Hz Gain 9 dB Q 1")
        guard case .parametric(_, let filters) = loud.curve else { return }
        #expect(filters.count == 1)
        let mapped = loud.bandGains()
        #expect(mapped.gains[5] == 12)
        #expect(mapped.preamp == -12)
        #expect(throws: AutoEQProfile.ParseError.unrecognized) { try AutoEQProfile.parse("<html>404</html>") }
        #expect(throws: AutoEQProfile.ParseError.unrecognized) { try AutoEQProfile.parse("GraphicEQ: nonsense") }
    }
}

/// Serves fixtures by URL and records requests; never touches the network.
private final class StubAutoEQTransport: AutoEQTransport, @unchecked Sendable {
    let responses: Mutex<[String: (Data, Int)]>
    let requests = Mutex<[URL]>([])
    let failAll: Bool

    init(responses: [String: (Data, Int)] = [:], failAll: Bool = false) {
        self.responses = Mutex(responses)
        self.failAll = failAll
    }

    func data(from url: URL, limit: Int) async throws -> (Data, Int) {
        requests.withLock { $0.append(url) }
        if failAll { throw URLError(.notConnectedToInternet) }
        guard let response = responses.withLock({ $0[url.absoluteString] }) else { return (Data(), 404) }
        if response.0.count > limit { throw AutoEQError.tooLarge }
        return response
    }
}

@Suite("AutoEQ client", .serialized)
struct AutoEQClientTests {
    private let indexURL = AutoEQClient.resultsURL.appending(path: "INDEX.md").absoluteString

    private func cacheURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("autoeq-\(UUID().uuidString)/index.md")
    }

    @Test("The index downloads once over HTTPS and is cached")
    func cachesIndex() async throws {
        let index = Data(try fixture("autoeq-index.md").utf8)
        let transport = StubAutoEQTransport(responses: [indexURL: (index, 200)])
        let cache = cacheURL()
        let client = AutoEQClient(transport: transport, cacheURL: cache)
        #expect(try await client.index().count == 15)
        #expect(try await client.search("650").count == 1)
        #expect(transport.requests.withLock { $0.count } == 1)
        #expect(transport.requests.withLock { $0.allSatisfy { $0.scheme == "https" } })
        #expect(FileManager.default.fileExists(atPath: cache.path))

        // A new client finds the fresh cache without asking the network.
        let offline = StubAutoEQTransport(failAll: true)
        #expect(try await AutoEQClient(transport: offline, cacheURL: cache).index().count == 15)
        #expect(offline.requests.withLock { $0.isEmpty })
    }

    @Test("A stale cache is still used when the network is down")
    func staleCacheOffline() async throws {
        let cache = cacheURL()
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(try fixture("autoeq-index.md").utf8).write(to: cache)
        let later = Date().addingTimeInterval(AutoEQClient.indexLifetime * 2)
        let transport = StubAutoEQTransport(failAll: true)
        let client = AutoEQClient(transport: transport, cacheURL: cache, now: { later })
        #expect(try await client.index().count == 15)
        #expect(transport.requests.withLock { $0.count } == 1)
    }

    @Test("Offline with nothing cached reports offline")
    func offlineWithoutCache() async {
        let client = AutoEQClient(transport: StubAutoEQTransport(failAll: true), cacheURL: cacheURL())
        await #expect(throws: AutoEQError.offline) { try await client.index() }
    }

    @Test("An oversized or garbled index is refused")
    func refusesBadIndex() async {
        let huge = Data(count: AutoEQClient.indexLimit + 1)
        let client = AutoEQClient(transport: StubAutoEQTransport(responses: [indexURL: (huge, 200)]), cacheURL: cacheURL())
        await #expect(throws: AutoEQError.tooLarge) { try await client.index() }
        let garbled = AutoEQClient(transport: StubAutoEQTransport(responses: [indexURL: (Data("<html/>".utf8), 200)]), cacheURL: cacheURL())
        await #expect(throws: AutoEQError.unreadable) { try await garbled.index() }
    }

    @Test("Profiles prefer FixedBandEQ and fall back to ParametricEQ")
    func profileFallback() async throws {
        let entry = AutoEQEntry(name: "Sennheiser HD 600", source: "oratory1990",
                                pathComponents: ["oratory1990", "over-ear", "Sennheiser HD 600"])
        let base = AutoEQClient.resultsURL.appending(path: "oratory1990").appending(path: "over-ear").appending(path: "Sennheiser HD 600")
        let fixed = base.appending(path: "Sennheiser HD 600 FixedBandEQ.txt").absoluteString
        let parametric = base.appending(path: "Sennheiser HD 600 ParametricEQ.txt").absoluteString
        #expect(fixed.hasPrefix("https://raw.githubusercontent.com/jaakkopasanen/AutoEq/master/results/oratory1990/over-ear/Sennheiser%20HD%20600/"))

        let both = StubAutoEQTransport(responses: [
            fixed: (Data(try fixture("autoeq-hd600-fixedband.txt").utf8), 200),
            parametric: (Data(try fixture("autoeq-hd600-parametric.txt").utf8), 200),
        ])
        let fromFixed = try await AutoEQClient(transport: both, cacheURL: cacheURL()).profile(for: entry)
        #expect(fromFixed.bandGains().preamp == -7.5)

        let parametricOnly = StubAutoEQTransport(responses: [parametric: (Data(try fixture("autoeq-hd600-parametric.txt").utf8), 200)])
        let fromParametric = try await AutoEQClient(transport: parametricOnly, cacheURL: cacheURL()).profile(for: entry)
        guard case .parametric(let preamp, _) = fromParametric.curve else {
            Issue.record("expected the parametric profile")
            return
        }
        #expect(preamp == -6.3)

        let none = AutoEQClient(transport: StubAutoEQTransport(), cacheURL: cacheURL())
        await #expect(throws: AutoEQError.notFound) { try await none.profile(for: entry) }
        let down = AutoEQClient(transport: StubAutoEQTransport(failAll: true), cacheURL: cacheURL())
        await #expect(throws: AutoEQError.offline) { try await down.profile(for: entry) }
    }

    @Test("The live transport refuses plain HTTP")
    func httpsOnly() async {
        let transport = URLSessionAutoEQTransport()
        await #expect(throws: AutoEQError.unreadable) {
            _ = try await transport.data(from: URL(string: "http://example.invalid/INDEX.md")!, limit: 10)
        }
    }
}
