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
