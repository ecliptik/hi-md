# Accessibility audit: 2026-10-25

**Summary:** 0 CRITICAL, 6 HIGH, 14 MEDIUM, 7 LOW (27 findings).

This was a static audit of the `fix/navidrome-placeholder` checkout. Contrast was computed by hand from the asset catalog and the accent hex values, assuming a 10–15% tint on bordered buttons and white labels on `.borderedProminent`. VoiceOver behaviour is inferred. Health: NON-COMPLIANT on the strict rubric, but the core player and library flows work with VoiceOver, so in practice it's closer to GAPS. The last audit had 1 CRITICAL; this one has none.

## Surface

- **Controls:** about 500 controls. About 44 of 50 icon-only controls sampled have labels.
- **Gestures:** 7 of 9 have alternatives. The two without are the cover easter egg and the crop view's pinch and pan.
- **Fonts:** mostly semantic, with about 95% scaling coverage. The mini player is clamped to xxxLarge.
- **Reduce Motion:** respected by the logo spin, the marquee, toasts and Wrapped. Not respected by skeletons, shimmer, the equaliser bars or lyrics motion.
- **Accent:** gold by default (light #926A0C, dark #9A6D04), plus 8 other choices.

## Regression check against audit-all-2026-10-20

| Previous | Status |
|---|---|
| C1/X6 Wrapped is gesture-only | Fixed: labelled Close, adjustable and named actions, and auto-advance stops under VoiceOver or Switch Control. Remaining issue in M12. |
| H1/X7 toasts and errors not announced | Mostly fixed. The AI screens still don't announce (M4). |
| H2 accent contrast | Partly fixed: white on gold is now 4.9 and 4.6:1. New regressions: H1 and H2. |
| H3 Wrapped palette contrast | Still present (H5) |
| H4 fixed fonts | Fixed (`@ScaledMetric`, `scaledFont`) |
| H5 looping animations ignore Reduce Motion | Still present (H6) |
| H6 song rows not buttons | Fixed (`SongRow.swift:197-200`) |
| H7 state shown only by colour | Partly fixed: search chips now have `.isSelected`. Still missing on the player toolbar, the pills and the Wrapped period picker. |
| Mediums: artist hero buttons, lyrics toggle, mini player, scrubber and reorder handle, credential icons, headings | Still present |
| Cover images unlabelled | Improved. The player cover is still unlabelled (M1). |

## HIGH

| ID | Finding | Where | Fix | Urgency | Blast radius | Effort | ROI |
|---|---|---|---|---|---|---|---|
| H1 | **The 8 non-gold accents fail white-on-fill contrast in dark mode:** green 1.7, teal 1.9, orange 2.3, blue 2.5, purple 2.6, pink 2.7, coral 2.9 and red 3.1:1. They're used for prominent buttons, search chips, the period picker, empty-state and onboarding buttons, and the picker's own checkmark. | `AppearanceSettings.swift:27-39` and call sites | Retune the dark variants to a luminance of about 0.175–0.183 (gold's band), or use `fillColor` | Soon | Non-gold accents in dark mode | S | High |
| H2 | **Gold used as text on tinted or raised surfaces falls below 4.5:1:** 3.0–4.4:1 on tinted buttons, grouped backgrounds and raised rows (Open Album, Bandcamp, MusicBrainz, Continue, Undo). | `FreshReleaseDetailSheet.swift:81-92`, `ArtistDetailView.swift:948-967`, `AIRecommendationsView.swift:125-197`, `ToastView.swift:25-28` | A separate text-only gold token | Soon | AI screens, link buttons, toasts | S–M | High |
| H3 | **The player toolbar shows the active Lyrics and Queue button only by colour.** Gold on cover backgrounds is about 1.6–2.5:1, and dimmer than the inactive white icons. There's no `.isSelected`, the Repeat pill doesn't say its mode, and auto-extend doesn't say its state. | `FullPlayerView.swift:393-429, 1021-1066` | `.isSelected`, an `accessibilityValue` for repeat, and a non-colour cue (filled pill or underline) | Soon | Every player session | S | High |
| H4 | **Widget links have no accessible name.** VoiceOver just says "link" (Recently Played, and Pinned's open link). | `CollectionWidgets.swift:66-95`, `SnapshotProvider.swift:44-61` | `.accessibilityLabel(item.title)`, and hide the artwork | Soon | VoiceOver users of 2 widgets | S | High |
| H5 | **Wrapped palettes fail contrast**, including 2026's gold (white text at 2.4:1). | `WrappedYearPalette.swift:9-62`, `MeshGradientBackground.swift:47-55` | Cap the luminance of each gradient stop, or add a black overlay of about 35% behind the text | Soon | All of Wrapped | M | Medium |
| H6 | **Looping animations ignore Reduce Motion** (skeletons, shimmer, equaliser bars). | `SkeletonBlock.swift:20-24`, `LoadingStateView.swift:96-100`, `NowPlayingBarsIndicator.swift:29-44` | Check `accessibilityReduceMotion` and show a static state | Later | Every loading state | S | Medium |

## Specific answers

- **App Icon picker:** buttons with labels and `.isSelected`, a 62 pt target, and the ring passes 3:1. Gaps are in M7.
- **MinidiscLogoView:** a correct single "Minidisc" element, hidden where it's decorative, and the spin respects Reduce Motion. In the player it replaces the cover, which leads to M1.
- **The cover easter egg:** reachable only by chance, through a double-tap on an unlabelled image. Make it a named custom action.
- **The shared header:** the thumbnail stays in the accessibility tree, so VoiceOver finds a duplicate unlabelled cover.
- **Lyrics dimmed to 0.5 in the player:** passes as large text (about 3.2:1 worst case). Full screen fails (M3).
- **Playlists search:** no defects.
- **CoverArtView:** the logo placeholder is hidden; the other placeholder icons aren't (L1).

## MEDIUM

1. **M1. The full-player cover is unlabelled, and the easter egg isn't announced.** The cover also appears twice while the header shows. Label it with album and artist, hide it while the header shows, and add an "Show spinning disc" action.
2. **M2. Lyric lines have no button role or current-line state, the auto-scroll toggle has no label or state, and the animations ignore Reduce Motion** (`LyricsLineView.swift:57-63`, `LyricsView.swift:71, 126-135`, `KaraokeLyricsView.swift:91`).
3. **M3. Karaoke dimming (0.4 and 0.25 opacity, plus blur) is about 2.25–2.5:1 on bright covers.** Raise the minimum to 0.55. Drop the blur, and use 0.7 or higher, when Increase Contrast or Reduce Transparency is on.
4. **M4. The AI screens never announce loading, success, failure or Test Connection results.**
5. **M5. Green and orange status text in light mode is about 2.2:1** (AI screens, server form). Use darker semantic colours.
6. **M6. Each AI recommendation row is about 6 VoiceOver stops, with identical "Share" labels.** Combine them, and label "Share {album}".
7. **M7. The Appearance pickers lack group context. The accent swatches are 38 pt. A failed icon change isn't announced, and the icon picker shows no checkmark.**
8. **M8. At large text sizes:**
   - the compact header title is one line and truncates;
   - volume disappears at AX1 and above;
   - "Sleep timer on" is overridden by "More options";
   - the queue badge isn't spoken.
9. **M9. Queue pills are 40 pt and have no selected state.**
10. **M10. Small targets and missing roles:**
    - the scrubber is 32 pt high;
    - queue rows are `onTapGesture` with no button trait;
    - the Reorder handle has no actions.
11. **M11. The mini player expands on `onTapGesture` with no trait. "Previous" is swipe-only.**
12. **M12. Wrapped auto-advance still runs for Voice Control, Full Keyboard Access and users who need more time.** Add a visible pause button.
13. **M13. The credential icon buttons (eye, copy, remove) rely on automatic symbol labels** (`ServerFormView.swift:134-164`).
14. **M14. Only 3 elements are marked `.isHeader`** (empty states, AI headings and shelf titles aren't).

## LOW

1. **L1.** Decorative icons aren't hidden (empty states, `CoverArtView` placeholders, AI card icons).
2. **L2.** `MinidiscLogoView` has no `.isImage` trait for when it stands in for the cover.
3. **L3.** The easter egg's scale transition and the matched-geometry morph aren't gated by Reduce Motion.
4. **L4.** The privacy notice's "Continue" is ambiguous, and its headline isn't marked as a heading.
5. **L5.** The crop view is pinch and pan only. The default crop is usable.
6. **L7.** The circular play button in the Now Playing widget relies on its symbol's automatic label.
7. **L8.** System secondary text is about 3.5–4.6:1 on grouped backgrounds.

## Recommendations

1. **First:** H4, widget link names. It's Level A, with a one-line fix per widget.
2. **Short term:**
   - H1: retune the dark accents.
   - H2: a text-only gold token.
   - H3 and M9: selected traits, plus a cue that isn't just colour.
   - H5: Wrapped contrast.
   - H6: Reduce Motion guards.
   - M2 and M10: roles for lyric lines and queue rows.
   - M4: AI announcements.
   - M1: cover label and an easter-egg action.
3. **Later:** M8, M6, M7 and M14.

## Testing checklist

- VoiceOver: player, lyrics, queue, Settings pickers, AI screens, widgets, Watch.
- AX5 text size: player header, mini player, AI rows.
- Reduce Motion: skeleton, shimmer, equaliser, lyrics scrolling, player morph, easter egg.
- Increase Contrast with a non-gold accent in dark mode.
- Contrast checked with an eyedropper on a tinted gold button and on the toolbar over a bright cover.
- A keyboard on iPad: the player toolbar and queue.
