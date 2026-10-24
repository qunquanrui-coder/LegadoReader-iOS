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
            VStack(spacing: 0) {
                // Top Summary Dashboard Card
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("已启用 \(storage.bookSources.filter { $0.enabled ?? true }.count) / \(storage.bookSources.count) 个书源")
                            .font(.system(size: 16, weight: .bold, design: .serif))
                        Text("内置 20 个已通过目录与正文实测的纯净书源")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        storage.loadDefaultSources()
                    } label: {
                        Text("重置精选源")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.indigo.opacity(0.14))
                            .foregroundColor(.indigo)
                            .clipShape(Capsule())
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜索书源名称或域名...", text: $searchSourceText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                    if !searchSourceText.isEmpty {
                        Button {
                            searchSourceText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                // Source List
                List {
                    ForEach(filteredSources) { source in
                        HStack(spacing: 12) {
                            Circle()
                                .fill((source.enabled ?? true) ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(source.bookSourceName)
                                    .font(.system(size: 15, weight: .semibold))
                                Text(source.bookSourceUrl)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
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
                            .tint(.indigo)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete(perform: deleteSource)
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("书源中心")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingImportSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("网络导入")
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.indigo)
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
