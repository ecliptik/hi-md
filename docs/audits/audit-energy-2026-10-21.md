# Energy audit: 2026-10-21

This is a static analysis of `main` at f8f505f by the Axiom energy-auditor. Nothing was built, run or profiled, so every drain figure is an estimate and needs confirming with Power Profiler. The three HIGH findings were spot-checked against the source.

**Result:** 0 CRITICAL, 3 HIGH, 11 MEDIUM and 12 LOW. Health is rated *wasteful*, with an estimated 2–4 %/hour above the audio baseline (unmeasured).

Items marked **Engine** touch the two-deck gapless/crossfade path. Run the gapless and crossfade regression tests before shipping any of them.

## Energy profile

- **Background modes:** `audio` and `processing` are both used. `processing` runs a daily `BGProcessingTask` (`MinidiscApp.swift:56-63`) that doesn't require external power.
- **Audio session:** deactivated on pause, stop and end of queue (`PlayerService.swift:1566, 1801, 3645`). The progress and save loops stop with it.
- **Steady wakeups while playing:** about 5 per second, all with the screen off.
  - Progress loop, 500 ms (`PlayerService.swift:3139-3148`).
  - Engine watchdog, 500 ms (`AVPlayerEngine.swift:727-740`).
  - Now Playing push, about 1 s (`PlayerService.swift:4084-4102`).
  - Position save, 15 s.
  - None of these timers sets tolerance or leeway.
- **Timers near a track change:**
  - A 0.25 s periodic observer runs only in the last roughly 15 s plus crossfade length of each track (`AVPlayerEngine.swift:529-538`).
  - A 50 ms ramp runs only during the crossfade itself.
- **Network:** event-driven. There is no polling of Home, scan status, Lidarr, AudioMuse or AI recommendations. The heavy users are the stream cache, the upcoming-song prefetcher, the offline-favourites sync and the launch-time playlist retry.
- **Widgets, Live Activity and Watch:**
  - Widget timelines use `.never` and reload only when the snapshot changes.
  - The Live Activity updates once per song.
  - Watch messages are debounced 400 ms.
- **GPU:** the MeshGradient animations are gated on `systemPrefersReducedResourceUsage`.
- **Low Power Mode and thermal state:** never checked. A grep finds no `isLowPowerModeEnabled` or `thermalState` anywhere.

## Status of the energy findings from audit-all-2026-10-20

| Prior finding | Status |
|---|---|
| 30 s local-music rescan rewrites `index.json` | Fixed. It now runs every 120 s, foreground only, and skips the write when nothing changed. |
| 8–12 wakeups per second with no tolerance | Still present. Re-measured at about 5/s, plus 4/s in each track's tail (H1, H2, M1, M2). |
| Offline-favourites sync on every foreground | Still present (M3). |
| MeshGradient animations never stop | Mostly fixed. They are now gated on Low Power Mode and Reduce Motion (L9). |
| Streamed tracks downloaded a second time | Still present (H3). |
| Launch-time playlist retry with no cellular gating | Still present (M6). |
| Wrapped story loop runs at 20 Hz | Still present (M9). |
| Now Playing rewritten about every 1 s | Still present (H2). |
| Lyrics and marquee loops | Lyrics fixed. Marquee still present (L12). |
| Position save every 15 s; whole queue re-encoded per track | Still present (M10). |
| Download journal rewrites are O(n²) | Partly fixed. Enqueue is batched, but state changes still rewrite the whole journal (M6). |
| DominantColorExtractor rewrites its UserDefaults dictionary | Still present (L6). |
| Daily BG processing task | Still present (L8). |

## HIGH

| ID | Finding | Location | Fix effort | Engine? |
|---|---|---|---|---|
| H1 | Progress loop wakes at 2 Hz, with about 6 actor hops and an audio-route query on every tick | `PlayerService.swift:3139-3195` | S/M | Adjacent |
| H2 | The whole Now Playing dictionary is rewritten every second | `PlayerService.swift:4084-4102`, `NowPlayingCenterPresenter+MediaPlayer.swift:118-130` | S | No |
| H3 | Every streamed song is downloaded a second time 30 s in, ignoring Low Data and Low Power Mode | `PlayerService.swift:749-788, 3932-4045, 285-289` | S/M | No |

**H1. Progress loop.** Each 500 ms tick:
- reads the engine's progress and duration;
- queries `currentAudioRouteOutputs()`;
- writes the position to state;
- accumulates scrobble time and checks the scrobble threshold;
- checks whether to prefetch the next song;
- checks whether Now Playing needs a push.

