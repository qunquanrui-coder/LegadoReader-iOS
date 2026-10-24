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
                    Label("探索", systemImage: "sparkle.magnifyingglass")
                }
            
            SourceManagerView()
                .tabItem {
                    Label("书源", systemImage: "globe.asia.australia.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(.indigo)
    }
}

struct SettingsView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var cacheSizeStr = "计算中..."
    @State private var showClearAlert = false
    
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "3.2.1"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.orange, Color.indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 58, height: 58)
                            Image(systemName: "book.pages.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ReaderConfig.isDuoEditionBuild ? "风读小说 · iPhone Duo 专享版" : "风读小说 · 纯净阅读版")
                                .font(.system(size: 18, weight: .bold, design: .serif))
                            Text(ReaderConfig.isDuoEditionBuild
                                 ? "v\(appVersion) · 支持 5.4\" 外屏 & 7.6\" 折叠内屏双页对开 · 锁屏听书"
                                 : "v\(appVersion) · 真人情感语音锁屏听书 · 全本离线缓存")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                
                Section("阅读偏好") {
                    Picker("默认背景主题", selection: Binding(
                        get: { storage.readerConfig.theme },
                        set: { val in
                            storage.readerConfig.theme = val
                            storage.saveConfig()
                        }
                    )) {
                        ForEach(ReaderBackgroundTheme.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    
                    Picker("默认字体排版", selection: Binding(
                        get: { storage.readerConfig.fontDesign },
                        set: { val in
                            storage.readerConfig.fontDesign = val
                            storage.saveConfig()
                        }
                    )) {
                        ForEach(ReaderFontDesign.allCases, id: \.self) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                }
                
                Section("存储与缓存") {
                    HStack {
                        Label("离线章节缓存", systemImage: "internaldrive")
                        Spacer()
                        Text(cacheSizeStr)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        showClearAlert = true
                    } label: {
                        Label("清理离线章节缓存", systemImage: "trash")
                    }
                }
                
                Section("书源引擎") {
                    HStack {
                        Label("已加载有效书源", systemImage: "network")
                        Spacer()
                        Text("\(storage.bookSources.count) 个")
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        storage.loadDefaultSources()
                    } label: {
                        Label("恢复内置 20 个实测高速书源", systemImage: "arrow.counterclockwise")
                            .foregroundColor(.indigo)
                    }
                }
            }
            .navigationTitle("关于与设置")
            .onAppear {
                calculateCacheSize()
            }
            .alert("确认清理离线缓存？", isPresented: $showClearAlert) {
                Button("立即清理", role: .destructive) {
                    clearCache()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("书架记录与阅读进度将保留，仅清理已下载的章节文本。")
            }
        }
    }
    
    private func calculateCacheSize() {
        let total = storage.chapterCacheSizeBytes()
        let mb = Double(total) / (1024 * 1024)
        cacheSizeStr = String(format: "%.2f MB", mb)
    }
    
    private func clearCache() {
        storage.clearAllChapterCache()
        calculateCacheSize()
    }
}
