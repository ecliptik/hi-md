# Memory audit: 2026-10-25

**Summary:** 0 CRITICAL, 1 HIGH, 4 MEDIUM, 11 LOW. No retain cycles were found.

This was static analysis of the `fix/navidrome-placeholder` checkout; nothing was profiled. The Winamp skin loader, the visualiser ring buffers and the Mac target aren't in this checkout and weren't audited.

Health: LEAKING by the rubric, but only because of `LidarrImageStore`. Fixing that one finding moves it to NEEDS ATTENTION.

## Ownership map

- **AVPlayerEngine:** its `deinit` tears everything down. That covers the timers, observers, KVO and the tap storage, whose retain and release are balanced.
- **PlayerService:** about 13 tasks and 4 session observers. It has no `deinit`, which is fine because it lives as long as the app.
- **AppContainer:** its `deinit` cancels its own tasks but not those of the widget publisher, Spotlight indexer, prefetcher or Watch bridge. That's fine while the container is created only once.
- **View-scoped:** `LyricsViewModel` (released when the player collapses) and the FullPlayerView state.
- **Combine:** none is used.

| Metric | Value |
|---|---|
| Ownership coverage | About 10 of 17 owners have teardown. The rest last as long as the app. |
| Timers | 2 DispatchSourceTimers, both cancelled. About 6 task-loop timers, all with stop paths. |
| Observers | 8 added and 3 removed; the 5 not removed are on app-lifetime objects with `[weak self]`. 5 KVO added, 5 invalidated. 2 time observers added, 2 removed. |
| Tasks | About 45 stored, about 60% with cancel paths |
| Unbounded collections | 1 significant (`LidarrImageStore`) and 2 moderate |

## Regression check against audit-all-2026-10-20

| Previous | Status |
|---|---|
| H1 `ArtworkLoader` cache unbounded | Fixed: NSCache with 40 entries and 24 MB, and the log line is redacted |
| H2 `LidarrImageStore` unbounded | Still present (H-1) |
| M1 `ArtworkImageCache` count cap with no memory-warning handling | Still present (M-1) |
| M2 ListenBrainz offline queue unbounded | Still present (M-4) |
| M3 a URLSession per SwiftSonic client | Still present, now confirmed in SwiftSonic's source (M-2) |
| X12 a task per song in playlist downloads | Still present (L-1) |
| `DominantColorExtractor` | Still present (L-6) |

**New findings:**
- M-3: the lyrics view model isn't handed over on a track change.
- L-2 and L-3: AI recommendation tasks.
- L-8: the logo's memory footprint.

**New code that's clean:**
- The logo's TimelineView pauses when it isn't spinning.
- The easter-egg state is freed when the player collapses.
- The lyrics keep-alive releases the view model on a track change.

## HIGH

### H-1. `LidarrImageStore.shared` caches every Lidarr cover forever

- **Where:** `Views/Lidarr/LidarrCoverImage.swift:5-11, 34-40`.
- **Problem:** a singleton `[String: UIImage]` with no cap, no eviction and no memory-warning handling. Memory grows with every cover browsed in a session, to tens or hundreds of MB.
- **Fix:** an `NSCache` with `countLimit` 120 and `totalCostLimit` 48 MB, costed by pixel size. Better still, downsample with ImageIO before storing.

| Urgency | Blast radius | Effort | ROI |
|---|---|---|---|
| Soon | Lidarr users during long browsing sessions | S | High |

## MEDIUM

### M-1. `ArtworkImageCache` is capped only by entry count, and nothing responds to memory pressure

- **Where:** `ArtworkImageCache.swift:159-161, 983-990`.
- **Problem:** the cap is 110 entries, but a hero cover is about 5.8 MB, so the cache can exceed 100 MB. There's no `didReceiveMemoryWarning` handling.
- **Fix:** a cost limit, plus a memory-warning observer that trims hero covers.

### M-2. A new URLSession is created for every SwiftSonic client and every AI client

- **Where:** `CustomHeadersTransport.swift:13-20`, `ServerConnection.swift:42-57`, `AIRecommendationCloudClient.swift:16-25`.
- **Problem:** `URLSessionTransport` creates a session and never invalidates it. Clients are made per call in many places:
  - every download job (`DownloadQueueController.swift:256`);
  - the reachability probe, every 3 s while offline (`NetworkMonitor.swift:62`);
  - the prefetcher, PlayerService, MediaResolver, LyricsService and MusicIntentService;
  - the AI recommender, including each Test Connection.

  This causes connection, file-descriptor and TLS churn.
