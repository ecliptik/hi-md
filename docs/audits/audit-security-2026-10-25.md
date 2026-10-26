# Security and privacy audit: 2026-10-25

**Summary:** 0 CRITICAL, 2 HIGH, 9 MEDIUM, 14 LOW (25 findings). Since the last audit, 3 findings are fixed and 2 are partly fixed. Posture: GAPS. App Store readiness: NOT READY, because of H2.

The iOS code was audited on the `fix/navidrome-placeholder` checkout. The Winamp code (`ZipArchive`, `WinampSkin`, `M3UPlaylist`, `WinampSkinStore`) was read from the agent worktree copies. Re-check the Winamp findings once that code is merged.

## Map

| Area | State |
|---|---|
| Privacy manifest | Present but partial. SystemBootTime is missing (H2) and FileTimestamp lacks reason 3B52.1 (M3). The widget and Watch extensions have no manifest (L8). |
| Credentials | All in the keychain, including the new AI keys, with `AfterFirstUnlockThisDeviceOnly`. No secrets in UserDefaults or `@AppStorage`, and none hard-coded. |
| Network | ATS is off globally, a documented product decision. Integration endpoints are validated and warn on `http://`. The AI endpoints are fixed `https://` URLs on an ephemeral session. |
| Logging | Logger only, but about 6 sites log errors or URLs publicly (M2). The AI code logs only the provider, the status and counts. |
| ATT and export compliance | ATT not used. `ITSAppUsesNonExemptEncryption = NO` is correct. |
| Entitlements | Minimal |

## Regression check against audit-all-2026-10-20

**Fixed:**
- **sec H1:** integration endpoints accepted any URL scheme. `IntegrationEndpoint.swift` now restricts to http and https and warns on `http://`.
- **sec H2:** artwork URLs carrying the token were logged publicly. They're now redacted, and the loader's cache is bounded.
- **The `minidisc://` URL handler:** it's in place, and only extracts IDs.

**Partly fixed:**
- **X8, redirects:** `OriginScopedRedirectDelegate` is in place, with gaps (M5).

**Still present:**
- M1: ATS off.
- M2: `URLError` logged publicly.
- M3: FileTimestamp reason missing.
- M4: downloads included in backups.
- L1: the server base URL logged.
- L2: keychain items survive reinstall.
- L12: the scrobble queue in the temp folder.

**New:** H1, H2, M6–M9, L3–L10, L13, L14.

## HIGH

| ID | Finding | Where | Fix | Urgency | Blast radius | Effort | ROI |
|---|---|---|---|---|---|---|---|
| H1 | **Path traversal: server-controlled song and cover IDs become file paths.** `commitDownloadedSong` builds `"\(serverId)/\(song.id).\(ext)"` from the ID and the suffix or MIME type, then removes and copies files. Cover IDs go into `appendingPathComponent` for read, write, delete and move, and `_downloadCoverArt` writes unvalidated bytes. A hostile server, or someone intercepting plain `http://` with ATS off, can delete or overwrite files anywhere in the app container, up to corrupting the SwiftData store. `AudioStreamCache.swift:86-88` already guards against this class of bug. | `DownloadService.swift:379-431, 555-569, 1045-1077`, `ArtworkImageCache.swift:434, 476-479` | Use hashed file names (SHA-256 hex) or reject `/`, `\`, NUL, `.` and `..`. Allow-list file extensions. Check every path stays inside its folder. Migrate existing files once. Model on `LocalFileReference.url(in:)`. | Before any wider release | Hostile or intercepted servers | S | High |
| H2 | **`ProcessInfo.systemUptime` is used without a SystemBootTime declaration** (ITMS-91053), in the Now Playing anchor. | `PlayerService.swift:4117, 4134`, `PrivacyInfo.xcprivacy` | Declare SystemBootTime with reason 35F9.1, or switch to `ContinuousClock`. | Before any App Store upload | Whole app | S | High |

## MEDIUM

1. **M1. ATS is off globally** (`Info.plist:33-34`). Keep this as a product decision and note it for App Review. Consider `NSAllowsLocalNetworking`, and a banner for `http://` servers that aren't local.
2. **M2. Logging a `URLError` publicly includes the failing URL**, which carries the Subsonic `u`, `t` and `s` parameters (`PlayerService.swift:4019`, `DownloadService.swift:714, 831, 996, 1024`). Add an `error.logSafe` helper that logs only the domain and code, as `ServerService.swift:464` already does.
3. **M3. FileTimestamp is missing reason 3B52.1** for the local-music folder modification dates (`LocalMusicLibrary.swift:186`).
4. **M4. Downloads and cover caches are included in backups** (`DownloadService.swift:222-227`). Set `isExcludedFromBackup` on `downloads/` and `coverarts/`, and keep `playlistcovers/`.
5. **M5. Redirect header scoping is incomplete.** `CustomHeadersTransport` sets `httpAdditionalHeaders` on the session, and `checkCodecSupport` uses `URLSession.shared` with no redirect delegate (`CustomHeadersTransport.swift:19`, `PlayerService.swift:1043`). Inject the headers per request, and pass the delegate.
6. **M6. Secret custom-header values are copied to the general pasteboard** (`ServerFormView.swift:196-197`, `PlatformPasteboard.swift:5`). Use a local-only copy that expires after 60 s for sensitive values.
7. **M7. A Winamp `region.txt` with huge point counts overflows an integer and crashes the app** (`WinampSkin.swift:104-109`). Compare `count <= (coordinates.count - cursor) / 2` instead of multiplying.
8. **M8. An M3U `#EXTINF` duration of `inf` or `1e30` crashes when converted to an integer** (`M3UPlaylist.swift:169-173`). Check that the value is finite and below a week.
9. **M9. Skin BMPs are decoded with no format or size limits.** ImageIO sniffs the content, so non-BMP formats get through, and RLE BMPs can declare huge dimensions (`WinampSkin.swift:226-230`, 32 MB per entry). Require the `BM` magic number, check the header for at most 2048×2048, set `ShouldCache: false`, and cap entries at about 2 MB for BMPs and 64 KB for text files.

