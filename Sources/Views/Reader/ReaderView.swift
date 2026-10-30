import SwiftUI
import UIKit

public enum ChapterCacheScope {
    case nextCount(Int)
    case allRemaining
    case entireBook
}

/// Mutable reference box used to throttle progress writes without triggering SwiftUI re-renders
final class ProgressSaveThrottle {
    var lastSave: Date = .distantPast
    var pending: DispatchWorkItem?
}

public struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var storage = StorageManager.shared
    @ObservedObject var speech = SpeechSynthesizerManager.shared

    @State var book: Book
    @State private var chapters: [Chapter] = []
    @State private var currentChapterIndex: Int
    @State private var currentParagraphIndex: Int
    @State private var currentCharacterOffset: Int = 0
    @State private var currentPageIndex: Int = 0
    @State private var currentSpreadIndex: Int = 0
    @State private var chapterTurnBackward: Bool?
    @State private var showDuoSidebarTOC: Bool = false
    @State private var currentContent: String = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showHUD = false
    @State private var showTTSBar = false
    @State private var showChapterList = false
    @State private var showSettings = false
    @State private var showChangeSource = false

    // Batch / Full-Book Caching State
    @State private var cacheProgressText: String? = nil
    @State private var isCachingChapters = false
    @State private var activeCacheTask: Task<Void, Never>? = nil
    @State private var chapterLoadTask: Task<Void, Never>?
    @State private var loadTokens = LoadTokenSet()
    @State private var prefetchTask: Task<Void, Never>?
    @State private var tocLoadTask: Task<Void, Never>?
    @State private var tocRefreshTask: Task<Void, Never>?
    // TTS hand-off state: chapter/book switches stop the old audio before the new chapter
    // becomes current, then resume on the new text (keeping the previous pause state).
    @State private var pendingTTSCarryOver = false
    @State private var pendingTTSPaused = false
    @State private var pendingTTSSession: Int = 0
    @State private var pendingListenStart = false
    /// Content URL of the chapter currently held in `formattedParagraphs`. While a new chapter
    /// is still loading this stays on the previous chapter, so 听书 must not start on it.
    @State private var loadedContentChapterURL: String?
    /// Whether the current chapter list was fetched completely (drives "全本缓存完成" wording).
    @State private var isTocComplete: Bool = true

    // Intra-Chapter Paragraph Restoration State
    @State private var targetRestoreParagraph: Int? = nil
    @State private var isRestoringPosition: Bool = false
    @State private var visibleParagraphIndices: Set<Int> = []
    @State private var restoreToastMessage: String? = nil

    public init(book: Book) {
        let saved = StorageManager.shared.getSavedReadingPosition(for: book)
        var initialBook = StorageManager.shared.bookshelf.first(where: {
            $0.id == book.id || ($0.title == book.title && $0.author == book.author)
        }) ?? book
        initialBook.currentChapterIndex = saved.chapterIndex
        initialBook.currentParagraphIndex = saved.paragraphIndex
        initialBook.currentCharacterOffset = saved.characterOffset
        _book = State(initialValue: initialBook)
        _currentChapterIndex = State(initialValue: saved.chapterIndex)
        _currentParagraphIndex = State(initialValue: saved.paragraphIndex)
        _currentCharacterOffset = State(initialValue: saved.characterOffset)
        _targetRestoreParagraph = State(initialValue: saved.paragraphIndex > 0 || saved.characterOffset > 0 ? saved.paragraphIndex : nil)
        _isRestoringPosition = State(initialValue: saved.paragraphIndex > 0 || saved.characterOffset > 0)
    }

    private var currentChapter: Chapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }

    /// Cached paragraphs of the current chapter — rebuilt only when content or purify/convert config changes,
    /// instead of re-running regex splitting & Chinese conversion on every SwiftUI render.
    @State private var formattedParagraphs: [String] = []
    /// Cached screen-sized pages for horizontal / Duo modes — rebuilt only when paragraphs, viewport, or font config changes.
    @State private var readerPages: [ReaderPage] = []
    private var paginatedPages: [[PaginatedParagraph]] { readerPages.map { $0.items } }
    @State private var readingAreaSize: CGSize = .zero
    @State private var readingLayout: ReaderPresentation = .scroll
    @State private var readingLayoutReady = false
    @State private var layoutRestoration = ReaderLayoutRestoration()
    @State private var chapterLanding = ReaderChapterLanding()
    @State private var lastFormattingConfig: ReaderConfig?
    /// Actual measured page viewport size from GeometryReader (single page width & height)
    @State private var pageViewportSize: CGSize = .zero
    /// Reference holder for progress-save throttling (mutating it never triggers a re-render).
    @State private var progressSaver = ProgressSaveThrottle()

    private func applyChapterContent(_ text: String) {
        currentContent = text
        if readingAreaSize.width > 0 && readingAreaSize.height > 0 {
            // New content can require a different fallback even when the window hasn't resized.
            updateReaderViewport(readingAreaSize, force: true)
        } else { rebuildLayout() }
    }

    private var spineWidth: CGFloat { storage.readerConfig.effectiveShowDuoSpine ? 18 : 1 }
    private var typographyProfile: ReaderViewportProfile { ReaderLayoutPolicy.typographyProfile(availableWidth: readingAreaSize.width) }
    private var typography: ReaderTypography { storage.readerConfig.typography(for: typographyProfile) }
    private var pageStyle: ReaderPageStyle { ReaderPageStyle(config: storage.readerConfig.applyingTypography(for: typographyProfile)) }
    private var isDuoSpreadActive: Bool { readingLayout == .spread }

    private func updateReaderViewport(_ size: CGSize, force: Bool = false) {
        guard size.width > 0, size.height > 0 else { return }
        let changed = abs(size.width - readingAreaSize.width) > 1 || abs(size.height - readingAreaSize.height) > 1
        guard changed || force || !readingLayoutReady else { return }
        // Suppress outgoing-view callbacks before replacing/reflowing its content.
        isRestoringPosition = true
        progressSaver.pending?.cancel()
        progressSaver.pending = nil
        let anchor = ReaderTextAnchor(chapterURL: currentChapter?.url ?? loadedContentChapterURL ?? "",
                                      paragraphIndex: currentParagraphIndex, characterOffset: currentCharacterOffset)
        layoutRestoration.begin(anchor)
        targetRestoreParagraph = anchor.paragraphIndex
        visibleParagraphIndices.removeAll()
        readingAreaSize = size
        readingLayout = ReaderLayoutPolicy.presentation(size: size,
            preferred: storage.readerConfig.effectivePageTurnMode,
            autoSpread: storage.readerConfig.effectiveAutoDuoSpread,
            fontSize: typography.fontSize, spineWidth: spineWidth)
        pageViewportSize = CGSize(width: readingLayout == .spread ? (size.width - spineWidth) / 2 : size.width,
                                  height: max(0, size.height - 22))
        rebuildLayout()
        if readingLayout != .scroll && !formattedParagraphs.isEmpty && readerPages.isEmpty {
            readingLayout = .scroll
        }
        readingLayoutReady = true
        if !formattedParagraphs.isEmpty {
            let paragraph = min(max(0, currentParagraphIndex), formattedParagraphs.count - 1)
            let offset = paragraph == currentParagraphIndex
                ? min(max(0, currentCharacterOffset), (formattedParagraphs[paragraph] as NSString).length) : 0
            if paragraph != currentParagraphIndex || offset != currentCharacterOffset {
                currentParagraphIndex = paragraph
                currentCharacterOffset = offset
                targetRestoreParagraph = paragraph
                layoutRestoration.begin(ReaderTextAnchor(chapterURL: currentChapter?.url ?? "",
                                                         paragraphIndex: paragraph, characterOffset: offset))
            }
        }
        let landedAtChapterEnd = applyPendingChapterLanding()
        restorePageFromParagraphIfNeeded()
        if readingLayout != .scroll && !(readingLayout == .spread && showDuoSidebarTOC) { finishPaginatedRestoration() }
        if landedAtChapterEnd, let chapter = currentChapter {
            saveProgress(force: true)
            resumeTTSIfNeeded(autoContinueTTS: pendingTTSCarryOver, chapter: chapter)
        }
    }

    private func rebuildLayout() {
        formattedParagraphs = ChapterTextFormatter.paragraphs(from: currentContent, config: storage.readerConfig)
        let title = currentChapter.map { storage.readerConfig.effectiveChineseConversion.convert($0.title) } ?? ""
        readerPages = ReaderPaginator.paginate(paragraphs: formattedParagraphs, chapterTitle: title,
                                               style: pageStyle, viewport: pageViewportSize)
    }

    private func applyPendingChapterLanding() -> Bool {
        guard !isLoading, let chapterURL = currentChapter?.url, loadedContentChapterURL == chapterURL,
              let target = chapterLanding.consume(chapterURL: chapterURL, paragraphs: formattedParagraphs,
                  pages: readerPages, presentation: readingLayout, viewportReady: readingLayoutReady) else { return false }
        currentParagraphIndex = target.anchor.paragraphIndex
        currentCharacterOffset = target.anchor.characterOffset
        currentPageIndex = target.pageIndex
        currentSpreadIndex = target.spreadIndex
        targetRestoreParagraph = target.anchor.paragraphIndex
        layoutRestoration.begin(target.anchor)
        isRestoringPosition = true
        return true
    }

    private var liveSpokenParagraph: Int? {
        guard speech.isSpeaking, !speech.isPaused, speech.context?.book.id == book.id,
              speech.context?.chapterIndex == currentChapterIndex else { return nil }
        return min(speech.currentParagraphIndex, max(0, formattedParagraphs.count - 1))
    }

    private func finishPaginatedRestoration() {
        let token = layoutRestoration.token
        let chapterURL = currentChapter?.url
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard self.readingLayout != .scroll,
                  let anchor = self.layoutRestoration.finish(token, chapterURL: chapterURL, liveParagraphIndex: self.liveSpokenParagraph),
                  self.currentChapter?.url == chapterURL else { return }
            self.currentParagraphIndex = min(anchor.paragraphIndex, max(0, self.formattedParagraphs.count - 1))
            self.currentCharacterOffset = anchor.characterOffset
            self.targetRestoreParagraph = nil
            self.restorePageFromParagraphIfNeeded()
            self.isRestoringPosition = false
            self.saveProgress(force: true)
        }
    }

    private var readingArea: some View {
        GeometryReader { geo in
            Group {
                if !readingLayoutReady { Color.clear }
                else if readingLayout == .spread { duoBookSpreadReaderView }
                else if readingLayout == .page && !readerPages.isEmpty { horizontalPageReaderView }
                else { verticalScrollReaderView }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { updateReaderViewport(geo.size, force: chapterLanding.pendingChapterURL != nil) }
            .onChange(of: geo.size) { size in updateReaderViewport(size) }
            .accessibilityIdentifier("reader.area.\(readingLayout.rawValue)")
        }
    }

    public var body: some View {
        ZStack {
            // Theme Background
            storage.readerConfig.theme.backgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Subtle Top Running Header
                HStack {
                    Text(storage.readerConfig.effectiveChineseConversion.convert(currentChapter?.title ?? book.title))
                        .font(.system(size: 11, design: storage.readerConfig.fontDesign.swiftUIDesign))
                        .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.45))
                        .lineLimit(1)
                    Spacer()
                    if speech.isSpeaking && ownsSpeech {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                            Text(speech.isPaused ? "听书已暂停" : "正在朗读 · \(speech.selectedVoice.shortName)")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.indigo)
                    } else if let cacheMsg = cacheProgressText {
                        Text(cacheMsg)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.indigo)
                    } else {
                        Text("\(isDuoSpreadActive ? "iPhone Duo 双屏 · " : "")第 \(currentParagraphIndex + 1) 段 · \(book.sourceName)")
                            .font(.system(size: 10))
                            .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.42))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 6)

                // Main Reading Area: Vertical Scroll, Horizontal Slide, OR iPhone Duo Dual-Page Book Spread
                ZStack {
                    if isLoading {
                        loadingStateView
                    } else if let error = errorMessage {
                        errorStateView(error)
                    } else {
                        readingArea
                            .id(loadedContentChapterURL)
                            .transition(chapterPageTransition)
                    }
                }
                .clipped()
                .animation(chapterTurnBackward == nil || reduceMotion ? nil : .easeInOut(duration: 0.28),
                           value: loadedContentChapterURL)

                // Subtle Bottom Footer
                HStack {
                    Text(storage.readerConfig.effectiveChineseConversion.convert(book.title))
                        .font(.system(size: 10))
                        .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    if !chapters.isEmpty {
                        let pct = min(100.0, Double(currentChapterIndex + 1) / Double(chapters.count) * 100.0)
                        if isDuoSpreadActive && !readerPages.isEmpty {
                            Text(String(format: "双页对开 %d/%d 组 · %d/%d 章 (%.1f%%)", min(currentSpreadIndex + 1, ((readerPages.count + 1) / 2)), ((readerPages.count + 1) / 2), currentChapterIndex + 1, chapters.count, pct))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.45))
                        } else if readingLayout == .page && !readerPages.isEmpty {
                            Text(String(format: "第 %d/%d 页 · %d/%d 章 (%.1f%%)", min(currentPageIndex + 1, paginatedPages.count), paginatedPages.count, currentChapterIndex + 1, chapters.count, pct))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.45))
                        } else {
                            Text(String(format: "第 %d/%d 段 · %d/%d 章 (%.1f%%)", min(currentParagraphIndex + 1, max(1, formattedParagraphs.count)), max(1, formattedParagraphs.count), currentChapterIndex + 1, chapters.count, pct))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.45))
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 6)
            }

            // Top Toast Pill when Restoring Intra-Chapter Paragraph
            if let toast = restoreToastMessage {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11))
                        Text(toast)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.indigo.opacity(0.92))
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
                    .padding(.top, 42)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Floating TTS Audio Player Bar
            if showTTSBar || (speech.isSpeaking && ownsSpeech) {
                VStack {
                    Spacer()
                    ttsControlOverlay
                        .padding(.bottom, showHUD ? 130 : 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
            lastFormattingConfig = storage.readerConfig
            setupSpeechCallbacks()
            initializeReader()
        }
        .onDisappear {
            saveProgress(force: true)
            // A dismissed reader must never commit a late load into shared progress or speech.
            // Invalidate identities as well as cancelling: transports may complete despite cancellation.
            loadTokens.invalidateAll()
            layoutRestoration.cancel()
            chapterLanding.cancel()
            chapterLoadTask?.cancel()
            chapterLoadTask = nil
            tocLoadTask?.cancel()
            tocLoadTask = nil
            tocRefreshTask?.cancel()
            tocRefreshTask = nil
            prefetchTask?.cancel()
            prefetchTask = nil
            activeCacheTask?.cancel()
            activeCacheTask = nil
            isCachingChapters = false
            // Cancel any pending "start listening on the new chapter" intent: the page is gone.
            pendingListenStart = false
            pendingTTSCarryOver = false
            pendingTTSPaused = false
            // Hand TTS over to the engine so it keeps reading & auto-advancing chapters after the page closes
            if let ctx = speech.context,
               ctx.book.title == book.title && ctx.book.author == book.author {
                speech.detachReader()
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                saveProgress(force: true)
            }
        }
        .onChange(of: storage.readerConfig) { config in
            if let previous = lastFormattingConfig,
               previous.effectiveChineseConversion != config.effectiveChineseConversion
                || previous.effectivePurifyRules != config.effectivePurifyRules {
                currentCharacterOffset = 0
            }
            lastFormattingConfig = config
            updateReaderViewport(readingAreaSize, force: true)
        }
        .sheet(isPresented: $showChapterList) {
            ChapterListView(
                bookId: book.id,
                chapters: chapters,
                currentIndex: currentChapterIndex,
                onSelectChapter: { newIndex in
                    switchChapter(to: newIndex, proxy: nil)
                }
            )
        }
        .sheet(isPresented: $showSettings) {
            ReaderSettingsSheet(initialTypographyProfile: typographyProfile)
        }
        .sheet(isPresented: $showChangeSource) {
            ChangeSourceSheet(currentBook: book) { newBook in
                chapterLoadTask?.cancel()
                loadTokens.beginChapterLoad()
                prefetchTask?.cancel()
                activeCacheTask?.cancel()
                isCachingChapters = false
                cacheProgressText = nil
                // Paragraphs being read aloud came from the old source — stop them
                if speech.isSpeaking,
                   let ctx = speech.context,
                   ctx.book.title == book.title && ctx.book.author == book.author {
                    speech.stop()
                    showTTSBar = false
                }
                self.book = newBook
                self.currentCharacterOffset = 0
                initializeReader()
            }
        }
    }

    // MARK: - Loading & Error Views
    private var loadingStateView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
            Text("正在加载章节正文...")
                .font(.system(size: 13))
                .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorStateView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
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

                if !chapters.isEmpty {
                    Button("查看目录") {
                        showChapterList = true
                    }
                    .buttonStyle(.bordered)
                }

                Button("切换书源") {
                    showChangeSource = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - 1. Vertical Scroll Reader View (LazyVStack for Exact Paragraph Tracking & Restoration)
    private var verticalScrollReaderView: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: typography.lineSpacing + 14) {
                    Color.clear
                        .frame(height: 1)
                        .id("chapterTop")

                    if let chapter = currentChapter {
                        Text(storage.readerConfig.effectiveChineseConversion.convert(chapter.title))
                            .font(.system(
                                size: typography.fontSize + 5,
                                weight: .bold,
                                design: storage.readerConfig.fontDesign.swiftUIDesign
                            ))
                            .foregroundColor(storage.readerConfig.theme.textColor)
                            .padding(.top, 8)
                            .padding(.bottom, 6)
                    }

                    ForEach(Array(formattedParagraphs.enumerated()), id: \.offset) { idx, paragraph in
                        let isSpoken = speech.isSpeaking && ownsSpeech && speech.currentParagraphIndex == idx
                        Text(paragraph)
                            .font(.system(
                                size: typography.fontSize,
                                design: storage.readerConfig.fontDesign.swiftUIDesign
                            ))
                            .lineSpacing(typography.lineSpacing)
                            .foregroundColor(isSpoken ? .indigo : storage.readerConfig.theme.textColor)
                            .padding(.vertical, isSpoken ? 4 : 0)
                            .padding(.horizontal, isSpoken ? 6 : 0)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSpoken ? Color.indigo.opacity(0.10) : Color.clear)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("para_\(idx)")
                            .onAppear {
                                visibleParagraphIndices.insert(idx)
                                if !isRestoringPosition, let topIdx = visibleParagraphIndices.min() {
                                    if topIdx != currentParagraphIndex {
                                        currentParagraphIndex = topIdx
                                        currentCharacterOffset = 0
                                        saveProgress()
                                    }
                                }
                            }
                            .onDisappear {
                                visibleParagraphIndices.remove(idx)
                                if !isRestoringPosition, let topIdx = visibleParagraphIndices.min() {
                                    if topIdx != currentParagraphIndex {
                                        currentParagraphIndex = topIdx
                                        currentCharacterOffset = 0
                                        saveProgress()
                                    }
                                }
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
                    .padding(.top, 28)
                    .padding(.bottom, 50)
                }
                .padding(.horizontal, 22)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showHUD.toggle()
                }
            }
            .onAppear {
                restoreParagraphScrollIfNeeded(proxy: scrollProxy)
            }
            .onChange(of: currentContent) { _ in
                restoreParagraphScrollIfNeeded(proxy: scrollProxy)
            }
            .onChange(of: layoutRestoration.token) { _ in
                restoreParagraphScrollIfNeeded(proxy: scrollProxy)
            }
            .onChange(of: speech.currentParagraphIndex) { newIdx in
                if speech.isSpeaking && ownsSpeech {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollProxy.scrollTo("para_\(newIdx)", anchor: .center)
                    }
                }
            }
        }
    }

    private func restoreParagraphScrollIfNeeded(proxy: ScrollViewProxy) {
        guard !formattedParagraphs.isEmpty else { return }
        guard let target = targetRestoreParagraph else { return }
        let clamped = min(max(0, target), formattedParagraphs.count - 1)
        let chapterURL = currentChapter?.url
        // Initial reopening and fold transitions both use an identity-bound restoration.
        if layoutRestoration.anchor == nil {
            layoutRestoration.begin(ReaderTextAnchor(chapterURL: chapterURL ?? "", paragraphIndex: clamped))
        }
        let token = layoutRestoration.token
        isRestoringPosition = true
        currentParagraphIndex = clamped
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            guard self.currentChapter?.url == chapterURL,
                  self.layoutRestoration.accepts(token, chapterURL: chapterURL) else { return }
            withAnimation(.none) { proxy.scrollTo("para_\(clamped)", anchor: .top) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            guard self.currentChapter?.url == chapterURL,
                  self.layoutRestoration.accepts(token, chapterURL: chapterURL) else { return }
            let restoredParagraph = self.liveSpokenParagraph ?? clamped
            withAnimation(.none) { proxy.scrollTo("para_\(restoredParagraph)", anchor: .top) }
            self.currentParagraphIndex = restoredParagraph
            self.currentCharacterOffset = 0
            self.targetRestoreParagraph = nil
            _ = self.layoutRestoration.finish(token, chapterURL: chapterURL, liveParagraphIndex: self.liveSpokenParagraph)
            self.isRestoringPosition = false
            self.saveProgress(force: true)
        }
    }

    // MARK: - Paginated reading with shared TextKit typography
    private func pageContent(_ page: ReaderPage, number: Int) -> some View {
        VStack(spacing: 0) {
            MeasuredReaderPage(page: page, style: pageStyle, size: pageViewportSize,
                               textColor: storage.readerConfig.theme.textColor,
                               highlightedParagraph: speech.isSpeaking && ownsSpeech ? speech.currentParagraphIndex : nil)
            Text("第 \(number) 页")
                .font(.system(size: 10))
                .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.4))
                .frame(height: 22)
        }
    }

    private func selectPage(_ pageIndex: Int) {
        guard !isRestoringPosition, readerPages.indices.contains(pageIndex),
              let first = readerPages[pageIndex].items.first else { return }
        currentParagraphIndex = first.index
        currentCharacterOffset = first.characterOffset
        saveProgress()
    }

    private func turnPage(backward: Bool, spread: Bool) {
        guard !isLoading, !isRestoringPosition else { return }
        if showHUD { withAnimation { showHUD = false }; return }
        let index = spread ? currentSpreadIndex : currentPageIndex
        let count = spread ? (readerPages.count + 1) / 2 : readerPages.count
        if backward && index > 0 {
            if spread { currentSpreadIndex -= 1 } else { currentPageIndex -= 1 }
            selectPage(spread ? currentSpreadIndex * 2 : currentPageIndex)
        } else if !backward && index + 1 < count {
            if spread { currentSpreadIndex += 1 } else { currentPageIndex += 1 }
            selectPage(spread ? currentSpreadIndex * 2 : currentPageIndex)
        } else if backward && currentChapterIndex > 0 {
            switchChapter(to: currentChapterIndex - 1, proxy: nil, pageTurnBackward: true)
        } else if !backward && currentChapterIndex + 1 < chapters.count {
            switchChapter(to: currentChapterIndex + 1, proxy: nil, pageTurnBackward: false)
        }
    }

    private var chapterPageTransition: AnyTransition {
        guard let backward = chapterTurnBackward, !reduceMotion else { return .identity }
        return .asymmetric(insertion: .move(edge: backward ? .leading : .trailing).combined(with: .opacity),
                           removal: .move(edge: backward ? .trailing : .leading).combined(with: .opacity))
    }

    private func handlePageTap(_ region: ReaderPageTapRegion, spread: Bool) {
        switch region {
        case .backward: turnPage(backward: true, spread: spread)
        case .center: withAnimation { showHUD.toggle() }
        case .forward: turnPage(backward: false, spread: spread)
        }
    }

    private func pagerSelection(spread: Bool) -> Binding<Int> {
        let token = layoutRestoration.token
        let chapterURL = currentChapter?.url
        return Binding(get: { spread ? self.currentSpreadIndex : self.currentPageIndex }, set: { index in
            // Only a completed swipe from the current chapter/layout may commit progress.
            guard !self.isRestoringPosition, !self.isLoading,
                  self.layoutRestoration.token == token, self.currentChapter?.url == chapterURL else { return }
            if spread { self.currentSpreadIndex = index } else { self.currentPageIndex = index }
            self.selectPage(spread ? index * 2 : index)
        })
    }

    private var horizontalPageReaderView: some View {
        AnimatedReaderPager(selection: pagerSelection(spread: false), count: readerPages.count,
                            identity: AnyHashable(layoutRestoration.token), animateChanges: !isRestoringPosition,
                            tapMode: storage.readerConfig.effectiveTapMode,
                            onTap: { handlePageTap($0, spread: false) },
                            onBoundarySwipe: { turnPage(backward: $0, spread: false) }) { index in
            if readerPages.indices.contains(index) {
                pageContent(readerPages[index], number: index + 1)
            }
        }
        .onAppear { restorePageFromParagraphIfNeeded(); finishPaginatedRestoration() }
    }

    private var duoBookSpreadReaderView: some View {
        Group {
            if showDuoSidebarTOC {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("目录").font(.headline)
                            Spacer()
                            Button("收起") { setDuoSidebar(false) }
                        }.padding(12)
                        Divider()
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(chapters) { chapter in
                                        Button {
                                            switchChapter(to: chapter.index, proxy: nil)
                                        } label: {
                                            Text(chapter.title)
                                                .font(.system(size: 13, weight: chapter.index == currentChapterIndex ? .bold : .regular))
                                                .foregroundColor(chapter.index == currentChapterIndex ? .indigo : storage.readerConfig.theme.textColor)
                                                .lineLimit(2)
                                                .padding(12)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .id(chapter.index)
                                    }
                                }
                            }
                            .onAppear { proxy.scrollTo(currentChapterIndex, anchor: .center) }
                            .onChange(of: currentChapterIndex) { proxy.scrollTo($0, anchor: .center) }
                        }
                    }
                    .frame(width: ReaderLayoutPolicy.sidebarWidth(availableWidth: readingAreaSize.width))
                    Divider()
                    verticalScrollReaderView
                }
            } else {
                AnimatedReaderPager(selection: pagerSelection(spread: true), count: (readerPages.count + 1) / 2,
                                    identity: AnyHashable(layoutRestoration.token), animateChanges: !isRestoringPosition,
                                    tapMode: storage.readerConfig.effectiveTapMode,
                                    onTap: { handlePageTap($0, spread: true) },
                                    onBoundarySwipe: { turnPage(backward: $0, spread: true) }) { spread in
                    if readerPages.indices.contains(spread * 2) {
                        HStack(spacing: 0) {
                            pageContent(readerPages[spread * 2], number: spread * 2 + 1)
                            if storage.readerConfig.effectiveShowDuoSpine { duoCenterHingeCrease }
                            else { storage.readerConfig.theme.textColor.opacity(0.1).frame(width: 1) }
                            if spread * 2 + 1 < readerPages.count {
                                pageContent(readerPages[spread * 2 + 1], number: spread * 2 + 2)
                            } else {
                                Text("本章完").font(.caption)
                                    .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.4))
                                    .frame(width: pageViewportSize.width, height: readingAreaSize.height)
                            }
                        }
                    }
                }
                .onAppear { restorePageFromParagraphIfNeeded(); finishPaginatedRestoration() }
            }
        }
    }

    private func setDuoSidebar(_ visible: Bool) {
        // Lock progress before the outgoing subtree can send visibility callbacks.
        isRestoringPosition = true
        showDuoSidebarTOC = visible
        updateReaderViewport(readingAreaSize, force: true)
    }

    private var duoCenterHingeCrease: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.02),
                    Color.black.opacity(0.14),
                    Color.black.opacity(0.26),
                    Color.white.opacity(0.08),
                    Color.black.opacity(0.12),
                    Color.black.opacity(0.01)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 1)
        }
        .frame(width: 18)
    }

    // MARK: - Floating TTS Control Bar (with Neural Voice Actor Selector)
    private var ttsControlOverlay: some View {
        VStack(spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .foregroundColor(.indigo)
                    Text("真人情感听书 · 第 \(min(speech.currentParagraphIndex + 1, max(1, formattedParagraphs.count)))/\(max(1, formattedParagraphs.count)) 段")
                        .font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                if let mins = speech.sleepTimerMinutes {
                    Text("定时 \(mins)m")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.14))
                        .clipShape(Capsule())
                }
                Button {
                    speech.stop()
                    showTTSBar = false
                    // Explicitly ending the session must also cancel any pending chapter-switch resume.
                    pendingListenStart = false
                    pendingTTSCarryOver = false
                    pendingTTSPaused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }

            if readingAreaSize.width < 460 {
                HStack(spacing: 16) { ttsPlaybackControls; Spacer() }
                HStack(spacing: 12) { ttsSettingsControls; Spacer(minLength: 0) }
            } else {
                HStack(spacing: 14) { ttsPlaybackControls; Spacer(); ttsSettingsControls }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var ttsPlaybackControls: some View {
        Button {
            speech.skipPrevious()
        } label: {
            Image(systemName: "backward.end.fill")
                .font(.system(size: 16))
        }

        Button {
            if speech.isSpeaking && ownsSpeech {
                speech.togglePlayPause(paragraphs: formattedParagraphs, currentIndex: currentParagraphIndex)
            } else {
                // Stopped, or another book owns playback: take over explicitly for this chapter.
                beginListeningHere()
            }
        } label: {
            ZStack {
                Image(systemName: (speech.isSpeaking && !speech.isPaused) ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.indigo)
                if speech.isLoadingAudio {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
        }

        Button {
            speech.skipNext()
        } label: {
            Image(systemName: "forward.end.fill")
                .font(.system(size: 16))
        }

    }

    @ViewBuilder
    private var ttsSettingsControls: some View {

        Menu {
            ForEach(NeuralVoiceActor.allCases) { actor in
                Button {
                    speech.setVoice(actor)
                } label: {
                    HStack {
                        Text(actor.displayName)
                        if speech.selectedVoice == actor {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "person.wave.2.fill")
                    .font(.system(size: 10))
                Text(speech.selectedVoice.shortName)
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color.orange.opacity(0.15))
            .foregroundColor(.orange)
            .clipShape(Capsule())
        }

        Menu {
            ForEach([Float(0.8), Float(1.0), Float(1.25), Float(1.5)], id: \.self) { rate in
                Button(String(format: "%.2gx 语速", rate)) {
                    speech.setRate(rate)
                }
            }
        } label: {
            Text(String(format: "%.2gx", speech.speechRateMultiplier))
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.indigo.opacity(0.14))
                .foregroundColor(.indigo)
                .clipShape(Capsule())
        }

        Menu {
            Button("关闭定时") { speech.setSleepTimer(minutes: nil) }
            Button("15 分钟后停止") { speech.setSleepTimer(minutes: 15) }
            Button("30 分钟后停止") { speech.setSleepTimer(minutes: 30) }
            Button("60 分钟后停止") { speech.setSleepTimer(minutes: 60) }
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .padding(6)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(Circle())
        }    }

    // MARK: - Top HUD Bar (with Duo Split-TOC Toggle & Multi-Option Cache Menu)
    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                saveProgress(force: true)
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

            if isDuoSpreadActive {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        setDuoSidebar(!showDuoSidebarTOC)
                        showHUD = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: showDuoSidebarTOC ? "book.pages.fill" : "sidebar.left")
                        if readingAreaSize.width >= 560 { Text(showDuoSidebarTOC ? "双页" : "目录栏") }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.15))
                    .foregroundColor(.purple)
                    .clipShape(Capsule())
                }
            }

            if isCachingChapters {
                Button {
                    activeCacheTask?.cancel()
                    isCachingChapters = false
                    cacheProgressText = "已暂停缓存"
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.circle.fill")
                        Text("停止")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.15))
                    .foregroundColor(.red)
                    .clipShape(Capsule())
                }
            } else {
                Menu {
                    Button {
                        startCaching(scope: .nextCount(30))
                    } label: {
                        Label("缓存后 30 章", systemImage: "arrow.down.circle")
                    }
                    Button {
                        startCaching(scope: .nextCount(100))
                    } label: {
                        Label("缓存后 100 章", systemImage: "arrow.down.circle.fill")
                    }
                    Button {
                        startCaching(scope: .allRemaining)
                    } label: {
                        Label("缓存后续全部章节 (\(max(0, chapters.count - currentChapterIndex))章)", systemImage: "tray.and.arrow.down.fill")
                    }
                    Divider()
                    Button {
                        startCaching(scope: .entireBook)
                    } label: {
                        Label("全本完整缓存 (共\(chapters.count)章)", systemImage: "books.vertical.fill")
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                        if readingAreaSize.width >= 420 { Text("缓存") }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.14))
                    .foregroundColor(.indigo)
                    .clipShape(Capsule())
                }
            }

            Button {
                showChangeSource = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    if readingAreaSize.width >= 420 { Text("换源") }
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
                    beginListeningHere()
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: speech.isSpeaking && ownsSpeech ? "waveform.circle.fill" : "headphones")
                            .font(.system(size: 18))
                            .foregroundColor(speech.isSpeaking && ownsSpeech ? .indigo : .primary)
                        Text("听书").font(.system(size: 11, weight: .medium))
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
    /// True when the TTS engine is idle, or is currently reading THIS book
    private var ownsSpeech: Bool {
        guard speech.isSpeaking, let ctx = speech.context else { return true }
        return ctx.book.title == book.title && ctx.book.author == book.author
    }

    /// Explicit "listen here" intent (听书 button / play in the floating TTS bar).
    /// Takes ownership away from any other book or chapter before new audio is loaded.
    private func beginListeningHere() {
        showHUD = false
        showTTSBar = true
        pendingTTSCarryOver = false
        pendingTTSPaused = false
        guard !chapters.isEmpty else {
            // TOC still loading: remember the intent and start as soon as the chapter exists.
            pendingListenStart = true
            return
        }
        if speech.isSpeaking {
            let sameChapter = speech.context?.book.id == book.id
                && speech.context?.chapterIndex == currentChapterIndex
            if !sameChapter {
                // Another book (or another chapter) is being read aloud: stop it first.
                speech.stop()
            } else {
                setupSpeechCallbacks(force: true)
                if speech.isPaused {
                    speech.togglePlayPause(paragraphs: formattedParagraphs, currentIndex: currentParagraphIndex)
                }
                return
            }
        }
        // While the next chapter is still fetching, `formattedParagraphs` may still contain the
        // previous chapter — starting TTS now would read it under the new chapter's title/progress.
        guard PlaybackTransitionPolicy.canStartListening(loadedChapterURL: loadedContentChapterURL,
                                                         currentChapterURL: currentChapter?.url,
                                                         hasParagraphs: !formattedParagraphs.isEmpty)
        else {
            pendingListenStart = true
            return
        }
        setupSpeechCallbacks(force: true)
        speech.startReading(
            paragraphs: formattedParagraphs,
            fromIndex: max(0, min(currentParagraphIndex, formattedParagraphs.count - 1)),
            bookTitle: book.title,
            chapterTitle: currentChapter?.title
        )
        pendingListenStart = false
    }

    /// Attaches this reader page to the TTS engine. When another book is being read aloud in the
    /// background, the reader leaves it alone unless `force` is set (user tapped 听书 here).
    private func setupSpeechCallbacks(force: Bool = false) {
        if !force {
            guard ownsSpeech else { return }
            // Same book, but the engine is further ahead in the background: stay a passive
            // observer instead of stealing its context (the callbacks below would mis-map indices).
            if speech.isSpeaking, let ctx = speech.context, ctx.chapterIndex != currentChapterIndex {
                return
            }
        }
        if !chapters.isEmpty {
            speech.setContext(book: book, chapters: chapters, chapterIndex: currentChapterIndex)
        }
        speech.updateNowPlayingMetadata(
            bookTitle: book.title,
            chapterTitle: currentChapter?.title ?? book.title
        )
        speech.onParagraphChanged = { idx in
            // Only the chapter that is actually being spoken may write progress. This stops
            // stale audio from another book/chapter from corrupting the current position.
            guard self.speech.context?.book.id == self.book.id,
                  self.speech.context?.chapterIndex == self.currentChapterIndex else { return }
            self.currentParagraphIndex = idx
            self.currentCharacterOffset = 0
            self.saveProgress()
            let pages = self.paginatedPages
            if let pageIdx = pages.firstIndex(where: { $0.contains(where: { $0.index == idx }) }) {
                self.currentPageIndex = pageIdx
                self.currentSpreadIndex = pageIdx / 2
            }
        }
        speech.onChapterFinished = {
            guard self.speech.context?.book.id == self.book.id,
                  self.speech.context?.chapterIndex == self.currentChapterIndex else { return }
            if self.currentChapterIndex + 1 < self.chapters.count {
                self.switchChapter(to: self.currentChapterIndex + 1, proxy: nil, autoContinueTTS: true)
            } else {
                self.speech.stop()
            }
        }
    }

    private func initializeReader() {
        chapterTurnBackward = nil
        chapterLanding.cancel()
        tocLoadTask?.cancel()
        tocRefreshTask?.cancel()
        chapterLoadTask?.cancel()
        loadTokens.beginChapterLoad()
        prefetchTask?.cancel()
        activeCacheTask?.cancel()
        pendingListenStart = false
        pendingTTSCarryOver = false
        pendingTTSPaused = false
        let loadID = loadTokens.beginTocLoad()
        let requestedBook = book
        isLoading = true
        errorMessage = nil

        storage.markBookAsRecentlyRead(book)

        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)

        // 1) Offline-first: a persisted TOC is enough to open every already-cached chapter.
        if let cachedToc = storage.loadCachedToc(for: requestedBook) {
            applyToc(cachedToc.chapters, consumeRelocation: true)
            isTocComplete = cachedToc.complete
            isLoading = false
            loadCurrentChapterContent()
            refreshTocInBackground(book: requestedBook, source: source, loadID: loadID)
            return
        }

        // 2) No local TOC yet: fetch it once from the network, then persist it for offline use.
        tocLoadTask = Task {
            do {
                let result = try await LegadoParser.shared.fetchToc(bookUrl: requestedBook.bookUrl, source: source)
                try Task.checkCancellation()
                await MainActor.run {
                    guard self.loadTokens.isCurrentTocLoad(loadID), self.book.bookUrl == requestedBook.bookUrl else { return }
                    if result.chapters.isEmpty {
                        self.errorMessage = "当前书源未能解析出目录，请点击「切换书源」"
                        self.isLoading = false
                        return
                    }
                    self.applyToc(result.chapters, consumeRelocation: true)
                    self.isTocComplete = result.complete
                    self.storage.saveCachedToc(for: requestedBook, chapters: result.chapters, complete: result.complete)
                    self.loadCurrentChapterContent()
                    if !result.complete {
                        self.showTOCNotice("目录可能不完整（已获取 \(result.chapters.count) 章）")
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.loadTokens.isCurrentTocLoad(loadID) else { return }
                    self.errorMessage = "目录拉取失败，请点击「切换书源」或重试"
                    self.isLoading = false
                }
            }
        }
    }

    /// Installs a chapter list and re-locates the chapter that was being read.
    /// Returns true when the chapter at the current index now points at different content.
    @discardableResult
    private func applyToc(_ newChapters: [Chapter], consumeRelocation: Bool = false) -> Bool {
        guard !newChapters.isEmpty else { return false }
        let previousURL = currentChapter?.url
        let previousTitle = currentChapter?.title
        let previousIndex = currentChapterIndex

        chapters = newChapters
        book.totalChapters = newChapters.count

        // Source switch: re-locate by title in the new site's chapter numbering.
        if consumeRelocation, let relocateTitle = storage.consumePendingRelocation(for: book) {
            chapterLanding.cancel()
            currentCharacterOffset = 0
            let matched = ChapterTextFormatter.bestMatchIndex(title: relocateTitle, in: newChapters, nearIndex: previousIndex)
            currentChapterIndex = matched ?? min(max(0, previousIndex), newChapters.count - 1)
            currentPageIndex = 0
            currentSpreadIndex = 0
            visibleParagraphIndices.removeAll()
            targetRestoreParagraph = currentParagraphIndex > 0 ? currentParagraphIndex : nil
            isRestoringPosition = currentParagraphIndex > 0
            showTOCNotice(matched != nil ? "换源成功，已定位到「\(chapters[currentChapterIndex].title)」"
                                         : "新书源未找到同名章节，已定位到相近位置")
            return true
        }

        let resolved = ChapterTextFormatter.resolvedChapterIndex(
            in: newChapters,
            preferredURL: previousURL,
            preferredTitle: previousTitle,
            fallbackIndex: previousIndex
        )
        currentChapterIndex = resolved
        if previousURL == nil && resolved != previousIndex {
            currentParagraphIndex = 0
            currentCharacterOffset = 0
            targetRestoreParagraph = nil
        }
        let movedToDifferentChapter = previousURL.map { $0 != newChapters[resolved].url } ?? false
        if movedToDifferentChapter {
            chapterLanding.cancel()
            currentCharacterOffset = 0
            currentPageIndex = 0
            currentSpreadIndex = 0
            visibleParagraphIndices.removeAll()
            targetRestoreParagraph = nil
            isRestoringPosition = false
        }
        return movedToDifferentChapter
    }

    private func showTOCNotice(_ message: String) {
        withAnimation { restoreToastMessage = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation { self.restoreToastMessage = nil }
        }
    }

    /// Silently refreshes the TOC when the reader opened from the persisted snapshot.
    /// Failures keep the offline copy and never surface an error banner.
    private func refreshTocInBackground(book requestedBook: Book, source: BookSource, loadID: UUID) {
        tocRefreshTask?.cancel()
        tocRefreshTask = Task {
            do {
                let result = try await LegadoParser.shared.fetchToc(bookUrl: requestedBook.bookUrl, source: source)
                try Task.checkCancellation()
                guard !result.chapters.isEmpty else { return }
                await MainActor.run {
                    guard self.loadTokens.isCurrentTocLoad(loadID),
                          TocUpdatePolicy.matchesRequest(currentSourceUrl: self.book.sourceUrl,
                                                         currentBookUrl: self.book.bookUrl,
                                                         requestedSourceUrl: requestedBook.sourceUrl,
                                                         requestedBookUrl: requestedBook.bookUrl),
                          TocUpdatePolicy.shouldAcceptRefresh(resultComplete: result.complete,
                                                              localChapterCount: self.chapters.count)
                    else { return }
                    self.isTocComplete = result.complete
                    let chapterChanged = self.applyToc(result.chapters)
                    self.storage.saveCachedToc(for: requestedBook, chapters: result.chapters, complete: result.complete)
                    if chapterChanged {
                        self.loadCurrentChapterContent()
                    } else {
                        self.setupSpeechCallbacks()
                    }
                }
            } catch {
                // Offline / site down: keep using the cached TOC.
            }
        }
    }

    private func switchChapter(to newIndex: Int, proxy: ScrollViewProxy?, autoContinueTTS: Bool = false,
                               pageTurnBackward: Bool? = nil) {
        guard newIndex >= 0 && newIndex < chapters.count else { return }
        guard newIndex != currentChapterIndex else { return }
        chapterTurnBackward = pageTurnBackward
        // If this book is being read aloud, stop the old chapter's audio before the new
        // chapter becomes current; otherwise stale audio would keep writing its paragraph
        // index into the newly selected chapter. Playback resumes once the text is loaded.
        var resumeTTS = autoContinueTTS
        if speech.isSpeaking && ownsSpeech {
            pendingTTSCarryOver = true
            // Reading backwards lands at the chapter tail. Keep listening paused there;
            // resuming automatically from the chapter start would undo the visual landing.
            pendingTTSPaused = speech.isPaused || pageTurnBackward == true
            pendingTTSSession = speech.sessionStopCount
            resumeTTS = true
            speech.suspendForChapterTransition()
            showTTSBar = true
        }
        layoutRestoration.cancel()
        chapterLanding.cancel()
        if pageTurnBackward == true { chapterLanding.requestEnd(chapterURL: chapters[newIndex].url) }
        currentChapterIndex = newIndex
        currentParagraphIndex = 0
        currentCharacterOffset = 0
        currentPageIndex = 0
        currentSpreadIndex = 0
        targetRestoreParagraph = nil
        isRestoringPosition = false
        visibleParagraphIndices.removeAll()
        if let proxy = proxy {
            proxy.scrollTo("chapterTop", anchor: .top)
        }
        loadCurrentChapterContent(autoContinueTTS: resumeTTS)
    }

    private func loadCurrentChapterContent(forceRefresh: Bool = false, autoContinueTTS: Bool = false) {
        guard let chapter = currentChapter else { return }
        chapterLoadTask?.cancel()
        let loadID = loadTokens.beginChapterLoad()
        let requestedBook = book

        if !forceRefresh, let cached = storage.getCachedChapter(bookId: book.id, chapterIndex: chapter.index,
                                                               chapterURL: chapter.url, sourceURL: book.sourceUrl) {
            self.applyChapterContent(cached)
            self.loadedContentChapterURL = chapter.url
            self.isLoading = false
            self.errorMessage = nil
            self.restorePageFromParagraphIfNeeded()
            self.saveProgress(force: true)
            self.setupSpeechCallbacks()
            self.prefetchNextChapter()
            self.resumeTTSIfNeeded(autoContinueTTS: autoContinueTTS, chapter: chapter)
            return
        }

        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)

        isLoading = true
        errorMessage = nil

        let nextURL = currentChapterIndex + 1 < chapters.count ? chapters[currentChapterIndex + 1].url : nil
        chapterLoadTask = Task {
            do {
                let content = try await ChapterContentLoader.shared.load(chapter: chapter, source: source,
                                                                         referer: requestedBook.bookUrl, nextChapterURL: nextURL)
                try Task.checkCancellation()

                await MainActor.run {
                    guard self.loadTokens.isCurrentChapterLoad(loadID), self.currentChapter?.url == chapter.url,
                          self.book.bookUrl == requestedBook.bookUrl else { return }
                    self.applyChapterContent(content.text)
                    self.loadedContentChapterURL = chapter.url
                    self.isLoading = false
                    self.storage.saveChapterCache(bookId: requestedBook.id, chapterIndex: chapter.index, content: content)
                    self.restorePageFromParagraphIfNeeded()
                    self.saveProgress(force: true)
                    self.setupSpeechCallbacks()
                    self.prefetchNextChapter()
                    self.resumeTTSIfNeeded(autoContinueTTS: autoContinueTTS, chapter: chapter)
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard self.loadTokens.isCurrentChapterLoad(loadID) else { return }
                    let wasCarryOver = self.pendingTTSCarryOver
                    self.pendingTTSCarryOver = false
                    self.pendingTTSPaused = false
                    self.pendingListenStart = false
                    if wasCarryOver {
                        // The switch belonged to an active listening session but the text failed
                        // to load: end that session instead of leaving a half-paused player.
                        self.speech.stop()
                        self.showTTSBar = false
                    }
                    self.errorMessage = "正文抓取失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    /// Restarts TTS after a chapter switch (or after an explicit 听书 tap that happened
    /// before the chapter text existed). Never starts playback the user did not ask for.
    private func resumeTTSIfNeeded(autoContinueTTS: Bool, chapter: Chapter) {
        // Loading can finish while the window is changing. Wait for its real geometry
        // before resuming the paused listening session at the reverse-turn destination.
        guard chapterLanding.pendingChapterURL != chapter.url else { return }
        if pendingListenStart {
            pendingListenStart = false
            speech.stop()
            setupSpeechCallbacks(force: true)
            guard !formattedParagraphs.isEmpty else { return }
            speech.startReading(paragraphs: formattedParagraphs,
                                fromIndex: max(0, min(currentParagraphIndex, formattedParagraphs.count - 1)),
                                bookTitle: book.title, chapterTitle: chapter.title)
            return
        }
        // Resume only if this load was a chapter-switch carry-over AND the user did not stop
        // listening while the chapter was loading (which clears pendingTTSCarryOver).
        guard PlaybackTransitionPolicy.shouldResume(carryOverRequested: autoContinueTTS,
                                                    carryOverPending: pendingTTSCarryOver,
                                                    hasParagraphs: !formattedParagraphs.isEmpty,
                                                    sessionUnchanged: speech.sessionStopCount == pendingTTSSession)
        else {
            pendingTTSCarryOver = false
            pendingTTSPaused = false
            return
        }
        let wasPaused = pendingTTSPaused
        pendingTTSCarryOver = false
        pendingTTSPaused = false
        speech.startReading(paragraphs: formattedParagraphs,
                            fromIndex: max(0, min(currentParagraphIndex, formattedParagraphs.count - 1)),
                            bookTitle: book.title,
                            chapterTitle: chapter.title,
                            initiallyPaused: wasPaused)
    }

    private func restorePageFromParagraphIfNeeded() {
        guard !readerPages.isEmpty else { return }
        currentPageIndex = ReaderPageLocator.pageIndex(paragraphIndex: targetRestoreParagraph ?? currentParagraphIndex,
                                                       characterOffset: currentCharacterOffset, pages: readerPages)
        currentSpreadIndex = currentPageIndex / 2
    }

    private func prefetchNextChapter() {
        let nextIdx = currentChapterIndex + 1
        guard nextIdx < chapters.count else { return }

        let nextCh = chapters[nextIdx]
        let requestedBook = book
        guard !storage.isChapterCached(bookId: book.id, chapterIndex: nextCh.index,
                                       chapterURL: nextCh.url, sourceURL: book.sourceUrl) else { return }
        let followingURL = nextIdx + 1 < chapters.count ? chapters[nextIdx + 1].url : nil
        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)

        prefetchTask?.cancel()
        prefetchTask = Task {
            if let content = try? await ChapterContentLoader.shared.load(chapter: nextCh, source: source,
                                                                        referer: requestedBook.bookUrl, nextChapterURL: followingURL),
               !Task.isCancelled {
                storage.saveChapterCache(bookId: requestedBook.id, chapterIndex: nextCh.index, content: content)
            }
        }
    }

    // MARK: - Concurrent Chapter Caching (30 / 100 / Remaining / Full Book)
    private func startCaching(scope: ChapterCacheScope) {
        guard !chapters.isEmpty else { return }
        let startIdx: Int
        let endIdx: Int
        switch scope {
        case .nextCount(let count):
            startIdx = currentChapterIndex
            endIdx = min(chapters.count - 1, currentChapterIndex + count - 1)
        case .allRemaining:
            startIdx = currentChapterIndex
            endIdx = chapters.count - 1
        case .entireBook:
            startIdx = 0
            endIdx = chapters.count - 1
        }
        guard startIdx <= endIdx else { return }

        let completeTOC = chapters
        let targetChapters = Array(chapters[startIdx...endIdx])
        let total = targetChapters.count
        // Completeness is part of the download snapshot: a TOC refresh during the run must not
        // let this (possibly partial) download report a complete book.
        let tocCompleteSnapshot = isTocComplete
        let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl })
            ?? BookSource(bookSourceName: book.sourceName, bookSourceUrl: book.sourceUrl)
        let bookId = book.id
        let bookUrl = book.bookUrl

        showHUD = false
        isCachingChapters = true
        cacheProgressText = "正在高速缓存 0/\(total) 章..."

        activeCacheTask?.cancel()
        activeCacheTask = Task {
            var completed = 0
            let batchSize = 6
            for chunkStart in stride(from: 0, to: total, by: batchSize) {
                guard !Task.isCancelled else { break }
                let chunkEnd = min(total, chunkStart + batchSize)
                let slice = Array(targetChapters[chunkStart..<chunkEnd])

                let savedCount = await withTaskGroup(of: Bool.self) { group -> Int in
                    for ch in slice {
                        group.addTask {
                            guard !Task.isCancelled else { return false }
                            if StorageManager.shared.isChapterCached(bookId: bookId, chapterIndex: ch.index,
                                                                      chapterURL: ch.url, sourceURL: source.bookSourceUrl) { return true }
                            let nextURL = ch.index + 1 < completeTOC.count ? completeTOC[ch.index + 1].url : nil
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
                let currentDone = completed
                let pct = Int(Double(currentDone) / Double(max(1, total)) * 100.0)
                await MainActor.run {
                    self.cacheProgressText = "已成功缓存 \(currentDone)/\(total) 章 (\(pct)%)"
                }
            }
            guard !Task.isCancelled else { return }
            let savedTotal = completed
            await MainActor.run {
                self.isCachingChapters = false
                if TocUpdatePolicy.isFullCacheComplete(savedCount: savedTotal, totalCount: total,
                                                       tocComplete: tocCompleteSnapshot) {
                    self.cacheProgressText = "缓存完成（\(total) 章完整就绪）"
                } else if savedTotal == total {
                    self.cacheProgressText = "已缓存当前获取的 \(total) 章，但目录尚不完整，无法确认全本"
                } else {
                    self.cacheProgressText = "缓存未完成：成功 \(savedTotal)/\(total) 章，请重试失败章节"
                }
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                if !self.isCachingChapters {
                    self.cacheProgressText = nil
                }
            }
        }
    }

    private func saveProgress(force: Bool = false) {
        guard let ch = currentChapter else { return }
        let bookId = book.id
        let bookTitle = book.title
        let bookAuthor = book.author
        let chIdx = currentChapterIndex
        let chTitle = ch.title
        let totalCh = chapters.count
        // Layout callbacks must not roll progress back while the new view finds its anchor.
        if isRestoringPosition && !force { return }
        let anchor = layoutRestoration.anchor.flatMap { $0.chapterURL == ch.url ? $0 : nil }
        let liveParagraph = liveSpokenParagraph
        let paraIdx = liveParagraph ?? anchor?.paragraphIndex ?? currentParagraphIndex
        let offset = liveParagraph != nil ? 0 : (anchor?.characterOffset ?? currentCharacterOffset)

        let commitSave = {
            StorageManager.shared.updateBookProgress(
                bookId: bookId,
                bookTitle: bookTitle,
                bookAuthor: bookAuthor,
                chapterIndex: chIdx,
                chapterTitle: chTitle,
                totalChapters: totalCh,
                paragraphIndex: paraIdx,
                characterOffset: offset
            )
        }

        progressSaver.pending?.cancel()
        progressSaver.pending = nil

        let now = Date()
        if force || now.timeIntervalSince(progressSaver.lastSave) >= 1.2 {
            progressSaver.lastSave = now
            commitSave()
        } else {
            let work = DispatchWorkItem { [weak progressSaver] in
                progressSaver?.lastSave = Date()
                commitSave()
            }
            progressSaver.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
    }
}
