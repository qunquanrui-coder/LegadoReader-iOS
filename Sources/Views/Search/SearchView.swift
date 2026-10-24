import SwiftUI

public struct SearchView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    @State private var searchText = ""
    @State private var searchResults: [Book] = []
    @State private var isSearching = false
    @State private var searchProgress = ""
    
    private let hotKeywords = [
        "凡人修仙传", "诡秘之主", "剑来", "遮天",
        "道诡异仙", "大奉打更人", "完美世界", "仙逆",
        "诛仙", "雪中悍刀行", "万相之王", "深空彼岸"
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Modern Search Bar
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.indigo)
                            .font(.system(size: 15, weight: .semibold))
                        
                        TextField("搜索书名、作者或主角...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .onSubmit {
                                performSearch(keyword: searchText)
                            }
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                                searchResults.removeAll()
                                searchProgress = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.indigo.opacity(0.18), lineWidth: 1)
                    )
                    
                    Button {
                        performSearch(keyword: searchText)
                    } label: {
                        Text("搜索")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                // Progress Pill
                if isSearching || !searchProgress.isEmpty {
                    HStack(spacing: 8) {
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.75)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                        Text(searchProgress)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    .padding(.bottom, 8)
                }
                
                // Discovery Tags or Search Results
                if searchResults.isEmpty && !isSearching {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            // Search History
                            if !storage.searchHistory.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("搜索历史")
                                            .font(.system(size: 15, weight: .bold, design: .serif))
                                        Spacer()
                                        Button("清空") {
                                            storage.clearSearchHistory()
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                    
                                    FlowLayoutChips(items: storage.searchHistory) { kw in
                                        searchText = kw
                                        performSearch(keyword: kw)
                                    }
                                }
                            }
                            
                            // Hot Recommendations
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 6) {
                                    Image(systemName: "flame.fill")
                                        .foregroundColor(.orange)
                                    Text("热门经典推荐 (点击即搜)")
                                        .font(.system(size: 15, weight: .bold, design: .serif))
                                }
                                
                                FlowLayoutChips(items: hotKeywords) { kw in
                                    searchText = kw
                                    performSearch(keyword: kw)
                                }
                            }
                            
                            // Active Sources Info Card
                            HStack(spacing: 12) {
                                Image(systemName: "bolt.shield.fill")
                                    .font(.title2)
                                    .foregroundColor(.indigo)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("多书源并发引擎已就绪")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("当前已启用 \(storage.bookSources.filter { $0.enabled ?? true }.count) 个高速书源，支持智能目录嗅探与自动换源")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                        .padding(16)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { book in
                                NavigationLink {
                                    BookDetailView(book: book)
                                } label: {
                                    SearchResultCard(book: book)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("全网搜书")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func performSearch(keyword rawKey: String) {
        let keyword = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        
        storage.addSearchHistory(keyword)
        isSearching = true
        searchResults.removeAll()
        
        let allEnabled = storage.bookSources.filter { ($0.enabled ?? true) && ($0.searchUrl != nil) }
        let enabledSources = Array(allEnabled.prefix(35))
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
                            self.searchProgress = "已检索 \(currentFinished)/\(enabledSources.count) 个书源 · 找到 \(snapshot.count) 本结果"
                        }
                    }
                }
            }
            
            let finalCount = allResults.count
            await MainActor.run {
                self.isSearching = false
                self.searchProgress = "搜索完成 · 共找到 \(finalCount) 条可用结果"
            }
        }
    }
}

struct FlowLayoutChips: View {
    let items: [String]
    let onTap: (String) -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 95), spacing: 10)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(Color(.secondarySystemGroupedBackground))
                        .foregroundColor(.primary)
                        .clipShape(Capsule())
                        .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                }
            }
        }
    }
}

struct SearchResultCard: View {
    let book: Book
    
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCoverView(
                title: book.title,
                author: book.author,
                coverUrl: book.coverUrl,
                width: 66,
                height: 92,
                cornerRadius: 7
            )
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center) {
                    Text(book.title)
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(book.sourceName)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.12))
                        .foregroundColor(.indigo)
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .font(.system(size: 10))
                    Text(book.author)
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.secondary)
                
                if let lastChapter = book.latestChapter, !lastChapter.isEmpty {
                    Text("最新：\(lastChapter)")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
                
                if let intro = book.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.85))
                        .lineLimit(2)
                        .lineSpacing(2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
        )
    }
}
