import SwiftUI
import UIKit

@MainActor
public struct SearchView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    @ObservedObject var recommendationEngine = BookRecommendationEngine.shared
    
    @State private var searchText = ""
    @StateObject private var searchSession = SourceSearchSession()
    @State private var submittedKeyword = ""
    private var searchResults: [Book] { sortResultsByRelevance(searchSession.results, keyword: submittedKeyword) }
    private var isSearching: Bool { searchSession.isSearching }
    private var searchProgress: String { searchSession.status }
    
    // Real-time search suggestions (Auto-complete)
    @State private var suggestions: [SearchSuggestion] = []
    @State private var showSuggestions = false
    @State private var suggestionTask: Task<Void, Never>? = nil
    
    // Popular novel recommendation category
    @State private var selectedCategory: NovelCategory = .trending
    
    // Keyboard focus state
    @FocusState private var isSearchFieldFocused: Bool
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Top Search Bar with Keyboard Control
                searchBarHeader
                
                // MARK: - Real-Time Search Auto-complete Suggestions Overlay
                if showSuggestions && !suggestions.isEmpty && !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    suggestionListView
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    // Progress Pill when searching or showing results
                    if isSearching || !searchProgress.isEmpty {
                        searchStatusPill
                    }
                    
                    // Main Content: Explore Recommendations OR Search Results
                    if searchResults.isEmpty && !isSearching {
                        exploreRecommendationsScrollView
                    } else {
                        searchResultsScrollView
                    }
                }
            }
            .background(AppAmbientBackdrop())
            .navigationTitle("全网搜书")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await recommendationEngine.refreshLiveRankingsIfNeeded()
            }
            .onDisappear { searchSession.cancel(); suggestionTask?.cancel() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        hideKeyboard()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "keyboard.chevron.compact.down")
                            Text("收起键盘")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.indigo)
                    }
                }
            }
        }
    }
    
    // MARK: - Search Bar Header
    private var searchBarHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.indigo)
                    .font(.system(size: 15, weight: .semibold))
                
                TextField("输入书名、作者或首字联想...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onChange(of: searchText) { newValue in
                        if newValue != submittedKeyword { searchSession.clear() }
                        handleSearchTextChanged(newValue)
                    }
                    .onSubmit {
                        hideKeyboard()
                        performSearch(keyword: searchText)
                    }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        suggestions.removeAll()
                        showSuggestions = false
                        searchSession.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppPalette.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSearchFieldFocused ? AppPalette.inkAccent.opacity(0.6) : AppPalette.cardBorder, lineWidth: 1)
            )
            
            if isSearchFieldFocused && searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    hideKeyboard()
                } label: {
                    Text("取消")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                }
            } else {
                Button {
                    hideKeyboard()
                    performSearch(keyword: searchText)
                } label: {
                    Text("搜索")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(AppPalette.primaryGradient)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
    // MARK: - Live Auto-complete Suggestion List
    private var suggestionListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Direct search row for current input
                Button {
                    hideKeyboard()
                    performSearch(keyword: searchText)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.indigo)
                        Text("直接全网搜索「\(searchText.trimmingCharacters(in: .whitespaces))」")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.indigo)
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(Color(.secondarySystemGroupedBackground))
                }
                .buttonStyle(.plain)
                
                Divider().padding(.leading, 48)
                
                ForEach(suggestions) { item in
                    Button {
                        searchText = item.title
                        hideKeyboard()
                        performSearch(keyword: item.title)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.tag != nil ? "flame.fill" : "book.closed.fill")
                                .font(.system(size: 14))
                                .foregroundColor(item.tag != nil ? .orange : .indigo.opacity(0.75))
                                .frame(width: 22)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.system(size: 15, weight: .medium, design: .serif))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                if let author = item.author, !author.isEmpty {
                                    Text("作者：\(author)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            
                            Spacer()
                            
                            if let tag = item.tag, !tag.isEmpty {
                                Text(tag)
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.orange.opacity(0.14))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                            }
                            
                            Image(systemName: "arrow.up.backward")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemGroupedBackground))
                    }
                    .buttonStyle(.plain)
                    
                    Divider().padding(.leading, 48)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
        }
        .scrollDismissesKeyboard(.immediately)
    }
    
    // MARK: - Search Status Card
    private var searchStatusPill: some View {
        let totalCount = max(1, storage.bookSources.filter { ($0.enabled ?? true) && SourceSearchPolicy.unsupportedReason($0) == nil }.count)
        let fraction = min(1.0, max(0.05, Double(searchSession.finished) / Double(totalCount)))
        
        return VStack(spacing: 7) {
            HStack(spacing: 8) {
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.78)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 13))
                }
                Text(searchProgress)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if !searchResults.isEmpty {
                    Text("\(searchResults.count) 条结果")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.indigo.opacity(0.12))
                        .foregroundColor(.indigo)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                if isSearching {
                    Button("停止") { searchSession.cancel() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                } else if searchSession.hasMore {
                    Button("继续搜索") { searchSession.continueSearch() }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.indigo)
                }
                if !searchResults.isEmpty {
                    Button {
                        hideKeyboard()
                        searchSession.clear()
                        searchText = ""
                    } label: {
                        Text("返回榜单")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.indigo.opacity(0.10))
                            .foregroundColor(.indigo)
                            .clipShape(Capsule())
                    }
                }
            }
            
            if isSearching {
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
                            .frame(width: max(12, geo.size.width * fraction), height: 3.5)
                    }
                }
                .frame(height: 3.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.indigo.opacity(0.14), lineWidth: 0.8)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    
    // MARK: - Explore & Popular Recommendations ScrollView
    private var exploreRecommendationsScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // 1. Search History
                if !storage.searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            HStack(spacing: 5) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.indigo)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("搜索历史")
                                    .font(.system(size: 15, weight: .bold, design: .serif))
                            }
                            Spacer()
                            Button("清空") {
                                storage.clearSearchHistory()
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        FlowLayoutChips(items: storage.searchHistory) { kw in
                            searchText = kw
                            hideKeyboard()
                            performSearch(keyword: kw)
                        }
                    }
                }
                
                // 2. Quick Hot Search Chips (Dynamic Live Hot Titles)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .foregroundColor(AppPalette.gildedAmber)
                        Text("大家都在搜")
                            .font(.system(size: 15.5, weight: .bold, design: .serif))
                        Spacer()
                        Text("热榜实时词")
                            .font(.system(size: 10.5, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(AppPalette.gildedAmber.opacity(0.14))
                            .foregroundColor(AppPalette.gildedAmber)
                            .clipShape(Capsule())
                    }
                    
                    FlowLayoutChips(items: recommendationEngine.dynamicHotKeywords, highlightTopThree: true) { kw in
                        searchText = kw
                        hideKeyboard()
                        performSearch(keyword: kw)
                    }
                }
                
                // 3. Latest Live High-Rated Novel Leaderboards
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 7) {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(AppPalette.warmGoldGradient)
                            Text("全网最新高分热门榜")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                            Spacer()
                            
                            Button {
                                Task {
                                    await recommendationEngine.refreshLiveRankingsIfNeeded(force: true)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    if recommendationEngine.isRefreshingRankings {
                                        ProgressView()
                                            .scaleEffect(0.65)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 10.5, weight: .bold))
                                    }
                                    Text(recommendationEngine.isRefreshingRankings ? "同步中" : "刷新榜单")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(AppPalette.inkAccent.opacity(0.12))
                                .foregroundColor(AppPalette.inkAccent)
                                .clipShape(Capsule())
                            }
                            .disabled(recommendationEngine.isRefreshingRankings)
                        }
                        
                        HStack(spacing: 6) {
                            Circle()
                                .fill(recommendationEngine.lastRefreshedAt != nil ? AppPalette.celadon : AppPalette.gildedAmber)
                                .frame(width: 6, height: 6)
                            Text(recommendationEngine.liveStatusLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text("·")
                                .foregroundColor(.secondary)
                            Text(selectedCategory.subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    // Category Selector Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 9) {
                            ForEach(NovelCategory.allCases) { category in
                                let isSelected = (selectedCategory == category)
                                Button {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        selectedCategory = category
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: category.iconName)
                                            .font(.system(size: 11.5, weight: .semibold))
                                        Text(category.rawValue)
                                            .font(.system(size: 12.5, weight: .semibold))
                                    }
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 8)
                                    .background(
                                        Group {
                                            if isSelected {
                                                AppPalette.primaryGradient
                                            } else {
                                                LinearGradient(
                                                    colors: [AppPalette.cardBackground, AppPalette.cardBackground],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            }
                                        }
                                    )
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(isSelected ? Color.clear : AppPalette.cardBorder, lineWidth: 0.8)
                                    )
                                    .shadow(color: isSelected ? AppPalette.inkAccent.opacity(0.25) : Color.clear, radius: 5, x: 0, y: 2)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    // Top 3 Editorial Spotlight Podium + Ranked Novel List for Selected Category
                    let rankedBooks = recommendationEngine.books(for: selectedCategory)
                    if rankedBooks.count >= 3 {
                        TopThreeSpotlightStrip(books: Array(rankedBooks.prefix(3))) { item in
                            searchText = item.title
                            hideKeyboard()
                            performSearch(keyword: item.title)
                        }
                    }
                    
                    let listStartIndex = rankedBooks.count >= 3 ? 3 : 0
                    LazyVStack(spacing: 11) {
                        ForEach(Array(rankedBooks.dropFirst(listStartIndex).enumerated()), id: \.element.id) { offset, item in
                            RecommendedNovelRow(rank: listStartIndex + offset + 1, novel: item) {
                                searchText = item.title
                                hideKeyboard()
                                performSearch(keyword: item.title)
                            }
                        }
                    }
                }
                
                // 4. Active Sources Status Footer
                HStack(spacing: 12) {
                    Image(systemName: "bolt.shield.fill")
                        .font(.title2)
                        .foregroundStyle(AppPalette.primaryGradient)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("多书源并发引擎 + 智能相关度排序已开启")
                            .font(.system(size: 13, weight: .semibold))
                        Text("已启用 \(storage.bookSources.filter { $0.enabled ?? true }.count) 个书源，精确匹配的同名原著将优先显示")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppPalette.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AppPalette.cardBorder, lineWidth: 0.8)
                        )
                )
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.immediately)
        .simultaneousGesture(
            TapGesture().onEnded {
                if isSearchFieldFocused {
                    hideKeyboard()
                }
            }
        )
    }
    
    // MARK: - Search Results ScrollView
    private var searchResultsScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(searchResults, id: \.searchResultID) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        SearchResultCard(book: book, searchKeyword: searchText)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            hideKeyboard()
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollDismissesKeyboard(.immediately)
    }
    
    // MARK: - Helper: Dismiss Keyboard Reliably
    private func hideKeyboard() {
        isSearchFieldFocused = false
        showSuggestions = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    // MARK: - Live Autocomplete Handler
    private func handleSearchTextChanged(_ newValue: String) {
        suggestionTask?.cancel()
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            suggestions.removeAll()
            showSuggestions = false
            return
        }
        // Only show live autocomplete while typing before search results take over or when field is focused
        if isSearchFieldFocused {
            showSuggestions = true
        }
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000) // 120ms debounce
            guard !Task.isCancelled else { return }
            let fetched = await BookRecommendationEngine.shared.fetchSuggestions(for: trimmed)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.suggestions = fetched
            }
        }
    }
    
    // MARK: - Relevance Sorting Engine (Exact Match Always Top #1)
    private func sortResultsByRelevance(_ books: [Book], keyword rawKeyword: String) -> [Book] {
        let kw = normalizeTitle(rawKeyword)
        guard !kw.isEmpty else { return books }
        
        // Known canonical author for the searched novel (from live rankings or curated database)
        let canonicalAuthor = recommendationEngine.canonicalAuthor(for: kw)
        
        return books.sorted { a, b in
            let scoreA = relevanceScore(for: a, keyword: kw, canonicalAuthor: canonicalAuthor)
            let scoreB = relevanceScore(for: b, keyword: kw, canonicalAuthor: canonicalAuthor)
            if scoreA != scoreB {
                return scoreA > scoreB
            }
            // Tie-breaker: shorter title first, then title alphabetical
            if a.title.count != b.title.count {
                return a.title.count < b.title.count
            }
            return a.sourceName < b.sourceName
        }
    }
    
    private func relevanceScore(for book: Book, keyword: String, canonicalAuthor: String?) -> Int {
        let cleanTitle = normalizeTitle(book.title)
        let cleanAuthor = book.author.trimmingCharacters(in: .whitespacesAndNewlines)
        var score = 0
        
        // 1. Title Matching Tiers
        if cleanTitle == keyword {
            // Exact title match (e.g. "剑来" == "剑来") -> Top priority!
            score += 10000
        } else if cleanTitle.hasPrefix(keyword) {
            // Prefix match (e.g. "剑来（精校版）" or "剑来：文圣薪火")
            // Penalize extra length so shorter/closer titles rank higher
            let extraChars = max(0, cleanTitle.count - keyword.count)
            score += max(4000, 6000 - extraChars * 80)
        } else if cleanTitle.contains(keyword) {
            // Contained match (e.g. "从剑来开始")
            let extraChars = max(0, cleanTitle.count - keyword.count)
            score += max(2000, 3500 - extraChars * 60)
        } else {
            // Fuzzy character overlap (e.g. "剑自雪中来" contains '剑' and '来' separately)
            var matchedChars = 0
            for ch in keyword where cleanTitle.contains(ch) {
                matchedChars += 1
            }
            score += matchedChars * 150
        }
        
        // 2. Author Matching Bonus
        if let canon = canonicalAuthor, !canon.isEmpty, cleanAuthor.contains(canon) {
            // Matches the famous original author (e.g. "烽火戏诸侯" for "剑来")
            score += 2500
        } else if cleanAuthor == keyword {
            // User searched for an author's name directly
            score += 5000
        } else if cleanAuthor.contains(keyword) {
            score += 1800
        }
        
        // 3. Metadata Completeness Bonus
        if !cleanAuthor.isEmpty && cleanAuthor != "佚名" {
            score += 120
        }
        if let last = book.latestChapter, !last.isEmpty {
            score += 80
        }
        if let cover = book.coverUrl, cover.hasPrefix("http") {
            score += 50
        }
        
        return score
    }
    
    private func normalizeTitle(_ text: String) -> String {
        return text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
            .lowercased()
    }
    
    // MARK: - Perform Multi-Source Concurrent Search
    private func performSearch(keyword rawKey: String) {
        let keyword = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        hideKeyboard()
        storage.addSearchHistory(keyword)
        submittedKeyword = keyword
        searchSession.start(keyword: keyword, sources: storage.bookSources)
    }

}

