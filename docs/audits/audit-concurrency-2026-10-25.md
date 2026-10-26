# Concurrency audit: 2026-10-25

**Summary:** 1 CRITICAL (compound), 3 HIGH, 11 MEDIUM, 11 LOW. Readiness: NOT READY.

This was a static audit of the `fix/navidrome-placeholder` checkout; nothing was built or run under the Thread Sanitizer. The visualiser tap and analyser weren't in this checkout; a pre-merge checklist is at the end.

## Isolation map

- **Defaults:** MainActor default isolation, approachable concurrency, strict concurrency `complete`, Swift 6.0.
- **Actors:** about 50 actors.
  - `PlayerService`, `NowPlayingService`, `ArtworkLoader`, `DownloadService`, `MediaResolver`, `LibraryService` and `LocalMusicStore` are actors.
  - `ArtworkImageCache`, `NowPlayingCenterPresenter`, `LyricsViewModel`, `AppContainer`, `WidgetSnapshotPublisher` and `SpotlightIndexer` are on the MainActor.
- **Audio engine:** `AVPlayerEngine` is a `nonisolated @unchecked Sendable` class guarded by an `NSRecursiveLock`.
  - The tap callbacks are nonisolated free functions using atomics and preallocated EQ buffers.
  - `AudioEngineBridge` creates one Task per engine event.
- **Entry points:** about 351 `Task {}` sites, with only 2 structured ones. `@concurrent` is used in 6 files.
- **Cancellation:** stored tasks are cancelled by stop helpers. `PlayerService` has no `deinit`, which is fine because it lives as long as the app.

| Metric | Value |
|---|---|
| Isolation coverage | About 100% by default. Engine and tap code is explicitly nonisolated. |
| Structured concurrency | Under 5% |
| Escape hatches | 10 `@unchecked Sendable` (up from 6), 0 `@preconcurrency`, 0 `nonisolated(unsafe)` |
| Cancellation coverage | About 85% |
| GCD | 13 `main.asyncAfter` sheet-sequencing sites. The engine's ramp queue and the network monitor's queue are legitimate. |

## Regression check against audit-all-2026-10-20

| Previous | Status |
|---|---|
| H1 launch waits on session restore plus an artwork fetch | Still present (H1) |
| H2 30 s local-music rescan | Fixed: now 120 s, and gated |
| H3 per-track SwiftData recount on the MainActor | Fixed: targeted recounts |
| H4 launch-time SwiftData and file I/O on the MainActor | Still present (H2) |
| H5 a task per song in downloads, using `try?` | Still present, now CRITICAL (C1) |
| M1 unordered Task per engine event | Still present (M1) |
| M2 restore-pause Task re-entrancy | Still present (M2) |
| M3 uncancelled Task in ArtistDetailViewModel | Still present (M10) |
| M4 optimistic update with rollback across an await | Still present (M7) |
| M6 `ModelContext` in plain actors | Still present (M8) |
| M7 CoverRevalidationStore file I/O on the MainActor | Still present (M9) |
| M9 playlist retry before a connection exists | Still present (M11) |
| `@unchecked Sendable` count (positive in the last audit) | Regressed: 10, up from 6 |

**New:** H3, M3, M4, M5, M6, L1, L5, L6, L7, L8, L11.

## CRITICAL

### C1. An unstructured task per song, with errors swallowed

- **Where:** `PlaylistService.swift:258-262, 308-312`.
- **Problem:** `for song in addedSongs { Task { try? await download(...) } }`, and the same in `retryMissingPlaylistDownloads`, which runs on every launch. That is 500 racing tasks for 500 songs, with no handle and no error handling. Songs fail silently.
- **Fix:** add a batch download API that returns the failures, and log them.

| Urgency | Blast radius | Effort | ROI |
|---|---|---|---|
| Soon | Adding playlists, and every launch | S–M | High |

## HIGH

