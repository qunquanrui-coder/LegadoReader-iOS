import Foundation
import XCTest
@testable import LegadoReader

/// Opt-in curator check. The JSON lives in the test bundle only, never the app.
final class LiveSourceProbeTests: XCTestCase {
    func testCandidateSourcesThroughNativeReader() async throws {
        guard let url = Bundle(for: Self.self).url(forResource: "SourceProbeCandidates", withExtension: "json") else {
            throw XCTSkip("No local curation input; see Tests/README.md.")
        }
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: url))
        XCTAssertFalse(sources.isEmpty)
        XCTAssertEqual(Set(sources.map(\.bookSourceUrl)).count, sources.count, "Duplicate candidate identities")

        var passed = 0
        for start in stride(from: 0, to: sources.count, by: 4) {
            let batch = sources[start..<min(start + 4, sources.count)]
            await withTaskGroup(of: ProbeResult.self) { group in
                for source in batch { group.addTask { await Self.probe(source) } }
                for await result in group {
                    let label = "\(result.source.bookSourceName) [\(result.source.bookSourceUrl)]"
                    if let failure = result.failure {
                        XCTFail("\(label): \(failure)")
                    } else {
                        passed += 1
                        print("Source probe passed: \(label) (\(result.keyword), \(result.tocSize) chapters, \(result.elapsedMilliseconds) ms)")
                    }
                }
            }
        }
        print("Source probe summary: \(passed)/\(sources.count) passed")
    }

    private struct ProbeResult {
        var source: BookSource
        var keyword = ""
        var tocSize = 0
        var elapsedMilliseconds = 0
        var failure: String?
    }

    private static func probe(_ source: BookSource) async -> ProbeResult {
        var result = ProbeResult(source: source)
        let titles = ["斗罗大陆", "诡秘之主", "凡人修仙传", "三体", "红楼梦", "紅樓夢", "三國演義"]
        let start = Date()
        var stage = "搜索"
        do {
            for title in titles {
                result.keyword = title
                let target = Book(title: title, author: "", sourceUrl: "", sourceName: "", bookUrl: "")
                guard let book = try await SourceSearchService.search(source: source, keyword: title)
                    .first(where: { SourceSearchPolicy.isCandidate($0, for: target) }) else { continue }

                stage = "目录"
                let toc = try await LegadoParser.shared.fetchToc(bookUrl: book.bookUrl, source: source)
                result.tocSize = toc.chapters.count
                guard toc.complete, toc.chapters.count >= 5 else {
                    result.failure = "目录不完整或章节过少"
                    return result
                }

                stage = "连续章节正文"
                // Use an interior pair so a preface or free first chapter cannot pass on its own.
                let index = min(toc.chapters.count / 4, toc.chapters.count - 3)
                let loader = ChapterContentLoader.shared
                let first = try await loader.load(chapter: toc.chapters[index], source: source, referer: book.bookUrl,
                                                  nextChapterURL: toc.chapters[index + 1].url)
                let second = try await loader.load(chapter: toc.chapters[index + 1], source: source, referer: book.bookUrl,
                                                   nextChapterURL: toc.chapters[index + 2].url)
                guard first.text.count >= 300, second.text.count >= 300, first.text != second.text else {
                    result.failure = "相邻章节正文过短或重复"
                    return result
                }
                result.elapsedMilliseconds = Int(Date().timeIntervalSince(start) * 1000)
                return result
            }
            result.failure = "样本书名均无精确搜索结果"
        } catch {
            // Some transport errors include response URLs; print only the error kind/code.
            result.failure = "\(stage)失败：\(type(of: error)) (\((error as NSError).code))"
        }
        return result
    }
}
