import SwiftUI

public struct SearchView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    @State private var searchText = ""
    @State private var searchResults: [Book] = []
    @State private var isSearching = false
    @State private var searchProgress = ""
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack {
                // Search Input Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("输入书名或作者搜索...", text: $searchText)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            performSearch()
                        }
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    Button("搜索") {
                        performSearch()
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Status banner
                if isSearching || !searchProgress.isEmpty {
                    HStack {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(searchProgress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                
                // Result List
                if searchResults.isEmpty && !isSearching {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("支持多书源并发检索")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("当前已启用 \(storage.bookSources.filter { $0.enabled ?? true }.count) 个书源")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else {
                    List(searchResults) { book in
                        NavigationLink {
                            BookDetailView(book: book)
                        } label: {
                            SearchResultRow(book: book)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("搜索小说")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func performSearch() {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return }
        
        isSearching = true
        searchResults.removeAll()
        
        let allEnabled = storage.bookSources.filter { ($0.enabled ?? true) && ($0.searchUrl != nil) }
        // Limit to first 40 active sources per batch to prevent socket exhaustion when 3000+ sources are loaded
        let enabledSources = Array(allEnabled.prefix(40))
        searchProgress = "正在并发检索 \(enabledSources.count) 个书源..."
        
        Task {
            var allResults: [Book] = []
            
            await withTaskGroup(of: [Book]?.self) { group in
                for source in enabledSources {
                    group.addTask {
                        do {
                            let (html, finalUrl) = try await NetworkManager.shared.executeSearch(source: source, keyword: keyword)
                            let parsed = try LegadoParser.shared.parseSearch(html: html, baseUrl: finalUrl, source: source)
                            return parsed
                        } catch {
                            return nil
                        }
                    }
                }
                
                var finishedCount = 0
                for await books in group {
                    finishedCount += 1
                    if let books = books, !books.isEmpty {
                        allResults.append(contentsOf: books)
                        let snapshot = allResults
                        let currentFinished = finishedCount
                        await MainActor.run {
                            self.searchResults = snapshot
                            self.searchProgress = "已检索 \(currentFinished)/\(enabledSources.count) 个书源，找到 \(snapshot.count) 本结果"
                        }
                    }
                }
            }
            
            let finalCount = allResults.count
            await MainActor.run {
                self.isSearching = false
                self.searchProgress = "搜索完成，共找到 \(finalCount) 条结果"
            }
        }
    }
}

struct SearchResultRow: View {
    let book: Book
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 60, height: 80)
                
                if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { img in
                        img.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Text(book.title.prefix(2))
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    .frame(width: 60, height: 80)
                    .cornerRadius(6)
                    .clipped()
                } else {
                    Text(book.title.prefix(2))
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 16, weight: .bold))
                
                HStack {
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(book.sourceName)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                }
                
                if let lastChapter = book.latestChapter {
                    Text("最新: \(lastChapter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                if let intro = book.intro {
                    Text(intro)
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