- **Fix:** cache one client per connection version in ServerService, as `LibraryService` and `PlaylistService` already do, and use one shared session for the AI client.

### M-3. Lyrics tracking stops after a track change while the lyrics panel is open

- **Where:** `FullPlayerView.swift:99-108, 216-222`, `LyricsView.swift:28-30`, `LyricsViewModel.swift:165-181`.
- **Problem:** this comes from the keep-alive change. The new view model replaces the old one while `LyricsView` stays on screen, so `onAppear` doesn't fire again and `setVisible(true)` is never called. The highlight and auto-scroll freeze until the panel is reopened.
- **Fix:** do what `KaraokeLyricsView` does: `.onChange(of: ObjectIdentifier(viewModel), initial: true)` hands the visible state to the new view model. Or give `LyricsView` an `.id` keyed to its view model. Add a test that the visible count stays balanced across the swap.

### M-4. The ListenBrainz offline queue is uncapped and rewritten in full on every enqueue

- **Where:** `ListenBrainzService.swift:556-577, 607-625`.
- **Problem:** the whole queue is sent as one batch.
- **Fix:** cap it (for example 5,000 entries, dropping the oldest), send it in chunks of about 1,000, and append to a journal instead of rewriting the file.

## LOW

| # | Finding | Where |
|---|---|---|
| L-1 | One unstructured task per song in a playlist download. Batch it through `DownloadQueueController.enqueue`. | `PlaylistService.swift:258-262, 308-312` |
| L-2 | AI recommendation loads from buttons and `onDismiss` aren't cancelled; they can overlap and race. Keep the load task and cancel it, or use `.task(id:)`. | `AIRecommendationsView.swift:55, 80, 85, 127, 131` |
| L-3 | Saving the API key builds a task chain and writes to the keychain on every keystroke. Debounce it. | `AIRecommender.swift:76-84` |
| L-4 | `ArtistDetailViewModel` starts an uncancelled task that captures `self` strongly. | `ArtistDetailViewModel.swift:204` |
| L-5 | `ArtworkImageCache` bookkeeping maps (`missingArtwork`, `coverGenerations`, `revalidationDeferred`) are never pruned. They are tiny. | `ArtworkImageCache.swift:182, 193, 196, 772-774` |
| L-6 | `DominantColorExtractor` caches grow without limit, and it creates a `CIContext` per call. | `DominantColorExtractor.swift:17-24, 146, 185-195` |
| L-7 | Small unbounded caches: PlaylistService detail cache, artist info, track resolver, external artist images, ListenBrainz recommendations. | various |
| L-8 | `MinidiscLogoView` decodes three 1280 px layers (about 19 MB) even when shown at 72 pt. Ship smaller layers, or use the thumbnail when it isn't spinning. | `MinidiscLogoView.swift`, `SettingsView.swift:185` |
| L-9 | `transitionArtwork` keeps one hero image alive after the player closes. Set it to nil after the collapse. | `PlayerContainer.swift:21, 165` |
| L-10 | App-lifetime services never remove their observers or loops (PlayerService, PhoneWatchBridge, WidgetSnapshotPublisher, SpotlightIndexer, UpcomingSongsPrefetcher). This would leak if the container were ever rebuilt, for example when switching servers. Add `stop()` and `deinit`. | various |
| L-11 | Minor: a `Task.detached` MIME sniff isn't cancelled; Wrapped's `longPressTask` isn't cancelled; a cancelled lyrics load becomes an error. | `AVPlayerEngine.swift:1029-1034`, `WrappedStoryPlayerView.swift:24-25`, `LyricsViewModel.swift:60-79` |

## Recommendations

1. **Now:** H-1, a bounded `LidarrImageStore`.
2. **Short term:**
   - M-3: the lyrics view-model handoff. It's a regression and cheap to fix.
   - M-1: memory-warning trimming.
   - M-2: one SwiftSonic client per connection.
   - M-4: ListenBrainz queue cap.
3. **Longer term:** L-10 teardown, L-2 cancellation, L-5 to L-7 cache caps, L-8 smaller logo layers.
4. **Re-audit after the Mac and Winamp merge:**
   - storage balance for the second tap;
   - ring-buffer ownership across tap prepare, unprepare and finalize;
   - the lifetime of skin CGImages;
   - tap install on both decks.
5. **Instruments:**
   - Allocations and Leaks across 30 skips, with lyrics open and then hidden.
   - Allocation generations while browsing 200 Lidarr covers, then 200 hero covers.
   - Live URLSession count during a 200-song download.
   - The Memory Graph after dismissing the full player.
