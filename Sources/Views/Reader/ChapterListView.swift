import SwiftUI

public struct ChapterListView: View {
    @Environment(\.dismiss) var dismiss
    let bookId: String?
    let sourceURL: String?
    let chapters: [Chapter]
    let currentIndex: Int
    let onSelectChapter: (Int) -> Void
    
    @State private var searchKeyword = ""
    @State private var isReversed = false
    @State private var cachedIndices: Set<Int> = []
    
    public init(
        bookId: String? = nil,
        sourceURL: String? = nil,
        chapters: [Chapter],
        currentIndex: Int,
        onSelectChapter: @escaping (Int) -> Void
    ) {
        self.bookId = bookId
        self.sourceURL = sourceURL
        self.chapters = chapters
        self.currentIndex = currentIndex
        self.onSelectChapter = onSelectChapter
    }
    
    private var displayedChapters: [Chapter] {
        let base: [Chapter]
        if searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty {
            base = chapters
        } else {
            base = chapters.filter { $0.title.localizedCaseInsensitiveContains(searchKeyword) }
        }
        return isReversed ? base.reversed() : base
    }

    private var cacheIdentity: String {
        ([bookId ?? "", sourceURL ?? ""] + chapters.map { "\($0.index):\($0.url)" }).joined(separator: "\n")
    }
    
    public var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                VStack(spacing: 0) {
                    // Search & Quick Action Bar
                    HStack(spacing: 10) {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("快速检索章节...", text: $searchKeyword)
                                .textFieldStyle(.plain)
                                .submitLabel(.search)
                            if !searchKeyword.isEmpty {
                                Button {
                                    searchKeyword = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(9)
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                        
                        Button {
                            scrollToCurrentChapter(proxy: proxy, animated: true)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "location.fill")
                                Text("当前")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Color.indigo.opacity(0.14))
                            .foregroundColor(.indigo)
                            .cornerRadius(10)
                        }
                        
                        Button {
                            isReversed.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(isReversed ? "倒序" : "正序")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Color(.secondarySystemBackground))
                            .foregroundColor(.primary)
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    
                    Divider()
                    
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(displayedChapters, id: \.index) { ch in
                                let isCurrent = (ch.index == currentIndex)
                                Button {
                                    onSelectChapter(ch.index)
                                    dismiss()
                                } label: {
                                    HStack(spacing: 10) {
                                        if isCurrent {
                                            Image(systemName: "location.fill")
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.indigo)
                                        }
                                        
                                        Text(ch.title)
                                            .font(.system(size: 15, weight: isCurrent ? .bold : .regular))
                                            .foregroundColor(isCurrent ? .indigo : .primary)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        if cachedIndices.contains(ch.index) {
                                            Text("已缓存")
                                                .font(.system(size: 10, weight: .medium))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.14))
                                                .foregroundColor(.green)
                                                .cornerRadius(4)
                                        }
                                        
                                        if isCurrent {
                                            Text("当前阅读")
                                                .font(.system(size: 11, weight: .bold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 3)
                                                .background(Color.indigo.opacity(0.16))
                                                .foregroundColor(.indigo)
                                                .cornerRadius(6)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 13)
                                    .contentShape(Rectangle())
                                    .background(isCurrent ? Color.indigo.opacity(0.08) : Color.clear)
                                }
                                .buttonStyle(.plain)
                                .id(ch.index)
                                
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .task(id: cacheIdentity) {
                        cachedIndices = []
                        guard let bid = bookId else { return }
                        let cacheDir = StorageManager.shared.cacheDirectoryURL
                        let source = sourceURL
                        let currentChapters = chapters
                        let indices = await Task.detached(priority: .userInitiated) {
                            ChapterContentCache(directory: cacheDir).cachedChapterIndices(bookId: bid, sourceURL: source,
                                                                                         chapters: currentChapters)
                        }.value
                        guard !Task.isCancelled else { return }
                        cachedIndices = indices
                    }
                    .onAppear {
                        // Multi-stage scroll guarantees exact centering even for 1,000+ chapters during sheet animation
                        scrollToCurrentChapter(proxy: proxy, animated: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToCurrentChapter(proxy: proxy, animated: false)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                            scrollToCurrentChapter(proxy: proxy, animated: false)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            scrollToCurrentChapter(proxy: proxy, animated: false)
                        }
                    }
                }
                .navigationTitle("目录 (\(chapters.count)章)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("完成") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
    }
    
    private func scrollToCurrentChapter(proxy: ScrollViewProxy, animated: Bool) {
        guard currentIndex >= 0 && currentIndex < chapters.count else { return }
        if animated {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        } else {
            withAnimation(.none) {
                proxy.scrollTo(currentIndex, anchor: .center)
            }
        }
    }
}