// MARK: - Top 3 Editorial Spotlight Podium
struct TopThreeSpotlightStrip: View {
    let books: [RecommendedBook]
    let onSelect: (RecommendedBook) -> Void
    
    private func medalColors(for rank: Int) -> [Color] {
        switch rank {
        case 1: return [Color(red: 0.96, green: 0.36, blue: 0.24), Color(red: 0.84, green: 0.17, blue: 0.17)]
        case 2: return [Color(red: 0.94, green: 0.56, blue: 0.20), Color(red: 0.85, green: 0.39, blue: 0.11)]
        default: return [Color(red: 0.91, green: 0.70, blue: 0.18), Color(red: 0.78, green: 0.53, blue: 0.10)]
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(books.prefix(3).enumerated()), id: \.element.id) { idx, book in
                let rank = idx + 1
                Button {
                    onSelect(book)
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        ZStack(alignment: .topLeading) {
                            BookCoverView(
                                title: book.title,
                                author: book.author,
                                coverUrl: book.coverUrl,
                                cornerRadius: 9,
                                badgeText: book.rating
                            )
                            
                            HStack(spacing: 2) {
                                Image(systemName: rank == 1 ? "crown.fill" : "flame.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("NO.\(rank)")
                                    .font(.system(size: 9, weight: .heavy, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                LinearGradient(
                                    colors: medalColors(for: rank),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .shadow(color: Color.black.opacity(0.22), radius: 3, x: 0, y: 1.5)
                            .offset(x: -3, y: -3)
                        }
                        
                        Text(book.title)
                            .font(.system(size: 13, weight: .bold, design: .serif))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(book.author)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppPalette.cardBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(
                                        rank == 1 ? AppPalette.gildedAmber.opacity(0.35) : AppPalette.cardBorder,
                                        lineWidth: rank == 1 ? 1.1 : 0.8
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 3)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Recommended Novel Leaderboard Card
struct RecommendedNovelRow: View {
    let rank: Int
    let novel: RecommendedBook
    let onSelect: () -> Void
    
    private var rankBadgeColors: [Color] {
        switch rank {
        case 1: return [Color(red: 0.95, green: 0.35, blue: 0.25), Color(red: 0.85, green: 0.18, blue: 0.18)]
        case 2: return [Color(red: 0.95, green: 0.55, blue: 0.20), Color(red: 0.88, green: 0.40, blue: 0.12)]
        case 3: return [Color(red: 0.92, green: 0.70, blue: 0.18), Color(red: 0.82, green: 0.55, blue: 0.10)]
        default: return [AppPalette.inkAccent.opacity(0.82), AppPalette.plumAccent.opacity(0.82)]
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 13) {
                ZStack(alignment: .topLeading) {
                    BookCoverView(
                        title: novel.title,
                        author: novel.author,
                        coverUrl: novel.coverUrl,
                        width: 64,
                        height: 88,
                        cornerRadius: 8
                    )
                    
                    // Rank Badge
                    Text("TOP \(rank)")
                        .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                colors: rankBadgeColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .offset(x: -3, y: -3)
                }
                
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 5) {
                        Text(novel.title)
                            .font(.system(size: 15.5, weight: .bold, design: .serif))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        Text(novel.rating)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundColor(AppPalette.gildedAmber)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppPalette.gildedAmber.opacity(0.13))
                            .clipShape(Capsule())
                            .lineLimit(1)
                        
                        if novel.isLive {
                            Text("实时")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(AppPalette.celadon)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(AppPalette.celadon.opacity(0.13))
                                .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 3) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 10, weight: .bold))
                            Text("搜书")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(AppPalette.inkAccent.opacity(0.12))
                        .foregroundColor(AppPalette.inkAccent)
                        .clipShape(Capsule())
                    }
                    
                    HStack(spacing: 6) {
                        Text(novel.author)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        
                        Text("·")
                            .foregroundColor(.secondary)
                        
                        Text(novel.tagline)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppPalette.inkAccent.opacity(0.85))
                            .lineLimit(1)
                    }
                    
                    Text(novel.intro)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.88))
                        .lineLimit(2)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppPalette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(AppPalette.cardBorder, lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FlowLayoutChips: View {
    let items: [String]
    var highlightTopThree: Bool = false
    let onTap: (String) -> Void
    
    private let columns = [
        GridItem(.adaptive(minimum: 98), spacing: 9)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 9) {
            ForEach(Array(items.enumerated()), id: \.element) { idx, item in
                let isHot = highlightTopThree && idx < 3
                Button {
                    onTap(item)
                } label: {
                    HStack(spacing: 4) {
                        if isHot {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(idx == 0 ? AppPalette.vermilion : AppPalette.gildedAmber)
                        }
                        Text(item)
                            .font(.system(size: 12.5, weight: isHot ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(AppPalette.cardBackground)
                    .foregroundColor(.primary)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(isHot ? AppPalette.gildedAmber.opacity(0.32) : AppPalette.cardBorder, lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
                }
            }
        }
    }
}

struct SearchResultCard: View {
    let book: Book
    var searchKeyword: String = ""
    
    private var isExactMatch: Bool {
        let cleanBook = book.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanKey = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !cleanKey.isEmpty && cleanBook == cleanKey
    }
    
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
                HStack(alignment: .center, spacing: 6) {
                    Text(book.title)
                        .font(.system(size: 16, weight: .bold, design: .serif))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if isExactMatch {
                        Text("最佳匹配")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    
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
                .fill(AppPalette.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(isExactMatch ? AppPalette.inkAccent.opacity(0.35) : AppPalette.cardBorder, lineWidth: isExactMatch ? 1.1 : 0.8)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }
}
