# iOS 27 adoption plan

Status: proposed, 2026-10-20.

## Decisions

| Question | Decision |
|---|---|
| Minimum iOS | iOS 27.0. iOS 26 support is dropped, and the existing `#available(iOS 27…)` checks go away. |
| Priorities | Lock Screen and Live Activity, widgets and controls, Siri and Apple Intelligence, UI refresh. All four are in scope. |
| CarPlay | Planned. It starts with the entitlement request, because CarPlay audio needs Apple's approval. |
| Upstream | Upstream still targets iOS 26.1. Raising the target and adding extension targets make merges touch `project.pbxproj` more often, so keep each phase in its own commits. |

Every API named below was checked against the iPhoneOS 27.1 SDK in Xcode 27.1 unless it is marked *(Axiom)*. Those items are documented in the Axiom 27 skills but were not found as symbols.

## Phase 0: require iOS 27 (prerequisite) — done 2026-10-20

Outcome: the deployment target is 27.0 and the app builds with warnings as errors. The compiler only flagged `BGTaskScheduler.submit`, `AVPlayerItem.errorLog()` and the interruption notification and keys; the notification-name and `#ImplicitStrongCapture` items below never came up. Interruptions now come from `didBecomeInactiveNotification`, counting only deactivations by the system, and `resumptionRecommendationNotification`, mapped onto the existing began/ended events, so the recovery logic and its tests are unchanged. The new notifications' context objects have no public initializer, so the mapping itself can only be confirmed on a device: take a phone call or start another audio app mid-song. The error log is fetched asynchronously before a failure is reported. The two runtime fallbacks were removed (the queue list and the song swipe container). Upstream's `@available(iOS 27.0, *)` annotations and `#if compiler` guards stay, because they are inert at a 27 target and removing them would conflict with upstream edits.


The project builds with `-warnings-as-errors`. iOS 27 deprecates APIs the player uses today, so raising the target and replacing those calls have to land in the same change.

1. Set `IPHONEOS_DEPLOYMENT_TARGET = 27.0` for the app and both test targets, and update the doctor check if it pins the version.
2. Replace the deprecated calls:
   - **Audio interruptions:** `AVAudioSession.interruptionNotification` and its `InterruptionType`, `Option` and `Reason` keys (`PlayerService.swift`, the audio-session handling around `handleAudioSessionInterruption`). Move to `AVAudioSession.didBecomeInactiveNotification`, whose `DeactivationContext` gives the source and interruption, and `AVAudioSession.resumptionRecommendationNotification`, whose `ResumptionContext.recommendation` is `.shouldResume` or `.shouldNotResume`. Consider `activate(options:)` and `deactivate(options:)` too. This is the riskiest item in the phase. `PlayerRecoveryIntegrationTests` and `AudioSystemResetTests` cover the current behaviour, so extend them before changing it.
   - **AVPlayerItem logs:** `errorLog()` and `accessLog()` in `AVPlayerEngine.failure(item:error:)` become the async `fetchErrorLog()` and `fetchAccessLog()`. The failure path is synchronous today, so collect the log code asynchronously or drop it.
   - **Notification names:** the Swift-overlay names `NSNotification.Name.AVPlayerItemDidPlayToEndTime` and the related ones become `AVPlayerItem.didPlayToEndTimeNotification` and friends, where any remain.
   - **Background tasks:** `BGTaskScheduler.submit(_:)` in `MinidiscApp.scheduleWrappedUpdate` becomes `try await submitTaskRequest(_:)`.
3. Remove the iOS 26 fallbacks: the `@available(iOS 27.0, *)` annotations in `AppIntents/SiriAudioEntities.swift`, and the `#if compiler(>=6.4)` / `#available` branches in `SongQuickActions.swift`.
4. Check layouts in resizable windows *(Axiom)*. On iOS 27 an iPhone-only app can run resizable, in iPhone Mirroring and as an iPhone app on iPad, while still reporting a compact size class. Look for layout that assumes a fixed width.
5. Fix the new Swift 6.4 `#ImplicitStrongCapture` warnings *(Axiom)*, which are errors here.

Done when: the full test suite and `./Scripts/doctor.sh --build` pass with the 27.0 target.

## Phase 1: Lock Screen, Now Playing and Siri context — done 2026-10-20

Outcome: Now Playing moved to the NowPlaying framework behind the presenter's unchanged interface, so the engine and its gapless and crossfade hand-offs are untouched. The current server song carries its Siri entity identifier and is published to `RelevantEntities` for `.audio(.nowPlaying)`. Album and playlist downloads show a Live Activity. Lock Screen, Dynamic Island and crossfade behaviour still need checking on a device.


