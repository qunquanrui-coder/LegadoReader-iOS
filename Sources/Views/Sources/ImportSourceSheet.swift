import SwiftUI

public struct ImportSourceSheet: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var storage = StorageManager.shared
    
    @State private var inputUrl = ""
    @State private var isImporting = false
    @State private var statusMessage = ""
    @State private var isError = false
    
    // Quick presets
    private let presets: [(name: String, url: String)] = [
        ("3000+ 综合校验源 (推荐)", "https://fastly.jsdelivr.net/gh/shidahuilang/shuyuan-bak@main/good.json"),
        ("XIU2 精品书源 (高速稳定)", "https://cdn.jsdmirror.com/gh/XIU2/Yuedu/shuyuan")
    ]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section("书源网络地址 (JSON 直链)") {
                    TextField("粘贴 http(s):// 开头的书源 JSON 链接", text: $inputUrl)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    Button {
                        performImport(urlStr: inputUrl)
                    } label: {
                        if isImporting {
                            HStack {
                                ProgressView()
                                Text("正在下载解析...")
                            }
                        } else {
                            Text("立即导入")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(inputUrl.trimmingCharacters(in: .whitespaces).isEmpty || isImporting)
                }
                
                Section("快捷常用源推荐 (点击一键填入)") {
                    ForEach(presets, id: \.url) { preset in
                        Button {
                            inputUrl = preset.url
                            performImport(urlStr: preset.url)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preset.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                Text(preset.url)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                if !statusMessage.isEmpty {
                    Section {
                        Text(statusMessage)
                            .font(.subheadline)
                            .foregroundColor(isError ? .red : .green)
                    }
                }
            }
            .navigationTitle("网络导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
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
        statusMessage = "正在请求远程数据..."
        isError = false
        
        Task {
            do {
                let (jsonText, _) = try await NetworkManager.shared.fetchString(from: cleanUrl)
                let added = try storage.importSourcesFromJSON(jsonString: jsonText)
                await MainActor.run {
                    self.isImporting = false
                    self.isError = false
                    self.statusMessage = "导入成功！成功载入 \(added) 个新书源，现有总书源：\(storage.bookSources.count) 个"
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
