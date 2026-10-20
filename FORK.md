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
- **Links:** `MinidiscURLs` points at this GitHub repository, the App Store review and share rows are removed from Settings, and Acknowledgements credits upstream Minidisc.
- **Audits:** reports live in `docs/audits/`.

The 💽 artwork is Apple's emoji, which is Apple-copyrighted. That is acceptable for personal builds; replace it with an openly licensed design before any public or App Store distribution.
