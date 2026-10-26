# Swift performance audit: 2026-10-25

**Summary:** 1 CRITICAL, 7 HIGH, 9 MEDIUM, 8 LOW (25 issues). Health: BOTTLENECKED, because of the CRITICAL in a hot path, offline search scoring.

All costs are estimates; nothing was measured with Instruments. The audit was run on the `fix/navidrome-placeholder` checkout.

**Not covered:** the visualiser tap, the FFT analyser, the M3U parser, the ZIP reader and skin decoding. They live on `feat/macos-app`, `feat/winamp-window` and `feat/mac-ui`. Re-audit them after merging; the checks to make are listed at the end.

## Hot paths

| Path | Notes |
|---|---|
| Audio render tap: `AVPlayerEngine.swift:1260-1364`, `Equalizer.swift:114-225` | Realtime-safe: atomics, preallocated buffers, `vDSP_vsmul`. One `takeUnretainedValue()` retain/release per callback. A scalar 10-band biquad loop, about 1% CPU (estimated). |
| Artwork cache | On the MainActor, and `ServerPlaceholderArtwork.matches` runs there too (HIGH). |
| Search | Ranking is recomputed in the view body, with normalisation inside the sort comparator (CRITICAL and HIGH). |
| PlayerService | Queue-wide map and Set work on each track change (HIGH). |
| Value types | `DisplayableSong` has 21 fields, about 9 of them refcounted strings. SwiftSonic `Song` and `AlbumID3` are large. There are no `borrowing` or `consuming` annotations. |
| Library index | JSON payload decoded per row. Smart search pages the whole library. |
| Actor hops | Per-song awaits in loops that could be batched (HIGH). |

| Metric | Value |
|---|---|
| Value-type efficiency | About 6 large structs, 0 annotated. Mostly copy-on-write. |
| ARC discipline | 86 weak-self sites. A sample of about 20 were all appropriate. |
| Generic specialisation | 0 existential collections in hot paths |
| Collection efficiency | LRU arrays use O(n) `removeAll`. `reserveCapacity` is used once. |
| Actor efficiency | 5 per-item hop loops, 0 batched |
| Hot-path cleanliness | 3 of 10 clean: the render tap, the lyrics tick and the cache core |

## CRITICAL

### Offline search scores the whole downloaded library inside a sort comparator, inside a view body

- **Where:** `Views/Main/SearchView.swift:160-169, 188`; `Models/Domain/LibrarySearchMatch.swift:72-77, 80-97`.
- **Problem:** `offlineMatches` is evaluated on every body pass, on every keystroke and on the MainActor. It works like this:
  - Every downloaded song, album, artist and playlist is wrapped.
  - Each one is scored in `.filter`.
  - Each is scored again twice per comparison in `.sorted`, about 2·n·log₂n calls.
  - Each `score` call re-normalises the query and the title with `folding`, `components`, `filter` and `joined`.
- **Impact:** about 10,000 score calls for 500 items (150–300 ms), and seconds for 5,000.
- **Fix:**
  - Normalise the query once.
  - Store normalised titles in the offline snapshot.
  - Score each element once (decorate, sort, undecorate).
  - Memoise the result in `SearchViewModel`, keyed by query and snapshot revision.

| Urgency | Blast radius | Effort | ROI |
|---|---|---|---|
| Now | Offline users searching large downloads | S–M | High |

## HIGH

