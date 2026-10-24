import Foundation

/// Persisted copy of a book's chapter catalogue.
///
/// The reader must be able to open a book whose chapters were downloaded while the
/// device is offline. Chapter text alone is useless without the chapter list (titles +
/// content URLs), so the verified TOC is stored next to the chapter cache. The record
/// is bound to the source URL and book URL, which makes a book-source switch
/// invalidate it automatically instead of showing the previous site's chapters.
public struct TocSnapshot: Codable, Equatable {
    public var version: Int
    public var bookId: String
    public var sourceURL: String
    public var bookURL: String
    public var fetchedAt: Date
    /// True only when the catalogue walk finished without hitting a page limit, a
    /// repeated page, a URL loop or a fetch error.
    public var complete: Bool
    public var chapters: [Chapter]

    public init(version: Int = TocCache.currentVersion,
                bookId: String,
                sourceURL: String,
                bookURL: String,
                fetchedAt: Date = Date(),
                complete: Bool,
                chapters: [Chapter]) {
        self.version = version
        self.bookId = bookId
        self.sourceURL = sourceURL
        self.bookURL = bookURL
        self.fetchedAt = fetchedAt
        self.complete = complete
        self.chapters = chapters
    }
}

public final class TocCache {
    public static let currentVersion = 1

    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    /// Reads the persisted TOC only if it belongs to the same book + source.
    public func read(bookId: String, sourceURL: String, bookURL: String) -> TocSnapshot? {
        guard !bookId.isEmpty else { return nil }
        let url = fileURL(bookId: bookId)
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(TocSnapshot.self, from: data),
              snapshot.version == Self.currentVersion,
              snapshot.bookId == bookId,
              snapshot.sourceURL == sourceURL,
              snapshot.bookURL == bookURL,
              !snapshot.chapters.isEmpty else {
            return nil
        }
        return snapshot
    }

    @discardableResult
    public func save(bookId: String,
                     sourceURL: String,
                     bookURL: String,
                     chapters: [Chapter],
                     complete: Bool,
                     fetchedAt: Date = Date()) -> Bool {
        guard !bookId.isEmpty, !chapters.isEmpty else { return false }
        let snapshot = TocSnapshot(bookId: bookId, sourceURL: sourceURL, bookURL: bookURL,
                                   fetchedAt: fetchedAt, complete: complete, chapters: chapters)
        let url = fileURL(bookId: bookId)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    public func remove(bookId: String) {
        guard !bookId.isEmpty else { return }
        try? FileManager.default.removeItem(at: fileURL(bookId: bookId))
    }

    private func fileURL(bookId: String) -> URL {
        directory.appendingPathComponent(bookId).appendingPathComponent("toc.json")
    }
}