1. **Tie Now Playing to app entities.** Set `MPNowPlayingInfoPropertyAppEntityIdentifiers` (`MPAppEntityIdentifier`) on the current item in `NowPlayingCenterPresenter`, and publish `RelevantEntities.shared.updateEntities(_:for: .audio(.nowPlaying))` when the track changes. Siri and the system can then act on "this song", for example "add this to my Road Trip playlist".
2. **Evaluate the NowPlaying framework.** `MediaSession`, `MediaSessionRepresentable`, `MusicContent` (ISRC, genre, animated artwork), `MediaPlaybackSnapshot` and `MediaCommand` are the declarative successor to `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`. MediaPlayer is not deprecated, so start with a spike: model one track and the transport commands. Migrate only if it simplifies the presenter and handles gapless and crossfade hand-offs correctly. `requestToBecomeSystemPrimary()` is worth checking when another app takes audio focus.
3. **Live Activity for downloads.** The system already shows audio Now Playing on the Lock Screen and in the Dynamic Island, so a playback Live Activity would duplicate it. Downloading an album or playlist is a good fit: progress, current song, and a cancel button. This needs the widget extension from Phase 2 (build Phase 2's target first, or together). Use `isDynamicIslandLimitedInWidth` for the compact presentation.

## Phase 2: widgets and controls — done 2026-10-20

Outcome: the `MinidiscWidgets` extension and App Group are in place with the Now Playing, Recently Played, Pinned and Moods widgets and the Play or Pause, Next Track, Smart Shuffle and Play a Mood controls. Lock Screen support comes from the Now Playing widget's accessory families. Widget appearance still needs checking on a device or in Xcode previews.


1. **Widget extension and App Group.** Add a WidgetKit extension target (`com.ecliptik.minidisc.widgets`) and the App Group `group.com.ecliptik.minidisc` for both targets. Don't move the SwiftData store. Have the app write a small JSON snapshot and pre-rendered thumbnails into the group container: recent albums, pinned playlists, mood playlists and the current track. The extension then needs neither SwiftData nor the network.
2. **Home Screen widgets.** "Recently played" and "pinned and mood playlists", in small, medium, large and the new `systemExtraLargePortrait`, which iOS 27 also brings to the iPhone Home Screen *(Axiom)*. Tapping one opens the item through the shared `HomeDestination` resolver, which finally gives the `minidisc://` scheme a handler (an open item from the audit). Buttons in the widgets reuse the existing `AudioPlaybackIntent`s.
3. **Controls.** `ControlWidget` buttons for Control Center, the Lock Screen and the Action button: Play/Pause, Smart Shuffle and Play Mood, all backed by the existing `PlayMinidiscMoodIntent`, `MinidiscSmartShuffleIntent` and `ResumeMinidiscIntent`/`PauseMinidiscIntent`.
4. **Lock Screen accessory widgets** (`accessoryRectangular` and `accessoryCircular`) for the current track or a quick Smart Shuffle.

## Phase 3: Siri, App Intents and Apple Intelligence — done 2026-10-20

Outcome: the four remaining audio schemas are adopted. Add to library and Love star the item, Dislike and clearing the rating unstar it (Subsonic has no dislike), add to playlist skips songs already there, and a station is an Instant Mix from the playing song (the createStation schema has no item parameter). The SDK has no download schema, so downloads use a custom `LongRunningIntent`. Spotlight indexes artists, albums and playlists from the local index as `IndexedEntity`s, with Open actions and a `LinkRouter` for links that arrive during launch. Natural-language search was the Foundation Models spike: the model only fills `LibraryQuery` filters and matching stays local. The SiriKit entitlement was dropped because the personal team cannot use it. AppIntentsTesting was not adopted; the services behind the intents have unit tests instead. Siri phrasing, Spotlight results and the model's interpretations still need checking on a device.


1. **Finish the iOS 27 audio schema.** `.audio.playAudio` and the entities are already adopted. Add `addToLibrary` (star or favourite), `addToPlaylist`, `createStation` (Instant Mix from a song, artist or album) and `updateAudioAffinity` (love or dislike, mapped to star and unstar). Use `MediaIntents.AudioSearch` where Siri passes a search. *(Axiom)* Schemas carry their own authentication policy and confirmation behaviour, and Xcode fails the build when a related schema is missing, so expect some required companions.
2. **Download intent.** A `LongRunningIntent` that downloads an album or playlist in the background ("download my Road Trip playlist"), reporting through the Phase 1 Live Activity.
3. **Spotlight.** Index artists, albums and playlists as `IndexedEntity` so they appear in Spotlight and in Apple Intelligence's semantic search. Reindex after a library sync, scoped to the active server.
4. **On-device intelligence (Foundation Models).** Candidates, each behind `SystemLanguageModel.default.availability`: names and one-line descriptions for generated Mood playlists, and natural-language library search ("mellow 90s rock I haven't played lately") turned into structured filters over the local index. Pick one for a first spike. Tag-based mood matching already exists, so the model only adds wording and query parsing.
5. **Tests.** Use AppIntentsTesting to exercise the intents without Siri.

## Phase 4: UI refresh — partly done 2026-10-20

Outcome so far: `systemPrefersReducedResourceUsage` pauses the playlist hero's per-frame gradient, the Wrapped mesh backgrounds and the now-playing bars (item 7), and Wrapped text follows Dynamic Type through a capped `scaledFont` helper (item 8). Corrections to the items below: `toolbarVerticalCompressionBehavior` only offers `.automatic` and `.prefersToolbarItems`, and `presentationPlacement` only chooses leading, center or trailing for wide windows, so it belongs with the iPad work. Items 1, 2, 3 and 5 change how the app looks and feels, so they wait until the app can be tried on a device.


1. **Player presentation.** Try `NavigationTransition.crossFade` against the current zoom for opening the full player.
2. **Vertical space.** With a mini player and a minimising tab bar, use `toolbarVerticalCompressionBehavior(.prefersTabBar)` (27.1), `toolbarMinimizationBehavior(_:for:)` and `toolbarMinimizationRestoration(.atScrollEdge)` so the mini player and tab bar stop competing on scroll.
3. **Toolbars.** Use `ToolbarOverflowMenu` with `visibilityPriority(_:)` on screens with several actions (album, playlist, the player's More menu), and `topBarPinnedTrailing` for actions that must stay visible.
4. **Queue editing.** Already done upstream: `ReorderableQueueList` uses the iOS 27 reordering API, and it became the only queue list in Phase 0. Song rows use `swipeActionsContainer()` unconditionally since Phase 0.
5. **Tabs.** Consider `TabRole.prominent` if a dedicated Now Playing or Library tab should stand out. Search already uses the search role.
6. **Sheets.** Place sheets with `presentationPlacement(_:)` (Add to Playlist, Settings), which matters in resizable windows.
7. **Lighter rendering.** Honour `systemPrefersReducedResourceUsage` by stopping the Wrapped mesh-gradient animation and the player's colour-band background animation. This also closes an energy item from the audit.
8. **Carried over from the audit:** Dynamic Type for the Wrapped slides, done together with the layout work.

## Phase 5: CarPlay — built for the simulator 2026-10-20

Outcome: a `CPTemplateApplicationScene` with Home (recently played and pinned), Library (playlists, albums and artists from the local index), Downloads (downloaded songs) and Moods. Lists of songs have a Shuffle row; playback uses `PlayerService` and the system Now Playing template. The owner's team is a free personal team, which cannot request the CarPlay entitlement, so it is applied to simulator builds only. Check it in Simulator with I/O > External Displays > CarPlay; it reaches a car only after joining the paid program and getting Apple's approval.


1. **Entitlement first.** Request `com.apple.developer.carplay-audio` for `com.ecliptik.minidisc` from Apple. Nothing below ships to a car without it, but the CarPlay simulator works without it.
2. **Scene.** Add a `CPTemplateApplicationScene` delegate with tabs for Home (recent and pinned), Library (artists, albums and playlists from the local index, so it works offline), Downloads and Moods. `CPNowPlayingTemplate.allowsMiniPlayer` is on by default in iOS 27.
3. **Reuse.** Drive everything through `PlayerService` and `LibraryService`, with artwork from `ArtworkImageCache`. CarPlay needs no new playback code.
4. **Siri in the car.** It comes from the Phase 3 audio intents. `CPVoiceControlTemplate.backgroundImage` is new in iOS 27 for the voice UI.

## Order and size

| Phase | Depends on | Size | Main risk |
|---|---|---|---|
| 0 Require iOS 27 | none | M | Rewriting interruption handling without regressing recovery |
| 1 Lock Screen and Siri context | 0; Live Activity needs 2's target | M | NowPlaying framework behaviour with crossfade |
| 2 Widgets and controls | 0 | L | App Group provisioning, snapshot freshness |
| 3 Siri and Apple Intelligence | 0 | L | Schema completeness rules, model availability |
| 4 UI refresh | 0 | M | Visual regressions; needs device and simulator review |
| 5 CarPlay | 0, entitlement | L | Entitlement approval |

Suggested order: 0, then 1 and 2 together (they share the extension target), then 3, 4 and 5 as you like. Each phase gets a branch, targeted tests while working, and the full suite and doctor build before merging into `main`.

## Not changing

- **Spatial or lossless audio:** iOS 27 has no new API here.
- **AVSystemRouting (casting to non-AirPlay receivers):** it appears limited to some regions and is in beta. Revisit later.
- **MusicUnderstanding (tempo, key and structure analysis):** interesting for smarter crossfades, but research only for now.
