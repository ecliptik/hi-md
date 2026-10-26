# Winamp mode (feature request)

Status: phases 1 and 2 built on the native Mac app, plus a round of polish (2026-10-26). Requested by the owner on 2026-10-25 as an easter egg for the Mac version: a mode that looks and works like classic Winamp 2 / XMMS. Tracked on the "Minidisc Winamp mode" board card.

## Progress

- **Phase 1, main window:** done. Skins (`.wsz`), the main window with transport, seek, volume, balance, time, scrolling title, kbps/kHz, spectrum and oscilloscope, the clutter bar, Double Size and Always on Top, and the Eject folder browser.
- **Phase 2, playlist, equaliser and docking:** done.
  - Playlist window from `pledit.bmp` and `pledit.txt`, resizable in 25×29 steps, showing the play queue with numbers, titles, durations and "selected/total" time. Double-click plays, drag (or ⌥↑/⌥↓) reorders, Delete removes, and the +ADD / −REM / SEL / MISC / LIST menus work. ADD's URL opens the server folder browser, and FILE and DIR add local files (see Polish). Edits go through PlayerService's selection-checked move and remove, one song at a time, so the gapless or crossfade transition is re-prepared only when the next song changes; the playing song is never moved or removed.
  - Equaliser window from `eqmain.bmp`: ON, AUTO (the built-in preset for the playing song's genre), preamp and ten bands bound to `EqualizerSettings`, the spline curve, and Presets with save, delete, and Winamp `.eqf` import and export. Each slider drives the engine band in the same position (32 Hz to 16 kHz); Minidisc Gold is labelled with those frequencies. The app's preamp only cuts, so the preamp slider stops at 0 dB.
  - M3U: LIST saves the queue as `.m3u8` (`#EXTINF` plus the server path, or "Artist/Album/NN - Title" when the server gives none) and opens `.m3u`/`.m3u8` through `M3UPlaylistResolver`. LIST > Save also creates a server playlist.
  - Docking: windows snap to each other and to screen edges within 10 points, windows docked to the main window move with it, and windowshade, playlist resizing and zoom keep the stack docked. Windowshade for the main window, the playlist, and the equaliser when the skin has `eq_ex.bmp`. Positions, visibility, shade and the playlist's size are remembered.
- **Polish, from testing the signed build against Navidrome 0.64 (2026-10-26):** done.
  - The Add Music browser failed with "Couldn't reach your server": Navidrome sends `getMusicFolders` IDs as numbers (`"id": 1`, as the Subsonic spec does) and SwiftSonic's `MusicFolder.id` is a string, so the response didn't decode. `WinampSubsonicSource` now reads a failed response again with `MusicLibraryFolder`, which takes either. `getIndexes` and `getMusicDirectory` were checked against Navidrome-shaped responses (`MusicFolderBrowserNavidromeTests`). A listing that can't be read, or a server error, now says so instead of "couldn't reach".
  - ADD > URL opens the server folder browser. ADD > FILE (audio files) and ADD > DIR (folders, with their subfolders) use the open panel and append to the queue through `LocalMusicStore`, the iPhone's local music store: each chosen folder or file becomes an entry with a security-scoped bookmark on the Mac (read-only; the sandbox's user-selected files entitlement was already on), and the songs play as `local:` songs after a relaunch. Single files are entries with `isFile`. Opening `.m3u` files stays in LIST, View > Open Playlist File… and the playlist's right-click menu; Eject still opens the server browser. The Mac has no screen yet for removing local entries.
  - Zoom 1×, 2×, 3× and 4× replaces Double Size (2×), in `WinampPreferences.zoom`: a Zoom submenu in the main window's right-click menu and the playlist's MISC > options, and View > Winamp Zoom (⌘⌥1 to ⌘⌥4). The clutter bar's D switches between 1× and 2× and goes back to 1× from 3× or 4×. `WinampDocking.zoom` scales the windows about the main window's top-left corner with exact sizes, keeps docked windows docked, and moves the stack back inside its screen when a bigger zoom would run off an edge.
- **Still open:** the shaded equaliser's volume and balance sliders, the shaded main window's small visualiser, the hidden "nullsoft" way in, and opening `.m3u` files from Finder.

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
| Skins | Parse the `.wsz` zip: `main`, `cbuttons`, `titlebar`, `posbar`, `volume`, `balance`, `numbers`/`nums_ex`, `text`, `playpaus`, `monoster`, `shufrep`, `eqmain`, `pledit` BMPs, plus `pledit.txt`, `viscolor.txt` and `region.txt`. Draw sprites pixel-exact with nearest-neighbour scaling at 1× to 4×. |
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

## Decisions

- A native macOS target (`MinidiscMac`), not Catalyst.
- The equaliser keeps the app's ten bands; Winamp's sliders map onto them in order.
- Winamp mode opens alongside the main Mac window.
