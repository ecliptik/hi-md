# SwiftUI performance audit: 2026-10-25

**Summary:** 1 CRITICAL, 5 HIGH, 20 MEDIUM, 10 LOW.

This was a static audit of the `fix/navidrome-placeholder` checkout. Health: BROKEN under the rubric, because a CRITICAL sits in a path driven by `PlayerState`. Ordinary scrolling is closer to JANKY, and mostly clean after the last round of fixes.

## Context

- **Scrolling surfaces:**
  - `List` and `LazyVGrid`: Library, Albums, Artists, Songs, Favourites, Downloads, Playlist detail.
  - Album detail is a `LazyVStack`.
  - Home and Artist detail are non-lazy `VStack`s.
  - `SongRow` is a heavy cell: 2 tasks, 2 sheets, a context menu, swipe actions.
- **High-frequency state:**
  - `PlayerState.position` updates every 500 ms. The scrubber is isolated from it; the mini player isn't.
  - The swipe offset updates every frame.
  - `DownloadActivityState.transfers` updates on every queue event.
  - The `@Query` for `DownloadedTrack` and `FavoriteRecord` updates on every commit or toggle.
- **Scale:** the Songs tab can queue up to 200,000 tracks.
- **Fixed since last time:**
  - `ArtworkImageCache` storage is `@ObservationIgnored`.
  - `DominantColorExtractor`'s memo caches are ignored.
  - `LocalMusicLibrary` only assigns its snapshot when it changes.

| Metric | Value |
|---|---|
| View body purity | About 13 of 55 files do expensive work in `body` (about 24%) |
| Scrolling cells | 5 of 14 contexts are clean |
| Lazy containers | 100% for long lists |
| Collection operations in bodies | 8 of 20 cached, 12 O(n) per body |
| Observation | 54 `@Observable` types, 0 `ObservableObject` |

## CRITICAL

### C1. The full-player queue rebuilds the whole queue snapshot on every track change

- **Where:** `InlineQueueList.swift:159-170, 183-195`, `QueueTrackSelection.swift:14-32`.
- **Problem:** `QueueRowSnapshot.capture(playerState)` walks the entire queue and builds a `QueueTrackSelection` for every upcoming song, reading about 7 observed properties each time. It reruns on every skip and every edit, and the `List` then diffs up to 200,000 identities.
- **Impact:** estimated hundreds of ms on the MainActor when the queue opens and on each track change. That's the same MainActor the engine's transition hops use, which puts gapless and crossfade timing at risk.
- **Fix:**
  - Rows carry only `index` and `song`, and the selection is built in the tap handler.
  - Cache entries keyed on queue revision and current index.
  - Better: show a window of the next 200 tracks with "Show more".

| Urgency | Blast radius | Effort | ROI |
|---|---|---|---|
| Now | Large queues (Songs tab, Smart Shuffle) | M | High |

## HIGH

| ID | Finding | Where | Fix |
|---|---|---|---|
| H1 | **`DownloadedTrack` queries are too broad.** An unfiltered `@Query` in `PlaylistDetailView`; the rows and the progress view fetch every downloaded track just to read `songId`. Every download commit re-runs detail screens with O(n) work per body. | `PlaylistDetailView.swift:110, 924-1009`, `RecentlyAddedView.swift:16, 198`, `ArtistBestOfView.swift:18`, `AddMusicSheet.swift:573` | An observable store of downloaded IDs only, or a scoped child query. Remove the unused query. |
| H2 | **`SongSelectionSheet` deduplicates and normalises the whole list 3 times per body**, with up to 200,000 songs. | `SongSelectionSheet.swift:17-44` | A `DerivedValueCache` keyed on request and query, and one `visibleIDs` set |
| H3 | **`Array(songs.enumerated())` copies the whole list on every body** (about 330-byte structs). This hits favourite toggles while the Songs tab is mounted. | `SongsListView.swift:114, 118`; same in Favourites, Playlist, Album and Search | `ForEach(songs.enumerated(), id: \.element.id)`, with `.id` only where needed |
| H4 | **Every cover pays a skeleton flash and a second body pass, even on a RAM hit.** Each cover also owns an `@AppStorage` observer. | `CoverArtView.swift:42, 74-113`, `SkeletonBlock.swift:20-24` | Read the RAM cache synchronously in `body`. Use a plain placeholder with no repeating animation. Share the upload-version state. |
| H5 | **Offline search scores twice per comparison on every keystroke.** Also in the Swift performance audit. | `SearchView.swift:160-169, 188` | Score once into the view model, and debounce |

## MEDIUM

