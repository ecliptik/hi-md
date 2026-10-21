# UI redesign plan

Status: in progress, 2026-10-20. Based on the owner's mockups (screenshots of another Subsonic client, used for layout and style only; none of its name, artwork or trial UI is copied). Tracked on the "Minidisc UI redesign" card.

## Decisions

| Question | Decision |
|---|---|
| Tabs | Home, Discover, Library, Playlists, Search. Settings stays behind the Home button. Lidarr, when connected, becomes a Library tile so the bar stays at five tabs. |
| Album, playlist and artist screens | The mockup's layout. Black background by default, with an Appearance setting to bring back cover-coloured screens. |
| Accent colour | An Appearance > Accent Color setting, defaulting to the fork's gold. |
| Home and Search | Unchanged. |
| Mini player | Cover-tinted capsule with artwork, title, artist, Play/Pause and Next. |
| Equalizer | 10 bands (32 Hz to 16 kHz), presets and a preamp. |
| Auto-caching | Keeps favourites, recently played, pinned items and the upcoming queue on the phone, beyond explicit downloads. |

## Steps

1. **Appearance settings.** An Accent Color picker (gold by default) applied app-wide through the root tint, and a Detail Screens choice (Black or Cover Colours).
2. **Detail screens.** Album, playlist and artist screens: back, download and "…" buttons; centred cover, title, artist and "genre · year"; a shuffle button beside an accent-coloured Play button whose menu offers Play Next and Add to Queue; a "N tracks · total time" row; disc.track numbers on multi-disc albums, and a download marker and duration on each song. Black or cover-tinted per the setting.
3. **Mini player.** The capsule style, tinted from the playing album's cover colour.
4. **Tabs.** Add the Playlists tab (today's playlist list), move Lidarr into Library.
5. **Library tiles.** A grid of Albums, Album Artists, Tracks, Track Artists, Genres and Composers, then Shuffle Tracks and Shuffle Albums, then Recently Added. Favourites, Downloads, Local Files and Lidarr stay reachable as tiles or rows. Track Artists and Composers come from the library index (song artists and composer contributors).
6. **Equalizer.** Settings > Equalization with 10 bands, presets and a preamp. Implemented as biquad filters inside the existing per-deck ReplayGain audio tap, so streams, downloads and both crossfade decks are equalised alike. Gapless and crossfade must not regress: run the crossfade, gapless and recovery tests, and confirm by ear on a device.
7. **Auto-caching.** Settings > Downloads & Cache: keep favourites, recently played, pinned items and the next songs in the queue on the phone, with a storage limit and a Wi-Fi-only switch, separate from explicit downloads so the cache can be cleared on its own. A small progress indicator shows while it works.

Each step gets targeted tests and simulator screenshots; look and feel is confirmed on the phone once deployment works.
