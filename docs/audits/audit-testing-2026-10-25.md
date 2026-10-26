# Testing audit: 2026-10-25

**Summary:** 0 CRITICAL, 6 HIGH, 10 MEDIUM, 7 LOW. Health: GAPS. The unit suite is strong. The UI suite is red by default and slow, and one unit test is flaky.

This was static reading only; no test runs or result bundles were examined.

## Shape

- **Unit tests:**
  - 133 Swift Testing files with about 1,105 `@Test`s.
  - App-hosted, with MainActor default isolation.
  - Network calls are stubbed with `URLProtocol`.
- **UI tests:** 4 XCTest files. `MinidiscUXVerificationTests` has 39 scenarios.
- **Covered:** keychain (thin), persistence, networking, playback, crossfade, gapless.
- **Untested:** `SmartSearchService`/`SmartSearchError`, `RadioService`, `SearchHistoryService`, `LockedUserDefaults`.

| Metric | Value |
|---|---|
| Module coverage | About 85% |
| Error-path coverage | About 79% of error enums |
| Reliability | Unit: 0 blocking sleeps, 41 `Task.sleep` (8 real race windows). UI: 68 fixed 2–3 s sleeps. |
| Speed | All unit tests are hosted. The full UI run takes over an hour. |
| Keep | Per-test UserDefaults suites, in-memory SwiftData, `URLProtocol` stubs, `.timeLimit`, `.serialized` where stubs are shared |

## HIGH

| ID | Finding | Fix | Urgency | Blast radius | Effort | ROI |
|---|---|---|---|---|---|---|
| H1 | **`testFixtureQueueReorderAndSave` fails on the native drag.** The drag uses default velocity (few move events), so the iOS 27 `.reorderable()` gesture gets no hover. It aims at the exact midpoint of the target row (a before/after boundary) and reads the order once without polling. The test didn't change between 10-21 and 10-25, so something in the environment did. | Slow velocity with a hold, aim at the upper half of the row, poll with `XCTNSPredicateExpectation`, use the `queue.reorder.<id>` identifier, retry once. To confirm, look for the "Queue drag requested" log line, and run the test on f8f505f with today's simulator. | Soon | The only guard on queue reorder | S | High |
| H2 | **The recovery test races a busy MainActor.** `stalledStreamUsesNewlyCompletedCacheWithoutServerProbe(offline:)` uses `startupGrace` 100 ms. If more than 100 ms passes before `useCachedSource()`, a probe rebuilds from the stream URL. The negative-path tests (150–200 ms windows) have the same problem. | Quick fix: `startupGrace: .seconds(2)`, with `h.report` in the failure message. Lasting fix: inject a sleeper into the recovery timing so tests control time. Put `stop()` in a `defer`. | Now | About 31 recovery tests | S/M | High |
| H3 | **The two LargeText scenarios fail a geometry check** at line 1329 (`isHittable && maxY < app.maxY - 130`). The helper uses a fixed 124±12 alignment, absolute drag coordinates and an instant measurement at AX-XXXL. The minimising tab bar shifts the bottom inset. | Settle, then measure: derive the bounds from the navigation bar and tab bar, scroll the asserted label rather than the card top, poll until the frame is stable, and use a predicate for `hittable`. | Soon | 2 scenarios plus MoodRecovery | M | High |
| H4 | **Five scenarios are permanently red, which hides regressions.** | Fix them, or skip each with a tracked reason, then gate merges on "no new failures". | Soon | The whole UX suite | M | High |
| H5 | **`testLaunch` runs once per UI configuration** (`runsForEachTargetApplicationUIConfiguration = true`). It asserts nothing, has no fixture, and once hung. This is the cause of the hour-long runs. | Remove the override. Remove the template tests `testExample` and `testLaunchPerformance`. Put localised screenshots in an opt-in test plan. | Now | Every full UI run | S | Very high |
| H6 | **Hosted unit tests boot the whole app**, with no XCTest guard, and suites default to the MainActor. That causes timing flakes like H2. | Skip `launchIfNeeded()` when `XCTestConfigurationFilePath` is set. Mark pure suites `nonisolated`. Later, move pure logic into a Swift package. | Soon | All 133 files | M | Med–High |

## Diagnoses of known UI failures

