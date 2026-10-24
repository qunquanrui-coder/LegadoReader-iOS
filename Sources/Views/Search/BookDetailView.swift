import SwiftUI

public struct BookDetailView: View {
    @ObservedObject var storage = StorageManager.shared
    @State var book: Book
    @State private var chapters: [Chapter] = []
    @State private var isLoadingChapters = true
    @State private var errorMessage: String?
    @State private var isReading = false
    
    public init(book: Book) {
        _book = State(initialValue: book)
    }
    
    private var isAddedToShelf: Bool {
        storage.bookshelf.contains(where: { $0.id == book.id })
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top, spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 90, height: 120)
                        
                        if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                            AsyncImage(url: url) { img in
                                img.resizable().aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Text(book.title.prefix(2))
                                    .font(.title)
                                    .foregroundColor(.blue)
                            }
                            .frame(width: 90, height: 120)
                            .cornerRadius(8)
                            .clipped()
                        } else {
                            Text(book.title.prefix(2))
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.title)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text("作者: \(book.author)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("书源: \(book.sourceName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if let latest = book.latestChapter {
                            Text("最新: \(latest)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button {
                        if isAddedToShelf {
                            storage.removeBookFromShelf(book)
                        } else {
                            storage.addBookToShelf(book)
                        }
                    } label: {
                        HStack {
                            Image(systemName: isAddedToShelf ? "checkmark" : "plus")
                            Text(isAddedToShelf ? "已在书架" : "加入书架")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(isAddedToShelf ? Color.secondary.opacity(0.2) : Color.blue.opacity(0.15))
                        .foregroundColor(isAddedToShelf ? .secondary : .blue)
                        .cornerRadius(10)
                    }
                    
                    Button {
                        storage.addBookToShelf(book)
                        isReading = true
                    } label: {
                        HStack {
                            Image(systemName: "book.fill")
                            Text("立即阅读")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
                
                // Intro
                if let intro = book.intro, !intro.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("简介")
                            .font(.headline)
                        Text(intro)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                    }
                    .padding(.vertical, 4)
                }
                
                // Chapters
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("目录")
                            .font(.headline)
                        Spacer()
                        if !chapters.isEmpty {
                            Text("共 \(chapters.count) 章")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if isLoadingChapters {
                        HStack {
                            Spacer()
                            ProgressView("正在抓取目录...")
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(chapters.prefix(20)) { ch in
                            HStack {
                                Text(ch.title)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            Divider()
                        }
                        if chapters.count > 20 {
                            Text("点击“立即阅读”查看全部 \(chapters.count) 个章节...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadChapters()
        }
        .fullScreenCover(isPresented: $isReading) {
            ReaderView(book: book)
        }
    }
    
    private func loadChapters() {
        guard let source = storage.bookSources.first(where: { $0.bookSourceUrl == book.sourceUrl }) else {
            errorMessage = "未找到对应书源"
            isLoadingChapters = false
            return
        }
        
        Task {
            do {
                let (html, finalUrl) = try await NetworkManager.shared.fetchString(from: book.bookUrl)
                let parsedChapters = try LegadoParser.shared.parseToc(html: html, baseUrl: finalUrl, source: source)
                await MainActor.run {
                    self.chapters = parsedChapters
                    self.book.totalChapters = parsedChapters.count
                    self.isLoadingChapters = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "目录解析失败: \(error.localizedDescription)"
                    self.isLoadingChapters = false
                }
            }
        }
    }
}
