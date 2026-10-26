# Fork notes

This repository, [ecliptik/Minidisc](https://github.com/ecliptik/Minidisc), is a hard fork of [Loriage/Minidisc](https://github.com/Loriage/Minidisc), itself a fork of [Cassette](https://github.com/CassetteLab/cassette). Changes are not sent upstream, but upstream work is merged in from time to time. The code stays under the Mozilla Public License 2.0; `LICENSE`, `NOTICE` and `COPYRIGHT` are upstream's and stay unchanged. The README summarises how the fork differs; this file is for building and maintaining it.

## Branches

- `main`: everything — the iOS app with its widgets and watch app, and the native Mac app (`MinidiscMac`) with its Winamp mode. Work happens on short-lived branches merged into `main`.

## Remotes

    git remote add upstream https://github.com/Loriage/Minidisc.git
    git remote set-url --push upstream DISABLED-no-pushes-to-upstream

`upstream` is fetch-only, so nothing is pushed there by accident.

## Bringing in upstream changes

    git fetch upstream
    git log --oneline main..upstream/main      # review what is new
    git switch -c sync/upstream-<date> main
    git merge upstream/main                    # or cherry-pick individual commits

Then build, run the `MinidiscTests` scheme and `./Scripts/doctor.sh --build` before merging the sync branch into `main`.

## Signing

The project carries no signing team. `Config/Signing.xcconfig` is the project-level base configuration for Debug and Release; it sets an empty `DEVELOPMENT_TEAM` and includes `Config/Signing.local.xcconfig` if it exists. That file is git-ignored; copy `Config/Signing.local.xcconfig.example` to create it and set your own team ID. Targets must not set `DEVELOPMENT_TEAM` themselves, because a target setting overrides the xcconfig. The one exception is the UI-test runner, which signs locally with an empty team.

A free personal team works, with two limits:

- It cannot use the Siri capability, so `com.apple.developer.siri` is left out of `Minidisc.entitlements`. Upstream's SiriKit play handler stays but goes unused, and App Shortcuts still work.
- Apple allows only 10 new App IDs per 7 days across all of the team's apps. Minidisc uses three: the app, the widget extension and the watch app.

## Fork-specific changes to keep during merges

- **Minimum iOS:** the deployment target is iOS 27.0 (upstream: 26.1). Keep 27.0 when merging `project.pbxproj`; the iOS 27 adoption plan is `docs/plans/ios27.md`.
- **Identity:** bundle ID `com.ecliptik.minidisc` (plus `.tests`, `.uitests`, `.widgets` and `.watchkitapp`), the App Group `group.com.ecliptik.minidisc`, the background download session ID in `BackgroundDownloadTransport.swift`, the URL type name in `Info.plist`, and the bundle-ID check in `Scripts/doctor.sh`. Anyone building their own copy for a device changes this prefix, since a bundle ID belongs to one team.
- **Signing:** `Config/Signing.xcconfig` as the project's base configuration, and no `DEVELOPMENT_TEAM` in the targets (see above).
- **Branding:** the photographed MiniDisc in `AppIcon.icon`, `AppIconDark.icon` and `AppIconLight.icon` (gold, dark and light), the `MinidiscLogo*`, `AppIconPreview*` and `NowPlayingNoArtwork` images, `docs/app-icon.png` (exported from `AppIcon.icon` with Icon Composer), the gold accent colour sets in `Assets.xcassets`, `MinidiscColors.AccentRamp`, `ColorContrastUtils` and the 2026 palette in `WrappedYearPalette`. The light and dark accents are chosen so white button labels stay at or above 4.5:1.
- **Mac (native):** the `MinidiscMac` target is a native macOS 27 app (not Catalyst; `SUPPORTS_MACCATALYST = NO` on the iOS target). It uses the same bundle ID, `com.ecliptik.minidisc` and the same signing setup. Its own code is in `MinidiscMac/`. It also compiles the `Minidisc` and `Shared` folders, minus the iOS-only files listed in its `PBXFileSystemSynchronizedBuildFileExceptionSet` (`Views/` apart from `CoverArtView.swift`, `CarPlay/`, `Services/Watch/`, the widget snapshot writers, the SiriKit handler, the UIKit-only design-system components, `MinidiscApp.swift`, `Info.plist` and the entitlements). Xcode doesn't exclude folders from synchronized groups, so the list names every file: **a new file under `Views/` or another excluded folder must be added to that list** or the Mac build breaks. The sandbox (outgoing network, user-selected files) and the hardened runtime come from build settings. On the Mac, the MediaPlayer-based `NowPlayingCenterPresenter+MediaPlayer.swift` drives Now Playing and the media keys, the audio-session controller is a no-op, and the download activity, haptics and background tasks are no-ops. `Scripts/run-mac.sh` builds and opens it, signed to run locally. The Mac's Home and Discover reuse the iPhone's view models (`HomeFeedViewModel`, `DiscoverViewModel`) and lay out their shelves with the shared `HomeFeedLayout` and `DiscoverShelves` helpers, so a section added to the iPhone's Home or Discover belongs in those helpers too.
- **Apple Watch:** the `MinidiscWatch` target (watchOS 27) and the `WatchShared/` folder compiled into the app and the watch app. `PhoneWatchBridge` publishes Now Playing over WatchConnectivity and runs the watch's commands.
- **CarPlay:** `Minidisc/CarPlay/` and a hand-written `UIApplicationSceneManifest` in `Info.plist` (generation is off). The `com.apple.developer.carplay-audio` entitlement is only in `Minidisc-Simulator.entitlements`, selected by `CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]`; move it into `Minidisc.entitlements` once a paid team has Apple's approval.
- **Widget extension:** the `MinidiscWidgets` target, the `Shared/` folder compiled into both targets, and the App Group in both entitlements files. Upstream has no extension, so merges of `project.pbxproj` must keep the target, the embed phase and the `Shared` group.
- **Now Playing:** `NowPlayingCenterPresenter` uses the iOS 27 NowPlaying framework instead of MediaPlayer; keep it when upstream edits that file.
- **Playback engine:** the two-deck engine's gapless playback and crossfades must survive every merge, along with the fork's buffering and caching (`docs/PlaybackContinuity.md`).
- **ListenBrainz:** the app reads from ListenBrainz but doesn't submit listens (`ListenBrainzService.submitsListens` is off); plays reach ListenBrainz through the server's scrobbling.
- **Links:** `MinidiscURLs` points Report an Issue and View Source at this repository, the lyrics and artist-image User-Agents name it, the App Store review and share rows are removed from Settings, and Acknowledgements credits upstream Minidisc and Cassette.
- **Notices:** `THIRD_PARTY_NOTICES.md` lists third-party code and data; add to it when bringing in more. Upstream's `.github/FUNDING.yml` is removed so the fork doesn't show upstream's sponsor links.
- **Audits:** reports live in `docs/audits/`.

## Licence compliance

- Upstream files keep their MPL-2.0 terms, and new files are MPL-2.0 as well. The `NOTICE`, `COPYRIGHT` and `LICENSE` files are not altered (MPL-2.0 §3.4).
- `NOTICE` asks modified versions to acknowledge Cassette; the README and the in-app Acknowledgements screen credit Cassette and upstream Minidisc.
- The source of every change is published in this repository, which meets MPL-2.0's source-availability requirement for anyone distributing a build.
- Third-party code and data (SwiftSonic and AutoEq, both MIT) are listed with their notices in `THIRD_PARTY_NOTICES.md`.