| # | Finding | Where | Fix | Status |
|---|---|---|---|---|
| H1 | Online search ranking re-normalises inside the comparator. `matches` is a computed property read twice per body (once directly, once through `selectableSongs`). Up to 350 candidates is about 6,000 score calls per evaluation. | `LibrarySearchMatch.swift:64-97`, `SearchViewModel.swift:27-30`, `SearchView.swift:171-176, 188, 192` | Store the ranked results in the view model, recompute only when the inputs change, and score once per element. | Carried over (was H6) |
| H2 | `ServerPlaceholderArtwork.matches` runs on the MainActor for every cover read from disk and every network fetch. Each call creates a CGContext, looks up the colour space, makes a 1024-element `[Pixel]` and about 8 temporary arrays (about 70 KB of churn per cover). The disk check exists only to purge files saved by older builds. | `ArtworkImageCache.swift:476, 569`, `CoverArtView.swift:129`, `ServerPlaceholderArtwork.swift:35-121` | Run it inside the detached decode task. Bump the cover-store version once to wipe old files, then drop the disk-hit check. Make the colour space a static, and compute in one pass with accumulators. | New |
| H3 | The download queue rewrites the whole journal once per scheduled job and on each failure. `publish()` sorts every job on every progress event. `id(for:)` is a linear scan inside `enqueue` (O(N²)). | `DownloadQueueController.swift:129, 244, 262, 314, 336, 345, 353` | Persist once per scheduling pass and debounce writes. Keep a key-to-UUID index. Keep the snapshot ordered incrementally, or throttle publishing to about 2 Hz. | Partly fixed (was H3) |
| H4 | Per-song actor hops: `isDownloaded` per song, favourites `localURL` per song, and `playlist(id:)` per playlist. A batch API already exists (`downloadedSongIds`). | `LibraryService.swift:271-279`, `DownloadQueueController.swift:118-123`, `OfflineBrowsingLibrary.swift:91-104` | Fetch the ID set once and add batch lookups. | Carried over (was H4) |
| H5 | The whole queue is JSON-encoded and rewritten through SwiftData on every `saveSession`, even when only the index changed (16 call sites). A new `JSONEncoder` is made each time. | `PlaybackSession.swift:33, 61`, `PlaybackSessionService.swift:14-29`, `PlayerService.swift:2319-2330` | Save the queue only when it changes (use a generation number). Save the index and position cheaply. Store IDs only, and reuse the encoder. | Carried over (was H2) |
| H6 | O(queue) work on the MainActor around every track change: `state.queue.map(\.id)` comparisons, and `evaluateAutoExtend` builds `Set(queue ids)` before its guards. | `PlayerService.swift:497, 502, 1411-1413` | Run the cheap guards first, and compare queues by generation number. | Carried over (was H1) |
| H7 | `OfflineLibraryReader` fetches all rows from every server and then filters in memory, inside `MainActor.run`. `downloadedSongIds` also checks the file system per track. | `OfflineLibraryReader.swift:36-175` | Use `#Predicate { $0.serverId == serverId }` and a ModelContext owned by an actor. | Carried over (was H5) |

## MEDIUM

1. **Smart search normalises its search terms once per song and decodes the whole library.**
   - Where: `LibraryQuery.swift:51-109`, `SmartSearchService.swift:46-58`.
   - Fix: prepare the query once, and move year, starred and played into SQL predicates.
2. **Local search encodes and decodes its JSON twice more** (three passes in all), plus three `localizedStandardContains` scans per keystroke.
   - Where: `LibraryCatalog.swift:483-490`, `LibraryIndexStore.swift:710-744`.
   - Fix: build `SearchResult3` directly.
3. **Track-order comparators normalise strings inside the sort.**
   - Where: `LibraryIndexStore.swift:1021-1034`.
   - Fix: sort on precomputed keys, or use the existing `sortTitle` column.
4. **`OfflineBrowsingSnapshot.init` is O(artists × albums), and its lookups are linear.**
   - Where: `OfflineBrowsingLibrary.swift:20-21, 35, 54-55`.
   - Fix: build grouped dictionaries once.
5. **`ArtworkImageCache` eviction is first-in-first-out for view reads.** `cachedImage(for:)` doesn't refresh recency. The cap is a count of 110, not a size, and nothing responds to memory warnings.
   - Where: `ArtworkImageCache.swift:159-161, 265-276, 983-995`.
   - Fix: switch to an `NSCache` with `totalCostLimit`, or a cost-based cap, and refresh recency on view reads.
6. **`DominantColorExtractor` rewrites its whole UserDefaults dictionary for every cover, and creates a new `CIContext` on every call.**
   - Where: `DominantColorExtractor.swift:128-156, 185-189`.
   - Fix: batch the writes, and share one `CIContext`.
