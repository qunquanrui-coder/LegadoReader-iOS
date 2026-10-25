import SwiftUI

public struct ImportSourceSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    
    @State private var inputUrl = ""
    @State private var isImporting = false
    @State private var statusMessage = ""
    @State private var isError = false
    @State private var updateExisting = true
    
    private let presets: [(name: String, desc: String, url: String)] = [
        (
            "风读内置精选书源",
            "适合日常阅读；站点可用性会随时间和网络变化",
            "https://fastly.jsdelivr.net/gh/qunquanrui-coder/LegadoReader-iOS@main/Resources/default_sources.json"
        ),
        (
            "全网 3000+ 综合书源合集",
            "数量较多，部分规则暂不支持；导入后可测试搜索",
            "https://fastly.jsdelivr.net/gh/shidahuilang/shuyuan-bak@main/good.json"
        )
    ]
    
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
                    Toggle("更新已有同地址书源的规则", isOn: $updateExisting)
                        .disabled(isImporting)
                } footer: {
                    Text("保留原有启用/禁用设置。导入只保存规则，不代表书源已通过联网验证。")
                }
                Section("书源仓库 (点击一键导入)") {
                    ForEach(presets, id: \.url) { preset in
                        Button {
                            inputUrl = preset.url
                            performImport(urlStr: preset.url)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(preset.name)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundColor(.indigo)
                                }
                                Text(preset.desc)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(isImporting)
                    }
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
