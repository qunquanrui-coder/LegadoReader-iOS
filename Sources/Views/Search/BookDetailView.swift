import SwiftUI

public struct BookDetailView: View {
    @ObservedObject var storage = StorageManager.shared
    @State var book: Book
    @State private var chapters: [Chapter] = []
    @State private var isLoadingChapters = true
    @State private var errorMessage: String?
    @State private var isReading = false
    @State private var showChangeSource = false
    @State private var showAllChapters = false
    @State private var isCachingFullBook = false
    @State private var fullCacheStatusText: String? = nil
    @State private var cacheTask: Task<Void, Never>? = nil
    @State private var tocTask: Task<Void, Never>? = nil
    /// False when the catalogue was only partially fetched — "全本缓存完成" must not be claimed.
    @State private var isTocComplete: Bool = true
    /// Identity (source URL + book URL) of the chapter list currently shown in this page.
    @State private var loadedTocSourceUrl: String? = nil
    @State private var loadedTocBookUrl: String? = nil
    
    public init(book: Book) {
        _book = State(initialValue: book)
    }
    
    private var isAddedToShelf: Bool {
        storage.bookshelf.contains(where: { $0.title == book.title && $0.author == book.author })
    }
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Hero Book Card
                HStack(alignment: .top, spacing: 18) {
                    BookCoverView(
                        title: book.title,
                        author: book.author,
                        coverUrl: book.coverUrl,
                        width: 96,
                        height: 132,
                        cornerRadius: 10
                    )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(book.title)
                            .font(.system(size: 20, weight: .bold, design: .serif))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "person.text.rectangle")
                                .font(.caption)
                                .foregroundColor(.indigo)
                            Text(book.author)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 8) {
                            Text(book.sourceName)
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.indigo.opacity(0.12))
                                .foregroundColor(.indigo)
                                .clipShape(Capsule())
                            
                            Button {
                                showChangeSource = true
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("换源")
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                            }
                        }
                        
                        if let latest = book.latestChapter, !latest.isEmpty {
                            Text("最新：\(latest)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
                )
                
                // Primary Action Buttons
                HStack(spacing: 12) {
                    Button {
                        if isAddedToShelf {
                            storage.removeBookFromShelf(book)
                        } else {
                            storage.addBookToShelf(book)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isAddedToShelf ? "checkmark.circle.fill" : "plus.circle.fill")
                            Text(isAddedToShelf ? "已在书架" : "加入书架")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(isAddedToShelf ? Color.secondary.opacity(0.15) : Color.indigo.opacity(0.12))
                        .foregroundColor(isAddedToShelf ? .secondary : .indigo)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    
                    Button {
                        if let saved = storage.bookshelf.first(where: { $0.title == book.title && $0.author == book.author }) {
                            book.currentChapterIndex = saved.currentChapterIndex
                            book.currentParagraphIndex = saved.currentParagraphIndex
                            book.currentChapterTitle = saved.currentChapterTitle
                        }
                        storage.markBookAsRecentlyRead(book)
                        isReading = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "book.fill")
                            Text(isAddedToShelf ? "继续阅读" : "立即阅读")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(
                            LinearGradient(
                                colors: [Color.indigo, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: Color.indigo.opacity(0.3), radius: 6, x: 0, y: 3)
                    }
                    
                    Button {
                        if isCachingFullBook {
                            cacheTask?.cancel()
                            isCachingFullBook = false
                            fullCacheStatusText = "已暂停缓存"
                        } else {
                            startFullBookCache()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isCachingFullBook ? "stop.circle.fill" : "arrow.down.to.line.circle.fill")
                            Text(isCachingFullBook ? "停止" : "全本缓存")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(Color.orange.opacity(0.15))
                        .foregroundColor(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .disabled(chapters.isEmpty)
                }
                
                if let status = fullCacheStatusText {
                    HStack(spacing: 8) {
                        if isCachingFullBook {
                            ProgressView().scaleEffect(0.75)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                        }
                        Text(status)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.indigo)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                }
                
                // Synopsis Card
                if let intro = book.intro, !intro.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("作品简介")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                        Text(intro)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .lineSpacing(5)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
                
                // Chapters Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("章节目录")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                        Spacer()
                        if !chapters.isEmpty {
                            Button {
                                showAllChapters = true
                            } label: {
                                HStack(spacing: 4) {
                                    Text("共 \(chapters.count) 章 · 查看全部")
                                    Image(systemName: "chevron.right")
                                }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.indigo)
                            }
                        }
                    }
                    
                    if isLoadingChapters {
                        HStack(spacing: 10) {
                            Spacer()
                            ProgressView()
                            Text("正在智能解析章节目录...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 30)
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            HStack(spacing: 12) {
                                Button("重试加载") {
                                    loadChapters()
                                }
                                .buttonStyle(.bordered)
                                
                                Button("一键换源") {
                                    showChangeSource = true
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(chapters.prefix(15)) { ch in
                                Button {
                                    book.currentChapterIndex = ch.index
                                    book.currentChapterTitle = ch.title
                                    book.currentParagraphIndex = 0
                                    storage.addBookToShelf(book)
                                    storage.updateBookProgress(
                                        bookId: book.id,
                                        bookTitle: book.title,
                                        bookAuthor: book.author,
                                        chapterIndex: ch.index,
                                        chapterTitle: ch.title,
                                        totalChapters: chapters.count,
                                        paragraphIndex: 0
                                    )
                                    isReading = true
                                } label: {
                                    HStack {
                                        Text(ch.title)
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.4))
                                    }
                                    .padding(.vertical, 11)
                                }
                                Divider()
                            }
                            
                            if chapters.count > 15 {
                                Button {
                                    showAllChapters = true
                                } label: {
                                    Text("展开全部 \(chapters.count) 个章节")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.indigo)
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 12)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadChapters()
        }
        .onDisappear {
            tocTask?.cancel()
        }
        .sheet(isPresented: $showChangeSource) {
            ChangeSourceSheet(currentBook: book) { newBook in
                self.book = newBook
                loadChapters()
            }
        }
        .sheet(isPresented: $showAllChapters) {
            ChapterListView(
                bookId: book.id,
                chapters: chapters,
                currentIndex: book.currentChapterIndex,
                onSelectChapter: { idx in
                    book.currentChapterIndex = idx
                    book.currentParagraphIndex = 0
                    if idx < chapters.count {
                        book.currentChapterTitle = chapters[idx].title
                    }
                    storage.addBookToShelf(book)
                    storage.updateBookProgress(
                        bookId: book.id,
                        bookTitle: book.title,
                        bookAuthor: book.author,
                        chapterIndex: idx,
                        chapterTitle: idx < chapters.count ? chapters[idx].title : "",
                        totalChapters: chapters.count,
                        paragraphIndex: 0
                    )
                    isReading = true
                }
            )
        }
        .fullScreenCover(isPresented: $isReading) {
            ReaderView(book: book)
        }
    }
    
    private func startFullBookCache() {
        guard !chapters.isEmpty else { return }
        storage.addBookToShelf(book)
        isCachingFullBook = true
        let allChapters = chapters
        let total = allChapters.count
        // Snapshot the completeness together with the chapter list: a TOC refresh during the
        // download must not let this old download claim a complete-book cache.
        let tocCompleteSnapshot = isTocComplete
        fullCacheStatusText = "正在启动全本高速缓存 (0/\(total) 章)..."
        
        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)
        let bookId = book.id
        let bookUrl = book.bookUrl
        
        cacheTask?.cancel()
        cacheTask = Task {
            var completed = 0
            let chunkSize = 6
            for chunkStart in stride(from: 0, to: total, by: chunkSize) {
                guard !Task.isCancelled else { break }
                let chunkEnd = min(total, chunkStart + chunkSize)
                let slice = Array(allChapters[chunkStart..<chunkEnd])
                
                let savedCount = await withTaskGroup(of: Bool.self) { group -> Int in
                    for ch in slice {
                        group.addTask {
                            guard !Task.isCancelled else { return false }
                            if StorageManager.shared.isChapterCached(bookId: bookId, chapterIndex: ch.index,
                                                                      chapterURL: ch.url, sourceURL: source.bookSourceUrl) { return true }
                            let nextURL = ch.index + 1 < allChapters.count ? allChapters[ch.index + 1].url : nil
                            do {
                                let content = try await ChapterContentLoader.shared.load(chapter: ch, source: source,
                                                                                       referer: bookUrl, nextChapterURL: nextURL)
                                try Task.checkCancellation()
                                return StorageManager.shared.saveChapterCache(bookId: bookId, chapterIndex: ch.index, content: content)
                            } catch { return false }
                        }
                    }
                    var saved = 0
                    for await success in group { if success { saved += 1 } }
                    return saved
                }
                completed += savedCount
                let doneNow = completed
                let pct = Int(Double(doneNow) / Double(max(1, total)) * 100.0)
                await MainActor.run {
                    self.fullCacheStatusText = "正在全本缓存 \(doneNow)/\(total) 章 (\(pct)%)"
                }
            }
            guard !Task.isCancelled else { return }
            let savedTotal = completed
            await MainActor.run {
                self.isCachingFullBook = false
                if TocUpdatePolicy.isFullCacheComplete(savedCount: savedTotal, totalCount: total,
                                                       tocComplete: tocCompleteSnapshot) {
                    self.fullCacheStatusText = "全本 \(total) 章完整缓存完成"
                } else if savedTotal == total {
                    self.fullCacheStatusText = "已缓存当前获取的 \(total) 章，但目录尚不完整，无法确认全本"
                } else {
                    self.fullCacheStatusText = "缓存未完成：成功 \(savedTotal)/\(total) 章，请重试失败章节"
                }
            }
        }
    }
    
    private func loadChapters() {
        tocTask?.cancel()
        isLoadingChapters = true
        errorMessage = nil
        
        let requestedBook = book
        let source = storage.bookSources.first(where: { $0.bookSourceUrl == requestedBook.sourceUrl })
            ?? BookSource(bookSourceName: requestedBook.sourceName, bookSourceUrl: requestedBook.sourceUrl)
        
        // A source switch must drop the previous source's catalogue (and its running download):
        // otherwise a failed new-source request keeps showing A's chapters, and a partial B
        // result would be rejected because a stale non-empty list is still considered "local".
        if TocUpdatePolicy.requiresTocReset(loadedSourceUrl: loadedTocSourceUrl,
                                            loadedBookUrl: loadedTocBookUrl,
                                            currentSourceUrl: requestedBook.sourceUrl,
                                            currentBookUrl: requestedBook.bookUrl) {
            cacheTask?.cancel()
            isCachingFullBook = false
            fullCacheStatusText = nil
            chapters = []
            isTocComplete = false
            loadedTocSourceUrl = requestedBook.sourceUrl
            loadedTocBookUrl = requestedBook.bookUrl
        }
        
        // Offline-first: the persisted TOC also powers 目录预览 and 全本缓存 without network.
        if let cachedToc = storage.loadCachedToc(for: requestedBook) {
            chapters = cachedToc.chapters
            book.totalChapters = cachedToc.chapters.count
            isTocComplete = cachedToc.complete
            isLoadingChapters = false
        }
        
        tocTask = Task {
            do {
                let result = try await LegadoParser.shared.fetchToc(bookUrl: requestedBook.bookUrl, source: source)
                try Task.checkCancellation()
                await MainActor.run {
                    // A slow request from the previous source must never touch the new one.
                    guard self.book.sourceUrl == requestedBook.sourceUrl,
                          self.book.bookUrl == requestedBook.bookUrl else { return }
                    // An incomplete refresh must never replace a usable catalogue.
                    guard TocUpdatePolicy.shouldAcceptRefresh(resultComplete: result.complete,
                                                              localChapterCount: self.chapters.count) else {
                        self.isLoadingChapters = false
                        return
                    }
                    self.isTocComplete = result.complete
                    if result.chapters.isEmpty {
                        if self.chapters.isEmpty {
                            self.errorMessage = "当前站点未返回有效目录，建议点击「一键换源」切换其他书源"
                        }
                    } else {
                        self.chapters = result.chapters
                        self.book.totalChapters = result.chapters.count
                        self.storage.saveCachedToc(for: requestedBook, chapters: result.chapters, complete: result.complete)
                    }
                    self.isLoadingChapters = false
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.book.sourceUrl == requestedBook.sourceUrl,
                          self.book.bookUrl == requestedBook.bookUrl else { return }
                    if self.chapters.isEmpty {
                        self.errorMessage = "目录拉取超时或站点受限，请点击「一键换源」切换书源"
                    }
                    self.isLoadingChapters = false
                }
            }
        }
    }
}
