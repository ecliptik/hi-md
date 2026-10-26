import Accelerate
import AVFoundation
#if targetEnvironment(macCatalyst)
import CoreAudio // UnsafeMutableAudioBufferListPointer on the Mac
#endif
import Foundation
import MediaToolbox
import OSLog
import Synchronization

/// Two AVPlayer decks alternate active and standby roles for gapless playback and crossfades.
/// A recursive lock protects deck roles and transition state across control calls and callbacks.
/// ReplayGain boosts use an audio processing tap because AVPlayer.volume cannot exceed 1. The same
/// tap runs the equalizer, the stereo fold-down of multichannel sources and the peak limiter, so it
/// is also installed whenever the equalizer is on or a multichannel track is to be folded down, and
/// copies samples to `VisualizerTap` while a visualiser is attached.
nonisolated final class AVPlayerEngine: AudioEngine, @unchecked Sendable {
    private enum StandbyPreparationState {
        case idle
        case preparing
        case ready
    }

    private enum ReplayGainDeck: Sendable {
        case a
        case b
    }

    /// Identifies the exact physical deck load for which an asynchronous tap install was requested.
    /// Deck roles may swap while AVFoundation loads the audio track, so neither "active" nor
    /// "standby" is a stable identity across the suspension.
    private struct ReplayGainInstallRequest: Sendable {
        let deck: ReplayGainDeck
        let trackID: String
        let generation: UInt64
    }

    private let lock = NSRecursiveLock()
    private weak var storedDelegate: AudioEngineDelegate?

    var delegate: AudioEngineDelegate? {
        get { lock.withLock { storedDelegate } }
        set { lock.withLock { storedDelegate = newValue } }
    }

    private let playerFactory: @Sendable () -> AVPlayer
    private var deckA: AVPlayer
    private var deckB: AVPlayer
    private var contextA = ReplayGainTapContext()
    private var contextB = ReplayGainTapContext()
    /// Accessed only while `lock` is held. Separate counters allow both physical decks to prepare
    /// their taps concurrently without one deck invalidating the other's request.
    private var replayGainGenerationA: UInt64 = 0
    private var replayGainGenerationB: UInt64 = 0
    /// Accessed only while `lock` is held.
    private var replayGainTaskA: Task<Void, Never>?
    private var replayGainTaskB: Task<Void, Never>?
    private var activeIsA = true
    private var activePlayer: AVPlayer { activeIsA ? deckA : deckB }
    private var standbyPlayer: AVPlayer { activeIsA ? deckB : deckA }
    private var activeContext: ReplayGainTapContext { activeIsA ? contextA : contextB }
    private var standbyContext: ReplayGainTapContext { activeIsA ? contextB : contextA }

    private var currentItem: AVPlayerItem?
    private var currentAsset: AVAsset?
    private var currentTrackID: String?
    private var currentSourceHeaders: [String: String] = [:]
    /// The load for which an unidentified container was already retried. One retry per load.
    private var mimeRecoveryToken: AudioEnginePlaybackToken?
    private var currentPlaybackToken: AudioEnginePlaybackToken?
    private var preloadedItem: AVPlayerItem?
    private var preloadedAsset: AVAsset?
    private var preloadedTrackID: String?
    private var preloadedPlaybackToken: AudioEnginePlaybackToken?
    private var preloadedSourceURL: URL?
    private var preloadedSourceHeaders: [String: String] = [:]
    private var preloadedStartPosition: TimeInterval = 0
    private var standbyPreparationState: StandbyPreparationState = .idle
    /// Monotonic within this engine instance. It is deliberately never reset with the decks, so a
    /// callback queued for an item that was stopped can never alias a later load of the same song.
    private var nextPlaybackTokenRawValue: UInt64 = 0
    /// Overlap window for the pending transition (0 = gapless butt-splice).
    private var pendingOverlap: Double = 0
    /// URL of an item the engine already promoted at a hand-off; the next `play` with it adopts.
    private var handedOffTrackID: String?

    /// PlayerService-facing volume (restore mute, user fades). Deck volumes = fadeLevel × ramp.
    private var fadeLevel: Float = 1
    private var rampActive: Float = 1
    private var rampStandby: Float = 1
    private var overlapTimer: DispatchSourceTimer?
    private var overlapDuration: TimeInterval = 0
    private var overlapStartedAt: Date?
    private var overlapAwaitingStandbyPlayback = false
    private var isOverlapping = false
    private let rampQueue = DispatchQueue(label: "minidisc.engine.crossfade")
    private var overlapBoundaryToken: Any?
    private var overlapBoundaryOwner: AVPlayer?
    /// Authoritative track length from the library metadata. AVPlayer's own `item.duration` is an
    /// estimate that drifts on transcoded/VBR streams, which would arm the overlap at the wrong time.
    private var metadataDuration: Double = 0

    /// Orchestration intent: true between a play/resume and the next pause/stop. What separates
    /// "AVPlayer stopped on its own" (end of file, stall) from "the user pressed pause".
    private var shouldBePlaying = false
    /// Set once per item when the end has been reported, so the end-of-item notification and the
    /// watchdog below can never both advance the queue.
    private var didSignalEnd = false
    private var watchdogTimer: DispatchSourceTimer?
    private var lastWatchdogTime: Double = -1
    private var lastWatchdogAdvance = Date()
    private static let watchdogInterval = 500
    private static let endOfFileTolerance: Double = 1.5
    private static let frozenClockGrace: Double = 1.0

    private var timeControlObservers: [NSKeyValueObservation] = []
    private var equalizerObserver: (any NSObjectProtocol)?
    private var visualizerObserver: (any NSObjectProtocol)?
    private var downmixObserver: (any NSObjectProtocol)?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var standbyStatusObserver: NSKeyValueObservation?
    private var periodicToken: Any?
    private var periodicOwner: AVPlayer?

    init(playerFactory: @escaping @Sendable () -> AVPlayer = { AVPlayer() }) {
        self.playerFactory = playerFactory
        deckA = playerFactory()
        deckB = playerFactory()
        configurePlayers()
        equalizerObserver = NotificationCenter.default.addObserver(
            forName: EqualizerParameters.didChange, object: nil, queue: nil
        ) { [weak self] _ in
            self?.equalizerSettingsDidChange()
        }
        visualizerObserver = NotificationCenter.default.addObserver(
            forName: VisualizerTap.attachmentDidChange, object: VisualizerTap.shared, queue: nil
        ) { [weak self] _ in
            self?.equalizerSettingsDidChange()
        }
        downmixObserver = NotificationCenter.default.addObserver(
            forName: DownmixParameters.didChange, object: DownmixParameters.shared, queue: nil
        ) { [weak self] _ in
            self?.downmixSettingsDidChange()
        }
    }

    /// Installs observers on the current physical players, including after a system reset.
    /// Caller holds the lock, except during initialization.
    private func configurePlayers() {
        for deck in [deckA, deckB] {
            deck.automaticallyWaitsToMinimizeStalling = true
            deck.actionAtItemEnd = .pause
        }
        // State events follow the ACTIVE deck only; the standby warming up must not leak states.
        for deck in [deckA, deckB] {
            timeControlObservers.append(deck.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                guard let self else { return }
                self.lock.lock()
                let isActive = player === self.activePlayer
                let playbackToken = isActive ? self.currentPlaybackToken : nil
                if !isActive, player === self.standbyPlayer {
                    switch player.timeControlStatus {
                    case .playing:
                        self.startOverlapRampIfPossible()
                    case .paused, .waitingToPlayAtSpecifiedRate:
                        if self.isOverlapping {
                            // A buffering incoming deck must never leave the only audible deck
                            // partially faded. Its media clock freezes, so the ramp resumes from
                            // the same point once AVPlayer renders it again.
                            self.rampActive = 1
                            self.rampStandby = 0
                            self.applyDeckVolumes()
                        }
                    @unknown default:
                        break
                    }
                }
                self.lock.unlock()
                guard isActive, let playbackToken else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.delegate?.audioEngineDidChangeState(.playing, playbackToken: playbackToken)
                case .paused:
                    self.delegate?.audioEngineDidChangeState(.paused, playbackToken: playbackToken)
                case .waitingToPlayAtSpecifiedRate:
                    self.delegate?.audioEngineDidChangeState(.buffering, playbackToken: playbackToken)
                @unknown default:                    break
                }
            })
        }
    }

    deinit {
        if let equalizerObserver { NotificationCenter.default.removeObserver(equalizerObserver) }
        if let visualizerObserver { NotificationCenter.default.removeObserver(visualizerObserver) }
        if let downmixObserver { NotificationCenter.default.removeObserver(downmixObserver) }
        replayGainTaskA?.cancel()
        replayGainTaskB?.cancel()
        overlapTimer?.cancel()
        watchdogTimer?.cancel()
        clearItemObservers()
        standbyStatusObserver?.invalidate()
        timeControlObservers.forEach { $0.invalidate() }
        if let periodicToken, let periodicOwner {
            periodicOwner.removeTimeObserver(periodicToken)
        }
        if let overlapBoundaryToken, let overlapBoundaryOwner {
            overlapBoundaryOwner.removeTimeObserver(overlapBoundaryToken)
        }
    }

    // MARK: - Asset construction

    /// Precise timing is required for reliable seeks in lossless streams.
    private static func assetOptions(headers: [String: String], mimeType: String? = nil) -> [String: Any] {
        var options: [String: Any] = [AVURLAssetPreferPreciseDurationAndTimingKey: true]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        if let mimeType {
            options[AVURLAssetOverrideMIMETypeKey] = mimeType
        }
        return options
    }

    /// Seconds of audio AVPlayer is asked to buffer ahead of the playhead for a remote item. Four
    /// minutes rides out a cellular dead zone, and most songs are then buffered to the end within
    /// seconds of starting. Local files keep the system default (0): they never wait for data.
    nonisolated static let remoteForwardBufferDuration: TimeInterval = 240

    nonisolated static func preferredForwardBufferDuration(for url: URL) -> TimeInterval {
        url.isFileURL ? 0 : remoteForwardBufferDuration
    }

    /// Every item, on either deck, is built here so both get the same buffering policy.
    private static func makeItem(asset: AVURLAsset) -> AVPlayerItem {
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = preferredForwardBufferDuration(for: asset.url)
        return item
    }

    // MARK: - AudioEngine

    @discardableResult
    func play(trackID: String, url: URL, headers: [String: String]) -> AudioEnginePlaybackToken {
        lock.lock()
        defer { lock.unlock() }

        // A Next command may beat the failed item's callback to PlayerService. A failed
        // AVPlayer is terminal: replacing its AVPlayerItem is not enough to revive it.
        if deckA.status == .failed || deckB.status == .failed {
            recreatePlayers()
        }

        if trackID == handedOffTrackID,
           currentItem != nil,
           let currentPlaybackToken {
            handedOffTrackID = nil
            beginPlaying()
            return currentPlaybackToken
        }

        if trackID == preloadedTrackID,
           standbyPreparationState == .ready,
           preloadedItem?.status == .readyToPlay {
            promotePreloaded(startPlaying: true)
            // `preloadedItem` had a token before promotion, so this is an internal invariant rather
            // than a recoverable playback failure.
            return currentPlaybackToken!
        }

        resetDecks()
        let asset = AVURLAsset(url: url, options: Self.assetOptions(headers: headers))
        let item = Self.makeItem(asset: asset)
        attachItemObservers(item)
        currentItem = item
        currentAsset = asset
        currentTrackID = trackID
        currentSourceHeaders = headers
        let playbackToken = makePlaybackToken()
        currentPlaybackToken = playbackToken
        activePlayer.replaceCurrentItem(with: item)
        applyDeckVolumes()
        beginPlaying()
        installReplayGainTapIfNeeded(context: activeContext, trackID: trackID)
        return playbackToken
    }

    func setTrackEndTrim(_ seconds: Double, expectedCurrentTrackID: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let item = currentItem, isCurrentTrackForPreload(expectedCurrentTrackID) else { return }
        guard seconds > 0 else {
            item.forwardPlaybackEndTime = .invalid
            return
        }
        let duration = item.duration.isNumeric ? CMTimeGetSeconds(item.duration) : metadataDuration
        guard duration > seconds else { return }
        // Ending the item early makes AVPlayer post didPlayToEndTime at that point, so the hand-off
        // fires where the music actually stops rather than after the encoder's padding.
        item.forwardPlaybackEndTime = CMTime(seconds: duration - seconds, preferredTimescale: 600)
    }

    func preloadNext(
        trackID: String,
        url: URL,
        headers: [String: String],
        crossfadeDuration: Double,
        leadInTrim: Double,
        replayGainDB: Float,
        expectedCurrentTrackID: String
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard currentItem != nil else { return }
        guard isCurrentTrackForPreload(expectedCurrentTrackID) else {
            Logger.player.debug(
                "[ENGINE] ignored stale preload track='\(trackID, privacy: .public)' expectedCurrent='\(expectedCurrentTrackID, privacy: .public)'"
            )
            return
        }
        if trackID == preloadedTrackID {
            pendingOverlap = crossfadeDuration
            if crossfadeDuration > 0 {
                installTransitionObservers(on: activePlayer)
            } else {
                removeTransitionObservers()
            }
            return
        }
        clearPreloadedDeck()
        let asset = AVURLAsset(url: url, options: Self.assetOptions(headers: headers))
        let item = Self.makeItem(asset: asset)
        standbyPlayer.replaceCurrentItem(with: item)
        preloadedItem = item
        preloadedAsset = asset
        preloadedTrackID = trackID
        preloadedPlaybackToken = makePlaybackToken()
        preloadedSourceURL = url
        preloadedSourceHeaders = headers
        preloadedStartPosition = max(0, leadInTrim)
        standbyPreparationState = .preparing
        pendingOverlap = crossfadeDuration
        if crossfadeDuration > 0 {
            installTransitionObservers(on: activePlayer)
        } else {
            removeTransitionObservers()
        }
        standbyContext.gain = pow(10, replayGainDB / 20)
        applyDeckVolumes()
        installReplayGainTapIfNeeded(context: standbyContext, trackID: trackID)
        // Preroll once ready so the hand-off starts render-tight, and park the playhead past the
        // track's silent lead-in first — seeking after the deck is audible would be heard.
        standbyStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self else { return }
            var failedTrackID: String?
            defer { self.reportStandbyFailure(failedTrackID) }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard item === self.preloadedItem else { return }
            if item.status == .failed {
                Logger.player.warning("[ENGINE] standby preload failed — falling back to a cold transition")
                failedTrackID = self.discardFailedStandby()
                return
            }
            guard item.status == .readyToPlay else { return }
            Logger.player.info(
                "[CROSSFADE] standby item ready track='\(self.preloadedTrackID ?? "unknown", privacy: .public)' overlap=\(self.pendingOverlap, format: .fixed(precision: 1))s"
            )
            if leadInTrim > 0 {
                item.seek(
                    to: CMTime(seconds: leadInTrim, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                ) { [weak self] completed in
                    guard let self else { return }
                    var failedTrackID: String?
                    defer { self.reportStandbyFailure(failedTrackID) }
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    guard item === self.preloadedItem else { return }
                    guard completed else {
                        Logger.player.warning("[ENGINE] standby lead-in seek failed — using cold transition")
                        failedTrackID = self.discardFailedStandby()
                        return
                    }
                    self.prerollStandby(item)
                }
            } else {
                self.prerollStandby(item)
            }
        }
    }

    /// Clears a standby deck that failed to load, seek or preroll. Caller holds `lock` and passes
    /// the returned track to `reportStandbyFailure` once it has unlocked.
    private func discardFailedStandby() -> String? {
        let trackID = preloadedTrackID
        clearPreloadedDeck()
        return trackID
    }

    /// Lets PlayerService retry the preload instead of leaving the next track to start cold.
    private func reportStandbyFailure(_ trackID: String?) {
        guard let trackID else { return }
        delegate?.audioEngineStandbyPreloadDidFail(trackID: trackID)
    }

    /// A preload belongs to the track it follows. After a hand-off the engine has already promoted
    /// that standby deck, so until PlayerService adopts it every preload for the old track is stale.
    /// Caller holds `lock`.
    private func isCurrentTrackForPreload(_ expectedCurrentTrackID: String) -> Bool {
        currentTrackID == expectedCurrentTrackID && handedOffTrackID == nil
    }

    /// `readyToPlay` only means that the item can begin loading. A standby deck becomes eligible
    /// for promotion only after AVPlayer confirms that its media pipeline has actually been primed.
    private func prerollStandby(_ item: AVPlayerItem) {
        guard item === preloadedItem else { return }
        standbyPreparationState = .preparing
        standbyPlayer.preroll(atRate: 1) { [weak self, weak item] succeeded in
            guard let self, let item else { return }
            var failedTrackID: String?
            defer { self.reportStandbyFailure(failedTrackID) }
            self.lock.lock()
            defer { self.lock.unlock() }
            guard item === self.preloadedItem else { return }
            guard succeeded else {
                Logger.player.warning("[ENGINE] standby preroll failed — using cold transition")
                failedTrackID = self.discardFailedStandby()
                return
            }
            self.standbyPreparationState = .ready
            Logger.player.info(
                "[ENGINE] standby preroll completed track='\(self.preloadedTrackID ?? "unknown", privacy: .public)'"
            )
            // The exact overlap boundary may have passed while a slow stream was priming. The
            // periodic fallback computes the remaining playable window and starts safely now.
            if self.pendingOverlap > 0 {
                self.overlapTick()
            }
        }
    }

    func cancelPreload() {
        lock.lock()
        defer { lock.unlock() }
        // A path change can arrive while the standby deck is already audible in a crossfade.
        // Restore the active deck to full volume and stop the ramp before clearing standby;
        // otherwise the orphaned timer would keep fading the only remaining deck to silence.
        cancelOverlap()
        clearPreloadedDeck()
        currentItem?.forwardPlaybackEndTime = .invalid
    }

    func pause() {
        lock.lock()
        defer { lock.unlock() }
        cancelOverlap()
        shouldBePlaying = false
        stopWatchdog()
        activePlayer.pause()
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        // Queued pause callbacks can arrive after this deck already resumed/began buffering.
        // Reasserting play there restarts watchdog/overlap work without helping the connection.
        guard !shouldBePlaying || activePlayer.timeControlStatus == .paused else { return }
        beginPlaying()
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        resetDecks()
    }

    func resetAfterMediaServicesReset() {
        lock.withLock { recreatePlayers() }
    }

    /// Caller holds the lock. Discard both decks, their observers, and all pending work
    /// tied to the old media services. Tokens never restart, even if the same song reloads.
    private func recreatePlayers() {
        let activeGain = activeContext.gain
        timeControlObservers.forEach { $0.invalidate() }
        timeControlObservers.removeAll()
        replayGainTaskA?.cancel()
        replayGainTaskB?.cancel()
        replayGainTaskA = nil
        replayGainTaskB = nil
        replayGainGenerationA &+= 1
        replayGainGenerationB &+= 1
        resetDecks()
        deckA = playerFactory()
        deckB = playerFactory()
        contextA = ReplayGainTapContext()
        contextB = ReplayGainTapContext()
        activeIsA = true
        contextA.gain = activeGain
        configurePlayers()
        applyDeckVolumes()
    }

    func seek(to seconds: Double) async -> Bool {
        let (player, item) = lock.withLock {
            cancelOverlap()
            // A seek moves the playhead on its own; without a fresh baseline the watchdog would read the
            // jump as a frozen clock (or, seeking backwards, as one that never advanced).
            resetWatchdogBaseline()
            didSignalEnd = false
            return (activePlayer, currentItem)
        }

        let finished = await withCheckedContinuation { continuation in
            // Exact seeks avoid approximate time-to-byte mappings on raw FLAC streams.
            player.seek(
                to: CMTime(seconds: seconds, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { completed in
                continuation.resume(returning: completed)
            }
        }

        return lock.withLock {
            finished && item != nil && item === currentItem && player === activePlayer
        }
    }

    var volume: Float {
        get {
            lock.lock()
            defer { lock.unlock() }
            return fadeLevel
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            fadeLevel = newValue
            applyDeckVolumes()
        }
    }

    func applyReplayGain(dB: Float) {
        lock.lock()
        defer { lock.unlock() }
        activeContext.gain = pow(10, dB / 20)
        applyDeckVolumes()
        if currentItem != nil, currentAsset != nil, let trackID = currentTrackID {
            installReplayGainTapIfNeeded(context: activeContext, trackID: trackID)
        }
    }

    var progress: Double {
        lock.lock()
        defer { lock.unlock() }
        let time = activePlayer.currentTime()
        return time.isNumeric ? CMTimeGetSeconds(time) : 0
    }

    var duration: Double {
        lock.lock()
        defer { lock.unlock() }
        guard let duration = currentItem?.duration, duration.isNumeric else { return 0 }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite && seconds > 0 ? seconds : 0
    }

    var isSeekable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentItem?.seekableTimeRanges.isEmpty == false
    }

    var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentItem == nil
    }

    var bufferedDuration: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        guard let ranges = currentItem?.loadedTimeRanges else { return 0 }
        return ranges.reduce(0) { total, value in
            let seconds = CMTimeGetSeconds(value.timeRangeValue.duration)
            return seconds.isFinite ? total + max(0, seconds) : total
        }
    }

    // MARK: - Transition machinery (all called with the lock held)

    /// A boundary observer starts the blend on the media timeline. The low-frequency periodic
    /// observer remains as a fallback when the standby finishes prerolling after that boundary.
    private func installTransitionObservers(on player: AVPlayer) {
        installPeriodicObserver(on: player)
        installBoundaryObserver(on: player)
    }

    private func installPeriodicObserver(on player: AVPlayer) {
        removePeriodicObserver()
        periodicOwner = player
        periodicToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4),
            queue: .main
        ) { [weak self] _ in
            self?.overlapTick()
        }
    }

    private func removePeriodicObserver() {
        if let periodicToken, let periodicOwner {
            periodicOwner.removeTimeObserver(periodicToken)
        }
        periodicToken = nil
        periodicOwner = nil
    }

    private func installBoundaryObserver(on player: AVPlayer) {
        removeBoundaryObserver()
        guard pendingOverlap > 0, let item = currentItem else { return }
        let itemDuration = item.duration.isNumeric ? CMTimeGetSeconds(item.duration) : 0
        let trackDuration = metadataDuration > 0 ? metadataDuration : itemDuration
        guard trackDuration > 0 else { return }
        let boundary = max(0, trackDuration - pendingOverlap)
        let boundaryTime = CMTime(seconds: boundary, preferredTimescale: 600)
        overlapBoundaryOwner = player
        overlapBoundaryToken = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: boundaryTime)],
            queue: .main
        ) { [weak self] in
            self?.overlapTick()
        }
        let current = player.currentTime().isNumeric ? CMTimeGetSeconds(player.currentTime()) : 0
        if current >= boundary {
            overlapTick()
        }
    }

    private func removeBoundaryObserver() {
        if let overlapBoundaryToken, let overlapBoundaryOwner {
            overlapBoundaryOwner.removeTimeObserver(overlapBoundaryToken)
        }
        overlapBoundaryToken = nil
        overlapBoundaryOwner = nil
    }

    private func removeTransitionObservers() {
        removePeriodicObserver()
        removeBoundaryObserver()
    }

    func setTrackDuration(_ seconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        metadataDuration = seconds
        if pendingOverlap > 0, currentItem != nil {
            installBoundaryObserver(on: activePlayer)
        }
    }

    private func overlapTick() {
        lock.lock()
        defer { lock.unlock() }
        guard !isOverlapping, !overlapAwaitingStandbyPlayback, pendingOverlap > 0,
              standbyPreparationState == .ready,
              let preloadedItem, preloadedItem.status == .readyToPlay,
              activePlayer.timeControlStatus == .playing,
              let item = currentItem else { return }
        let itemDuration = item.duration.isNumeric ? CMTimeGetSeconds(item.duration) : 0
        let trackDuration = metadataDuration > 0 ? metadataDuration : itemDuration
        guard trackDuration > 0 else { return }
        let remaining = trackDuration - CMTimeGetSeconds(activePlayer.currentTime())
        guard remaining > 0, remaining <= pendingOverlap else { return }
        requestOverlap()
    }

    /// Requests playback at zero gain. The ramp itself does not start until AVPlayer reports that
    /// the standby deck is genuinely rendering, preventing the outgoing deck from fading into a
    /// buffering incoming stream.
    private func requestOverlap() {
        overlapAwaitingStandbyPlayback = true
        rampStandby = 0
        applyDeckVolumes()
        standbyPlayer.play()
        startOverlapRampIfPossible()
    }

    private func startOverlapRampIfPossible() {
        guard overlapAwaitingStandbyPlayback,
              !isOverlapping,
              standbyPlayer.timeControlStatus == .playing,
              let item = currentItem else { return }
        let itemDuration = item.duration.isNumeric ? CMTimeGetSeconds(item.duration) : 0
        let trackDuration = metadataDuration > 0 ? metadataDuration : itemDuration
        let activePosition = activePlayer.currentTime().isNumeric
            ? CMTimeGetSeconds(activePlayer.currentTime())
            : 0
        let remaining = trackDuration - activePosition
        guard remaining > 0 else { return }

        overlapAwaitingStandbyPlayback = false
        isOverlapping = true
        overlapDuration = min(pendingOverlap, remaining)
        overlapStartedAt = Date()
        Logger.player.info(
            "[CROSSFADE] overlap started duration=\(self.overlapDuration, format: .fixed(precision: 2))s"
        )
        let timer = DispatchSource.makeTimerSource(queue: rampQueue)
        timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in
            self?.overlapRampTick()
        }
        overlapTimer = timer
        timer.resume()
    }

    private func overlapRampTick() {
        var endedTransition: AudioEngineTrackEnd?
        lock.lock()
        defer {
            lock.unlock()
            if let endedTransition {
                delegate?.audioEngineDidReachEndOfTrack(endedTransition)
            }
        }
        guard isOverlapping, overlapTimer != nil else { return }
        guard standbyPlayer.timeControlStatus == .playing else {
            rampActive = 1
            rampStandby = 0
            applyDeckVolumes()
            return
        }
        let standbyTime = standbyPlayer.currentTime()
        let standbyPosition = standbyTime.isNumeric ? CMTimeGetSeconds(standbyTime) : preloadedStartPosition
        let audibleProgress = max(0, standbyPosition - preloadedStartPosition)
        let progress = overlapDuration > 0 ? min(1, audibleProgress / overlapDuration) : 1
        let levels = Self.equalPowerLevels(progress: progress)
        rampActive = levels.outgoing
        rampStandby = levels.incoming
        applyDeckVolumes()
        if progress >= 1 {
            Logger.player.info("[CROSSFADE] overlap completed")
            overlapTimer?.cancel()
            overlapTimer = nil
            // Commit at the end of the blend; the outgoing item’s estimated EOF can arrive later.
            endedTransition = finalizeAdvance()
        }
    }

    nonisolated static func equalPowerLevels(progress: Double) -> (outgoing: Float, incoming: Float) {
        let x = Float(min(1, max(0, progress)))
        return (cos(x * .pi / 2), sin(x * .pi / 2))
    }

    /// Aborts a blend in progress (pause, seek, engine reset): the incoming deck rewinds and stays
    /// preloaded, the active deck returns to full level. The window re-arms via the periodic tick.
    private func cancelOverlap() {
        overlapTimer?.cancel()
        overlapTimer = nil
        let shouldReprepareStandby = isOverlapping || overlapAwaitingStandbyPlayback
        if shouldReprepareStandby {
            isOverlapping = false
            overlapAwaitingStandbyPlayback = false
            overlapStartedAt = nil
            overlapDuration = 0
            standbyPlayer.pause()
            if let item = preloadedItem {
                standbyPreparationState = .preparing
                item.seek(
                    to: CMTime(seconds: preloadedStartPosition, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                ) { [weak self, weak item] completed in
                    guard let self, let item else { return }
                    self.lock.lock()
                    defer { self.lock.unlock() }
                    guard completed, item === self.preloadedItem else { return }
                    self.prerollStandby(item)
                }
            }
        }
        rampActive = 1
        rampStandby = 1
        applyDeckVolumes()
    }

    // MARK: - End-of-track watchdog

    /// Starts the active deck and arms the watchdog. Every path that puts audio back in motion goes
    /// through here so playback intent and the watchdog can never drift apart.
    private func beginPlaying() {
        shouldBePlaying = true
        activePlayer.play()
        startWatchdog()
    }

    private func startWatchdog() {
        watchdogTimer?.cancel()
        resetWatchdogBaseline()
        let timer = DispatchSource.makeTimerSource(queue: rampQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(Self.watchdogInterval),
            repeating: .milliseconds(Self.watchdogInterval)
        )
        timer.setEventHandler { [weak self] in
            self?.watchdogTick()
        }
        watchdogTimer = timer
        timer.resume()
    }

    private func stopWatchdog() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
    }

    private func resetWatchdogBaseline() {
        lastWatchdogTime = -1
        lastWatchdogAdvance = Date()
    }

    /// Handles a missing EOF notification only when playback is intended, the clock has
    /// stopped for the grace period, and the position is within the end-of-file tolerance.
    private func watchdogTick() {
        var endedTransition: AudioEngineTrackEnd?
        lock.lock()
        defer {
            lock.unlock()
            if let endedTransition {
                delegate?.audioEngineDidReachEndOfTrack(endedTransition)
            }
        }
        guard shouldBePlaying, !didSignalEnd, let item = currentItem else { return }

        let itemDuration = item.duration.isNumeric ? CMTimeGetSeconds(item.duration) : 0
        let trackDuration = metadataDuration > 0 ? metadataDuration : itemDuration
        // A live stream has no length to compare against, so it is never "finished".
        guard trackDuration > 0 else { return }

        let time = activePlayer.currentTime()
        let position = time.isNumeric ? CMTimeGetSeconds(time) : 0

        if position > lastWatchdogTime + 0.05 {
            lastWatchdogTime = position
            lastWatchdogAdvance = Date()
            return
        }
        // `position > 0` keeps a track that never started (still opening the stream, failed to load)
        // out of this path — that is an error for PlayerService to handle, not a finished track.
        let remaining = trackDuration - position
        guard position > 0,
              Date().timeIntervalSince(lastWatchdogAdvance) >= Self.frozenClockGrace,
              remaining >= -Self.endOfFileTolerance,
              remaining <= Self.endOfFileTolerance else { return }

        let reading = String(format: "%.2fs of %.2fs", position, trackDuration)
        Logger.player.warning(
            "[ENGINE] end-of-track watchdog fired — AVPlayer never reported EOF (\(reading, privacy: .public))"
        )
        endedTransition = finalizeAdvance()
    }

    /// Promotes standby before notifying PlayerService; the subsequent play call adopts that deck.
    @discardableResult
    private func finalizeAdvance() -> AudioEngineTrackEnd? {
        // The notification, the crossfade ramp and the watchdog all land here, and any two of them can
        // fire for the same track — one advance per item.
        guard !didSignalEnd, let endedPlaybackToken = currentPlaybackToken else { return nil }
        let endedTime = activePlayer.currentTime()
        let endedPosition = endedTime.isNumeric ? max(0, CMTimeGetSeconds(endedTime)) : 0
        didSignalEnd = true
        guard standbyPreparationState == .ready,
              let preloadedItem, preloadedItem.status == .readyToPlay,
              let trackID = preloadedTrackID,
              let promotedPlaybackToken = preloadedPlaybackToken,
              let sourceURL = preloadedSourceURL else {
            clearPreloadedDeck()
            return AudioEngineTrackEnd(
                endedPlaybackToken: endedPlaybackToken,
                endedPosition: endedPosition,
                promotedPlayback: nil
            )
        }
        let wasOverlapping = isOverlapping
        let incomingTime = standbyPlayer.currentTime()
        let incomingPosition = incomingTime.isNumeric
            ? max(preloadedStartPosition, CMTimeGetSeconds(incomingTime))
            : preloadedStartPosition
        let promotedPlayback = AudioEnginePromotedPlayback(
            playbackToken: promotedPlaybackToken,
            trackID: trackID,
            sourceURL: sourceURL,
            sourceHeaders: preloadedSourceHeaders,
            startedAt: overlapStartedAt ?? Date(),
            position: incomingPosition,
            audibleDuration: wasOverlapping ? max(0, incomingPosition - preloadedStartPosition) : 0
        )
        handedOffTrackID = trackID
        promotePreloaded(startPlaying: !wasOverlapping)
        return AudioEngineTrackEnd(
            endedPlaybackToken: endedPlaybackToken,
            endedPosition: endedPosition,
            promotedPlayback: promotedPlayback
        )
    }

    private func promotePreloaded(startPlaying: Bool) {
        overlapTimer?.cancel()
        overlapTimer = nil
        isOverlapping = false
        overlapAwaitingStandbyPlayback = false
        overlapDuration = 0
        overlapStartedAt = nil
        clearItemObservers()
        standbyStatusObserver?.invalidate()
        standbyStatusObserver = nil
        activePlayer.pause()
        activePlayer.replaceCurrentItem(with: nil)
        activeContext.tapInstalled = false
        activeIsA.toggle()
        currentItem = preloadedItem
        currentAsset = preloadedAsset
        currentTrackID = preloadedTrackID
        currentSourceHeaders = preloadedSourceHeaders
        currentPlaybackToken = preloadedPlaybackToken
        preloadedItem = nil
        preloadedAsset = nil
        preloadedTrackID = nil
        preloadedPlaybackToken = nil
        preloadedSourceURL = nil
        preloadedSourceHeaders = [:]
        preloadedStartPosition = 0
        standbyPreparationState = .idle
        pendingOverlap = 0
        metadataDuration = 0
        rampActive = 1
        rampStandby = 1
        applyDeckVolumes()
        if let item = currentItem {
            attachItemObservers(item)
        }
        // The promoted deck carries on playing: either it was started here, or it has been audible
        // since the crossfade began. Either way the new item starts its own end-detection cycle.
        didSignalEnd = false
        shouldBePlaying = true
        if startPlaying {
            activePlayer.play()
        }
        startWatchdog()
        removeTransitionObservers()
    }

    private func resetDecks() {
        removeTransitionObservers()
        overlapTimer?.cancel()
        overlapTimer = nil
        isOverlapping = false
        overlapAwaitingStandbyPlayback = false
        overlapDuration = 0
        overlapStartedAt = nil
        shouldBePlaying = false
        didSignalEnd = false
        stopWatchdog()
        clearItemObservers()
        standbyStatusObserver?.invalidate()
        standbyStatusObserver = nil
        deckA.pause()
        deckB.pause()
        deckA.cancelPendingPrerolls()
        deckB.cancelPendingPrerolls()
        deckA.replaceCurrentItem(with: nil)
        deckB.replaceCurrentItem(with: nil)
        currentItem = nil
        currentAsset = nil
        currentTrackID = nil
        currentSourceHeaders = [:]
        currentPlaybackToken = nil
        preloadedItem = nil
        preloadedAsset = nil
        preloadedTrackID = nil
        preloadedPlaybackToken = nil
        preloadedSourceURL = nil
        preloadedSourceHeaders = [:]
        preloadedStartPosition = 0
        standbyPreparationState = .idle
        handedOffTrackID = nil
        pendingOverlap = 0
        metadataDuration = 0
        rampActive = 1
        rampStandby = 1
        contextA.tapInstalled = false
        contextB.tapInstalled = false
        applyDeckVolumes()
    }

    /// Clears only the standby role. Caller holds `lock`.
    private func clearPreloadedDeck() {
        removeTransitionObservers()
        standbyStatusObserver?.invalidate()
        standbyStatusObserver = nil
        standbyPlayer.pause()
        standbyPlayer.cancelPendingPrerolls()
        standbyPlayer.replaceCurrentItem(with: nil)
        standbyContext.tapInstalled = false
        preloadedItem = nil
        preloadedAsset = nil
        preloadedTrackID = nil
        preloadedPlaybackToken = nil
        preloadedSourceURL = nil
        preloadedSourceHeaders = [:]
        preloadedStartPosition = 0
        standbyPreparationState = .idle
        overlapAwaitingStandbyPlayback = false
        overlapDuration = 0
        overlapStartedAt = nil
        pendingOverlap = 0
    }

    /// Caller holds `lock`.
    private func makePlaybackToken() -> AudioEnginePlaybackToken {
        nextPlaybackTokenRawValue &+= 1
        return AudioEnginePlaybackToken(rawValue: nextPlaybackTokenRawValue)
    }

    private func applyDeckVolumes() {
        activePlayer.volume = fadeLevel * rampActive * activeContext.deckVolumeScale
        standbyPlayer.volume = fadeLevel * rampStandby * standbyContext.deckVolumeScale
    }

    // MARK: - Per-item observers

    private func attachItemObservers(_ item: AVPlayerItem) {
        clearItemObservers()
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self, item.status == .failed else { return }
            let failure = AudioEngineFailure(error: item.error)
            if self.retryUnidentifiedMedia(failedItem: item, failure: failure) { return }
            let playbackToken = self.lock.withLock {
                item === self.currentItem ? self.currentPlaybackToken : nil
            }
            guard let playbackToken else { return }
            self.reportFailure(failure, of: item, playbackToken: playbackToken)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            guard let self else { return }
            self.lock.lock()
            // A queued EOF from the retired deck must not advance the newly promoted track.
            let endedTransition: AudioEngineTrackEnd? = if let item, item === self.currentItem {
                self.finalizeAdvance()
            } else {
                nil
            }
            self.lock.unlock()
            if let endedTransition {
                self.delegate?.audioEngineDidReachEndOfTrack(endedTransition)
            }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] note in
            guard let self else { return }
            let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            let failure = AudioEngineFailure(error: error)
            let playbackToken: AudioEnginePlaybackToken? = self.lock.withLock {
                guard let item, item === self.currentItem else { return nil }
                return self.currentPlaybackToken
            }
            guard let item, let playbackToken else { return }
            self.reportFailure(failure, of: item, playbackToken: playbackToken)
        }
    }

    // MARK: - Unidentified container recovery

    /// Reopens a stream AVFoundation could not identify, naming its container from the bytes.
    ///
    /// AVFoundation picks a decoder from the server's Content-Type and the URL's file extension.
    /// Subsonic stream URLs have no extension, and some servers send FLAC as `audio/x-flac` or
    /// `application/octet-stream`, so the load fails at once. The retry runs only after that
    /// specific failure, so streams that already work are never touched.
    /// Returns true when the failure is being handled and must not be reported yet.
    private func retryUnidentifiedMedia(failedItem: AVPlayerItem, failure: AudioEngineFailure) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard failure.isUnidentifiedMedia,
              failedItem === currentItem,
              let token = currentPlaybackToken,
              mimeRecoveryToken != token,
              let url = (currentAsset as? AVURLAsset)?.url,
              ["http", "https"].contains(url.scheme?.lowercased()) else { return false }
        mimeRecoveryToken = token
        let headers = currentSourceHeaders
        Task.detached { [weak self] in
            let mimeType = await Self.sniffedMIMEType(of: url, headers: headers)
            self?.finishUnidentifiedMediaRetry(
                token: token, url: url, headers: headers, mimeType: mimeType, failure: failure
            )
        }
        return true
    }

    private func finishUnidentifiedMediaRetry(
        token: AudioEnginePlaybackToken,
        url: URL,
        headers: [String: String],
        mimeType: String?,
        failure: AudioEngineFailure
    ) {
        lock.lock()
        guard token == currentPlaybackToken, let failedItem = currentItem, let trackID = currentTrackID else {
            lock.unlock()
            return
        }
        guard let mimeType else {
            lock.unlock()
            Logger.player.warning("[ENGINE] stream container could not be identified; reporting the original failure")
            delegate?.audioEngineDidError(failure, playbackToken: token)
            return
        }
        Logger.player.info("[ENGINE] reopening stream as \(mimeType, privacy: .public) after an unidentified container")
        let asset = AVURLAsset(url: url, options: Self.assetOptions(headers: headers, mimeType: mimeType))
        let item = Self.makeItem(asset: asset)
        item.forwardPlaybackEndTime = failedItem.forwardPlaybackEndTime
        attachItemObservers(item)
        currentItem = item
        currentAsset = asset
        activeContext.tapInstalled = false
        activePlayer.replaceCurrentItem(with: item)
        applyDeckVolumes()
        if shouldBePlaying { beginPlaying() }
        installReplayGainTapIfNeeded(context: activeContext, trackID: trackID)
        lock.unlock()
    }

    /// Reads the first bytes of the stream and names its container. Nil when unreachable or unknown.
    private static func sniffedMIMEType(of url: URL, headers: [String: String]) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("bytes=0-\(AudioContainer.magicPrefixLength - 1)", forHTTPHeaderField: "Range")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        guard let (bytes, response) = try? await URLSession.shared.bytes(for: request, delegate: OriginScopedRedirectDelegate()),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else { return nil }
        // A server that ignores Range sends the whole file; stop after the prefix either way.
        var prefix: [UInt8] = []
        do {
            for try await byte in bytes {
                prefix.append(byte)
                if prefix.count >= AudioContainer.magicPrefixLength { break }
            }
        } catch { return nil }
        return AudioContainer.sniff(magic: prefix)?.mimeType
    }

    /// Adds the item's last error-log code, which often carries the HTTP or CoreMedia status, then
    /// reports the failure. iOS 27 only offers the log asynchronously, so the delegate is called from
    /// AVFoundation's completion queue rather than the notification queue.
    private func reportFailure(_ failure: AudioEngineFailure, of item: AVPlayerItem, playbackToken: AudioEnginePlaybackToken) {
        item.fetchErrorLog { [weak self] log in
            let logCode = log?.events.last.map {
                AudioEngineFailure.Code(domain: $0.errorDomain, value: $0.errorStatusCode)
            }
            self?.delegate?.audioEngineDidError(failure.adding(logCode: logCode), playbackToken: playbackToken)
        }
    }

    private func clearItemObservers() {
        statusObserver?.invalidate()
        statusObserver = nil
        for observer in [endObserver, failObserver].compactMap({ $0 }) {
            NotificationCenter.default.removeObserver(observer)
        }
        endObserver = nil
        failObserver = nil
    }

    // MARK: - ReplayGain tap install

    private func installReplayGainTapIfNeeded(context: ReplayGainTapContext, trackID: String) {
        let previousTask: Task<Void, Never>?
        if context === contextA {
            previousTask = replayGainTaskA
        } else {
            previousTask = replayGainTaskB
        }
        previousTask?.cancel()

        // Whether a fold-down is needed depends on the track's channel count, known only once loaded.
        guard Self.requiresAudioTap(linearGain: context.gain) || DownmixParameters.shared.isEnabled else { return }
        // `item` and `asset` are intentionally not captured by the Task: both are non-Sendable
        // Objective-C references. The asynchronous worker resolves them from the locked engine state.
        let request = makeReplayGainInstallRequest(context: context, trackID: trackID)
        let task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await self?.performReplayGainTapInstall(request)
        }
        switch request.deck {
        case .a:
            replayGainTaskA = task
        case .b:
            replayGainTaskB = task
        }
    }

    /// Creates a request for the physical deck represented by `context`. Caller holds `lock`.
    private func makeReplayGainInstallRequest(
        context: ReplayGainTapContext,
        trackID: String
    ) -> ReplayGainInstallRequest {
        if context === contextA {
            replayGainGenerationA &+= 1
            return ReplayGainInstallRequest(
                deck: .a,
                trackID: trackID,
                generation: replayGainGenerationA
            )
        } else {
            replayGainGenerationB &+= 1
            return ReplayGainInstallRequest(
                deck: .b,
                trackID: trackID,
                generation: replayGainGenerationB
            )
        }
    }

    /// Loads the audio track without holding the engine lock, then revalidates deck identity before
    /// mutating AVPlayerItem. A preload promotion can legitimately swap roles during the `await`.
    @MainActor
    private func performReplayGainTapInstall(_ request: ReplayGainInstallRequest) async {
        let asset = lock.withLock {
            replayGainTarget(for: request)?.asset
        }
        guard let asset else { return }

        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            guard !Task.isCancelled else { return }
            Logger.player.warning(
                "[REPLAYGAIN] no audio track available for '\(request.trackID, privacy: .public)'"
            )
            return
        }
        guard !Task.isCancelled else { return }
        let formats = (try? await track.load(.formatDescriptions)) ?? []
        guard !Task.isCancelled else { return }
        let channelCount = formats.first
            .flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame }
            .map(Int.init) ?? 2
        let channelLabels = formats.first.flatMap(DownmixMatrix.channelLabels(of:))

        let installed = lock.withLock {
            guard let target = replayGainTarget(for: request),
                  Self.requiresAudioTap(linearGain: target.context.gain, channelCount: channelCount),
                  !target.context.tapInstalled,
                  let tap = Self.makeReplayGainTap(context: target.context, channelLabels: channelLabels) else { return false }

            let params = AVMutableAudioMixInputParameters(track: track)
            params.audioTapProcessor = tap
            let mix = AVMutableAudioMix()
            mix.inputParameters = [params]
            target.item.audioMix = mix
            target.context.tapInstalled = true
            applyDeckVolumes()
            return true
        }
        if installed {
            Logger.player.info(
                "[REPLAYGAIN] audio tap installed for '\(request.trackID, privacy: .public)'"
            )
        }
    }

    /// Resolves a physical deck after checking both its request generation and current logical role.
    /// Caller holds `lock`.
    private func replayGainTarget(
        for request: ReplayGainInstallRequest
    ) -> (item: AVPlayerItem, asset: AVAsset, context: ReplayGainTapContext)? {
        let context: ReplayGainTapContext
        let generation: UInt64
        switch request.deck {
        case .a:
            context = contextA
            generation = replayGainGenerationA
        case .b:
            context = contextB
            generation = replayGainGenerationB
        }
        guard generation == request.generation else { return nil }

        if context === activeContext,
           currentTrackID == request.trackID,
           let currentItem,
           let currentAsset {
            return (currentItem, currentAsset, context)
        }
        if context === standbyContext,
           preloadedTrackID == request.trackID,
           let preloadedItem,
           let preloadedAsset {
            return (preloadedItem, preloadedAsset, context)
        }
        return nil
    }

    nonisolated static func requiresReplayGainTap(linearGain: Float) -> Bool {
        linearGain > 1
    }

    /// A ReplayGain boost, the equalizer, an attached visualiser or a multichannel track to fold down
    /// needs the tap.
    nonisolated static func requiresAudioTap(linearGain: Float,
                                             equalizerEnabled: Bool = EqualizerParameters.shared.isEnabled,
                                             visualizerAttached: Bool = VisualizerTap.shared.isAttached,
                                             channelCount: Int = 2,
                                             downmixEnabled: Bool = DownmixParameters.shared.isEnabled) -> Bool {
        requiresReplayGainTap(linearGain: linearGain) || equalizerEnabled || visualizerAttached
            || (downmixEnabled && channelCount > 2)
    }

    /// Turning the equalizer on, or attaching a visualiser, mid-song installs the tap on the playing
    /// and preloaded items. Turning it off leaves installed taps in place; they pass audio through unchanged.
    private func equalizerSettingsDidChange() {
        lock.withLock {
            guard EqualizerParameters.shared.isEnabled || VisualizerTap.shared.isAttached else { return }
            installMissingTaps()
        }
    }

    /// Turning the fold-down on mid-song installs the tap on multichannel items. Turning it off
    /// leaves installed taps in place; they pass every channel through.
    private func downmixSettingsDidChange() {
        lock.withLock {
            guard DownmixParameters.shared.isEnabled else { return }
            installMissingTaps()
        }
    }

    /// Caller holds `lock`. Each install checks for itself whether its item needs a tap.
    private func installMissingTaps() {
        if let trackID = currentTrackID, !activeContext.tapInstalled {
            installReplayGainTapIfNeeded(context: activeContext, trackID: trackID)
        }
        if let trackID = preloadedTrackID, !standbyContext.tapInstalled {
            installReplayGainTapIfNeeded(context: standbyContext, trackID: trackID)
        }
    }

    nonisolated static func replayGainDeckVolumeScale(linearGain: Float, tapInstalled: Bool) -> Float {
        tapInstalled ? 1 : min(linearGain, 1)
    }

    private static func makeReplayGainTap(
        context: ReplayGainTapContext,
        channelLabels: [AudioChannelLabel]?
    ) -> MTAudioProcessingTap? {
        let storage = AudioTapStorage(context: context, channelLabels: channelLabels)
        let clientInfo = UnsafeMutableRawPointer(Unmanaged.passRetained(storage).toOpaque())
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: replayGainTapInit,
            finalize: replayGainTapFinalize,
            prepare: audioTapPrepare,
            unprepare: nil,
            process: replayGainTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            // Balance the passRetained above — finalize will never run for a failed create.
            Unmanaged<AudioTapStorage>.fromOpaque(clientInfo).release()
            return nil
        }
        return tap
    }
}

