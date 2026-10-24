import SwiftUI

public struct SourceManagerView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var showingImportSheet = false
    @State private var searchSourceText = ""
    @State private var isTestingSpeed = false
    @State private var speedTestStatus = ""
    
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
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已启用 \(storage.bookSources.filter { $0.enabled ?? true }.count) / \(storage.bookSources.count) 个书源")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                            Text(speedTestStatus.isEmpty ? "支持一键全自动并发测速、按极速排序与失效源自动禁用" : speedTestStatus)
                                .font(.system(size: 11))
                                .foregroundColor(isTestingSpeed ? .indigo : .secondary)
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 10) {
                        Button {
                            runSpeedTestAndOptimize()
                        } label: {
                            HStack(spacing: 5) {
                                if isTestingSpeed {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text(isTestingSpeed ? "正在并发测速..." : "一键测速 & 智能优选")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .disabled(isTestingSpeed)
                        
                        Button {
                            storage.loadDefaultSources()
                            speedTestStatus = "已恢复内置精选书源"
                        } label: {
                            Text("重置精选源")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.indigo.opacity(0.14))
                                .foregroundColor(.indigo)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
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
                                HStack(spacing: 6) {
                                    Text(source.bookSourceName)
                                        .font(.system(size: 15, weight: .semibold))
                                    
                                    if let ms = source.respondTime {
                                        speedBadge(ms: ms)
                                    }
                                }
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
    
    @ViewBuilder
    private func speedBadge(ms: Int) -> some View {
        if ms >= 90000 {
            Text("超时失效")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red.opacity(0.14))
                .foregroundColor(.red)
                .clipShape(Capsule())
        } else if ms < 600 {
            Text("\(ms)ms 极速")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.14))
                .foregroundColor(.green)
                .clipShape(Capsule())
        } else if ms < 1800 {
            Text("\(ms)ms 良好")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.14))
                .foregroundColor(.orange)
                .clipShape(Capsule())
        } else {
            Text("\(ms)ms 较慢")
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.14))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
        }
    }
    
    private func runSpeedTestAndOptimize() {
        let sources = storage.bookSources
        guard !sources.isEmpty else { return }
        
        isTestingSpeed = true
        speedTestStatus = "正在检测 \(sources.count) 个书源响应速度..."
        
        Task {
            var updated: [BookSource] = []
            var aliveCount = 0
            
            await withTaskGroup(of: BookSource.self) { group in
                for src in sources {
                    group.addTask {
                        var copy = src
                        let cleanUrl = src.bookSourceUrl.components(separatedBy: "#").first ?? src.bookSourceUrl
                        guard let url = URL(string: cleanUrl) else {
                            copy.respondTime = 99999
                            copy.enabled = false
                            return copy
                        }
                        var req = URLRequest(url: url)
                        req.timeoutInterval = 6.0
                        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
                        
                        let start = Date()
                        do {
                            let (_, resp) = try await URLSession.shared.data(for: req)
                            let elapsedMs = max(15, Int(Date().timeIntervalSince(start) * 1000))
                            if let http = resp as? HTTPURLResponse, http.statusCode >= 500 {
                                copy.respondTime = 99999
                                copy.enabled = false
                            } else {
                                copy.respondTime = elapsedMs
                                copy.enabled = true
                            }
                        } catch {
                            copy.respondTime = 99999
                            copy.enabled = false
                        }
                        return copy
                    }
                }
                
                for await res in group {
                    if (res.respondTime ?? 99999) < 90000 {
                        aliveCount += 1
                    }
                    updated.append(res)
                }
            }
            
            // Sort fastest working sources first
            updated.sort { ($0.respondTime ?? 99999) < ($1.respondTime ?? 99999) }
            let finalUpdated = updated
            let finalAlive = aliveCount
            
            await MainActor.run {
                storage.bookSources = finalUpdated
                storage.saveBookSources()
                isTestingSpeed = false
                speedTestStatus = "测速完成 · \(finalAlive) 个极速可用源已置顶，失效源已自动禁用"
            }
        }
    }
    
    private func deleteSource(at offsets: IndexSet) {
        storage.bookSources.remove(atOffsets: offsets)
        storage.saveBookSources()
    }
}
