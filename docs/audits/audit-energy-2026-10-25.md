# Energy audit: 2026-10-25

**Summary:** 0 CRITICAL, 0 HIGH, 13 MEDIUM, 14 LOW. Of these, 2 MEDIUM and 2 LOW are new since 2026-10-21; the rest are carried over. Health: WASTEFUL. Estimated drain is about 1–2 %/hour above the audio baseline; this is a static estimate, not a measurement.

The audit was run on the `fix/navidrome-placeholder` checkout. It covers `Minidisc/`, `MinidiscWidgets/`, `MinidiscWatch/`, `Shared/` and `WatchShared/`. The code was read, not run or profiled.

**Not covered yet:** the visualiser tap and analyser, the native Mac target and the Winamp window. They live on `feat/macos-app`, `feat/mac-ui` and `feat/winamp-window`, and are covered by the pre-merge checklist at the end.

## Energy profile

- **Background modes:** `audio` and `processing`, both in use. One `BGProcessingTask`.
- **Audio session:** deactivated on pause, stop and end of queue.
- **Timers while playing:**
  - Progress tick: 500 ms with 100 ms tolerance, or 1 s with 500 ms tolerance in the background.
  - Engine watchdog: 500 ms, no leeway.
  - Position save: every 15 s.
  - Lyrics tracking: every 250 ms, only while lyrics are showing.
  - Tail observer: every 0.25 s.
  - Crossfade ramp: every 50 ms.
- **Display-linked work:**
  - `MinidiscLogoView`: TimelineView, paused when not spinning.
  - The animated gradient hero and mesh gradients: gated.
  - The marquee: gated on Reduce Motion only.
  - Wrapped story loop: 20 Hz.
- **Network:** event-driven. The heavy users are the stream cache, the prefetcher (3 songs), the offline-favourites sync, the launch playlist retry and the AI recommendation call. The unreachable-server ping runs every 60 s with no backoff.
- **Low Power and thermal state:** consulted only by the stream-cache gate.

| Metric | Value |
|---|---|
| Timer discipline | 9 periodic timers or loops while playing. Only the progress loop has tolerance. All are cancelled on stop. |
| Location | Not used |
| Network efficiency | 6 patterns. 3 respect Low Data. 2 respect Low Power. |
| Animation lifecycle | 6 sources. 5 stop when hidden. |
| Background modes | 2 registered, 2 used |
| Estimated idle drain | About 1–2 %/hour above the audio baseline. More with lyrics left open on a locked screen (N1). |

## Regression check against audit-energy-2026-10-21

| Previous | Status |
|---|---|
| H1 progress loop | Fixed, by commit 28a629c: the cadence depends on app visibility and has tolerance, and the per-tick route lookup is gone. A residue of 3 MainActor hops per tick remains; it is low value. |
| H2 Now Playing push | Fixed: it pushes only on drift, a duration change or a new anchor. |
| H3 duplicate stream download | Fixed: it skips on cellular (unless allowed), Low Data or Low Power, and the session doesn't use constrained networks. A "Save songs as they play" toggle was added, on by default. The Low Power check runs once, at the 30 s mark. |
| M1 watchdog without leeway | Still present: `AVPlayerEngine.swift:727-740` |
| M2 0.25 s tail observer | Still present: `AVPlayerEngine.swift:529-538` |
| M3 favourites sync too eager | Still present: `OfflineFavoritesSync.swift:9-23`, `MinidiscApp.swift:103-125` |
| M4 upcoming-song prefetcher | Partly fixed: it now skips Low Data, but has no Low Power check |
| M5 no power or thermal policy | Still present |
| M6 launch playlist retry | Still present: `AppContainer.swift:276-279`, `PlaylistService.swift:280-314` |
| M7 sleep timer polls every 1 s | Still present: `SleepTimer.swift:62` |
| M8 Karaoke disables the idle timer even when paused | Still present: `KaraokeLyricsView.swift:41-46` |
| M9 Wrapped 20 Hz loop | Still present: `WrappedStoryPlayerView.swift:250-261` |
| M10 position saved every 15 s | Still present: `PlayerService.swift:3123-3132` |
| M11 EQ tap installed when the EQ is on but flat | Still present: `AVPlayerEngine.swift:1237-1247`. Use `isAudible`. |
| L1–L12 | Still present, except: L4 is slightly worse (it also reloads controls), L7 is partly mitigated (fingerprint), and the L12 ListenBrainz retry is bounded, so closed |

## New: MEDIUM

### N1. Lyrics tracking keeps running in the background

