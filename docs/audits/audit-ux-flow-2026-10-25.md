# UX flow audit: 2026-10-25

**Summary:** 0 CRITICAL, 2 HIGH, 12 MEDIUM, 11 LOW (25 issues). Health: ROUGH EDGES.

The audit was run on the `fix/navidrome-placeholder` checkout. It covers `Minidisc/`, `MinidiscWidgets/` and `MinidiscWatch/`; the Mac target isn't merged yet. Findings come from reading the code: the app wasn't built or run. Check H2 on a device.

## Journey map

- **Entry points:**
  - `MinidiscApp`.
  - `.onOpenURL`, but only on `MainTabView`.
  - Spotlight and Shortcuts, through `LinkRouter`.
  - Widget links.
  - In-app routing through NotificationCenter.
- **Root gate (`RootView`):** a spinner while saved state loads, then `MainTabView` (server and onboarding done, or local files) or `OnboardingView`.
- **Tabs:** Home, Discover, Library, Playlists, Search. Without a server, only Library shows.
- **Player:** the mini player is a bottom accessory. The full player is mounted only while expanded, so its state resets on every open.
- **Critical flows:**
  1. Connecting a server.
  2. Local-files onboarding, now reversible.
  3. Browse, play, then the queue and lyrics.
  4. Adding to or creating a playlist.
  5. Recommended for You.
  6. The App Icon picker.

| Metric | Value |
|---|---|
| Critical flows complete | 5 of 6 (server onboarding can leave the user stuck, M9) |
| State handling, recent views | 7 of 9 (lyrics error, cover skeleton, Lidarr search) |
| Modal safety | About 45 presentations, all dismissible. Three are swipe-only; save sheets lock while saving. |
| Entry points | About 4 of 5 safe; widget URL on cold launch unverified (H2) |
| Accessibility reach | All critical flows reachable; only the easter egg is gesture-only |

## Regression check against audit-all-2026-10-20

| Previous | Status |
|---|---|
| C1 "Use Local Files" can't be undone | Fixed: Settings shows Add Server when there is none |
| H1/X5 dead `HomeDestination` links | Fixed: `resolvesHomeDestinations()` on Discover, Playlists, player and artist sheets; Search falls back correctly |
| H2/X7 toasts and errors not announced | Fixed: accessibility announcements |
| H3/X6 Wrapped is gesture-only and auto-advances | Fixed: no auto-advance under VoiceOver or Switch Control; actions added |
| H4 Lidarr interactive search has no Retry | Still present (H1) |
| M1 server form has no Cancel and can strand onboarding | Still present (M9) |
| M2 drafts discarded silently | Partly fixed: the server edit now asks before discarding |
| M3 no sign-out, remove or switch for servers | Still present (M10) |
| LOW New Playlist disabled offline with no reason | Still present |

## HIGH

| # | Finding | Where | Fix | Urgency | Blast radius | Effort | ROI |
|---|---|---|---|---|---|---|---|
| H1 | Lidarr interactive search failure shows "Search Failed" with no Retry. `load()` runs only on appear. | `LidarrInteractiveSearchView.swift:89-90, 173-187` | Add a Retry action to the empty state. | Next release | Lidarr users | S | High |
| H2 | Widget and deep-link URLs may be lost on a cold launch. `.onOpenURL` is only on `MainTabView`, which isn't on screen while `RootView` shows its spinner. `LinkRouter` was built for this race, but only Spotlight uses it. `open(_:)` also returns silently with no active server. | `MainTabView.swift:24, 139`, `RootView.swift:51-58`, `LinkRouter.swift:4-8` | Move `.onOpenURL { linkRouter.open($0) }` to `RootView`, and leave `MainTabView` as the only consumer. | Next release (check on device) | Every widget tap while the app isn't running | S | High |

## MEDIUM

1. **The App Icon picker fails silently.** The selection snaps back with no message.
   - A quick second tap can restore a stale selection.
   - There's no `supportsAlternateIcons` check.
   - Where: `SettingsView.swift:1009-1021`.
   - Fix: serialise changes, show a toast and log on failure, and hide the row when alternate icons aren't supported.
2. **Recommended for You:** the provider and its settings are only reachable after a failure.
   - Where: `AIRecommendationsView.swift:30-39, 53-55, 72-85`.
   - Fix: a toolbar or provider-row button that opens the settings.
3. **Switching provider leaves stale content.** The old error or results stay beside a new heading while the privacy notice is pending.
   - Where: `AIRecommendationsView.swift:40-65, 199-205`.
   - Fix: reset `failure` and `results` when the provider changes, or hide the failure while the notice shows.
