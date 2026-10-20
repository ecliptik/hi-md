# Fork notes

This repository is a hard fork of [Loriage/Minidisc](https://github.com/Loriage/Minidisc), itself a fork of [Cassette](https://github.com/CassetteLab/cassette). Changes are not sent upstream, but upstream work is brought in from time to time. The code stays under the Mozilla Public License 2.0.

## Remotes

| Remote | URL | Use |
|---|---|---|
| `origin` | `https://github.com/ecliptik/hi-md.git` | The fork's only home and push destination |
| `upstream` | `https://github.com/Loriage/Minidisc.git` | Fetch only; pushing is disabled |

A fresh clone needs `upstream` added again:

    git remote add upstream https://github.com/Loriage/Minidisc.git
    git remote set-url --push upstream DISABLED-no-pushes-to-upstream

## Bringing in upstream changes

    git fetch upstream
    git log --oneline main..upstream/main      # review what is new
    git switch -c sync/upstream-<date> main
    git merge upstream/main                    # or cherry-pick individual commits

Then build, run the `MinidiscTests` scheme and `./Scripts/doctor.sh --build` before merging the sync branch into `main`.

## Fork-specific changes to keep during merges

- **Minimum iOS:** the deployment target is iOS 27.0 (upstream: 26.1). Keep 27.0 when merging `project.pbxproj`; the iOS 27 adoption plan is `docs/plans/ios27.md`.
- **Identity:** bundle ID `com.ecliptik.minidisc` (plus `.tests` and `.uitests`), signing team `JG6P86C33U`, the background download session ID in `BackgroundDownloadTransport.swift`, the URL type name in `Info.plist`, and the bundle-ID check in `Scripts/doctor.sh`.
- **Branding:** `AppIcon.icon` (Apple 💽 emoji on a gold fill), `docs/app-icon.png`, the gold accent colour sets in `Assets.xcassets`, `MinidiscColors.AccentRamp`, `ColorContrastUtils` and the 2026 palette in `WrappedYearPalette`. The light and dark accents are chosen so white button labels stay at or above 4.5:1.
- **Signing:** team JG6P86C33U is a free personal team. It cannot use the Siri capability, so `com.apple.developer.siri` is left out of `Minidisc.entitlements` (upstream's SiriKit play handler stays but goes unused), and Apple allows only 10 new App IDs per 7 days across all of the team's apps.
- **CarPlay:** `Minidisc/CarPlay/` and a hand-written `UIApplicationSceneManifest` in `Info.plist` (generation is off). The `com.apple.developer.carplay-audio` entitlement is only in `Minidisc-Simulator.entitlements`, selected by `CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]`; move it into `Minidisc.entitlements` once a paid team has Apple's approval.
- **Widget extension:** the `MinidiscWidgets` target (`com.ecliptik.minidisc.widgets`), the `Shared/` folder compiled into both targets, and the App Group `group.com.ecliptik.minidisc` in both entitlements files. Upstream has no extension, so merges of `project.pbxproj` must keep the target, the embed phase and the `Shared` group.
- **Now Playing:** `NowPlayingCenterPresenter` uses the iOS 27 NowPlaying framework instead of MediaPlayer; keep it when upstream edits that file.
- **Links:** `MinidiscURLs` points at this GitHub repository, the App Store review and share rows are removed from Settings, and Acknowledgements credits upstream Minidisc.
- **Audits:** reports live in `docs/audits/`.

The 💽 artwork is Apple's emoji, which is Apple-copyrighted. That is acceptable for personal builds; replace it with an openly licensed design before any public or App Store distribution.
