import SwiftUI
import UniformTypeIdentifiers
import UIKit

public struct ContentView: View {
    @State private var selectedTab: Int = ProcessInfo.processInfo.arguments.contains("--ui-testing") ? 3 : 0

    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            BookshelfView()
                .tabItem {
                    Label("书架", systemImage: "books.vertical.fill")
                }
                .tag(0)
            
            SearchView()
                .tabItem {
                    Label("探索", systemImage: "sparkle.magnifyingglass")
                }
                .tag(1)
            
            SourceManagerView()
                .tabItem {
                    Label("书源", systemImage: "globe.asia.australia.fill")
                }
                .tag(2)
            
            SettingsView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
                .tag(3)
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
    @State private var preparingBackup = false
    @State private var backupTask: Task<Void, Never>?
    @State private var backupOperationID = UUID()
    @State private var preparedBackupURL: URL?
    @State private var showBackupShare = false
    @State private var pendingRestoreJSON: String?
    @State private var showRestoreConfirmation = false
    @State private var showResetSources = false
    @State private var sourcePolicy: BackupSourcePolicy = .keepLocal
    @State private var configPolicy: BackupConfigPolicy = .newest
    private let backupExporter = BackupFileExporter()
    
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

                Section("书源引擎") {
                    HStack {
                        Label("已保存书源规则", systemImage: "network")
                        Spacer()
                        Text("\(storage.bookSources.count) 个 · 首源：\(storage.bookSources.first?.bookSourceName ?? "无")")
                            .foregroundColor(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("settings.sources.summary")

                    Button {
                        let count = storage.loadDefaultSources()
                        backupAlertMessage = "已补充 \(count) 个内置书源，保留原有导入和自定义规则。"
                    } label: {
                        Label("补充内置精选书源", systemImage: "plus.circle")
                            .foregroundColor(.indigo)
                    }
                    .accessibilityIdentifier("settings.sources.supplement")
                    Button("完整重置书源…", role: .destructive) { showResetSources = true }
                        .accessibilityIdentifier("settings.sources.reset")
                    if storage.hasSourceResetSnapshot {
                        Button("撤销上次书源重置") {
                            do { let count = try storage.restoreSourcesFromLastResetSnapshot(); backupAlertMessage = "已恢复重置前的 \(count) 个书源。" }
                            catch { backupAlertMessage = "恢复书源快照失败：\(error.localizedDescription)" }
                        }
                        .accessibilityIdentifier("settings.sources.undoReset")
                    }
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
                    Button { prepareBackup(share: true) } label: {
                        Label(preparingBackup ? "正在准备备份…" : "导出完整备份文件 (书架/进度/书源)", systemImage: "square.and.arrow.up")
                    }.disabled(preparingBackup)
                    
                    Button {
                        prepareBackup(share: false)
                    } label: {
                        Label("复制备份 JSON 到剪贴板", systemImage: "doc.on.doc")
                    }
                    .disabled(preparingBackup)

                    Picker("恢复时的书源", selection: $sourcePolicy) {
                        Text("保留本地书源").tag(BackupSourcePolicy.keepLocal)
                        Text("使用备份书源").tag(BackupSourcePolicy.useBackup)
                    }
                    Picker("恢复时的阅读设置", selection: $configPolicy) {
                        Text("按设置修改时间").tag(BackupConfigPolicy.newest)
                        Text("保留本地设置").tag(BackupConfigPolicy.keepLocal)
                        Text("使用备份设置").tag(BackupConfigPolicy.useBackup)
                    }
                    Text("保留本地书源可继续使用原有离线内容；更换为备份书源后可能需要重新缓存。备份文件不包含离线正文。")
                        .font(.caption).foregroundColor(.secondary)
                    
                    Button {
                        guard let str = UIPasteboard.general.string, !str.isEmpty else {
                            backupAlertMessage = "剪贴板为空，请先复制备份 JSON 内容"
                            return
                        }
                        pendingRestoreJSON = str
                        showRestoreConfirmation = true
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
            }
            .navigationTitle("关于与设置")
            .onAppear {
                calculateCacheSize()
            }
            .onDisappear { backupOperationID = UUID(); backupTask?.cancel(); preparingBackup = false }
            .sheet(isPresented: $showBackupShare) {
                if let url = preparedBackupURL { BackupShareSheet(url: url) }
            }
            .alert("确认合并恢复备份？", isPresented: $showRestoreConfirmation) {
                Button("恢复") { restorePendingBackup() }
                Button("取消", role: .cancel) { pendingRestoreJSON = nil }
            } message: {
                Text("将按上面选择的书源和阅读设置策略合并备份，保留较新的阅读进度。")
            }
            .alert("完整重置全部书源？", isPresented: $showResetSources) {
                Button("保存快照并重置", role: .destructive) {
                    do { _ = try storage.resetSourcesToDefaults(); backupAlertMessage = "已重置为内置源，可使用“撤销上次书源重置”恢复。" }
                    catch { backupAlertMessage = "未重置书源：\(error.localizedDescription)" }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将替换全部导入和自定义书源。成功保存原列表快照后才会重置。")
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
                    backupTask?.cancel()
                    let operation = UUID(); backupOperationID = operation
                    backupTask = Task {
                        do {
                            let content = try await backupExporter.read(url)
                            guard !Task.isCancelled, operation == backupOperationID else { return }
                            pendingRestoreJSON = content
                            showRestoreConfirmation = true
                        } catch {
                            guard !Task.isCancelled, operation == backupOperationID else { return }
                            backupAlertMessage = "读取备份失败：\(error.localizedDescription)"
                        }
                    }
                case .failure(let err):
                    backupAlertMessage = "读取文件失败：\(err.localizedDescription)"
                }
            }
        }
    }

    private func prepareBackup(share: Bool) {
        backupTask?.cancel()
        let operation = UUID(); backupOperationID = operation
        let payload = storage.makeFullBackupPayload()
        preparingBackup = true
        backupTask = Task {
            do {
                let result = try await backupExporter.prepare(payload)
                guard !Task.isCancelled, operation == backupOperationID else { return }
                preparingBackup = false
                if share { preparedBackupURL = result.url; showBackupShare = true }
                else { UIPasteboard.general.string = result.json; backupAlertMessage = "完整备份 JSON 已复制到剪贴板。" }
            } catch {
                guard !Task.isCancelled, operation == backupOperationID else { return }
                preparingBackup = false
                backupAlertMessage = "生成备份失败：\(error.localizedDescription)"
            }
        }
    }

    private func restorePendingBackup() {
        guard let json = pendingRestoreJSON else { return }
        pendingRestoreJSON = nil
        do {
            let result = try storage.restoreFromBackupJSON(json, sourcePolicy: sourcePolicy, configPolicy: configPolicy)
            backupAlertMessage = "恢复完成：已处理 \(result.booksCount) 本书和 \(result.sourcesCount) 个书源。"
        } catch { backupAlertMessage = "备份恢复失败：\(error.localizedDescription)" }
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

private struct BackupShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
