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
        for start in stride(from: 0, to: sources.count, by: 3) {
            let batch = sources[start..<min(start + 3, sources.count)]
            await withTaskGroup(of: ProbeResult.self) { group in
                for source in batch { group.addTask { await Self.probe(source) } }
                for await result in group {
                    let label = "\(result.source.bookSourceName) [\(result.source.bookSourceUrl)]"
                    let attempts = result.attempts.joined(separator: "；")
                    if let failure = result.failure {
                        print("Source probe failed: \(label) · \(attempts) · \(result.elapsedMilliseconds) ms")
                        XCTFail("\(label): \(failure)")
                    } else {
                        passed += 1
                        print("Source probe passed: \(label) · \(attempts) · \(result.elapsedMilliseconds) ms")
                    }
                }
            }
        }
        print("Source probe summary: \(passed)/\(sources.count) passed")
    }

    private struct ProbeResult {
        var source: BookSource
        var attempts: [String] = []
        var elapsedMilliseconds = 0
        var failure: String?
    }

    private static func probe(_ source: BookSource) async -> ProbeResult {
        var result = ProbeResult(source: source)
        let titles = ["噩梦使徒", "我的细胞监狱", "不许没收我的人籍", "诡秘之主", "凡人修仙传", "斗罗大陆"]
        let start = Date()
        if let reason = SourceSearchPolicy.unsupportedReason(source) {
            result.attempts = ["搜索规则不支持（\(reason)）"]
            result.failure = reason
            return result
        }

        for title in titles {
            var stage = "搜索"
            do {
                let target = Book(title: title, author: "", sourceUrl: "", sourceName: "", bookUrl: "")
                guard let book = try await SourceSearchService.search(source: source, keyword: title)
                    .first(where: { SourceSearchPolicy.isCandidate($0, for: target) }) else {
                    result.attempts.append("\(title) 搜索无精确匹配")
                    continue
                }

                stage = "目录"
                let toc = try await LegadoParser.shared.fetchToc(bookUrl: book.bookUrl, source: source)
                guard toc.complete, toc.chapters.count >= 100 else {
                    result.attempts.append("\(title) 搜索通过，目录不完整或章节过少（\(toc.chapters.count) 章）")
                    continue
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
                    result.attempts.append("\(title) 搜索和目录通过，相邻章节正文过短或重复")
                    continue
                }
                stage = "目录末尾正文"
                let tailIndex = toc.chapters.indices.reversed().prefix(12).first { index in
                    let title = toc.chapters[index].title
                    return !["完本感言", "完结感言", "新书", "公告", "请假", "更新通知", "上架感言"].contains { title.hasPrefix($0) }
                } ?? (toc.chapters.count - 1)
                let tail = try await loader.load(chapter: toc.chapters[tailIndex], source: source, referer: book.bookUrl,
                                                 nextChapterURL: tailIndex + 1 < toc.chapters.count ? toc.chapters[tailIndex + 1].url : nil)
                guard tail.text.count >= 300, tail.text != first.text, tail.text != second.text else {
                    result.attempts.append("\(title) 目录末尾正文过短或重复")
                    continue
                }
                result.attempts.append("\(title) 搜索、完整目录（\(toc.chapters.count) 章）、相邻正文（\(first.pageCount)+\(second.pageCount) 页）和目录末尾正文通过")
                result.elapsedMilliseconds = Int(Date().timeIntervalSince(start) * 1000)
                return result
            } catch {
                // Transport errors can include response URLs. Keep only the kind and code in logs.
                result.attempts.append("\(title) \(stage)失败（\(type(of: error)) \((error as NSError).code)）")
            }
        }
        result.elapsedMilliseconds = Int(Date().timeIntervalSince(start) * 1000)
        result.failure = "所有样本均未走通搜索、目录和正文"
        return result
    }
}
