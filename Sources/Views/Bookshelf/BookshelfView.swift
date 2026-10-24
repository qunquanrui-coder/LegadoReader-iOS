import SwiftUI

public struct BookshelfView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var selectedBook: Book?
    @State private var showingSearch = false
    
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                if storage.bookshelf.isEmpty {
                    VStack(spacing: 20) {
                        Spacer(minLength: 120)
                        Image(systemName: "books.vertical")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        Text("书架空空如也")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("去搜索喜欢的网络小说，开启纯净阅读吧")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button {
                            showingSearch = true
                        } label: {
                            Label("前往搜索", systemImage: "magnifyingglass")
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(20)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(storage.bookshelf) { book in
                            BookshelfItemView(book: book)
                                .onTapGesture {
                                    selectedBook = book
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        storage.removeBookFromShelf(book)
                                    } label: {
                                        Label("移出书架", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("我的书架")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
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
}

struct BookshelfItemView: View {
    let book: Book
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [Color.blue.opacity(0.6), Color.purple.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .aspectRatio(0.72, contentMode: .fit)
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                
                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                             .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        fallbackCover
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .cornerRadius(8)
                    .clipped()
                } else {
                    fallbackCover
                }
            }
            
            Text(book.title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .foregroundColor(.primary)
            
            Text(book.currentChapterTitle ?? "尚未阅读")
                .font(.system(size: 11))
                .lineLimit(1)
                .foregroundColor(.secondary)
        }
    }
    
    var fallbackCover: some View {
        VStack {
            Spacer()
            Text(book.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(6)
            Spacer()
            Text(book.author)
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.85))
                .padding(.bottom, 6)
        }
    }
}
