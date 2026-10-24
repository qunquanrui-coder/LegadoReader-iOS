import Foundation

/// Rules for accepting a background catalogue refresh.
///
/// A refresh that stopped early (page limit, repeated page, URL loop or network error)
/// must never replace a locally usable catalogue: doing so can shrink a 1,000-chapter
/// TOC to the 100 chapters fetched before the failure and relocate the reading position.
public enum TocUpdatePolicy {
    /// A complete refresh always wins; an incomplete one is only usable when nothing
    /// was cached yet (first-time open of this book).
    public static func shouldAcceptRefresh(resultComplete: Bool, localChapterCount: Int) -> Bool {
        if resultComplete { return true }
        return localChapterCount == 0
    }

    /// Rejects results belonging to a book/source that is no longer the displayed one,
    /// e.g. an in-flight TOC request from source A finishing after the user switched to B.
    public static func matchesRequest(currentSourceUrl: String,
                                      currentBookUrl: String,
                                      requestedSourceUrl: String,
                                      requestedBookUrl: String) -> Bool {
        currentSourceUrl == requestedSourceUrl && currentBookUrl == requestedBookUrl
    }

    /// "全本缓存完成" is only true when both the catalogue itself is complete and every
    /// chapter in that catalogue was cached.
    public static func isFullCacheComplete(savedCount: Int, totalCount: Int, tocComplete: Bool) -> Bool {
        tocComplete && totalCount > 0 && savedCount == totalCount
    }

    /// True when the cached chapter list belongs to another book/source and must be dropped
    /// (e.g. after a book-source switch) instead of being shown as the new source's catalogue.
    public static func requiresTocReset(loadedSourceUrl: String?,
                                        loadedBookUrl: String?,
                                        currentSourceUrl: String,
                                        currentBookUrl: String) -> Bool {
        loadedSourceUrl != currentSourceUrl || loadedBookUrl != currentBookUrl
    }
}

/// Rules for restarting TTS after an asynchronous chapter load.
///
/// A chapter switch requests carry-over playback, but the user may stop listening while
/// the new chapter is still loading; restarting must then be suppressed.
public enum PlaybackTransitionPolicy {
    public static func shouldResume(carryOverRequested: Bool,
                                    carryOverPending: Bool,
                                    hasParagraphs: Bool,
                                    sessionUnchanged: Bool) -> Bool {
        carryOverRequested && carryOverPending && hasParagraphs && sessionUnchanged
    }

    /// The 听书 button must not read the previous chapter's paragraph buffer while the new
    /// chapter is still fetching: the loaded content URL has to match the current chapter.
    public static func canStartListening(loadedChapterURL: String?,
                                         currentChapterURL: String?,
                                         hasParagraphs: Bool) -> Bool {
        guard hasParagraphs, let current = currentChapterURL, !current.isEmpty else { return false }
        return loadedChapterURL == current
    }
}