4. **A failed API key save is only logged.** Test Connection uses the in-memory draft, so it reports "Connected" while the screen later says to add a key.
   - Where: `AIRecommender.swift:76-83`, `AIRecommendationsView.swift:346-352`.
   - Fix: show the save failure in the form.
5. **Lyrics can go blank with no way out when a live stream starts.** `showLyrics` stays on, the panel is empty, and the Lyrics and Queue buttons are hidden for live streams.
   - Where: `FullPlayerView.swift:78-90, 166, 195-223, 1020-1033`.
   - Fix: turn lyrics off and show the player when `isLiveStream` becomes true, or gate on it.
6. **The lyrics error has no Retry** and shows the raw error text. Reopening retries, but the user isn't told.
   - Where: `LyricsView.swift:172-185`, `LyricsViewModel.swift:83-87`.
   - Fix: add a "Try Again" button.
7. **The player's "Go to Album" sheet can go blank** when the track changes while it's open, and has no visible Close. It is enabled when `albumName` is nil. `ArtistDetailView` has the same pattern.
   - Where: `FullPlayerView.swift:533-542, 608-617`, `ArtistDetailView.swift:698-707`.
   - Fix: present it with `sheet(item:)` using the captured album, and add Done.
8. **The Playlists empty state says "Create playlists on your server"** while the screen has its own + button. It offers no action, and + is unlabelled and disabled offline with no reason.
   - Where: `PlaylistListView.swift:26-34, 72-77`.
   - Fix: change the copy and add a "New Playlist" action and label.
9. **Dismissing the onboarding server sheet while connecting strands the user** on the welcome screen even though the server connects. `onServerConnected` never fires.
   - Where: `OnboardingWelcomeView.swift:30-39`, `OnboardingView.swift:31-35`.
   - Fix: finish onboarding when `activeServer` becomes non-nil, and add Cancel.
10. **There's no way to remove, sign out of or switch servers.**
    - Where: `SettingsView.swift:128-151`, `EditServerView.swift`.
11. **Sheets that are saving lock dismissal with no Cancel.** Users wait for the network timeout.
    - Where: `AddMusicSheet:99`, `EditPlaylistSheet:73`, `AddToPlaylistSheet:34,41`, `CreatePlaylistSheet:85`.
    - Fix: a cancellable save task.
12. **`CoverArtView` can show a skeleton forever.** When `coverArtURL` is nil (no client), `AsyncImage(url: nil)` stays empty.
    - Where: `CoverArtView.swift:74-93, 146-150`.
    - Fix: show the placeholder when the fallback URL is nil.

## LOW

1. **The cover easter egg:**
   - It stays on across tracks, so the next cover is hidden.
   - It can't be toggled from the header thumbnail.
   - There's no VoiceOver action, which is acceptable for an easter egg.
   - It respects Reduce Motion.
   - Consider resetting it on a track change.
2. **Playlists refresh:** a failed refresh is invisible when playlists exist. "No Playlists" can flash before the Made For You rows load.
3. **Creating a playlist while a search is active** can hide the new row. The search logic itself is sound.
4. **Add to Lidarr from recommendations:** no progress or double-tap guard, and it returns silently on errors. The Bandcamp and MusicBrainz buttons do nothing when the URL is nil.
5. **The "No recommendations" title shows above previous results** when a refresh fails. Use "Couldn't refresh".
6. **"Open Settings" for an unavailable provider** opens the in-app sheet; "Choose Another Provider" would be clearer. The privacy acknowledgement can't be reviewed or revoked.
7. **The Wrapped empty state can hide a real downloaded playlist** on an offline cold start (`WrappedYearlyListView.swift:39-41`).
8. **The welcome screen:**
   - "Use Local Files" is a small, unexplained text button.
   - The entrance springs ignore Reduce Motion.
   - Get Started stays disabled if there's no container.
9. **The `CoverArtView` AsyncImage fallback** doesn't run server stand-in detection.
10. **The full player's Close handle** is a 28 pt hit area. Landscape hides volume.
11. **Earlier LOW themes:** swipe-delete confirmations and "Delete" vs "Remove" wording.

## Recommendations

1. **Now:**
   - H2: move `.onOpenURL` to `RootView`, then test by tapping a widget after force-quitting the app.
   - H1: add Retry to Lidarr search.
2. **Before the next release:**
   - M1: icon picker.
   - M2 and M3: Recommended for You.
   - M5: lyrics during a live stream.
   - M6: lyrics Retry.
   - M7: album sheet.
   - M8: Playlists empty state.
   - M9: onboarding.
   - M12: cover skeleton.
3. **Later:**
   - M10: server management.
   - M11: cancellable saves.
   - M4: keychain feedback.
   - A shared component for loading, empty, error and retry states.
