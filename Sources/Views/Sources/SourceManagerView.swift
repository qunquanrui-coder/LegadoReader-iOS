import SwiftUI

public struct SourceManagerView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var showingImportSheet = false
    @State private var searchSourceText = ""
    
    private var filteredSources: [BookSource] {
        if searchSourceText.trimmingCharacters(in: .whitespaces).isEmpty {
            return storage.bookSources
        }
        return storage.bookSources.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(searchSourceText) ||
            $0.bookSourceUrl.localizedCaseInsensitiveContains(searchSourceText)
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("筛选已导入的书源...", text: $searchSourceText)
                        .textFieldStyle(.plain)
                    if !searchSourceText.isEmpty {
                        Button {
                            searchSourceText = ""
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
                
                // Source List
                List {
                    Section(header: Text("总计 \(storage.bookSources.count) 个书源 (已启用: \(storage.bookSources.filter { $0.enabled ?? true }.count))")) {
                        ForEach(filteredSources) { source in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.bookSourceName)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(source.bookSourceUrl)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    if let comment = source.bookSourceComment, !comment.isEmpty {
                                        Text(comment)
                                            .font(.caption2)
                                            .foregroundColor(.secondary.opacity(0.8))
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { source.enabled ?? true },
                                    set: { newValue in
                                        if let idx = storage.bookSources.firstIndex(where: { $0.bookSourceUrl == source.bookSourceUrl }) {
                                            storage.bookSources[idx].enabled = newValue
                                            storage.saveBookSources()
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                        }
                        .onDelete(perform: deleteSource)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("书源管理")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingImportSheet = true
                    } label: {
                        Label("网络导入", systemImage: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportSourceSheet()
            }
        }
    }
    
    private func deleteSource(at offsets: IndexSet) {
        storage.bookSources.remove(atOffsets: offsets)
        storage.saveBookSources()
    }
}