- **Where:** `LyricsViewModel.swift:165-196`, `LyricsView.swift:28-30`, `KaraokeLyricsView.swift:35-40`.
- **Problem:** tracking runs while a lyrics view is mounted. Locking the screen doesn't unmount it, so with lyrics left open the 250 ms loop (no tolerance) keeps waking the main actor about 4 times a second.
- **Fix:** pass `scenePhase` to the view model and stop tracking unless the app is active. Better still, sleep until the next line's start time, with tolerance, instead of polling.

### N2. AI recommendations call the provider on every screen open

- **Where:** `AIRecommendationsView.swift:84-85, 199-208`, `AIRecommender.swift:97-141`, `AIRecommendationCloudClient.swift:10-23`.
- **Problem:** the results are view state, so every visit builds the profile, reads the whole library twice and makes one request. That request has `maxTokens` of 8192, a 90 s timeout, and no Low Data or Low Power gating. On Apple Intelligence it is an on-device model run instead.
- **Fix:**
  - Keep the last result, with its provider and a timestamp, and show it on open. Refresh only on request or after a time-to-live.
  - Read the library once.
  - Set `allowsConstrainedNetworkAccess = false` on the session.

## New: LOW

### N3. The spinning logo runs at the full refresh rate

- **Where:** `MinidiscLogoView.swift:16-31`.
- **Problem:** the TimelineView has no `minimumInterval`, so it can run at 120 Hz on ProMotion screens while redrawing three 1280 px layers. It ignores `systemPrefersReducedResourceUsage`.
- **Fix:** cap it at 30 fps, gate it on reduced resource usage, ship smaller image variants, and keep the shadow off the animating view.

### N4. Missing-artwork rechecks

- **Where:** `ArtworkImageCache.swift`, `ServerPlaceholderArtwork`.
- **Good:** there is no timer; rechecks are lazy.
- **Problems:**
  - `no-store` stand-ins are re-downloaded on every cell appearance.
  - Placeholder detection, a 32×32 draw, runs on the main actor for every cover.
  - The `missingArtwork` map is never pruned.
- **Fix:**
  - Back off for `no-store` answers: 30 s, then 2 minutes.
  - Run detection inside the detached decode task.
  - Prune old entries.

## Carried over: MEDIUM

M1, M2, M3, M5, M6, M7, M8, M9, M10 and M11, plus M4 (partly fixed), as in the regression table. The fixes are in the 2026-10-21 report.

## Compound findings

- **N1 with the 1 s background progress loop:** about 7 wakeups per second with lyrics left open on a locked screen. This becomes HIGH if that is common.
- **Prefetch and favourites sync with no Low Power gate:** the largest network consumers on battery.

## Visualiser, Winamp and Mac: pre-merge checklist

1. The visualiser tap is installed only while a consumer is attached, and removed with the last one.
2. The 30 fps FFT runs only while it is on screen, the app is active and audio is playing, and not in Low Power Mode.
3. Nothing on the audio thread allocates or locks: a lock-free ring, with the FFT off the audio thread.
4. Explicit 30 fps frame pacing. No 120 Hz timeline on the Mac.
5. The Winamp window goes idle when occluded, minimised or on another Space (`NSWindow.occlusionState`). Check App Nap.
6. Run the gapless and crossfade tests with the tap toggled across transitions.

## Recommendations

1. **Now:**
   - N1: lyrics tracking stops when the app is inactive and sleeps until the next line.
   - N2: cache AI results.
2. **Short term:**
   - M1: watchdog leeway.
   - M7: sleep timer.
   - M10: save the position every 60 s.
   - M3, M4, M6: Low Power and path gating.
   - M8: Karaoke idle timer.
   - M11: EQ tap only when audible. This touches the engine; test gapless and crossfade.
3. **Longer term:**
   - M5: one PowerPolicy feeding prefetch, caching, sync, timers and decorative animations, without changing crossfade.
   - N3: logo spin cap.
   - L4, L5, L7: widget, Watch and Spotlight publishers.
4. **Verify on a device with Power Profiler:** one hour with the screen locked, with EQ and crossfade each off and on. Repeat with lyrics open, and with the visualiser attached and detached.

## Keep

- Session deactivation on pause and stop.
- The visibility-dependent progress cadence.
- Now Playing pushing only on drift.
- The stream-cache gating.
- Debounced widget and Watch publishing.
- Fingerprinted Spotlight indexing.
- Gated mesh gradients.
- The logo timeline pausing when not spinning.
- The lyrics `visibleCount` logic.
- A cache with no timers, and revalidation deferred while offline.
