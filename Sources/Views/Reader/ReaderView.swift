import SwiftUI

public struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    
    let book: Book
    @State private var chapters: [Chapter] = []
    @State private var currentChapterIndex: Int
    @State private var currentContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showHUD = false
    @State private var showChapterList = false
    @State private var showSettings = false
    
    public init(book: Book) {
        self.book = book
        _currentChapterIndex = State(initialValue: book.currentChapterIndex)
    }
    
    private var currentChapter: Chapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }
    
    public var body: some View {
        ZStack {
            // Background Color
            storage.readerConfig.theme.backgroundColor
                .ignoresSafeArea()
            
            // Reading Text Area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let chapter = currentChapter {
                        Text(chapter.title)
                            .font(.system(size: storage.readerConfig.fontSize + 4, weight: .bold))
                            .foregroundColor(storage.readerConfig.theme.textColor)
                            .padding(.top, 40)
                            .padding(.bottom, 8)
                    }
                    
                    if isLoading {
                        HStack {
                            Spacer()
                            ProgressView("正在加载正文...")
                                .padding(.vertical, 100)
                            Spacer()
                        }
                    } else if let error = errorMessage {
                        VStack(spacing: 12) {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.subheadline)
                            Button("重新加载") {
                                loadCurrentChapterContent(forceRefresh: true)
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                    } else {
                        Text(currentContent)
                            .font(.system(size: storage.readerConfig.fontSize))
                            .lineSpacing(storage.readerConfig.lineSpacing)
                            .foregroundColor(storage.readerConfig.theme.textColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Chapter Bottom Navigation Buttons
                        HStack(spacing: 20) {
                            Button("上一章") {
                                if currentChapterIndex > 0 {
                                    switchChapter(to: currentChapterIndex - 1)
                                }
                            }
                            .disabled(currentChapterIndex <= 0)
                            .buttonStyle(.bordered)
                            
                            Spacer()
                            
                            Button("下一章") {
                                if currentChapterIndex < chapters.count - 1 {
                                    switchChapter(to: currentChapterIndex + 1)
                                }
                            }
                            .disabled(currentChapterIndex >= chapters.count - 1)
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 40)
                        .padding(.bottom, 60)
                    }
                }
                .padding(.horizontal, 20)
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showHUD.toggle()
                }
            }
            
            // HUD Overlays
            if showHUD {
                VStack {
                    // Top Bar
                    topBar
                    Spacer()
                    // Bottom Bar
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
                    switchChapter(to: newIndex)
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet()
        }
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }
            
            Spacer()
            
            VStack(spacing: 2) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let ch = currentChapter {
                    Text(ch.title)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button {
                loadCurrentChapterContent(forceRefresh: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Material.regular)
        .shadow(radius: 4)
    }
    
    // MARK: - Bottom Bar
    private var bottomBar: some View {
        VStack(spacing: 12) {
            // Slider / Progress
            HStack {
                Button("上一章") {
                    if currentChapterIndex > 0 {
                        switchChapter(to: currentChapterIndex - 1)
                    }
                }
                .disabled(currentChapterIndex <= 0)
                .font(.subheadline)
                
                Spacer()
                
                Text("\(currentChapterIndex + 1) / \(max(1, chapters.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("下一章") {
                    if currentChapterIndex < chapters.count - 1 {
                        switchChapter(to: currentChapterIndex + 1)
                    }
                }
                .disabled(currentChapterIndex >= chapters.count - 1)
                .font(.subheadline)
            }
            .padding(.horizontal)
            
            Divider()
            
            // Bottom Action Items
            HStack(spacing: 40) {
                Button {
                    showChapterList = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                        Text("目录").font(.caption2)
                    }
                }
                
                Button {
                    showSettings = true
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "textformat.size")
                        Text("设置").font(.caption2)
                    }
                }
                
                Button {
                    // Quick Toggle Dark mode
                    if storage.readerConfig.theme == .pureBlack || storage.readerConfig.theme == .darkGray {
                        storage.readerConfig.theme = .sepia
                    } else {
                        storage.readerConfig.theme = .pureBlack
                    }
                    storage.saveConfig()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: (storage.readerConfig.theme == .pureBlack || storage.readerConfig.theme == .darkGray) ? "sun.max" : "moon")
                        Text("夜间").font(.caption2)
                    }
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.vertical, 12)
        .background(Material.regular)
        .shadow(radius: 4)
    }
    
    // MARK: - Logic
    private func initializeReader() {
        guard let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl }) else {
            errorMessage = "未找到书籍对应的书源"
            isLoading = false
            return
        }
        
        Task {
            do {
                let (html, finalUrl) = try await NetworkManager.shared.fetchString(from: book.bookUrl)
                let parsedChapters = try LegadoParser.shared.parseToc(html: html, baseUrl: finalUrl, source: source)
                await MainActor.run {
                    self.chapters = parsedChapters
                    if self.currentChapterIndex >= parsedChapters.count {
                        self.currentChapterIndex = 0
                    }
                    self.loadCurrentChapterContent()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "目录拉取失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func switchChapter(to newIndex: Int) {
        guard newIndex >= 0 && newIndex < chapters.count else { return }
        currentChapterIndex = newIndex
        loadCurrentChapterContent()
    }
    
    private func loadCurrentChapterContent(forceRefresh: Bool = false) {
        guard let chapter = currentChapter else { return }
        
        // 1. Check disk cache
        if !forceRefresh, let cached = storage.getCachedChapter(bookId: book.id, chapterIndex: chapter.index) {
            self.currentContent = cached
            self.isLoading = false
            self.errorMessage = nil
            self.saveProgress()
            return
        }
        
        // 2. Fetch from source
        guard let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl }) else {
            errorMessage = "书源不可用"
            isLoading = false
            return
        }
        
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
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "正文抓取失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
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
