import SwiftUI

public struct PaginatedParagraph: Identifiable, Equatable {
    public var id: Int { index }
    public let index: Int
    public let text: String
}

public enum ChapterCacheScope {
    case nextCount(Int)
    case allRemaining
    case entireBook
}

public struct ReaderView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    @ObservedObject var speech = SpeechSynthesizerManager.shared
    
    @State var book: Book
    @State private var chapters: [Chapter] = []
    @State private var currentChapterIndex: Int
    @State private var currentParagraphIndex: Int
    @State private var currentPageIndex: Int = 0
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
    
    // Intra-Chapter Paragraph Restoration State
    @State private var targetRestoreParagraph: Int? = nil
    @State private var isRestoringPosition: Bool = false
    @State private var visibleParagraphIndices: Set<Int> = []
    @State private var restoreToastMessage: String? = nil
    
    public init(book: Book) {
        let saved = StorageManager.shared.getSavedReadingPosition(for: book)
        var initialBook = book
        initialBook.currentChapterIndex = saved.chapterIndex
        initialBook.currentParagraphIndex = saved.paragraphIndex
        _book = State(initialValue: initialBook)
        _currentChapterIndex = State(initialValue: saved.chapterIndex)
        _currentParagraphIndex = State(initialValue: saved.paragraphIndex)
        _targetRestoreParagraph = State(initialValue: saved.paragraphIndex > 0 ? saved.paragraphIndex : nil)
        _isRestoringPosition = State(initialValue: saved.paragraphIndex > 0)
    }
    
    private var currentChapter: Chapter? {
        guard currentChapterIndex >= 0 && currentChapterIndex < chapters.count else { return nil }
        return chapters[currentChapterIndex]
    }
    
    /// Splits chapter content into clean, distinct paragraphs with custom purification & Chinese conversion applied
    private var formattedParagraphs: [String] {
        guard !currentContent.isEmpty else { return [] }
        let normalized = currentContent
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\u{3000}\u{3000}", with: "\n")
            .replacingOccurrences(of: "\u{00A0}\u{00A0}", with: "\n")
        
        let customRules = storage.readerConfig.effectivePurifyRules
        let converter = storage.readerConfig.effectiveChineseConversion
        
        var rawList = normalized
            .components(separatedBy: .newlines)
            .map { line -> String in
                var cleaned = line
                    .replacingOccurrences(of: "\u{3000}", with: " ")
                    .replacingOccurrences(of: "\u{00A0}", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                for rule in customRules where !rule.isEmpty {
                    cleaned = cleaned.replacingOccurrences(of: rule, with: "")
                }
                return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }
        
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
        
        return rawList.map { "　　" + converter.convert($0) }
    }
    
    /// Slices `formattedParagraphs` into screen-sized pages for horizontal page-turning mode
    private var paginatedPages: [[PaginatedParagraph]] {
        let paras = formattedParagraphs
        guard !paras.isEmpty else { return [] }
        
        let fontFactor = max(14.0, Double(storage.readerConfig.fontSize))
        let spacingFactor = max(4.0, Double(storage.readerConfig.lineSpacing))
        let charsPerLine = max(14, Int(340.0 / fontFactor))
        let linesPerPage = max(12, Int(560.0 / (fontFactor + spacingFactor * 0.85)))
        let maxLinesBudget = linesPerPage
        
        var pages: [[PaginatedParagraph]] = []
        var currentPage: [PaginatedParagraph] = []
        var currentLinesUsed = 2
        
        for (idx, para) in paras.enumerated() {
            let estimatedLines = max(1, Int(ceil(Double(para.count) / Double(charsPerLine)))) + 1
            let item = PaginatedParagraph(index: idx, text: para)
            if !currentPage.isEmpty && (currentLinesUsed + estimatedLines > maxLinesBudget) {
                pages.append(currentPage)
                currentPage = [item]
                currentLinesUsed = estimatedLines
            } else {
                currentPage.append(item)
                currentLinesUsed += estimatedLines
            }
        }
        if !currentPage.isEmpty {
            pages.append(currentPage)
        }
        return pages
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
                    if speech.isSpeaking {
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
                        Text("第 \(currentParagraphIndex + 1) 段 · \(book.sourceName)")
                            .font(.system(size: 10))
                            .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.42))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 6)
                
                // Main Reading Area: Vertical Scroll OR Horizontal Slide Pages
                if isLoading {
                    loadingStateView
                } else if let error = errorMessage {
                    errorStateView(error)
                } else if storage.readerConfig.effectivePageTurnMode == .horizontalSlide {
                    horizontalPageReaderView
                } else {
                    verticalScrollReaderView
                }
                
                // Subtle Bottom Footer
                HStack {
                    Text(storage.readerConfig.effectiveChineseConversion.convert(book.title))
                        .font(.system(size: 10))
                        .foregroundColor(storage.readerConfig.theme.textColor.opacity(0.4))
                        .lineLimit(1)
                    Spacer()
                    if !chapters.isEmpty {
                        let pct = min(100.0, Double(currentChapterIndex + 1) / Double(chapters.count) * 100.0)
                        if storage.readerConfig.effectivePageTurnMode == .horizontalSlide && !paginatedPages.isEmpty {
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
            if showTTSBar || speech.isSpeaking {
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
            setupSpeechCallbacks()
            initializeReader()
        }
        .onDisappear {
            saveProgress()
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
                LazyVStack(alignment: .leading, spacing: storage.readerConfig.lineSpacing + 14) {
                    Color.clear
                        .frame(height: 1)
                        .id("chapterTop")
                    
                    if let chapter = currentChapter {
                        Text(storage.readerConfig.effectiveChineseConversion.convert(chapter.title))
                            .font(.system(
                                size: storage.readerConfig.fontSize + 5,
                                weight: .bold,
                                design: storage.readerConfig.fontDesign.swiftUIDesign
                            ))
                            .foregroundColor(storage.readerConfig.theme.textColor)
                            .padding(.top, 8)
                            .padding(.bottom, 6)
                    }
                    
                    ForEach(Array(formattedParagraphs.enumerated()), id: \.offset) { idx, paragraph in
                        let isSpoken = speech.isSpeaking && speech.currentParagraphIndex == idx
                        Text(paragraph)
                            .font(.system(
                                size: storage.readerConfig.fontSize,
                                design: storage.readerConfig.fontDesign.swiftUIDesign
                            ))
                            .lineSpacing(storage.readerConfig.lineSpacing)
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
                                        saveProgress()
                                    }
                                }
                            }
                            .onDisappear {
                                visibleParagraphIndices.remove(idx)
                                if !isRestoringPosition, let topIdx = visibleParagraphIndices.min() {
                                    if topIdx != currentParagraphIndex {
                                        currentParagraphIndex = topIdx
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
            .onChange(of: speech.currentParagraphIndex) { newIdx in
                if speech.isSpeaking {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scrollProxy.scrollTo("para_\(newIdx)", anchor: .center)
                    }
                }
            }
        }
    }
    
    private func restoreParagraphScrollIfNeeded(proxy: ScrollViewProxy) {
        let totalParas = formattedParagraphs.count
        guard totalParas > 0 else { return }
        guard let target = targetRestoreParagraph, target > 0 else {
            isRestoringPosition = false
            return
        }
        let clamped = min(target, totalParas - 1)
        isRestoringPosition = true
        currentParagraphIndex = clamped
        
        // Two-stage scroll on LazyVStack ensures intermediate cells materialize and target lands at top
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            withAnimation(.none) {
                proxy.scrollTo("para_\(clamped)", anchor: .top)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            withAnimation(.none) {
                proxy.scrollTo("para_\(clamped)", anchor: .top)
            }
            self.currentParagraphIndex = clamped
            self.targetRestoreParagraph = nil
            self.isRestoringPosition = false
            withAnimation {
                self.restoreToastMessage = "已自动续读至上次退出的第 \(clamped + 1) 段"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation {
                    self.restoreToastMessage = nil
                }
            }
        }
    }
    
    // MARK: - 2. Horizontal Slide Page-Turn Reader View
    private var horizontalPageReaderView: some View {
        GeometryReader { geo in
            let pages = paginatedPages
            ZStack {
                TabView(selection: $currentPageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { pageIdx, pageItems in
                        ScrollView(showsIndicators: false) {
                            VStack(alignment: .leading, spacing: storage.readerConfig.lineSpacing + 12) {
                                if pageIdx == 0, let chapter = currentChapter {
                                    Text(storage.readerConfig.effectiveChineseConversion.convert(chapter.title))
                                        .font(.system(
                                            size: storage.readerConfig.fontSize + 4,
                                            weight: .bold,
                                            design: storage.readerConfig.fontDesign.swiftUIDesign
                                        ))
                                        .foregroundColor(storage.readerConfig.theme.textColor)
                                        .padding(.top, 6)
                                        .padding(.bottom, 4)
                                }
                                
                                ForEach(pageItems) { item in
                                    let isSpoken = speech.isSpeaking && speech.currentParagraphIndex == item.index
                                    Text(item.text)
                                        .font(.system(
                                            size: storage.readerConfig.fontSize,
                                            design: storage.readerConfig.fontDesign.swiftUIDesign
                                        ))
                                        .lineSpacing(storage.readerConfig.lineSpacing)
                                        .foregroundColor(isSpoken ? .indigo : storage.readerConfig.theme.textColor)
                                        .background(isSpoken ? Color.indigo.opacity(0.10) : Color.clear)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(.horizontal, 22)
                            .padding(.vertical, 8)
                        }
                        .tag(pageIdx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .onChange(of: currentPageIndex) { newPage in
                    if newPage >= 0 && newPage < pages.count, let firstPara = pages[newPage].first {
                        currentParagraphIndex = firstPara.index
                        saveProgress()
                    }
                }
                
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.28)
                        .onTapGesture {
                            if showHUD {
                                withAnimation { showHUD = false }
                            } else if currentPageIndex > 0 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentPageIndex -= 1
                                }
                            } else if currentChapterIndex > 0 {
                                switchChapter(to: currentChapterIndex - 1, proxy: nil)
                            }
                        }
                    
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.44)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showHUD.toggle()
                            }
                        }
                    
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width * 0.28)
                        .onTapGesture {
                            if showHUD {
                                withAnimation { showHUD = false }
                            } else if currentPageIndex < pages.count - 1 {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    currentPageIndex += 1
                                }
                            } else if currentChapterIndex < chapters.count - 1 {
                                switchChapter(to: currentChapterIndex + 1, proxy: nil)
                            }
                        }
                }
            }
        }
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
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 14) {
                Button {
                    speech.skipPrevious()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 16))
                }
                
                Button {
                    speech.togglePlayPause(paragraphs: formattedParagraphs, currentIndex: currentParagraphIndex)
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
                
                Spacer()
                
                // Neural Voice Actor Selector
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
                
                // Speed Multiplier Selector
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
                
                // Sleep Timer Selector
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
                }
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Top HUD Bar (with Multi-Option & Full-Book Cache Menu)
    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                saveProgress()
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
            
            // Cache Menu: 30 Chapters / 100 Chapters / Remaining / Full Book
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
                        Text("缓存")
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
                    showHUD = false
                    showTTSBar = true
                    if !speech.isSpeaking {
                        speech.startReading(paragraphs: formattedParagraphs, fromIndex: currentParagraphIndex)
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: speech.isSpeaking ? "waveform.circle.fill" : "headphones")
                            .font(.system(size: 18))
                            .foregroundColor(speech.isSpeaking ? .indigo : .primary)
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
    private func setupSpeechCallbacks() {
        speech.onParagraphChanged = { idx in
            self.currentParagraphIndex = idx
            self.saveProgress()
            let pages = self.paginatedPages
            if let pageIdx = pages.firstIndex(where: { $0.contains(where: { $0.index == idx }) }) {
                self.currentPageIndex = pageIdx
            }
        }
        speech.onChapterFinished = {
            if self.currentChapterIndex + 1 < self.chapters.count {
                self.switchChapter(to: self.currentChapterIndex + 1, proxy: nil, autoContinueTTS: true)
            } else {
                self.speech.stop()
            }
        }
    }
    
    private func initializeReader() {
        isLoading = true
        errorMessage = nil
        
        // Ensure book is on shelf so progress is always tracked
        if !storage.bookshelf.contains(where: { $0.title == book.title && $0.author == book.author }) {
            storage.addBookToShelf(book)
        }
        
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
                            self.currentParagraphIndex = 0
                            self.targetRestoreParagraph = nil
                            self.isRestoringPosition = false
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
    
    private func switchChapter(to newIndex: Int, proxy: ScrollViewProxy?, autoContinueTTS: Bool = false) {
        guard newIndex >= 0 && newIndex < chapters.count else { return }
        currentChapterIndex = newIndex
        currentParagraphIndex = 0
        currentPageIndex = 0
        targetRestoreParagraph = nil
        isRestoringPosition = false
        visibleParagraphIndices.removeAll()
        if let proxy = proxy {
            proxy.scrollTo("chapterTop", anchor: .top)
        }
        loadCurrentChapterContent(autoContinueTTS: autoContinueTTS)
    }
    
    private func loadCurrentChapterContent(forceRefresh: Bool = false, autoContinueTTS: Bool = false) {
        guard let chapter = currentChapter else { return }
        
        if !forceRefresh, let cached = storage.getCachedChapter(bookId: book.id, chapterIndex: chapter.index) {
            self.currentContent = cached
            self.isLoading = false
            self.errorMessage = nil
            self.restorePageFromParagraphIfNeeded()
            self.saveProgress()
            self.prefetchNextChapter()
            if autoContinueTTS {
                self.speech.startReading(paragraphs: self.formattedParagraphs, fromIndex: 0)
            }
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
                    self.restorePageFromParagraphIfNeeded()
                    self.saveProgress()
                    self.prefetchNextChapter()
                    if autoContinueTTS {
                        self.speech.startReading(paragraphs: self.formattedParagraphs, fromIndex: 0)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "正文抓取失败: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func restorePageFromParagraphIfNeeded() {
        let target = targetRestoreParagraph ?? currentParagraphIndex
        guard target > 0 else { return }
        let pages = paginatedPages
        if let targetPage = pages.firstIndex(where: { $0.contains(where: { $0.index >= target }) }) {
            currentPageIndex = targetPage
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
        
        let targetChapters = Array(chapters[startIdx...endIdx])
        let total = targetChapters.count
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
                
                await withTaskGroup(of: Void.self) { group in
                    for ch in slice {
                        group.addTask {
                            guard !Task.isCancelled else { return }
                            if !StorageManager.shared.isChapterCached(bookId: bookId, chapterIndex: ch.index) {
                                if let (html, finalUrl) = try? await NetworkManager.shared.fetchString(from: ch.url, referer: bookUrl),
                                   let text = try? LegadoParser.shared.parseContent(html: html, baseUrl: finalUrl, source: source),
                                   text.count >= 50 {
                                    StorageManager.shared.saveChapterCache(bookId: bookId, chapterIndex: ch.index, content: text)
                                }
                            }
                        }
                    }
                }
                completed = chunkEnd
                let currentDone = completed
                let pct = Int(Double(currentDone) / Double(max(1, total)) * 100.0)
                await MainActor.run {
                    self.cacheProgressText = "已缓存 \(currentDone)/\(total) 章 (\(pct)%)"
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.isCachingChapters = false
                self.cacheProgressText = "缓存完成 (\(total) 章已离线就绪)"
            }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                if !self.isCachingChapters {
                    self.cacheProgressText = nil
                }
            }
        }
    }
    
    private func saveProgress() {
        if let ch = currentChapter {
            storage.updateBookProgress(
                bookId: book.id,
                bookTitle: book.title,
                bookAuthor: book.author,
                chapterIndex: currentChapterIndex,
                chapterTitle: ch.title,
                totalChapters: chapters.count,
                paragraphIndex: currentParagraphIndex
            )
        }
    }
}
