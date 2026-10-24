import SwiftUI

public struct ImportSourceSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    
    @State private var inputUrl = ""
    @State private var isImporting = false
    @State private var statusMessage = ""
    @State private var isError = false
    
    private let presets: [(name: String, desc: String, url: String)] = [
        (
            "风读官方 20+ 实测高速纯净源 (强烈推荐)",
            "全部通过搜索+目录+正文三重实测，秒开无报错",
            "https://fastly.jsdelivr.net/gh/qunquanrui-coder/LegadoReader-iOS@main/Resources/default_sources.json"
        ),
        (
            "全网 3000+ 综合书源合集",
            "数量庞大，自动过滤纯JS脚本源，适合冷门小说检索",
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
                
                Section("官方精选源仓库 (点击一键导入)") {
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
        guard !cleanUrl.isEmpty else { return }
        
        isImporting = true
        statusMessage = "正在拉取远程书源数据..."
        isError = false
        
        Task {
            do {
                let (jsonText, _) = try await NetworkManager.shared.fetchString(from: cleanUrl)
                let added = try storage.importSourcesFromJSON(jsonString: jsonText)
                await MainActor.run {
                    self.isImporting = false
                    self.isError = false
                    self.statusMessage = "✅ 导入成功！新增 \(added) 个兼容书源，当前总计可用：\(storage.bookSources.count) 个"
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