Nothing adapts when the screen is off or the app is in the background.

Fix:
- Use `Task.sleep(for: .milliseconds(500), tolerance: .milliseconds(250))`.
- Cache the route outputs and refresh them only on `routeChangeNotification`.
- Batch the MainActor reads into one hop.
- In the background, tick every 1 s. If you do, raise `PlaybackProgressTracker.maximumContinuousDelta` from 2 s to about 3 s so scrobble time isn't lost.

Gapless note: `checkPrefetchThreshold` schedules the standby preload when `remaining <= crossfade + 15 s`. A 1 s background tick leaves plenty of margin. Keep the foreground tick at 500 ms.

**H2. Now Playing push.** Each push reads the whole `nowPlayingInfo` dictionary, artwork included, and writes it back over IPC. iOS already extrapolates elapsed time from a rate of 1.0, so the periodic push is unnecessary.

Fix: push only on play, pause, seek, track change or rate change, or when the reported position drifts more than 2 s. Keep the push from the transition path (`PlayerService.swift:821`) so metadata stays correct after a gapless or crossfade hand-off.

**H3. Second download of streamed songs.** Thirty seconds into any streamed track, the whole file is fetched again into the stream cache while AVPlayer is still streaming it. There is no setting to turn this off. `cacheSession` sets neither `allowsConstrainedNetworkAccess = false` nor a Low Power Mode check, unlike the prefetcher and the favourites sync.

Fix:
- Skip the download on constrained paths and in Low Power Mode.
- Add a "cache streamed songs" setting, or limit caching to songs the user replays.
- Keep the guard that cancels this download before a transition (`:3302-3339`). Preloading a cached next song is faster and helps gapless.

## MEDIUM

- **M1 (Engine). Watchdog timer has no leeway.**
  - Where: `AVPlayerEngine.swift:727-740`. A 500 ms `DispatchSourceTimer` for the whole of playback.
  - Fix: `leeway: .milliseconds(250)`. That is safe against the 1.0 s and 1.5 s grace windows. Don't go past about 400 ms.
- **M2 (Engine). 0.25 s periodic observer on the main queue in each track's tail.**
  - Where: `AVPlayerEngine.swift:529-538`, installed from `preloadNext`. It is a fallback for the boundary observer.
  - Fix: install it only when the boundary fires before the standby deck is ready.
  - Risk: a late tick shortens the fade (`overlapDuration = min(pendingOverlap, remaining)`). This has the lowest payoff of the engine items; do it last or skip it.
- **M3. Offline-favourites sync is too eager.**
  - Where: `MinidiscApp.swift:103-108, 117-121`; `OfflineFavoritesSync.swift:97-199`.
  - Problem: on by default, and re-runs on every foreground and every network-path change, because the whole `networkPathEvent` is part of the task key. Each run makes N+14 sequential requests.
  - Fix: skip a run within about 15 minutes of the last successful sync. Key on online and expensive status only, skip in Low Power Mode, and fetch albums with limited concurrency.
- **M4. Upcoming-song prefetcher.**
  - Where: `UpcomingSongsPrefetcher.swift:42-99`.
  - Problem: fully downloads the next 3 songs after each track change, with no Low Power Mode check. Any edit to the queue restarts it and throws away partial downloads.
  - Fix: in Low Power Mode, keep only the next song (index +1), which helps gapless. Observe only the 3-song window.
- **M5. No Low Power Mode or thermal policy.** Add a small `PowerPolicy` that observes `NSProcessInfoPowerStateDidChange` and `thermalStateDidChangeNotification`. Feed it into prefetch, caching, sync, the playlist retry and timer cadence. Don't let it change crossfade behaviour.
- **M6. Playlist download retry on every launch.**
  - Where: `AppContainer.swift:276-279`, `PlaylistService.swift:280-314`.
  - Problem: the retry runs on a non-discretionary session that allows cellular, spawns one Task per song, and rewrites the whole journal on every state change (`DownloadQueueController.swift:262, 320, 336, 348-350`).
  - Fix: gate the retry on a non-expensive, non-constrained path outside Low Power Mode, and cap it per launch. Write the journal only on enqueue and completion, or make it append-only.
- **M7. Sleep timer polls once a second for up to 90 minutes.**
  - Where: `SleepTimer.swift:52-64`.
  - Fix: sleep until `endsAt - fadeDuration`, then run the 250 ms fade loop.
  - Keep the fade steps unchanged: they share `applyDeckVolumes` with the crossfade ramp.
