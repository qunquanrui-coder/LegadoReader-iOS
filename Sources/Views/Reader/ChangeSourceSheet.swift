import SwiftUI

public struct ChangeSourceSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    
    let currentBook: Book
    let onSelectNewSource: (Book) -> Void
    
    @State private var alternativeBooks: [Book] = []
    @State private var isSearching = true
    @State private var statusText = "正在搜索可用书源..."
    
    public init(currentBook: Book, onSelectNewSource: @escaping (Book) -> Void) {
        self.currentBook = currentBook
        self.onSelectNewSource = onSelectNewSource
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text(statusText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground))
                }
                
                if alternativeBooks.isEmpty && !isSearching {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "arrow.triangle.2.circlepath.circle")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text("未在其他启用书源中找到《\(currentBook.title)》")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("重新搜索") {
                            searchAlternatives()
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else {
                    List(alternativeBooks) { item in
                        Button {
                            let updated = storage.replaceBookSource(for: currentBook, with: item)
                            onSelectNewSource(updated)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 6) {
                                        Text(item.sourceName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(.primary)
                                        
                                        if item.sourceUrl == currentBook.sourceUrl {
                                            Text("当前书源")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.indigo.opacity(0.15))
                                                .foregroundColor(.indigo)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    
                                    Text("作者：\(item.author)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if let latest = item.latestChapter, !latest.isEmpty {
                                        Text("最新：\(latest)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: item.sourceUrl == currentBook.sourceUrl ? "checkmark.circle.fill" : "chevron.right")
                                    .foregroundColor(item.sourceUrl == currentBook.sourceUrl ? .indigo : .secondary.opacity(0.5))
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("切换书源 · \(currentBook.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                searchAlternatives()
            }
        }
    }
    
    private func searchAlternatives() {
        isSearching = true
        alternativeBooks.removeAll()
        let keyword = currentBook.title
        let sources = Array(storage.bookSources.filter { ($0.enabled ?? true) && ($0.searchUrl != nil) }.prefix(35))
        statusText = "正在比对 \(sources.count) 个书源..."
        
        Task {
            var found: [Book] = []
            await withTaskGroup(of: [Book]?.self) { group in
                for source in sources {
                    group.addTask {
                        do {
                            let (html, finalUrl) = try await NetworkManager.shared.executeSearch(source: source, keyword: keyword)
                            let list = try LegadoParser.shared.parseSearch(html: html, baseUrl: finalUrl, source: source)
                            return list.filter { $0.title.contains(keyword) || keyword.contains($0.title) }
                        } catch {
                            return nil
                        }
                    }
                }
                
                var done = 0
                for await res in group {
                    done += 1
                    if let res = res, let firstMatch = res.first {
                        found.append(firstMatch)
                        let snap = found
                        let d = done
                        await MainActor.run {
                            self.alternativeBooks = snap
                            self.statusText = "已检测 \(d)/\(sources.count) 个书源，可用 \(snap.count) 个"
                        }
                    }
                }
            }
            
            await MainActor.run {
                self.isSearching = false
            }
        }
    }
}
