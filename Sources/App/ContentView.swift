import SwiftUI
import UniformTypeIdentifiers
import UIKit

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
    @State private var showFileImporter = false
    @State private var backupAlertMessage: String? = nil
    
    private var appVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "3.3.0"
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
                
                Section("数据备份与恢复 (防丢失)") {
                    if let backupURL = storage.exportFullBackupFileURL() {
                        ShareLink(item: backupURL) {
                            Label("导出完整备份文件 (书架/进度/书源)", systemImage: "square.and.arrow.up")
                        }
                    }
                    
                    Button {
                        if let json = storage.exportFullBackupJSON() {
                            UIPasteboard.general.string = json
                            backupAlertMessage = "已将完整备份（含 \(storage.bookshelf.count) 本藏书、阅读进度与 \(storage.bookSources.count) 个书源）复制到剪贴板！"
                        }
                    } label: {
                        Label("复制备份 JSON 到剪贴板", systemImage: "doc.on.doc")
                    }
                    
                    Button {
                        guard let str = UIPasteboard.general.string, !str.isEmpty else {
                            backupAlertMessage = "剪贴板为空，请先复制备份 JSON 内容"
                            return
                        }
                        do {
                            let res = try storage.restoreFromBackupJSON(str)
                            backupAlertMessage = "恢复成功！已导入 \(res.booksCount) 本藏书、\(res.sourcesCount) 个书源及全部章节/段落阅读进度。"
                        } catch {
                            backupAlertMessage = "备份解析失败：\(error.localizedDescription)"
                        }
                    } label: {
                        Label("从剪贴板恢复备份", systemImage: "arrow.down.doc")
                    }
                    
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("从备份文件导入恢复 (.json)", systemImage: "folder.badge.plus")
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
                        Label("已保存书源规则", systemImage: "network")
                        Spacer()
                        Text("\(storage.bookSources.count) 个")
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        storage.loadDefaultSources()
                    } label: {
                        Label("恢复内置 20 个精选书源", systemImage: "arrow.counterclockwise")
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
            .alert("备份与恢复提示", isPresented: Binding(
                get: { backupAlertMessage != nil },
                set: { if !$0 { backupAlertMessage = nil } }
            )) {
                Button("好的", role: .cancel) { backupAlertMessage = nil }
            } message: {
                Text(backupAlertMessage ?? "")
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        do {
                            let res = try storage.restoreFromBackupJSON(content)
                            backupAlertMessage = "文件恢复成功！已导入 \(res.booksCount) 本藏书、\(res.sourcesCount) 个书源及全部阅读进度。"
                        } catch {
                            backupAlertMessage = "备份文件格式无效：\(error.localizedDescription)"
                        }
                    }
                case .failure(let err):
                    backupAlertMessage = "读取文件失败：\(err.localizedDescription)"
                }
            }
        }
    }
    
    private func calculateCacheSize() {
        let cacheDir = storage.cacheDirectoryURL
        Task.detached(priority: .utility) {
            let total = StorageManager.directorySizeBytes(at: cacheDir)
            let mb = Double(total) / (1024 * 1024)
            let formatted = String(format: "%.2f MB", mb)
            await MainActor.run {
                self.cacheSizeStr = formatted
            }
        }
    }
    
    private func clearCache() {
        storage.clearAllChapterCache()
        calculateCacheSize()
    }
}