| ID | Finding | Where | Fix |
|---|---|---|---|
| H1 | **Launch waits on session restore, which waits on a network artwork fetch.** On a cold launch, `NowPlayingService.update` goes to `ArtworkLoader`, a network call with a 10 s timeout, without checking disk first. Siri and App Intents wait too. | `MinidiscApp.swift:231`, `PlayerService.swift:2332-2390, 2476-2505`, `NowPlayingService.swift:100-126` | Don't await the artwork during restore, or check disk first. |
| H2 | **Launch does SwiftData and file I/O on the MainActor:** cover garbage collection fetches every download entity, plus cover-cache invalidation and the audio-extension migration. | `MinidiscApp.swift:256-285`, `AppContainer.swift:409-423, 471-520` | Compute the referenced IDs with a `@concurrent` context, and make the migrations nonisolated. |
| H3 | **Gapless: a failed preload is never retried, and the preload runs inside the progress tick.** `prefetchScheduled = true` is set before the preload. If `resolveSource` throws, it returns without clearing the flag, so there is no standby deck and the next track starts cold with a gap. A slow resolve also blocks the progress tick (position, scrobbling, Now Playing). | `PlayerService.swift:3154-3161, 3219-3222, 3343-3390, 3380, 3416-3419` | Clear the flag on every failed exit, with a retry budget. Run the preload as a stored task outside the tick, cancelled by `cancelPendingPrefetch()`. |

## MEDIUM

1. **M1. One unordered Task per engine event.** Very short tracks, or an end event followed by a state event, can arrive out of order (`PlayerService.swift:4796-4812`). Use an `AsyncStream` with a single consumer.
2. **M2. Restore-pause re-entrancy.** The task clears its own handle before awaiting, so a `resume()` in that window gets overwritten by "paused" (`PlayerService.swift:3752-3763`). Re-check the token after each await, and clear the handle last.
3. **M3. A stale preload can land after the engine has already promoted that track.** `preloadNext` and `setTrackEndTrim` don't check the current track (`PlayerService.swift:3442-3464`, `AVPlayerEngine.swift:274-314, 795-881`). Pass `expectedCurrent` and have the engine ignore mismatches. Cancel the preload when committing the hand-off.
4. **M4. The engine lock is held while calling AVFoundation**, whose KVO and notification callbacks take the same lock (`AVPlayerEngine.swift:36`). No deadlock was found. Confirm with the Thread Sanitizer and Thread Performance Checker through a crossfade, a skip during the overlap, and a media-services reset.
5. **M5. The hero cover is JPEG-encoded on the MainActor on every track change** (`NowPlayingCenterPresenter.swift:113`). Pass encoded data instead.
6. **M6. CPU work on the MainActor:**
   - placeholder detection in `ArtworkImageCache.swift:476, 569`
   - the Spotlight fingerprint (`SpotlightIndexer.swift:60-67, 107-113`)
   - the Watch thumbnail render (`PhoneWatchBridge.swift:75-96`)
7. **M7. Optimistic favourite and playlist updates roll back across awaits**, so overlapping calls can undo each other (`FavoritesService.swift:32-81`, `PlaylistService.swift:79-233`).
8. **M8. `ModelContext` is used in plain actors, and SwiftData runs inside `MainActor.run`** (`AudioStreamCache`, `PlaybackSessionService`, `FavoritesService`, `DownloadService.swift:332, 349, 598, 727, 845`). Use `@ModelActor`.
9. **M9. CoverRevalidationStore does synchronous file I/O on the MainActor.**
10. **M10. `ArtistDetailViewModel` starts an uncancelled, sequential task** (`:204-212`).
11. **M11. The playlist retry starts in `AppContainer.init`**, before a connection exists (`AppContainer.swift:276-279`).

## LOW

1. **L1. The render thread** (otherwise correct):
   - `EqualizerProcessor.refreshIfNeeded` takes a `Mutex` after settings change.
   - A lazy static (`Equalizer.frequencies`) is first touched on the render thread; touch it in `prepare`.
   - `takeUnretainedValue()` costs a retain and release per buffer.
   - Better: publish the coefficients through an atomic double buffer.
