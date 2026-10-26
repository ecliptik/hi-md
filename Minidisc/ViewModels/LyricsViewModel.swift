import SwiftUI
import SwiftSonic

@Observable
@MainActor
final class LyricsViewModel {
    private let lyricsService: LyricsService
    private let playerService: any PlayerServiceProtocol
    private let playerState: PlayerState
    private let track: DisplayableSong
    private let serverId: UUID
    private let source: LyricsSource

    private(set) var state: State = .loading
    private(set) var currentLineIndex: Int?
    private(set) var availableLanguages: [String] = []
    var selectedLanguage: String?
    var autoScrollEnabled: Bool = true
    private(set) var isUserScrolling: Bool = false
    /// Where the lyrics views should scroll next: set when the current line moves while the
    /// lyrics follow the song, and when a scrub or seek makes them follow again.
    private(set) var scrollRequest: ScrollRequest?
    /// The clock the views read, replaceable in tests.
    @ObservationIgnored var now: () -> Date = { .now }

    /// A line to bring to the middle: gliding for a few lines, cutting straight there for more.
    nonisolated struct ScrollRequest: Equatable, Sendable {
        let index: Int
        let animated: Bool
        /// Distinguishes two requests for the same line.
        let revision: Int
    }

    private var lyricsList: LyricsList?
    private var trackingTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    @ObservationIgnored private var clockTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var isObservingClock = false
    @ObservationIgnored private var handledSeekRevision: Int
    /// How many views show these lyrics: the player's lyrics panel and the full-screen karaoke
    /// view can overlap while one is presented over the other.
    private var visibleCount = 0
    private var isShown: Bool { visibleCount > 0 }

    nonisolated enum State: Equatable {
        case loading
        case loaded(StructuredLyrics)
        case empty
        case unsupported
        case error(String)
    }

    init(
        track: DisplayableSong,
        serverId: UUID,
        source: LyricsSource,
        lyricsService: LyricsService,
        playerService: any PlayerServiceProtocol,
        playerState: PlayerState
    ) {
        self.track = track
        self.serverId = serverId
        self.source = source
        self.lyricsService = lyricsService
        self.playerService = playerService
        self.playerState = playerState
        handledSeekRevision = playerState.lyricsClock.seekRevision
    }

    isolated deinit {
        trackingTask?.cancel()
        resumeTask?.cancel()
        clockTimeoutTask?.cancel()
    }

    // MARK: - Load

    func load() async {
        state = .loading
        do {
            let list = try await lyricsService.fetchLyrics(
                for: track,
                serverId: serverId,
                source: source
            )
            lyricsList = list
            applyCurrentLanguage()
        } catch LyricsError.notSupportedByServer {
            state = .unsupported
        } catch LyricsError.notFound {
            state = .empty
        } catch let error as LyricsError {
            state = .error(networkErrorMessage(from: error))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Whether these lyrics can be shown again for this track and source instead of reloading
    /// them. A failed load is retried.
    func canBeReused(forTrackID trackID: String, source: LyricsSource) -> Bool {
        guard track.id == trackID, self.source == source else { return false }
        if case .error = state { return false }
        return true
    }

    // MARK: - Line tracking

    /// The song position the lyrics show: a scrub or seek in progress, else the player's.
    private var lyricsTimeMs: Int {
        Int(playerState.lyricsClock.time(playbackPosition: playerState.position, at: now()) * 1000)
    }

    /// Moves the current line to the playback position now, rather than on the next tracking tick,
    /// so the lyrics open on the line being sung.
    func syncToPlayback() {
        update(elapsedMs: lyricsTimeMs)
    }

    func update(elapsedMs: Int) {
        guard case .loaded(let structured) = state, structured.synced else {
            currentLineIndex = nil
            return
        }
        let adjustedMs = elapsedMs - structured.offset
        var newIndex: Int? = nil
        for (index, line) in structured.line.enumerated() {
            guard let start = line.start else { continue }
            if start <= adjustedMs {
                newIndex = index
            } else {
                break
            }
        }
        if newIndex != currentLineIndex {
            let previous = currentLineIndex
            currentLineIndex = newIndex
            if let newIndex, autoScrollEnabled, !isUserScrolling {
                requestScroll(to: newIndex, animated: LyricsScrollPolicy.animates(from: previous, to: newIndex))
            }
        }
    }

    private func requestScroll(to index: Int, animated: Bool) {
        scrollRequest = ScrollRequest(index: index, animated: animated, revision: (scrollRequest?.revision ?? 0) &+ 1)
    }

    // MARK: - Scrubbing and seeking

    /// A scrubber moved or a seek was asked for: the line follows at once, and a new scrub or
    /// seek makes the lyrics follow the song again, even after the listener scrolled them away.
    func lyricsClockChanged() {
        let clock = playerState.lyricsClock
        if clock.seekRevision != handledSeekRevision {
            handledSeekRevision = clock.seekRevision
            followAgain()
        }
        syncToPlayback()
        // Paused, nothing else would move the line back if the seek never lands.
        clockTimeoutTask?.cancel()
        clockTimeoutTask = nil
        guard clock.pendingSeek != nil else { return }
        clockTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(LyricsClock.catchUpTimeout + 0.05))
            guard !Task.isCancelled else { return }
            self?.syncToPlayback()
        }
    }

