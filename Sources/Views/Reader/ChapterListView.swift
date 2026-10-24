import SwiftUI

public struct ChapterListView: View {
    @Environment(\.dismiss) var dismiss
    let chapters: [Chapter]
    let currentIndex: Int
    let onSelectChapter: (Int) -> Void
    
    @State private var searchKeyword = ""
    
    private var filteredChapters: [Chapter] {
        if searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty {
            return chapters
        }
        return chapters.filter { $0.title.localizedCaseInsensitiveContains(searchKeyword) }
    }
    
    public var body: some View {
        NavigationStack {
            VStack {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("快速检索章节...", text: $searchKeyword)
                        .textFieldStyle(.plain)
                    if !searchKeyword.isEmpty {
                        Button {
                            searchKeyword = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 8)
                
                List {
                    ForEach(filteredChapters) { ch in
                        Button {
                            onSelectChapter(ch.index)
                            dismiss()
                        } label: {
                            HStack {
                                Text(ch.title)
                                    .font(.system(size: 15))
                                    .foregroundColor(ch.index == currentIndex ? .blue : .primary)
                                    .fontWeight(ch.index == currentIndex ? .bold : .regular)
                                    .lineLimit(1)
                                Spacer()
                                if ch.index == currentIndex {
                                    Text("当前")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("目录 (\(chapters.count)章)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}