- **M8. Karaoke lyrics keep the screen on while paused.**
  - Where: `KaraokeLyricsView.swift:41-46, 58`. The idle timer is disabled on appear, behind a full-screen `blur(60)`.
  - Fix: disable the idle timer only while playing, and restore it after about 2 minutes without interaction. Use a static image when `systemPrefersReducedResourceUsage` is on.
- **M9. Wrapped story loop runs at 20 Hz while paused or on the last slide.**
  - Where: `WrappedStoryPlayerView.swift:250-261`.
  - Fix: one sleep or animation per slide.
- **M10. Session writes.**
  - Where: `PlayerService.swift:3110-3130, 826`; `PlaybackSession.swift:61`.
  - Problem: the position is saved every 15 s, and the whole queue is JSON-encoded on every track start.
  - Fix: save the position every 60 s; the scenePhase flushes already cover app kills. Store the queue only when it changes, and keep the index separate.
- **M11 (Engine). Equalizer tap is installed even when the EQ is flat.**
  - Where: `AVPlayerEngine.swift:1237-1281`. `requiresAudioTap` uses `isEnabled` rather than `isAudible`. The CPU render callback blocks hardware offload.
  - Fix: install the tap only when `isAudible` or when ReplayGain needs a boost.
  - Test: EQ on to off across a gapless transition, and a tapped/untapped pair across a crossfade.

## LOW

- **L1 (Engine).** The 50 ms crossfade ramp has no leeway. Leave it; at most add 10 ms.
- **L2.** While the server is unreachable, it's pinged every 60 s with no backoff, including during background playback (`NetworkMonitor.swift:87, 166-190`). Back off to 2 and then 5 minutes.
- **L3 (Engine).** `AVURLAssetPreferPreciseDurationAndTimingKey` is set on every stream (`AVPlayerEngine.swift:202`). It may cause extra range requests for VBR MP3. Measure before changing it, because it affects duration accuracy and trim.
- **L4.** The widget snapshot is rebuilt and `reloadAllTimelines` runs on every track change and every backgrounding (`WidgetSnapshotPublisher.swift:49-71`). Reload only the now-playing widget kind.
- **L5.** The Watch bridge renders artwork per track even when no Watch app is installed (`PhoneWatchBridge.swift:41-86`). Check `isWatchAppInstalled` first.
- **L6.** `DominantColorExtractor` rewrites its whole UserDefaults dictionary for each new cover (`:185-195`). Debounce the writes.
- **L7.** Spotlight fetches the full library and fingerprints it on every backgrounding (`SpotlightIndexer.swift:45-79`). Skip it when the library revision is unchanged.
- **L8.** The daily BG processing task has no `requiresExternalPower` (`MinidiscApp.swift:56-63`). Set it, with a 3–7 day `earliestBeginDate`.
- **L9.** Several Wrapped MeshGradient cards animate at once. Animate only the visible card.
- **L10.** Audio-recovery polling runs at 100 ms but is bounded to about 56 s per incident. Consider 250 ms.
- **L11.** The local-music folder is rescanned every 2 minutes in the foreground. Rescan only on scene activation and pull-to-refresh.
- **L12.** The marquee title animation ignores Low Power Mode. ListenBrainz retries have no backoff.

## Recommended order

1. **Immediate.** These are small fixes, and none touches the engine:
   - H2: remove the periodic Now Playing push.
   - H3: add the constrained-network and Low Power gates, plus a setting.
   - H1: add tolerance, cache the route, and run a 1 s cadence in the background.
2. **Short term:**
   - M1: add watchdog leeway (engine; safe).
   - M10: save the position every 60 s.
   - M7: make the sleep timer sleep until the fade window.
   - M3 and M6: gate the favourites sync and the playlist retry.
   - M8: tie Karaoke's idle-timer lock to playback.
   - M11: install the EQ tap only when audible (engine).
3. **Longer term:**
   - M5: a `PowerPolicy`.
   - M6: restructure the download journal.
   - L4, L5 and L7: trim the widget, Watch and Spotlight publishers.
4. **Verify** with Power Profiler on the device: a 1-hour session with the screen locked, FLAC over Wi-Fi, EQ off and on, crossfade off and on. Compare wakeups per second and network bytes before and after.

## Keep

- The audio session is deactivated on pause.
- Widgets reload only when their content changes.
- Publishers are debounced.
- Prefetch and favourites downloads respect constrained and expensive networks.
- The stream-cache download is cancelled before the standby preload starts.
- Lyrics tracking is gated on visibility.
- Animations respect `systemPrefersReducedResourceUsage`.
