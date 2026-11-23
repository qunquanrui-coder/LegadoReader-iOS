import SwiftUI

@MainActor
public struct ChangeSourceSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    
    let currentBook: Book
    let onSelectNewSource: (Book) -> Void
    
    @StateObject private var searchSession = SourceSearchSession()
    @State private var unverifiedCandidate: Book?
    @State private var showAuthorConfirmation = false
    private var alternativeBooks: [Book] { searchSession.results }
    private var isSearching: Bool { searchSession.isSearching }
    private var statusText: String { searchSession.status }
    
    public init(currentBook: Book, onSelectNewSource: @escaping (Book) -> Void) {
        self.currentBook = currentBook
        self.onSelectNewSource = onSelectNewSource
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !statusText.isEmpty {
                    let totalCount = max(1, storage.bookSources.filter { ($0.enabled ?? true) && SourceSearchPolicy.unsupportedReason($0) == nil }.count)
                    let fraction = min(1.0, max(0.05, Double(searchSession.finished) / Double(totalCount)))
                    VStack(spacing: 6) {
                        HStack(spacing: 8) {
                            if isSearching {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                            Text(statusText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            if isSearching {
                                Button("停止") { searchSession.cancel() }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.orange)
                            } else if searchSession.hasMore {
                                Button("继续搜索") { searchSession.continueSearch() }
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.indigo)
                            }
                        }
                        if isSearching {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.07))
                                        .frame(height: 3.5)
                                    Capsule()
                                        .fill(LinearGradient(colors: [.indigo, .purple], startPoint: .leading, endPoint: .trailing))
                                        .frame(width: max(12, geo.size.width * fraction), height: 3.5)
                                }
                            }
                            .frame(height: 3.5)
                        }
                    }
                    .padding(.horizontal, 16)
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
                    List(alternativeBooks, id: \.searchResultID) { item in
                        Button {
                            if SourceSearchPolicy.needsAuthorConfirmation(item, for: currentBook) {
                                unverifiedCandidate = item
                                showAuthorConfirmation = true
                            } else { select(item) }
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
                                    
                                    Text(item.title)
                                        .font(.subheadline)
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
            .onDisappear { searchSession.cancel() }
            .alert("作者信息不完整", isPresented: $showAuthorConfirmation) {
                Button("取消", role: .cancel) { unverifiedCandidate = nil }
                Button("确认切换") {
                    if let candidate = unverifiedCandidate { select(candidate) }
                }
            } message: {
                Text("候选书籍《\(unverifiedCandidate?.title ?? "")》，作者：\(unverifiedCandidate?.author ?? "未知")。请确认与当前书籍为同一部作品。")
            }
            .onAppear {
                searchAlternatives()
            }
        }
    }
    
    private func select(_ item: Book) {
        guard SourceSearchPolicy.isCandidate(item, for: currentBook) else { return }
        let updated = storage.replaceBookSource(for: currentBook, with: item)
        onSelectNewSource(updated)
        dismiss()
    }

    private func searchAlternatives() {
        searchSession.start(keyword: currentBook.title, sources: storage.bookSources, matching: currentBook)
    }
}