2. **L2. Escape hatches:**
   - `ReplayGainTapContext` can be checked `Sendable`.
   - The two Watch delegates could use `weak let` (SE-0481).
   - Add migration notes for `SendableArtworkImage`.
3. **L3. `Task.detached` at 9 sites doesn't propagate cancellation.** Use `@concurrent` functions instead.
4. **L4. `setAppVisible` is fire-and-forget,** so quick scene changes can arrive out of order. It's harmless for timing.
5. **L5. ReplayGain is applied to the still-audible old deck before `engine.play`** (`PlayerService.swift:662`). Apply it after play, or pass it into `play`.
6. **L6. Endless `for await` loops keep running after their owner is gone** (WidgetSnapshotPublisher, SpotlightIndexer, UpcomingSongsPrefetcher, PhoneWatchBridge, CarPlayController). Use `guard let self else { break }`.
7. **L7. LyricsViewModel:**
   - `load()` turns a cancellation into an error. Catch `CancellationError`.
   - Rapid line taps send seeks out of order.
8. **L8. Mac guards:**
   - The AppKit branches are dead code under Catalyst; the native Mac target uses them now.
   - The MediaPlayer remote-command closures may inherit the MainActor. Check at runtime, or mark them `@Sendable`.
9. **L9. 13 `DispatchQueue.main.asyncAfter` sheet sequencings.** Use `Task.sleep` or `onDismiss`.
10. **L10. PlayerService observers are never removed.** `BackgroundActivity` ends early when cancelled.
11. **L11. The isolation of the NowPlaying (iOS 27) closures is unverified.** Mark them `@Sendable`, or build them in nonisolated static factories.

## Verdicts by area

| Area | Verdict |
|---|---|
| Audio tap and engine | No allocation or lock on the steady render path. Tap retains and releases are balanced. Deck-role swaps are validated. Open: L1, M3, M4. |
| ArtworkImageCache | Sound: all MainActor, guarded by epoch and generation. Open: M6. `hasNoArtwork` ignores the recheck deadline, so a `no-store` stand-in counts as missing until a real image arrives. That's a logic issue, not a data race. |
| ArtworkLoader | Fine. It has its own cache, so a cover can be fetched twice. |
| NowPlayingService | A correct generation pattern for re-entrancy. Cost: M5. |
| PlayerService progress loop | Cancellable. Risks: H3 and L4. Overlapping ticks can both schedule a preload; the engine removes the duplicate. |
| Gapless and crossfade risks | H3, M1, M2, M3, M4, L5. The engine's own transition code is consistent. |

## Pre-merge checklist for the visualiser tap

1. A single-producer, single-consumer ring with atomic indexes, preallocated in `prepare`.
2. One ring per tap, because both decks' taps run during a crossfade, owned by `AudioTapStorage`.
3. No allocation, logging, locks, awaits or actor calls on the render path.
4. `@unchecked Sendable` only on the raw-pointer ring, with a comment documenting its contract.
5. Keep `requiresAudioTap` and `replayGainDeckVolumeScale` consistent, so gain isn't applied twice or skipped.
6. A single cancellable consumer task, with no strong `self`.
7. The analyser never calls into the engine while the engine holds its lock.

## Recommendations

1. **Now:**
   - C1: batch downloads.
   - H3: preload retry, moved outside the tick. This is the most valuable fix for gapless.
   - H1: don't make launch wait on artwork.
   - H2: launch work off the MainActor.
2. **Short term:**
   - M1: ordered engine events.
   - M2: restore-pause.
   - M3: an idempotent preload.
   - M4: a Thread Sanitizer run through crossfades.
   - M5 and M6: move CPU work off the MainActor.
   - L2: drop the unnecessary `@unchecked`.
3. **Longer term:**
   - L3: `@concurrent` instead of detached tasks.
   - M8 and M9: `@ModelActor`.
   - L9: replace `asyncAfter`.
   - L6: stop the `for await` loops when the owner is gone.
   - L8 and L11: check closure isolation at runtime.
