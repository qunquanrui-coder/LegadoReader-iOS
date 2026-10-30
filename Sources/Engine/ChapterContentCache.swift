import Foundation

/// Versioned records prevent legacy single-page text files from being accepted as complete chapters.
public final class ChapterContentCache {
    private struct Entry: Codable {
        let version: Int
        let complete: Bool
        let chapterURL: String
        let sourceURL: String
        let pageCount: Int
        let text: String
    }
    private let directory: URL
    public init(directory: URL) { self.directory = directory }

    /// Preserve old downloads for recovery, while excluding them from verified cache reads.
    func quarantineLegacyCaches(at directories: [URL]) {
        let archive = directory.appendingPathComponent("legacy-unverified", isDirectory: true)
        let manager = FileManager.default
        for legacy in directories {
            guard legacy.standardizedFileURL != directory.standardizedFileURL,
                  manager.fileExists(atPath: legacy.path) else { continue }
            let destination = archive.appendingPathComponent(legacy.lastPathComponent, isDirectory: true)
            guard !manager.fileExists(atPath: destination.path) else { continue }
            do {
                try manager.createDirectory(at: archive, withIntermediateDirectories: true)
                try manager.moveItem(at: legacy, to: destination)
            } catch {
                // Leave the original untouched when it cannot be moved.
            }
        }
    }

    public func read(bookId: String, chapterIndex: Int, chapterURL: String? = nil, sourceURL: String? = nil) -> String? {
        let url = fileURL(bookId: bookId, chapterIndex: chapterIndex)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.version == 1, entry.complete, entry.pageCount > 0, !entry.text.isEmpty,
              chapterURL.map({ $0 == entry.chapterURL }) ?? true,
              sourceURL.map({ $0 == entry.sourceURL }) ?? true else { return nil }
        return entry.text
    }

    @discardableResult
    public func save(_ content: CompleteChapterContent, bookId: String, chapterIndex: Int) -> Bool {
        guard !content.text.isEmpty, content.pageCount > 0 else { return false }
        let url = fileURL(bookId: bookId, chapterIndex: chapterIndex)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let entry = Entry(version: 1, complete: true, chapterURL: content.chapterURL,
                              sourceURL: content.sourceURL, pageCount: content.pageCount, text: content.text)
            try JSONEncoder().encode(entry).write(to: url, options: .atomic)
            return true
        } catch { return false }
    }

    /// Returns all verified cached chapter indices for a book so directory lists can render O(1) badges without main-thread disk I/O per row.
    public func cachedChapterIndices(bookId: String, sourceURL: String? = nil) -> Set<Int> {
        let bookDir = directory.appendingPathComponent(bookId, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: bookDir, includingPropertiesForKeys: nil) else {
            return []
        }
        var indices = Set<Int>()
        for file in files where file.pathExtension == "json" {
            guard let idx = Int(file.deletingPathExtension().lastPathComponent) else { continue }
            if read(bookId: bookId, chapterIndex: idx, sourceURL: sourceURL) != nil {
                indices.insert(idx)
            }
        }
        return indices
    }

    private func fileURL(bookId: String, chapterIndex: Int) -> URL {
        directory.appendingPathComponent(bookId).appendingPathComponent("\(chapterIndex).json")
    }
}