| Scenario | Likely cause | Fix |
|---|---|---|
| MusicShortcutsColdStart (confidence high) | The AppIntentsTesting process doesn't get `-AppleLanguages (fr)`, so the app runs in English. `"Lecture"` is `"Play"`; "Pause" is the same in both languages. | `player.mini.playPause` identifiers plus an accessibility value, and assert on the identifier |
| MoodRecoveryAndDeletion (medium–high) | The `scrollCardToTop` alignment can't be reached, or the drag lands on the horizontal carousel | Bring the card into the visible band instead |
| PlayerAfterFocusedSearch (low–medium) | `XCTAssertFalse(miniTitle.isHittable)` encodes iOS 26 keyboard behaviour; the "Fermer" button is ambiguous; a 5 s wait for the keyboard animation | Wait on a predicate, and dismiss search by its own control |
| SearchPlaylistNavigation and SearchRankingAndFilters (low) | `assertTopSearchResult` expects a playlist row's label to be exactly the title, but it's a combined label. `submitSearch` loses keystrokes. Exact-set comparisons. | Match with `BEGINSWITH` or a title identifier. Wait for the field value. Compare with `isSuperset` first. |

## MEDIUM

1. **M1. About 68 fixed 2–3 s sleeps in the UX suite** (about 156 s), plus a blocking `Thread.sleep(2)` in `require`. Use an env-gated `dwell()` that defaults to 0.
2. **M2. UX tests leak app state.** Toggles are only restored on success, and mood generation is left off. Use `addTeardownBlock`, reset state through the fixture or launch arguments, and allow about 15 s for onboarding on first launch.
3. **M3. Selectors depend on French strings, and one relative-date assertion will break as the calendar moves on** (`:866-869`). Use identifiers and an injected clock.
4. **M4. `LayoutCaptureTests` asserts nothing, rotates the device and runs first.** Move it to an opt-in plan, or restore orientation reliably.
5. **M5. The template UI tests have no assertions.** Delete them, or keep a single launch smoke test.
6. **M6. The Foundation Models and search services have no tests:** SmartSearch errors, `matchingSongs`, `RadioService`, `SearchHistoryService`. Add an availability-guarded smoke test.
7. **M7. Keychain tests cover only the happy path,** with no `defer` cleanup.
8. **M8. Unit tests wait in real time:**
   - a real 5 s lyrics wait;
   - 50 ms negative checks that can pass without proving anything;
   - debounce tests that don't pass `debounce: .zero`;
   - 80–350 ms recovery windows.
9. **M9. `@unchecked Sendable` stubs are only partly synchronised** (`MoodPlaylistServiceTests` and 4 others).
10. **M10. UX tests skip silently on any other simulator.** Fail instead when `UX_REQUIRE_FIXTURE=1` is set.

## LOW

1. **L1.** A placeholder test, `MinidiscTests.example()`.
2. **L2.** 49 UserDefaults suites created, only 2 removed.
3. **L3.** Tests write into the host app's real Documents folder (`OfflineBrowsingTests:50-58`).
4. **L4.** Five copies of the same polling helper. Migrate them to `TestPolling.pollUntil`.
5. **L5.** Static stub state in `AIRecommendationCloudClientTests` is only safe because the suite is `.serialized`.
6. **L6.** Tests that could be parameterised (`AutoExtendTruncationTests`, `MediaResolverOriginTests`, `StreamSettingsTests`).
7. **L7.** `.timeLimit` is missing on larger async suites, such as `LyricsViewModelTests`.

## Regression check against audit-all-2026-10-20

| Previous | Status |
|---|---|
| H1 no `.timeLimit` | Fixed: 18 traits |
| H2 UI scheme set to parallelizable | Fixed |
| H3 real clocks in the recovery tests | Still present, now a confirmed flake (H2) |
| Copy-pasted `eventually` helpers | Partly fixed: the budget is now 5 s and a shared helper exists |
| HomeFeedContinuity can hang | Fixed |
| Recovery tests don't guarantee `stop()` | Still present |
| `@unchecked` stubs | Partly fixed (M9) |
| Sleep used as synchronisation | Mostly fixed. Negative-path sleeps remain. |
| UserDefaults suites leaked | Still present (L2) |
| Tests writing to real Documents | Still present (L3) |
| Hosted tests with MainActor default isolation | Still present (H6) |
| UX state dependence | Still present (M2) |
| UX fixed sleeps | Still present, slightly worse (M1) |
| Keychain had no tests | Fixed, thinly (M7) |
| Placeholder tests | Still present |
| Debounce tests | Still present |
| Wall-clock asserts | Mitigated |

## Quick wins

1. Remove the `runsForEachTargetApplicationUIConfiguration` override and the two template tests. This can save most of an hour per UI run.
2. Set `startupGrace` to `.seconds(2)` and add `h.report` to the failure message.
3. An env-gated `dwell()` helper, saving about 3 minutes per UX run.
4. A `player.mini.playPause` identifier, which fixes MusicShortcutsColdStart.
5. `debounce: .zero` in the debounce tests, and delete the placeholder test.