7. **The 30 s local-music rescan is still a full tree walk**, with SHA-256 and a `String(format:)` hex per file.
   - Where: `RootView.swift:37-46`, `LocalMusicLibrary.swift:13, 160-218`.
   - Fix: rescan when the app becomes active or on refresh, and hex-encode with a lookup table.
8. **Locale-aware sorts run on large `Song` structs with no cached keys.**
   - Where: `SongSort.swift:29-45`, `AlbumSort.swift`, `ArtistSort.swift`.
   - Fix: sort precomputed `(key, index)` pairs.
9. **`LibraryFacets` decodes the whole library for each facet screen.**
   - Where: `LibraryFacets.swift:83-93`.
   - Fix: cache per index generation, or use SQL aggregates.

## LOW

1. **`LyricsViewModel.update` scans from line 0 every 250 ms.** Negligible. Optionally start from the previous index, and add tolerance to the sleep.
2. **Render-tap micro-costs** (`AVPlayerEngine.swift:1334, 1353`, `Equalizer.swift:160-213`):
   - a `takeUnretainedValue()` retain/release per callback;
   - class `var`s read inside the per-frame loop;
   - `vDSP_biquadm` could vectorise the filter;
   - `refreshIfNeeded` takes a `Mutex` and calls trig functions on the render thread, but only when settings change.
3. **`ArtworkImageCache` small allocations:** a String interpolated per key, O(110) `touch`, and copy-on-write of the waiters dictionary.
4. **`ExternalArtworkCache`** has the same LRU array pattern.
5. **`NavidromeCanonicalID.containsLegacyIDs`** is heavy per row, but runs once and off the main thread.
6. **`WidgetSnapshotPublisher.makeSnapshot`** awaits one at a time; it is coalesced to 500 ms.
7. **`filter{}.count` instead of `count(where:)`** in `DownloadService.swift:303, 327` and `OfflineLibraryRemovalCoordinator.swift:105`.
8. **N+1 point fetches** on small opportunistic index upserts (`LibraryIndexStore.swift:271-367`).

## Regression check against audit-all-2026-10-20

| Previous | Status |
|---|---|
| C3/X1 O(albums × tracks) recount per committed track | Fixed (`DownloadService.swift:309-329`) |
| C1/C2/H8 sorting and grouping in view bodies, the alphabet index, per-row `fetchCount` | Mostly fixed |
| X11 `ArtworkLoader` unbounded cache | Fixed (NSCache) |
| Observable `ArtworkImageCache` storage read from view bodies | Fixed (`@ObservationIgnored`) |
| X2/H7 local-music rescan | Partly fixed |
| H3/X12 download journal | Partly fixed |
| H1 queue work per track change | Not fixed |
| H2 queue re-encoded on every save | Not fixed |
| H4 per-song actor hops | Not fixed |
| H5 fetch-all-then-filter | Not fixed (`OfflineLibraryReader`) |
| H6 search ranking | Not fixed. Now CRITICAL for offline. |
| M quadratic snapshot, search JSON round trip, dominant colour, sort keys | Not fixed |

**New this audit:**
- placeholder detection on the MainActor (HIGH)
- smart-search normalisation per song
- `LibraryFacets` reloading the whole library
- first-in-first-out eviction for view reads

## Quick wins

1. Cache the ranked search results, online and offline, with pre-normalised titles. This removes the CRITICAL and H1.
2. Move placeholder detection into the detached decode, or drop the disk-hit check after a cover-store version bump.
3. Reorder `evaluateAutoExtend` so the cheap guards run first, and persist the queue only when it changes.

## Re-audit after the Mac and Winamp branches merge

- Allocation inside the render callback.
- Reuse of the vDSP FFT setup.
- Float versus Double buffers.
- `Data` slicing and inflate-buffer reuse in the ZIP reader.
- String splitting in the M3U parser.

## Verification

Profile with Instruments Time Profiler:
- typing a search offline with about 5,000 downloads;
- a fast cover scroll with a cold cache;
- skipping tracks with a 20,000-song queue;
- downloading a 500-song playlist.
