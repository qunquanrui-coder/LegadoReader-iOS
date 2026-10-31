import SwiftUI

public struct SourceManagerView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var showingImportSheet = false
    @State private var searchSourceText = ""
    @State private var isTestingSpeed = false
    @State private var speedTestStatus = ""
    @State private var validationTask: Task<Void, Never>?
    @State private var validationID = UUID()
    @State private var showResetConfirmation = false
    
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
                            Text(speedTestStatus.isEmpty ? "使用“斗罗大陆”测试搜索，成功源优先；保留手动启用设置" : speedTestStatus)
                                .font(.system(size: 11))
                                .foregroundColor(isTestingSpeed ? .indigo : .secondary)
                        }
                        Spacer()
                    }
                    
                    HStack(spacing: 10) {
                        Button {
                            if isTestingSpeed { cancelValidation() } else { runSpeedTestAndOptimize() }
                        } label: {
                            HStack(spacing: 5) {
                                if isTestingSpeed {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Image(systemName: "bolt.fill")
                                }
                                Text(isTestingSpeed ? "停止测试" : "测试搜索并排序")
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.indigo)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        
                        Button {
                            cancelValidation()
                            storage.loadDefaultSources()
                            speedTestStatus = "已补充内置精选书源，保留导入和自定义规则"
                        } label: {
                            Text("补充内置源")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.indigo.opacity(0.14))
                                .foregroundColor(.indigo)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        Menu {
                            Button("完整重置书源…", role: .destructive) { showResetConfirmation = true }
                            if storage.hasSourceResetSnapshot {
                                Button("撤销上次重置") {
                                    cancelValidation()
                                    do {
                                        let count = try storage.restoreSourcesFromLastResetSnapshot()
                                        speedTestStatus = "已恢复重置前的 \(count) 个书源"
                                    } catch { speedTestStatus = "恢复失败：\(error.localizedDescription)" }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").frame(minWidth: 32, minHeight: 36)
                        }
                        .accessibilityLabel("书源重置与恢复")
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
            .onDisappear { cancelValidation() }
            .alert("完整重置全部书源？", isPresented: $showResetConfirmation) {
                Button("重置并保存恢复快照", role: .destructive) {
                    cancelValidation()
                    do {
                        _ = try storage.resetSourcesToDefaults()
                        speedTestStatus = "已完整重置；可在菜单中撤销上次重置"
                    } catch { speedTestStatus = "重置未完成：\(error.localizedDescription)" }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这会替换所有已导入和自定义规则。重置前会先保存恢复快照；只想补回内置源，请使用“补充内置源”。")
            }
            .sheet(isPresented: $showingImportSheet) {
                ImportSourceSheet()
            }
        }
    }
    
    @ViewBuilder
    private func speedBadge(ms: Int) -> some View {
        if ms >= 90000 {
            Text("搜索未验证通过")
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
    
    private func cancelValidation() {
        validationID = UUID()
        validationTask?.cancel()
        validationTask = nil
        if isTestingSpeed { speedTestStatus = "测试已停止，保留原有设置" }
        isTestingSpeed = false
    }

    private func runSpeedTestAndOptimize() {
        let sources = storage.bookSources
        guard !sources.isEmpty else { return }
        cancelValidation()
        let id = UUID()
        validationID = id
        isTestingSpeed = true
        speedTestStatus = "正在测试实际搜索结果..."
        validationTask = Task {
            do {
                let tested = try await SourceValidationPolicy.validate(sources: sources) { done, total in
                    guard validationID == id else { return }
                    speedTestStatus = "已检查 \(done)/\(total) 个书源；可随时停止"
                }
                try Task.checkCancellation()
                guard validationID == id else { return }
                storage.bookSources = SourceValidationPolicy.applying(tested, original: sources, to: storage.bookSources)
                storage.saveBookSources()
                let passed = tested.filter { ($0.enabled ?? true) && ($0.respondTime ?? 99999) < 90000 }.count
                isTestingSpeed = false
                speedTestStatus = "测试完成：\(passed) 个源返回搜索结果。未通过不代表永久失效，启用设置保持不变。"
            } catch {
                guard validationID == id else { return }
                isTestingSpeed = false
                speedTestStatus = "测试已停止，保留原有设置"
            }
        }
    }

    private func deleteSource(at offsets: IndexSet) {
        let urls = Set(offsets.map { filteredSources[$0].bookSourceUrl })
        storage.bookSources.removeAll { urls.contains($0.bookSourceUrl) }
        storage.saveBookSources()
    }
}
