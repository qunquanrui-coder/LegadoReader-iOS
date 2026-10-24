import SwiftUI

public struct ContentView: View {
    public init() {}
    
    public var body: some View {
        TabView {
            BookshelfView()
                .tabItem {
                    Label("书架", systemImage: "books.vertical.fill")
                }
            
            SearchView()
                .tabItem {
                    Label("搜索", systemImage: "magnifyingglass")
                }
            
            SourceManagerView()
                .tabItem {
                    Label("书源", systemImage: "network")
                }
            
            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var cacheSizeStr = "计算中..."
    @State private var showClearAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("缓存管理") {
                    HStack {
                        Text("离线章节缓存")
                        Spacer()
                        Text(cacheSizeStr)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("清空离线小说缓存", role: .destructive) {
                        showClearAlert = true
                    }
                }
                
                Section("规则与书源") {
                    Button("重置并载入预置默认书源") {
                        storage.loadDefaultSources()
                    }
                    
                    HStack {
                        Text("当前已载入书源")
                        Spacer()
                        Text("\(storage.bookSources.count) 个")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section("关于软件") {
                    HStack {
                        Text("应用名称")
                        Spacer()
                        Text("风读 (LegadoReader)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0 (Native SwiftUI)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("书源规范")
                        Spacer()
                        Text("Legado 3.0 标准兼容")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("系统设置")
            .onAppear {
                calculateCacheSize()
            }
            .alert("确认清空缓存？", isPresented: $showClearAlert) {
                Button("清空", role: .destructive) {
                    clearCache()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("清空后已缓存的章节需要重新联网加载。")
            }
        }
    }
    
    private func calculateCacheSize() {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("NovelCache")
        
        var totalSize: Int64 = 0
        if let enumerator = fileManager.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        let mb = Double(totalSize) / (1024 * 1024)
        cacheSizeStr = String(format: "%.2f MB", mb)
    }
    
    private func clearCache() {
        let fileManager = FileManager.default
        let urls = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("NovelCache")
        try? fileManager.removeItem(at: dir)
        calculateCacheSize()
    }
}
