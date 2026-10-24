import SwiftUI

public struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    
    @State var book: Book
    @State private var chapters: [Chapter] = []
    @State private var currentChapterIndex: Int
    @State private var currentContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showHUD = false
    @State private var showChapterList = false
    @State private var showSettings = false
    @State private var showChangeSource = false
    @State private var cacheProgressText: String? = nil
    
    public init(book: Book) {
        _book = State(initialValue: book)
        _currentChapterIndex = State(initialValue: book.currentChapterIndex)
    }
    
    private var currentChapter: Chapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }
    
    /// Splits chapter content into clean, distinct paragraphs with guaranteed indentation and inter-paragraph spacing
    private var formattedParagraphs: [String] {
        guard !currentContent.isEmpty else { return [] }
        // Split on newlines OR two full-width spaces (in case of legacy cached text)
        let normalized = currentContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{3000}\u{3000}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}\u{00A0}", with: "\n")
        
        var rawList = normalized
            .components(separatedBy: .newlines)
            .map {
                $0.replacingOccurrences(of: "\u{3000}", with: " ")
                  .replacingOccurrences(of: "\u{00A0}", with: " ")
                  .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        
        // If a source stripped all <br>/<p> tags and returned a giant wall of text (e.g. <= 3 paragraphs for a whole chapter),
        // intelligently split after dialogue closing quotes (。” / ！” / ？”) or every 2-3 sentences
        if rawList.count <= 3 && currentContent.count > 250 {
            var smartSplit: [String] = []
            for block in rawList {
                let withDialogueBreaks = block.replacingOccurrences(
                    of: "([。！？…][”」』】])",
                    with: "$1\n",
                    options: .regularExpression
                )
                for sub in withDialogueBreaks.components(separatedBy: .newlines) {
                    let s = sub.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !s.isEmpty else { continue }
                    if s.count > 160 {
                        // Further split long narrative blocks every ~2 sentences
                        let sentences = s.replacingOccurrences(of: "([。！？])(?=[^”」』】])", with: "$1\n", options: .regularExpression)
                            .components(separatedBy: .newlines)
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        var buffer = ""
                        for sent in sentences {
                            buffer += sent
                            if buffer.count >= 85 {
                                smartSplit.append(buffer)
                                buffer = ""
                            }
                        }
                        if !buffer.isEmpty { smartSplit.append(buffer) }
                    } else {
                        smartSplit.append(s)
                    }
                }
            }
            if smartSplit.count > rawList.count {
                rawList = smartSplit
            }
        }
        
        return rawList.map { "　　" + $0 }
    }
    
    public var body: some View {
        ZStack {
            // Theme Background
            storage.readerConfig.theme.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Subtle Top Running Header
                HStack {
                    Text(currentChapter?.title ?? book.title)
                        .font(.system(size: 11, design: storage.readerConfig.fontDesign.swiftUIDesign))
                        .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.45))
                        .lineLimit(1)
                    Spacer()
                    if let cacheMsg = cacheProgressText {
                        Text(cacheMsg)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.indigo)
                    } else {
                        Text(book.sourceName)
                            .font(.system(size: 10))
                            .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.4))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 6)
                
                // Main Reading ScrollView
                ScrollViewReader { scrollProxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            Color.clear
                                .frame(height: 1)
                                .id("chapterTop")
                            
                            if let chapter = currentChapter {
                                Text(chapter.title)
                                    .font(.system(
                                        size: storage.readerConfig.fontSize + 5,
                                        weight: .bold,
                                        design: storage.readerConfig.fontDesign.swiftUIDesign
                                    ))
                                    .foregroundColor(storage.readerConfig.theme.textColor)
                                    .padding(.top, 8)
                                    .padding(.bottom, 6)
                            }
                            
                            if isLoading {
                                VStack(spacing: 14) {
                                    ProgressView()
                                    Text("正在加载章节正文...")
                                        .font(.system(size: 13))
                                        .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.6))
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 120)
                            } else if let error = errorMessage {
                                VStack(spacing: 16) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.orange)
                                    Text(error)
                                        .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.8))
                                        .font(.subheadline)
                                        .multilineTextAlignment(.center)
                                    
                                    HStack(spacing: 14) {
                                        Button("重试加载") {
                                            loadCurrentChapterContent(forceRefresh: true)
                                        }
                                        .buttonStyle(.bordered)
                                        
                                        Button("切换书源") {
                                            showChangeSource = true
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.indigo)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 90)
                            } else {
                                VStack(alignment: .leading, spacing: storage.readerConfig.lineSpacing + 14) {
                                    ForEach(Array(formattedParagraphs.enumerated()), id: \.offset) { _, paragraph in
                                        Text(paragraph)
                                            .font(.system(
                                                size: storage.readerConfig.fontSize,
                                                design: storage.readerConfig.fontDesign.swiftUIDesign
                                            ))
                                            .lineSpacing(storage.readerConfig.lineSpacing)
                                            .foregroundColor(storage.readerConfig.theme.textColor)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                
                                // Chapter Bottom Navigation Bar
                                HStack(spacing: 16) {
                                    Button {
                                        if currentChapterIndex > 0 {
                                            switchChapter(to: currentChapterIndex - 1, proxy: scrollProxy)
                                        }
                                    } label: {
                                        Text("上一章")
                                            .font(.system(size: 14, weight: .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(storage.readerConfig.theme.textColor.opacity(0.08))
                                            .foregroundColor(storage.readerConfig.theme.textColor)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .disabled(currentChapterIndex <= 0)
                                    
                                    Button {
                                        if currentChapterIndex < chapters.count - 1 {
                                            switchChapter(to: currentChapterIndex + 1, proxy: scrollProxy)
                                        }
                                    } label: {
                                        Text("下一章")
                                            .font(.system(size: 14, weight: .semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(Color.indigo)
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .disabled(currentChapterIndex >= chapters.count - 1)
                                }
                                .padding(.top, 36)
                                .padding(.bottom, 50)
                            }
                        }
                        .padding(.horizontal, 22)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showHUD.toggle()
                        }
                    }
                    .onChange(of: currentChapterIndex) { _ in
                        withAnimation(.none) {
                            scrollProxy.scrollTo("chapterTop", anchor: .top)
                        }
                    }
                }
                
                // Subtle Bottom Footer
                HStack {
                    Text(book.title)
                        .font(.system(size: 10))
                        .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    if !chapters.isEmpty {
                        let pct = min(100.0, Double(currentChapterIndex + 1) / Double(chapters.count) * 100.0)
                        Text(String(format: "%d/%d 章 (%.1f%%)", currentChapterIndex + 1, chapters.count, pct))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.45))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 6)
            }
            
            // Floating HUD Overlays
            if showHUD {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .statusBar(hidden: !showHUD)
        .onAppear {
            initializeReader()
        }
        .sheet(isPresented: $showChapterList) {
            ChapterListView(
                chapters: chapters,
                currentIndex: currentChapterIndex,
                onSelectChapter: { newIndex in
                    switchChapter(to: newIndex, proxy: nil)
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet()
        }
        .sheet(isPresented: $showChangeSource) {
            ChangeSourceSheet(currentBook: book) { newBook in
                self.book = newBook
                initializeReader()
            }
        }
    }
    
    // MARK: - Top HUD Bar
    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Text("来源：\(book.sourceName)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Batch Cache Next 30 Chapters
            Button {
                batchCacheChapters(count: 30)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle")
                    Text("缓存")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.indigo.opacity(0.14))
                .foregroundColor(.indigo)
                .clipShape(Capsule())
            }
            
            // Change Source
            Button {
                showChangeSource = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("换源")
                }
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.16))
                .foregroundColor(.orange)
                .clipShape(Capsule())
            }
            
            Button {
                loadCurrentChapterContent(forceRefresh: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
    }
    
    // MARK: - Bottom HUD Bar
    private var bottomBar: some View {
        VStack(spacing: 14) {
            // Chapter Progress Control
            HStack(spacing: 14) {
                Button {
                    if currentChapterIndex > 0 {
                        switchChapter(to: currentChapterIndex - 1, proxy: nil)
                    }
                } label: {
                    Text("上一章")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(currentChapterIndex <= 0)
                
                if chapters.count > 1 {
                    Slider(
                        value: Binding(
                            get: { Double(currentChapterIndex) },
                            set: { newVal in
                                let target = Int(newVal)
                                if target != currentChapterIndex {
                                    switchChapter(to: target, proxy: nil)
                                }
                            }
                        ),
                        in: 0...Double(max(1, chapters.count - 1)),
                        step: 1
                    )
                    .tint(.indigo)
                } else {
                    Spacer()
                }
                
                Button {
                    if currentChapterIndex < chapters.count - 1 {
                        switchChapter(to: currentChapterIndex + 1, proxy: nil)
                    }
                } label: {
                    Text("下一章")
                        .font(.system(size: 13, weight: .semibold))
                }
                .disabled(currentChapterIndex >= chapters.count - 1)
            }
            .padding(.horizontal, 18)
            
            Divider()
            
            // Action Tab Icons
            HStack {
                Spacer()
                Button {
                    showChapterList = true
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "list.bullet.indent")
                            .font(.system(size: 18))
                        Text("目录").font(.system(size: 11, weight: .medium))
                    }
                }
                Spacer()
                Button {
                    showChangeSource = true
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 18))
                        Text("换源").font(.system(size: 11, weight: .medium))
                    }
                }
                Spacer()
                Button {
                    if storage.readerConfig.theme.isDark {
                        storage.readerConfig.theme = .sepia
                    } else {
                        storage.readerConfig.theme = .darkGray
                    }
                    storage.saveConfig()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: storage.readerConfig.theme.isDark ? "sun.max.fill" : "moon.stars.fill")
                            .font(.system(size: 18))
                        Text(storage.readerConfig.theme.isDark ? "日间" : "夜间")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "textformat.alt")
                            .font(.system(size: 18))
                        Text("排版").font(.system(size: 11, weight: .medium))
                    }
                }
                Spacer()
            }
            .foregroundColor(.primary)
            .padding(.bottom, 6)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: -2)
    }
    
    // MARK: - Logic
    private func initializeReader() {
        isLoading = true
        errorMessage = nil
        
        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)
        
        Task {
            do {
                let parsedChapters = try await LegadoParser.shared.fetchAndParseToc(bookUrl: book.bookUrl, source: source)
                await MainActor.run {
                    if parsedChapters.isEmpty {
                        self.errorMessage = "当前书源未能解析出目录，请点击「切换书源」"
                        self.isLoading = false
                    } else {
                        self.chapters = parsedChapters
                        if self.currentChapterIndex >= parsedChapters.count {
                            self.currentChapterIndex = 0
                        }
                        self.loadCurrentChapterContent()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "目录拉取失败，请点击「切换书源」或重试"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func switchChapter(to newIndex: Int, proxy: ScrollViewProxy?) {
        guard newIndex >= 0 && newIndex < chapters.count else { return }
        currentChapterIndex = newIndex
        if let proxy = proxy {
            proxy.scrollTo("chapterTop", anchor: .top)
        }
        loadCurrentChapterContent()
    }
    
    private func loadCurrentChapterContent(forceRefresh: Bool = false) {
        guard let chapter = currentChapter else { return }
        
        if !forceRefresh, let cached = storage.getCachedChapter(bookId: book.id, chapterIndex: chapter.index) {
            self.currentContent = cached
            self.isLoading = false
            self.errorMessage = nil
            self.saveProgress()
            self.prefetchNextChapter()
            return
        }
        
        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let (html, finalUrl) = try await NetworkManager.shared.fetchString(from: chapter.url, referer: book.bookUrl)
                let text = try LegadoParser.shared.parseContent(html: html, baseUrl: finalUrl, source: source)
                
                await MainActor.run {
                    self.currentContent = text
                    self.isLoading = false
                    self.storage.saveChapterCache(bookId: self.book.id, chapterIndex: chapter.index, content: text)
                    self.saveProgress()
                    self.prefetchNextChapter()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "正文抓取失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func prefetchNextChapter() {
        let nextIdx = currentChapterIndex + 1
        guard nextIdx < chapters.count else { return }
        guard !storage.isChapterCached(bookId: book.id, chapterIndex: nextIdx) else { return }
        
        let nextCh = chapters[nextIdx]
        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)
        
        Task {
            if let (html, finalUrl) = try? await NetworkManager.shared.fetchString(from: nextCh.url, referer: book.bookUrl),
               let text = try? LegadoParser.shared.parseContent(html: html, baseUrl: finalUrl, source: source),
               text.count >= 50 {
                storage.saveChapterCache(bookId: book.id, chapterIndex: nextCh.index, content: text)
            }
        }
    }
    
    private func batchCacheChapters(count: Int) {
        let start = currentChapterIndex
        let end = min(chapters.count - 1, start + count - 1)
        guard start <= end else { return }
        
        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)
        
        showHUD = false
        cacheProgressText = "正在缓存 0/\(end - start + 1)..."
        
        Task {
            var done = 0
            let total = end - start + 1
            for idx in start...end {
                let ch = chapters[idx]
                if !storage.isChapterCached(bookId: book.id, chapterIndex: ch.index) {
                    if let (html, finalUrl) = try? await NetworkManager.shared.fetchString(from: ch.url, referer: book.bookUrl),
                       let text = try? LegadoParser.shared.parseContent(html: html, baseUrl: finalUrl, source: source) {
                        storage.saveChapterCache(bookId: book.id, chapterIndex: ch.index, content: text)
                    }
                }
                done += 1
                let currentDone = done
                await MainActor.run {
                    self.cacheProgressText = "已缓存 \(currentDone)/\(total) 章"
                }
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run {
                self.cacheProgressText = nil
            }
        }
    }
    
    private func saveProgress() {
        if let ch = currentChapter {
            storage.updateBookProgress(
                bookId: book.id,
                chapterIndex: currentChapterIndex,
                chapterTitle: ch.title,
                totalChapters: chapters.count
            )
        }
    }
}
