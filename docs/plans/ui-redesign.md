# UI redesign plan

Status: done in the simulator, 2026-10-20; look, feel and sound still to be checked on a device. Based on the owner's mockups (screenshots of another Subsonic client, used for layout and style only; none of its name, artwork or trial UI is copied).

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

## Outcome

All seven steps are on the `ui/redesign` branch. Differences from the plan: Settings stays behind the Home button, so the mockup's Settings tab is not used; the Library's Recently Added stays a grid; the mini player's capsule is the system tab-bar accessory, tinted from the cover. Auto-caching extends the existing offline-favourites sync and store instead of adding a new one, and its size is bounded by the 12-album recent limit rather than a byte cap. The equalizer is verified with synthetic signals in tests (a +6 dB band measures within 0.5 dB); it still needs a listen on a device, together with gapless and crossfade. The Siri permission row in Settings is hidden because the free team cannot sign the SiriKit entitlement; it crashed the app before.
