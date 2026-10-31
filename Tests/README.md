# Chapter integrity regression tests

Run `xcodegen generate`, then run the `LegadoReader` scheme's tests on an available iOS simulator.
The GitHub Actions workflow performs the same simulator tests before building either IPA.

The fixtures use `fixture.invalid` and an injected transport. They do not contact novel sites.

Coverage:
- Preserve chapter tails containing `,{` and normal prose mentioning phone reading.
- Traverse source-configured and conservative generic next-page links; retain the final page.
- Keep the next chapter separate, validate chapter numbers, accept Chinese/Arabic equivalents.
- Reject incomplete pages, missing continuation links, pagination loops, duplicate pages and page limits.
- Propagate cancellation without producing complete cacheable content.
- Accept valid short chapters and throw on missing content instead of caching an error message.
- Reject legacy plain-text caches, incomplete records, unsupported versions and source/URL mismatches.

Upgrade behavior: legacy downloaded chapter text is quarantined as unverified, not deleted, and must
be downloaded again before use as a verified chapter. Explicitly clearing all caches also clears the archive.
Bookshelf, sources, preferences and reading progress keep their existing storage keys.

Device acceptance still required for the reported books: compare the exact same source's complete
chapter ending and following chapter, test cached reopening, retry a failed later page, and verify
foreground/background TTS advances through the complete chapter. Fixture tests do not prove that
every third-party source provides complete text or usable pagination rules.


## Duo layout regressions (v3.5.0)

CI requires Xcode 27.1 with iOS SDK 27.1+ and runs the full suite on an iPhone Duo
simulator and an ordinary iPhone. It does not substitute another device for Duo.

ReaderAdaptiveLayoutTests cover narrow-window fallback and identity-bound restoration.
ReaderPaginationTests verify exact text preservation, grapheme boundaries, font/width effects,
and TextKit parity with UITextView. ReaderPageRenderingTests host the real SwiftUI page
and check every text view stays inside its page without hidden scrolling.

Physical folding, system split-view placement, asymmetric system bars, and headset behavior
still need device acceptance. These unit tests do not simulate hinge gestures.

## Page turn feedback (v3.5.1)

ReaderPagerTests exercise the native pager's directional animation requests, completed and
cancelled swipes, rapid requests, layout identity replacement, bounds and unanimated restoration.
The real pager is also mounted in a window to check that an animated turn has intermediate
visible movement and that its hosted page retains the measured text viewport.

On a device, check left/right taps, dragging then cancelling, several rapid taps, chapter
boundaries, and changing the Duo window during a turn. The center tap still opens the menu.

## Duo reading preferences and resume (v3.6.0)

ReaderChapterLandingTests cover reverse-turn chapter tails, odd/even spreads, deferred viewport
measurement, stale chapter identities and long paragraph offsets. ReadingPositionTests and
BackupMergeTests cover legacy JSON/maps, isolated UserDefaults round trips, source replacement
and winner-consistent backup merging. ReaderPreferenceTests and ReaderPagerTests cover independent
window typography and configurable tap regions. DuoReadingFlowTests persist an actual paginator
fragment from the first paragraph and relocate it under another window's typography.

Device acceptance: reopen a long paragraph in each paginated mode, reverse-turn across a cached
and uncached chapter, resize while that chapter loads, adjust each typography profile independently,
and try all three tap modes. Reverse-turning while listening pauses the new chapter at its landing
paragraph; resuming speech begins at that paragraph's start. Scroll mode resumes by paragraph.

## Final beta safety, bounded source expressions, and UI regressions (v3.8.0)

FinalDataFlowTests cover generation-bound `BookWriteToken` invalidation after shelf deletion or
source replacement, non-destructive `loadDefaultSources()` replenishment vs snapshot-backed
`resetSourcesToDefaults()` and `restoreSourcesFromLastResetSnapshot()`, cross-source backup merges
that preserve local offline chapter caches and relocate reading progress by chapter title, and
independent `readerConfigUpdatedAt` timestamps. BackupFileExporterTests verify off-body export and
stale temporary file cleanup. SpeechLifecycleTests cover `SpeechInterruptionPolicy` so audio
interruption `.ended` only resumes the exact session that was actively playing when interrupted.
SourceExpressionTests verify bounded expression evaluation, per-session `java.put/get` isolation,
step/loop rejection, cancellation, and mixed CSS/JS search list rejection. ReaderRenderWorkTests
verify paragraph cache reuse across font/viewport changes, coalesced background reflow, and
source+chapter URL verification for cached chapter badges.

SettingsSafetyUITests (`LegadoReaderUITests`) launch the real application on both iPhone Duo and
ordinary iPhone simulators to verify non-destructive built-in source replenishment, full-reset
confirmation, and one-tap undo restoration through the user interface.
