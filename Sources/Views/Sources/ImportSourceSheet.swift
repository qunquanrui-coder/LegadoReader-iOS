import SwiftUI

public struct ImportSourceSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    
    @State private var inputUrl = ""
    @State private var isImporting = false
    @State private var statusMessage = ""
    @State private var isError = false
    @State private var updateExisting = true
    
    private let externalCatalogURL = "https://fastly.jsdelivr.net/gh/shidahuilang/shuyuan-bak@main/good.json"
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("自定义网络导入 (JSON 直链)") {
                    TextField("粘贴 http(s):// 开头的书源 JSON 链接", text: $inputUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button {
                        performImport(urlStr: inputUrl)
                    } label: {
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("正在下载并校验规则...")
                            }
                        } else {
                            Text("立即网络导入")
                                .fontWeight(.semibold)
                                .foregroundColor(.indigo)
                        }
                    }
                    .disabled(inputUrl.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)
                }
                
                Section {
                    Toggle("网络导入时更新同地址规则", isOn: $updateExisting)
                        .disabled(isImporting)
                } footer: {
                    Text("保留原有启用/禁用设置。导入只保存规则，不代表书源已通过联网验证。")
                }
                Section("书源仓库 (点击一键导入)") {
                    Button {
                        let added = storage.loadDefaultSources()
                        isError = false
                        statusMessage = "已补充 \(added) 个内置书源。当前共保存 \(storage.bookSources.count) 个书源。"
                    } label: {
                        presetLabel("风读内置精选书源（\(storage.bundledSourceCount) 个）",
                                    description: "无需下载，补齐缺失的内置规则",
                                    icon: "plus.circle.fill")
                    }
                    .disabled(isImporting || storage.bundledSourceCount == 0)

                    Button {
                        inputUrl = externalCatalogURL
                        performImport(urlStr: externalCatalogURL)
                    } label: {
                        presetLabel("全网 3000+ 综合书源合集",
                                    description: "数量较多，部分规则暂不支持；导入后可测试搜索",
                                    icon: "arrow.down.circle.fill")
                    }
                    .disabled(isImporting)
                }
                
                if !statusMessage.isEmpty {
                    Section("导入结果") {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(isError ? .red : .green)
                    }
                }
            }
            .navigationTitle("导入书源")
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
    
    private func presetLabel(_ title: String, description: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: icon)
                    .foregroundColor(.indigo)
            }
            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func performImport(urlStr: String) {
        let cleanUrl = urlStr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanUrl.isEmpty, !isImporting else { return }
        let shouldUpdate = updateExisting
        
        isImporting = true
        statusMessage = "正在拉取远程书源数据..."
        isError = false
        
        Task {
            do {
                let (jsonText, _) = try await NetworkManager.shared.fetchString(from: cleanUrl)
                let report = try storage.importSourcesFromJSON(jsonString: jsonText, updateExisting: shouldUpdate)
                let unsupported = storage.bookSources.filter { SourceSearchPolicy.unsupportedReason($0) != nil }.count
                await MainActor.run {
                    self.isImporting = false
                    self.isError = false
                    self.statusMessage = "导入完成：新增 \(report.added)，更新 \(report.updated)，跳过 \(report.skipped)。共保存 \(storage.bookSources.count) 个书源，其中 \(unsupported) 个缺少搜索规则或暂不支持。实际可用性需联网测试。"
                }
            } catch {
                await MainActor.run {
                    self.isImporting = false
                    self.isError = true
                    self.statusMessage = "导入失败: \(error.localizedDescription)"
                }
            }
        }
    }
}