    /// Follows the song again and scrolls to the line now being sung, straight there: where the
    /// listener scrolled to is unknown.
    private func followAgain() {
        resumeTask?.cancel()
        resumeTask = nil
        isUserScrolling = false
        autoScrollEnabled = true
        let before = currentLineIndex
        syncToPlayback()
        if let index = currentLineIndex, index == before {
            requestScroll(to: index, animated: false)
        }
    }

    /// Watches the player's scrubs and seeks while a lyrics view shows these lyrics.
    private func observeLyricsClock() {
        guard isShown, !isObservingClock else { return }
        isObservingClock = true
        withObservationTracking {
            _ = playerState.lyricsClock
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObservingClock = false
                guard self.isShown else { return }
                self.lyricsClockChanged()
                self.observeLyricsClock()
            }
        }
    }

    // MARK: - Seek

    func userTapped(lineIndex: Int) {
        guard case .loaded(let structured) = state, structured.synced else { return }
        guard lineIndex < structured.line.count else { return }
        guard let startMs = structured.line[lineIndex].start else { return }
        let targetSeconds = TimeInterval(startMs + structured.offset) / 1000.0
        // Highlights the line now, before the player gets there.
        playerState.noteSeek(to: targetSeconds, at: now())
        Task { [weak self] in
            await self?.playerService.seek(to: targetSeconds)
        }
    }

    // MARK: - Auto-scroll

    func userStartedScrolling() {
        isUserScrolling = true
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.isUserScrolling = false
        }
    }

    func userStoppedScrolling() {
        userStartedScrolling()
    }

    // MARK: - Language selection

    func selectLanguage(_ lang: String) {
        guard selectedLanguage != lang else { return }
        selectedLanguage = lang
        currentLineIndex = nil
        applyCurrentLanguage()
    }

    // MARK: - Timer lifecycle

    var isPlaying: Bool { playerState.playbackState == .playing }

    private var hasSyncedLyrics: Bool {
        if case .loaded(let structured) = state { return structured.synced }
        return false
    }

    /// Called when a lyrics view appears/disappears. The auto-scroll resume task is torn down once
    /// no view shows the lyrics.
    func setVisible(_ visible: Bool) {
        visibleCount = max(0, visibleCount + (visible ? 1 : -1))
        if !isShown {
            resumeTask?.cancel()
            resumeTask = nil
            clockTimeoutTask?.cancel()
            clockTimeoutTask = nil
        } else {
            handledSeekRevision = playerState.lyricsClock.seekRevision
            observeLyricsClock()
        }
        reconcileTracking()
    }

    /// Runs line tracking only for visible, playing, time-synced lyrics.
    func reconcileTracking() {
        if isShown && isPlaying && hasSyncedLyrics {
            startTimer()
        } else {
            stopTimer()
        }
    }

    private func startTimer() {
        guard trackingTask == nil else { return }
        trackingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .milliseconds(250))
                } catch {
                    return
                }
                guard let self else { return }
                self.syncToPlayback()
            }
        }
    }

    private func stopTimer() {
        trackingTask?.cancel()
        trackingTask = nil
    }

    var isTrackingPlayback: Bool { trackingTask != nil }

    // MARK: - Private helpers

    private func applyCurrentLanguage() {
        guard let list = lyricsList else { return }
        var seen = Set<String>()
        availableLanguages = list.structuredLyrics
            .compactMap { $0.lang }
            .filter { seen.insert($0).inserted }
        let best = lyricsService.selectBestLanguage(from: list, preferred: selectedLanguage)
        currentLineIndex = nil
        state = best.map { .loaded($0) } ?? .empty
        syncToPlayback()
        reconcileTracking()
    }

    private func networkErrorMessage(from error: LyricsError) -> String {
        if case .networkError(let msg) = error { return msg }
        return error.localizedDescription
    }
}

/// The view model a lyrics view counts as visible. The player hands a view a new view model when
/// the song changes while the view stays on screen, so `onAppear` doesn't fire again; the new one
/// must be marked visible and the old one released, or line tracking stops.
@MainActor
struct LyricsVisibilityHandoff {
    private(set) var shown: LyricsViewModel?

    mutating func show(_ viewModel: LyricsViewModel) {
        guard shown !== viewModel else { return }
        shown?.setVisible(false)
        viewModel.setVisible(true)
        shown = viewModel
    }

    mutating func hide() {
        shown?.setVisible(false)
        shown = nil
    }
}
