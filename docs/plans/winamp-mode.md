# Winamp mode (feature request)

Status: idea, not started. Requested by the owner on 2026-10-25 as an easter egg for the Mac version: a mode that looks and works like classic Winamp 2 / XMMS. Tracked on the "Minidisc Winamp mode" board card.

## The request

- Look and feel of the classic player: the 275×116 main window with its LCD time, scrolling title, kbps/kHz and stereo indicators, visualiser, seek, volume and balance sliders, and the Prev/Play/Pause/Stop/Next/Eject buttons with Shuffle and Repeat.
- An equaliser window, and a playlist window that can be shown or hidden. Windows dock to each other, and there are windowshade (title-bar only) and double-size modes.
- Skins: load classic `.wsz` skins. XMMS uses the same format.
- Adding music browses Navidrome like a file system (artist folders, then album folders, then tracks), with the ability to save and open `.m3u` playlists.

## How it maps onto Minidisc

| Piece | Approach |
|---|---|
| Playback | The existing player service and two-deck engine. Winamp mode is a different face on the same queue, so gapless, crossfade, ReplayGain, scrobbling and Now Playing keep working. Gapless and crossfade must not regress. |
| Equaliser | The app already has 10 bands (32 Hz–16 kHz) and a preamp as biquads in the per-deck audio tap. Winamp's sliders are 60, 170, 310, 600 Hz, 1, 3, 6, 12, 14 and 16 kHz: either map them onto the existing bands or let the EQ use Winamp's frequencies in this mode. The ON, AUTO and Presets buttons map to the existing settings. |
| Visualiser | Spectrum and oscilloscope from a read-only tap after the mixer. It must never touch the decks' scheduling. Draw it only while the window is visible, at Winamp's ~30 fps, with colours from the skin's `viscolor.txt`. |
| Playlist window | The play queue: numbered rows with durations, the selected and playing colours from `pledit.txt`, a total time, and the +ADD/−REM/SEL/MISC/LIST buttons. It also has drag to reorder, J to jump to a file, and the Z X C V B shortcuts. |
| "Add" browser | Use Subsonic's folder endpoints, `getMusicFolders`, `getIndexes` and `getMusicDirectory`, which SwiftSonic already wraps. They follow the server's real directory layout. An optional view built from tags (Artist / Album / Track) covers libraries whose folders aren't tidy. Multi-select is supported, and "add folder" adds everything beneath it. |
| M3U | Save the playlist window as `.m3u8`: `#EXTM3U`, `#EXTINF:<seconds>,Artist - Title`, then each song's server `path`. Navidrome imports M3U files found in the music folder, so a saved list can come back as a server playlist. Optionally also save it straight to Navidrome with `createPlaylist`. Opening an `.m3u`/`.m3u8` resolves entries by path first, then by artist and title. |
| Skins | Parse the `.wsz` zip: `main`, `cbuttons`, `titlebar`, `posbar`, `volume`, `balance`, `numbers`/`nums_ex`, `text`, `playpaus`, `monoster`, `shufrep`, `eqmain`, `pledit` BMPs, plus `pledit.txt`, `viscolor.txt` and `region.txt`. Draw sprites pixel-exact with nearest-neighbour scaling at 1× or 2×. |
| Default skin | Ship an original skin made for Minidisc, gold on black. Don't bundle Nullsoft's base skin or third-party skins: they're copyrighted. Users load their own `.wsz` files. |
| Way in | A hidden toggle, for example a View > Winamp Mode menu item with a shortcut, or the classic "nullsoft" typed in About. It's remembered between launches. |

## Platform question

The Mac app today is Mac Catalyst: `SUPPORTS_MACCATALYST` is on, but the target currently builds for iPhone and iPad only. Classic Winamp needs:

- borderless, non-rectangular windows that snap together
- always-on-top
- pixel-exact drawing
- global media keys

Catalyst can't reach NSWindow for these without an AppKit plug-in bundle. Options:

1. **Catalyst plus an AppKit bundle** that owns the Winamp windows. This keeps one app.
2. **A native macOS target** (SwiftUI and AppKit) that shares `Shared/` and the services. It's cleaner for windowing, but more to maintain.

Both need checking against the free personal team's limits: Mac signing, and one App ID per new bundle (see the personal-team-signing notes).

## Suggested phases

1. **Main window.** A Mac window in the original skin with transport, seek, volume, the time display and the scrolling title, driven by the existing player.
2. **Playlist window.** Show/hide, the Navidrome folder browser for +ADD, and saving and opening M3U.
3. **Equaliser window.** Wired to the existing EQ, with presets.
4. **Skins and visualiser.** The `.wsz` loader and the spectrum and oscilloscope.
5. **Polish.** Docking and snapping, windowshade, double size, always-on-top, keyboard shortcuts, and the hidden way in.

## Open questions

- Catalyst plus AppKit bundle, or a native macOS target?
- Should the EQ follow Winamp's frequencies in this mode, or keep the app's 10 bands?
- Should Winamp mode replace the main Mac window while it's on, or open alongside it?
