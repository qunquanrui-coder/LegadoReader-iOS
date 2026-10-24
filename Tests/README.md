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
