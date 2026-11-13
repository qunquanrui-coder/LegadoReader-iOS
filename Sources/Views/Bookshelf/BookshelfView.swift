import SwiftUI

public struct BookshelfView: View {
    @ObservedObject var storage = StorageManager.shared
    @ObservedObject var speech = SpeechSynthesizerManager.shared
    @State private var selectedBook: Book?
    @State private var showingSearch = false
    @State private var isGridView = true
    
    // Let the current window choose the column count, including the outer screen and multitasking.
    private var adaptiveColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 16)]
    }

    public init() {}
    
    private func openBook(_ book: Book) {
        let fresh = storage.bookshelf.first(where: {
            $0.id == book.id || ($0.title == book.title && $0.author == book.author)
        }) ?? book
        storage.markBookAsRecentlyRead(fresh)
        selectedBook = storage.bookshelf.first(where: {
            $0.id == fresh.id || ($0.title == fresh.title && $0.author == fresh.author)
        }) ?? fresh
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if storage.bookshelf.isEmpty {
                    emptyShelfView
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        // Top Hero "Continue Reading" Card — always binds to the most recently read book
                        if let recentBook = storage.mostRecentBook {
                            continueReadingCard(book: recentBook)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                        
                        // Section Header & Studio Ribbon
                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "books.vertical.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(
                                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    )
                                Text("全部藏书")
                                    .font(.system(size: 18, weight: .bold, design: .serif))
                            }
                            
                            Text("\(storage.bookshelf.count) 册")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.indigo.opacity(0.12))
                                .foregroundColor(.indigo)
                                .clipShape(Capsule())
                            
                            let activeSources = storage.bookSources.filter { $0.enabled != false }.count
                            Text("\(activeSources) 源在线")
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.teal.opacity(0.10))
                                .foregroundColor(.teal)
                                .clipShape(Capsule())
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isGridView.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isGridView ? "list.bullet" : "square.grid.3x2")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(isGridView ? "列表" : "宫格")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color(.secondarySystemGroupedBackground))
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Bookshelf Grid or List
                        if isGridView {
                            LazyVGrid(columns: adaptiveColumns, spacing: 22) {
                                ForEach(storage.bookshelf) { book in
                                    BookshelfGridItem(book: book)
                                        .onTapGesture {
                                            openBook(book)
                                        }
                                        .contextMenu {
                                            bookContextMenu(for: book)
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(storage.bookshelf) { book in
                                    BookshelfListItem(book: book)
                                        .onTapGesture {
                                            openBook(book)
                                        }
                                        .contextMenu {
                                            bookContextMenu(for: book)
                                        }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                        }
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaInset(edge: .bottom) {
                if speech.isSpeaking {
                    miniTTSPlayerBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("风读 · 书架")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSearch = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "magnifyingglass")
                            Text("搜书")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.12))
                        .foregroundColor(.indigo)
                        .clipShape(Capsule())
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                SearchView()
            }
            .fullScreenCover(item: $selectedBook) { book in
                ReaderView(book: book)
            }
        }
    }
    
    // MARK: - Detached Mini TTS Player Bar
    private var speechBadgeText: String {
        switch speech.expressiveStyle {
        case .multiRoleDrama: return "剧场分角"
        case .storyteller: return "情感说书"
        case .standard: return speech.selectedVoice.shortName
        }
    }

    private var miniTTSPlayerBar: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                Image(systemName: speech.isPaused ? "headphones" : "waveform")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(speech.currentBookTitle)
                        .font(.system(size: 13, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(speechBadgeText)
                        .font(.system(size: 9.5, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color.indigo.opacity(0.15))
                        .foregroundColor(.indigo)
                        .clipShape(Capsule())
                }
                Text(speech.currentChapterTitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                if let ctx = speech.context {
                    openBook(ctx.book)
                } else if let recent = storage.mostRecentBook {
                    openBook(recent)
                }
            }
            
            Button {
                speech.resumeOrPause()
            } label: {
                Image(systemName: speech.isPaused ? "play.circle.fill" : "pause.circle.fill")
                    .font(.system(size: 29))
                    .foregroundStyle(
                        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            
            Button {
                speech.skipNext()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.85))
                    .frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            
            Button {
                speech.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.indigo.opacity(0.28), Color.purple.opacity(0.16), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.14), radius: 10, x: 0, y: 4)
    }
    
    // MARK: - Hero Continue Reading Banner
    private func continueReadingCard(book: Book) -> some View {
        let savedPos = storage.getSavedReadingPosition(for: book)
        let chapIdx = max(book.currentChapterIndex, savedPos.chapterIndex)
        let paraNum = (savedPos.chapterIndex == chapIdx ? savedPos.paragraphIndex : (book.currentParagraphIndex ?? 0)) + 1
        let progressFraction: Double = book.totalChapters > 0
            ? min(1.0, max(0.02, Double(chapIdx + 1) / Double(book.totalChapters)))
            : 0.08
        let progressPercent: Int = book.totalChapters > 0
            ? min(100, max(1, Int((Double(chapIdx + 1) / Double(book.totalChapters)) * 100)))
            : 0

        return Button {
            openBook(book)
        } label: {
            HStack(spacing: 16) {
                BookCoverView(
                    title: book.title,
                    author: book.author,
                    coverUrl: book.coverUrl,
                    width: 78,
                    height: 108,
                    cornerRadius: 9,
                    badgeText: progressPercent > 0 ? "\(progressPercent)%" : nil
                )
                
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9, weight: .bold))
                            Text("正在品读")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2.5)
                        .background(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.20), Color.pink.opacity(0.14)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.orange)
                        .clipShape(Capsule())
                        
                        Text(book.sourceName)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.08))
                            .foregroundColor(.indigo)
                            .clipShape(Capsule())
                            .lineLimit(1)
                    }
                    
                    Text(book.title)
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 5) {
                        Image(systemName: "bookmark.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.indigo.opacity(0.75))
                        Text(book.currentChapterTitle ?? "点击开始阅读第一章")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    // Visual Reading Progress Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.indigo, Color.purple, Color.orange.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(12, geo.size.width * progressFraction), height: 5)
                        }
                    }
                    .frame(height: 5)
                    .padding(.vertical, 1)
                    
                    HStack(alignment: .center) {
                        if book.totalChapters > 0 {
                            Text("第 \(chapIdx + 1)/\(book.totalChapters) 章 · 第 \(paraNum) 段")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("本章第 \(paraNum) 段 · 进度已同步")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        HStack(spacing: 4) {
                            Text("继续阅读")
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5.5)
                        .background(
                            LinearGradient(
                                colors: [Color.indigo, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .shadow(color: Color.indigo.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                }
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.indigo.opacity(0.22),
                                        Color.orange.opacity(0.15),
                                        Color.primary.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.07), radius: 12, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    private var emptyShelfView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 90)
            
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo.opacity(0.15), Color.orange.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)
                
                Image(systemName: "book.pages.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.indigo, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("一卷书香，清风自来")
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundColor(.primary)
            
            Text("随应用提供 \(storage.bundledSourceCount) 个内置书源\n可按书名或作者搜索，站点可用性以联网结果为准")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 36)
            
            Button {
                showingSearch = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text("探索全网小说")
                }
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 28)
                .padding(.vertical, 13)
                .background(
                    LinearGradient(
                        colors: [Color.indigo, Color.purple.opacity(0.9)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .clipShape(Capsule())
                .shadow(color: Color.indigo.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func bookContextMenu(for book: Book) -> some View {
        Button {
            openBook(book)
        } label: {
            Label("立即阅读", systemImage: "book.fill")
        }
        Button(role: .destructive) {
            storage.removeBookFromShelf(book)
        } label: {
            Label("移出书架", systemImage: "trash")
        }
    }
}

struct BookshelfGridItem: View {
    let book: Book
    
    private var badgeLabel: String? {
        if book.totalChapters > 0 {
            let pct = min(100, max(1, Int((Double(book.currentChapterIndex + 1) / Double(book.totalChapters)) * 100)))
            return "\(pct)%"
        }
        return book.currentChapterIndex > 0 ? "第\(book.currentChapterIndex + 1)章" : nil
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            BookCoverView(
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                cornerRadius: 9,
                badgeText: badgeLabel
            )
            
            Text(book.title)
                .font(.system(size: 13.5, weight: .bold, design: .serif))
                .lineLimit(1)
                .foregroundColor(.primary)
            
            Text(book.currentChapterTitle ?? book.author)
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(.secondary)
        }
    }
}

struct BookshelfListItem: View {
    let book: Book
    
    private var progressFraction: Double {
        guard book.totalChapters > 0 else { return 0 }
        return min(1.0, max(0.03, Double(book.currentChapterIndex + 1) / Double(book.totalChapters)))
    }
    
    var body: some View {
        HStack(spacing: 14) {
            BookCoverView(
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                width: 58,
                height: 80,
                cornerRadius: 7
            )
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(book.title)
                        .font(.system(size: 15.5, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(book.sourceName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.10))
                        .foregroundColor(.indigo)
                        .clipShape(Capsule())
                        .lineLimit(1)
                }
                
                Text(book.author.isEmpty ? "佚名" : book.author)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 10))
                        .foregroundColor(.indigo.opacity(0.8))
                    Text(book.currentChapterTitle ?? "尚未开始阅读")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.indigo)
                        .lineLimit(1)
                }
                
                if book.totalChapters > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.07))
                                .frame(height: 3.5)
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.indigo, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(8, geo.size.width * progressFraction), height: 3.5)
                        }
                    }
                    .frame(height: 3.5)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary.opacity(0.45))
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 2)
        )
    }
}