## LOW

1. **L1.** The server base URL is logged publicly (`AlbumsListView.swift:70`).
2. **L2.** Keychain items survive app deletion, and the AI keys inherit that. Consider clearing them on first launch when no server is configured.
3. **L3.** Some AI error bodies are shown to the user verbatim, and a body can quote the key (`AIRecommendationCloudClient.swift:149-158`). Drop the body or redact the key.
4. **L4.** The App Privacy label needs to cover cloud AI sending artist, album and playlist names to a third party. The in-app notice is good.
5. **L5.** The AI request's `x-api-key` header survives redirects; URLSession strips `Authorization` but not `x-api-key`. Add the redirect delegate.
6. **L6.** The API key field uses `.textContentType(.password)`, which can trigger password autofill. Remove it.
7. **L7.** `ExternalLinkOpener` should only accept http and https.
8. **L8.** The widget and Watch extensions have no privacy manifest. Check at archive validation.
9. **L9.** Siri and CarPlay entitlements are missing; this is expected on a personal team.
10. **L10.** The Mac sandbox lacks `files.bookmarks.app-scope`, so `WinampSkinStore.adopt` always falls back to copying the skin. The fallback is safe.
11. **L11.** `ExternalArtworkCache` logs full third-party artwork URLs publicly.
12. **L12.** The scrobble queue falls back to `NSTemporaryDirectory()` (`ListenBrainzService.swift:103`).
13. **L13.** The ZIP reader has no total archive size or decompression budget (`ZipArchive.swift:41-44`). Cap archives at about 16 MB.
14. **L14.** M3U files have no size or entry cap, and the resolver searches once per title. Cap at about 5,000 entries and 5 MB, and limit how many lookups run at once.

## Reviewed and clean

- **AI providers:**
  - keychain-only keys, never logged
  - ephemeral sessions to fixed https endpoints, with the field masked again when the app leaves the foreground
  - only the data the notice lists is sent (20 recent albums, 15 favourites, 25 artists, 15 playlist names); no IDs or URLs
  - links built with encoded query items
- **`ServerPlaceholderArtwork`** decodes only small images.
- **`ArtworkLoader`** limits decode size.
- **`LocalFileReference.url(in:)`** is the right model for H1.
- **The Winamp ZIP reader:**
  - no zip-slip, because nothing is extracted to disk
  - rejects ZIP64, encrypted archives and unknown compression methods
  - checks offsets and CRC
  - caps inflate at 32 MB per entry
- **The folder browser** has caps.
- **M3U entries** only look up songs on the user's own server.

## Recommendations

1. **Now:**
   - H2 and M3: manifest entries.
   - H1: safe file names plus containment checks.
   - M7 and M8: the Winamp crash fixes, before that code merges.
2. **Short term:**
   - M2: a safe-logging helper.
   - M5: per-request headers and the redirect delegate.
   - M4: backup exclusion.
   - M6: pasteboard.
   - M9, L13 and L14: parser limits.
3. **Longer term:**
   - M1: narrower ATS.
   - L8: extension manifests.
   - L4: privacy label.
   - Fuzz tests for the ZIP, M3U and region parsers.