// MARK: - ReplayGain audio tap

/// Shared between the engine and the realtime render callback. The Float bit pattern is atomic so
/// the callback never takes a lock and the access remains valid under Swift's memory model.
private nonisolated final class ReplayGainTapContext: @unchecked Sendable {
    private let gainBits = Atomic<UInt32>(Float(1).bitPattern)
    private let tapInstalledBits = Atomic<UInt8>(0)
    /// This deck's copy of its tap output for the visualiser. Allocated here, off the render thread.
    let visualizer = VisualizerTap.shared.makeRing()

    var gain: Float {
        get { Float(bitPattern: gainBits.load(ordering: .relaxed)) }
        set { gainBits.store(newValue.bitPattern, ordering: .relaxed) }
    }

    var tapInstalled: Bool {
        get { tapInstalledBits.load(ordering: .relaxed) == 1 }
        set { tapInstalledBits.store(newValue ? 1 : 0, ordering: .relaxed) }
    }

    var deckVolumeScale: Float {
        AVPlayerEngine.replayGainDeckVolumeScale(linearGain: gain, tapInstalled: tapInstalled)
    }
}

private nonisolated func replayGainTapInit(
    tap: MTAudioProcessingTap,
    clientInfo: UnsafeMutableRawPointer?,
    tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

/// One per tap: the deck's ReplayGain context, shared across that deck's items, and the
/// fold-down, equalizer and limiter state, which belong to this tap's item alone. Both decks read
/// the same shared settings, so during a crossfade each one is levelled and limited alike.
private nonisolated final class AudioTapStorage: @unchecked Sendable {
    let context: ReplayGainTapContext
    let downmix: StereoDownmixProcessor
    let equalizer = EqualizerProcessor()
    let limiter = PeakLimiter()

    init(context: ReplayGainTapContext, channelLabels: [AudioChannelLabel]?) {
        self.context = context
        downmix = StereoDownmixProcessor(labels: channelLabels)
    }
}

private nonisolated func replayGainTapFinalize(tap: MTAudioProcessingTap) {
    Unmanaged<AudioTapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private nonisolated func audioTapPrepare(
    tap: MTAudioProcessingTap,
    maxFrames: CMItemCount,
    processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    let storage = Unmanaged<AudioTapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let format = processingFormat.pointee
    let channels = Int(format.mChannelsPerFrame)
    let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
    storage.downmix.prepare(channels: channels, interleaved: interleaved)
    storage.equalizer.prepare(sampleRate: format.mSampleRate, channels: channels, interleaved: interleaved)
    storage.limiter.prepare(sampleRate: format.mSampleRate, channels: channels, interleaved: interleaved)
    storage.context.visualizer.sampleRate = format.mSampleRate
}

private nonisolated func replayGainTapProcess(
    tap: MTAudioProcessingTap,
    numberFrames: CMItemCount,
    flags: MTAudioProcessingTapFlags,
    bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    let storage = Unmanaged<AudioTapStorage>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
    let buffers = UnsafeMutableAudioBufferListPointer(bufferListInOut)
    let frames = Int(numberFramesOut.pointee)
    // Copies the final samples, after the limiter; returns at once with no visualiser attached.
    defer { storage.context.visualizer.write(buffers, frames: frames) }
    // Fold down first, so the equalizer, gain and limiter work on what is actually heard.
    storage.downmix.process(buffers, frames: frames)
    storage.equalizer.process(buffers, frames: frames)
    var gain = storage.context.gain
    if gain != 1.0 {
        // Tap audio is 32-bit float; a flat multiply is correct whether channels are interleaved or not.
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
            let samples = data.assumingMemoryBound(to: Float.self)
            vDSP_vsmul(samples, 1, &gain, samples, 1, vDSP_Length(count))
        }
    }
    storage.limiter.process(buffers, frames: frames)
}
