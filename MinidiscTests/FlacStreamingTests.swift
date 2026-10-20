import AVFoundation
import Foundation
import Network
import Synchronization
import Testing
@testable import Minidisc

/// Serves one file on loopback with byte-range support, the way a Subsonic server does.
private nonisolated final class RangeFileServer: @unchecked Sendable {
    private let listener: NWListener
    private let data: Data
    private let contentType: String
    private let queue = DispatchQueue(label: "range-file-server")

    private init(listener: NWListener, data: Data, contentType: String) {
        self.listener = listener
        self.data = data
        self.contentType = contentType
    }

    static func start(serving data: Data, contentType: String) async throws -> (server: RangeFileServer, url: URL) {
        let listener = try NWListener(using: .tcp, on: .any)
        let server = RangeFileServer(listener: listener, data: data, contentType: contentType)
        listener.newConnectionHandler = { server.handle($0) }
        let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { continuation in
            let resumed = Mutex(false)
            listener.stateUpdateHandler = { state in
                let first = resumed.withLock { done -> Bool in defer { done = true }; return !done }
                guard first else { return }
                switch state {
                case .ready:
                    if let port = listener.port { continuation.resume(returning: port) }
                    else { continuation.resume(throwing: URLError(.cannotConnectToHost)) }
                case .failed(let error): continuation.resume(throwing: error)
                default: resumed.withLock { $0 = false }
                }
            }
            listener.start(queue: server.queue)
        }
        // No file extension, like a Subsonic `stream` endpoint.
        return (server, URL(string: "http://127.0.0.1:\(port.rawValue)/rest/stream?id=track")!)
    }

    func stop() { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [self] request, _, _, _ in
            guard let request, let text = String(data: request, encoding: .utf8) else { connection.cancel(); return }
            connection.send(content: response(for: text), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func response(for request: String) -> Data {
        var start = 0, end = data.count - 1, partial = false
        if let line = request.split(separator: "\r\n").first(where: { $0.lowercased().hasPrefix("range:") }),
           let spec = line.split(separator: "=").last {
            let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
            if let first = bounds.first, let value = Int(first) { start = value }
            if bounds.count > 1, let value = Int(bounds[1]) { end = min(value, data.count - 1) }
            partial = true
        }
        start = min(start, data.count)
        let body = start <= end ? data[start...end] : Data()
        var head = "HTTP/1.1 \(partial ? "206 Partial Content" : "200 OK")\r\n"
        head += "Content-Type: \(contentType)\r\nAccept-Ranges: bytes\r\nContent-Length: \(body.count)\r\n"
        if partial { head += "Content-Range: bytes \(start)-\(max(start, end))/\(data.count)\r\n" }
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

private nonisolated final class FailureRecorder: AudioEngineDelegate, Sendable {
    private let failures = Mutex<[String]>([])
    var recorded: [String] { failures.withLock { $0 } }
    func audioEngineDidChangeState(_ state: AudioEngineState, playbackToken: AudioEnginePlaybackToken) {}
    func audioEngineDidReachEndOfTrack(_ transition: AudioEngineTrackEnd) {}
    func audioEngineDidError(_ failure: AudioEngineFailure, playbackToken: AudioEnginePlaybackToken) {
        failures.withLock { $0.append(failure.diagnosticDescription) }
    }
}

@Suite("FLAC streaming", .serialized)
struct FlacStreamingTests {
    /// Eight seconds of silence encoded as FLAC by the system encoder.
    private static func silentFLAC() throws -> Data {
        let url = URL.temporaryDirectory.appendingPathComponent("\(UUID()).flac")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatFLAC,
            AVSampleRateKey: 8_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitDepthHintKey: 16
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
            buffer.frameLength = 8_000
            for _ in 0..<8 { try file.write(from: buffer) }
        }
        return try Data(contentsOf: url)
    }

    /// Servers and reverse proxies label FLAC in several ways, and a Subsonic stream URL has no
    /// file extension to fall back on.
    @Test(arguments: ["audio/flac", "audio/x-flac", "application/octet-stream"])
    func flacStartsAndSeeksRegardlessOfTheServersContentType(contentType: String) async throws {
        let flac = try Self.silentFLAC()
        #expect(AudioContainer.sniff(magic: [UInt8](flac.prefix(12))) == .flac)
        let (server, url) = try await RangeFileServer.start(serving: flac, contentType: contentType)
        defer { server.stop() }

        let recorder = FailureRecorder()
        let engine = AVPlayerEngine()
        engine.delegate = recorder
        engine.play(trackID: "flac", url: url, headers: [:])
        defer { engine.stop() }

        let deadline = ContinuousClock.now + .seconds(15)
        while engine.progress < 0.3, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(engine.progress >= 0.3, "playback never started; failures: \(recorder.recorded)")
        #expect(recorder.recorded.isEmpty)

        #expect(await engine.seek(to: 5))
        #expect(engine.progress >= 4.9 && engine.progress < 7)
    }

    @Test func containerNamesMapToMIMETypesAVFoundationAccepts() {
        #expect(AudioContainer.flac.mimeType == "audio/flac")
        #expect(AudioContainer.mp3.mimeType == "audio/mpeg")
        #expect(AudioContainer.mp4.mimeType == "audio/mp4")
        #expect(AudioContainer.ogg.mimeType == nil)
    }

    @Test func unidentifiedContainerFailuresAreRecognised() {
        let notRecognized = AudioEngineFailure(error: NSError(domain: AVFoundationErrorDomain, code: AVError.fileFormatNotRecognized.rawValue))
        let unsupported = AudioEngineFailure(error: NSError(domain: NSOSStatusErrorDomain, code: -12847))
        let network = AudioEngineFailure(error: URLError(.timedOut))
        #expect(notRecognized.isUnidentifiedMedia)
        #expect(unsupported.isUnidentifiedMedia)
        #expect(!network.isUnidentifiedMedia)
    }
}
