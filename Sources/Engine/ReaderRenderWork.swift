import Foundation
import CoreGraphics

/// Font and viewport changes reuse the same formatted text; only text-changing settings
/// invalidate it. The reader owns one cache, so chapters and books never share mutable state.
struct ReaderParagraphCache {
    private var content: String?
    private var conversion: ChineseConversionMode?
    private var rules: [String] = []
    private var value: [String] = []
    private(set) var formattingCount = 0

    mutating func paragraphs(from text: String, config: ReaderConfig) -> [String] {
        if content != text || conversion != config.effectiveChineseConversion || rules != config.effectivePurifyRules {
            content = text
            conversion = config.effectiveChineseConversion
            rules = config.effectivePurifyRules
            value = ChapterTextFormatter.paragraphs(from: text, config: config)
            formattingCount += 1
        }
        return value
    }
}

struct ReaderPageWork {
    let size: CGSize
    let viewport: CGSize
    let presentation: ReaderPresentation
    let config: ReaderConfig
    let paragraphs: [String]
    let title: String
}

actor ReaderPageWorker {
    private let paginate: (ReaderPageWork) -> [ReaderPage]

    init(paginate: @escaping (ReaderPageWork) -> [ReaderPage] = { work in
        ReaderPaginator.paginate(paragraphs: work.paragraphs, chapterTitle: work.title,
                                 style: ReaderPageStyle(config: work.config), viewport: work.viewport)
    }) {
        self.paginate = paginate
    }

    func render(_ work: ReaderPageWork) throws -> [ReaderPage] {
        try Task.checkCancellation()
        guard work.presentation != .scroll else { return [] }
        // Each measurement constructs its own TextKit object graph and never attaches a
        // text view. No layout manager/storage/container is shared with the displayed UI.
        let pages = paginate(work)
        try Task.checkCancellation()
        return pages
    }
}

/// Coalesces continuous resize notifications and ignores a completed older request even
/// when its worker cannot immediately observe cancellation.
@MainActor
final class ReaderReflowQueue {
    typealias Renderer = (ReaderPageWork) async throws -> [ReaderPage]
    private var task: Task<Void, Never>?
    private var identity = UUID()
    private let renderer: Renderer
    private let delay: UInt64
    var pendingWork: Task<Void, Never>? { task }

    nonisolated init(delay: UInt64 = 80_000_000, renderer: Renderer? = nil) {
        self.delay = delay
        let worker = ReaderPageWorker()
        self.renderer = renderer ?? { try await worker.render($0) }
    }

    func cancel() {
        identity = UUID()
        task?.cancel()
        task = nil
    }

    func request(_ work: ReaderPageWork, commit: @escaping (ReaderPageWork, [ReaderPage]) -> Void) {
        cancel()
        let token = identity
        task = Task {
            do {
                if delay > 0 { try await Task.sleep(nanoseconds: delay) }
                let pages = try await renderer(work)
                guard !Task.isCancelled, identity == token else { return }
                commit(work, pages)
            } catch { /* superseded requests have no UI or progress side effects */ }
        }
    }
}