1. **M1. The mini player rebuilds every 500 ms**, because position is read in its tree. Move the progress bar into its own child view.
2. **M2. Each `SongRow` loads a duplicate cover** (only for the context-menu preview), has two sheets, and reads the whole `currentTrack`. Load the preview lazily, hoist the sheets, and expose a narrower `currentTrackID`.
3. **M3. `PlaylistDetailView` makes extra O(n) passes:** a second sort in the toolbar, four dictionaries for `downloadState`, and `FeaturedArtist.from`.
4. **M4. `PlaylistDownloadProgressView` builds its downloaded-ID set 3 times per body.**
5. **M5. Offline `AlbumDetailView` calls `displaySongs()` once in the body and 3 more times in the toolbar.**
6. **M6. `ArtistDetailView` depends on every starred song.** It builds a set per body and per row, and offline rows aren't lazy.
7. **M7. `SearchResultsContent` has an unfiltered favourites query**, and `songs` is passed by value into every row.
8. **M8. `LocalSearchResultsSection` recomputes everything** (diacritic-insensitive matching 3 times per track).
9. **M9. `FavoritesView` and `DownloadedContent` sort and merge in `body`.** Use `DerivedValueCache`.
10. **M10. Grid and shelf cells use a `GeometryReader` only to make the cover square.** Use `.aspectRatio(1, .fit)` with a constant size.
11. **M11. Each `PlaylistListView` row has its own `@Query`, a duplicate cover task, and a file-existence check.**
12. **M12. `SwipeableTrackMetadata` rebuilds 4 metadata copies per drag frame.** Apply the offset with `.visualEffect`.
13. **M13. The `MinidiscLogoView` TimelineView runs at the display rate**, even as the 56 pt header thumbnail and possibly behind karaoke. Use a render-server rotation, and gate it on the header being hidden.
14. **M14. Wrapped animations run without visibility gating**, including the mesh gradient and a 20 Hz story tick.
15. **M15. Download progress is processed in O(N) per event on the MainActor.** Throttle to about 4 Hz.
16. **M16. `AddMusicSelection` keeps an array; `contains` is O(N×S).** Use a set of IDs.
17. **M17. Stretchy headers read the global frame on every scroll frame.** Use `onScrollGeometryChange` or `visualEffect`.
18. **M18. `DominantColorExtractor` rewrites UserDefaults on every cover, creates a `CIContext`, and averages on the MainActor.**
19. **M19. `ArtworkImageCache` has one count-only LRU for both tiers**, and `touch` is O(110).
20. **M20. `WrappedView` loads every `PlaybackEvent` just to count them.** Use `fetchCount`.

## LOW

1. **L1.** `ProgressSlider` formats a `Duration` on every tick.
2. **L2.** `TrackInfoSection` runs `queue.contains(where: \.isLocalFile)` in its menu.
3. **L3.** The root scene body reads `offlineLibrary.request`.
4. **L4.** `ArtistListView` flatMaps on every body, so the cache key compare is O(N).
5. **L5.** `alphabetFirstLetter` creates a `Locale` per call.
6. **L6.** `AlbumsListView` logs a notice on every task run.
7. **L7.** Shimmer and skeleton each have their own `GeometryReader` and repeat animation.
8. **L8.** `recentDownloadedItems` is computed 3 times per offline body.
9. **L9.** Tasks started in `onAppear` in Home cards aren't cancelled.
10. **L10.** `MainTabView.hasTrack` and `MiniPlayerBottomMargin` read the whole `currentTrack`.

## Regression check against audit-all-2026-10-20

| Previous | Status |
|---|---|
| C1 a set rebuilt per row in playlist rows | Fixed |
| H1 favourites set per row in album rows | Fixed |
| H2 `fetchCount` per row in the Songs list | Fixed |
| H3 offline Songs list recomputed 5 times | Fixed (`DerivedValueCache`) |
| H4 alphabet index | Mostly fixed |
| H5 sorting Albums and Artists in `body` | Fixed |
| H6 `SongSelectionSheet` | Still present (H2) |
| H7 offline search scoring | Still present (H5) |
| H8 Downloads re-merging on progress ticks | Partly fixed |
| H9 unscoped Playlist `@Query` | Still present (H1) |
| Mediums: mini-player ticks, artist favourites, local search, queue re-snapshot (now C1), Add Music, Wrapped events, favourites sort, stretchy headers, mesh, LRU | Still present |
| Album detail observing the whole cache | Fixed |
| `DominantColorExtractor` | Partly fixed |
| X2 local-music rescan | Fixed |
| X4 sorting and grouping in bodies | Mostly fixed |

## Sweep of observable state with frequent unrelated changes

| State | Verdict |
|---|---|
| ArtworkImageCache storage | Fixed |
| `PlayerState.position` | M1 (mini player) |
| `PlayerState.currentTrack` | M2, L10 |
| `PlayerState.queue` / `currentIndex` | C1, L2 |
| `DownloadActivityState.transfers` | Isolated; M15 for the producer |
| `OfflineBrowsingLibrary.revision` | L3 |
| `TrackSwipeInteraction.offset` | M12 |

## Recommendations

1. **Now:** C1. Re-test gapless and crossfade when skipping with queues of 50,000 and 200,000.
2. **Short term:** H3, H2, H4, H1, H5.
3. **Medium term:** M1, M2, M11, M10, M15, M13, M14.
4. **Instruments:**
   - The SwiftUI template's view-body counts during a download and a favourite toggle.
   - Time Profiler and Hangs on opening the queue with 200,000 tracks.
   - Animation hitches while flinging a 500-song playlist.
