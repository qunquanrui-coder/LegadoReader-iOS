import SwiftUI

public struct BookshelfView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var selectedBook: Book?
    @State private var showingSearch = false
    @State private var isGridView = true
    
    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                if storage.bookshelf.isEmpty {
                    emptyShelfView
                } else {
                    VStack(alignment: .leading, spacing: 24) {
                        // Top Hero "Continue Reading" Card
                        if let recentBook = storage.bookshelf.first {
                            continueReadingCard(book: recentBook)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                        
                        // Section Header
                        HStack {
                            Text("全部藏书")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                            Text("\(storage.bookshelf.count)")
                                .font(.system(size: 12, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.indigo.opacity(0.12))
                                .foregroundColor(.indigo)
                                .clipShape(Capsule())
                            
                            Spacer()
                            
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    isGridView.toggle()
                                }
                            } label: {
                                Image(systemName: isGridView ? "list.bullet" : "square.grid.3x2")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Bookshelf Grid or List
                        if isGridView {
                            LazyVGrid(columns: columns, spacing: 22) {
                                ForEach(storage.bookshelf) { book in
                                    BookshelfGridItem(book: book)
                                        .onTapGesture {
                                            selectedBook = book
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
                                            selectedBook = book
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
    
    // MARK: - Hero Continue Reading Banner
    private func continueReadingCard(book: Book) -> some View {
        Button {
            selectedBook = book
        } label: {
            HStack(spacing: 16) {
                BookCoverView(
                    title: book.title,
                    author: book.author,
                    coverUrl: book.coverUrl,
                    width: 72,
                    height: 98,
                    cornerRadius: 8
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("最近阅读")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18))
                            .foregroundColor(.orange)
                            .clipShape(Capsule())
                        
                        Text(book.sourceName)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text(book.title)
                        .font(.system(size: 17, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(book.currentChapterTitle ?? "点击开始阅读第一章")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer(minLength: 4)
                    
                    HStack {
                        if book.totalChapters > 0 {
                            let pct = min(100, Int((Double(book.currentChapterIndex + 1) / Double(book.totalChapters)) * 100))
                            let paraNum = (book.currentParagraphIndex ?? 0) + 1
                            Text("已读 \(pct)% · 第\(book.currentChapterIndex + 1)章 · 第\(paraNum)段")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.indigo)
                        } else {
                            Text("开始阅读")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.indigo)
                        }
                        Spacer()
                        HStack(spacing: 3) {
                            Text("继续阅读")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [Color.indigo, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
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
            
            Text("已内置 \(storage.bookSources.count) 个经过实测的高速纯净书源\n搜索任意书名或作者，即刻开启无广告阅读")
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
            selectedBook = book
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            BookCoverView(
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                cornerRadius: 8
            )
            
            Text(book.title)
                .font(.system(size: 13, weight: .semibold, design: .serif))
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
    
    var body: some View {
        HStack(spacing: 14) {
            BookCoverView(
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                width: 56,
                height: 76,
                cornerRadius: 6
            )
            
            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.system(size: 15, weight: .bold, design: .serif))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(book.author) · \(book.sourceName)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(book.currentChapterTitle ?? "尚未开始阅读")
                    .font(.system(size: 12))
                    .foregroundColor(.indigo)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
