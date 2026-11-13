import SwiftUI

public enum SourceFilterCategory: String, CaseIterable, Identifiable {
    case all = "全部"
    case enabled = "已启用"
    case curatedNew = "新增精选"
    case fastVerified = "测速通过"
    
    public var id: String { rawValue }
}

public struct SourceManagerView: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var showingImportSheet = false
    @State private var searchSourceText = ""
    @State private var selectedFilter: SourceFilterCategory = .all
    @State private var isTestingSpeed = false
    @State private var speedTestStatus = ""
    @State private var speedTestFraction: Double = 0
    @State private var validationTask: Task<Void, Never>?
    @State private var validationID = UUID()
    @State private var showResetConfirmation = false
    
    private static let curatedNewURLs: Set<String> = [
        "https://www.deqixs.org",
        "https://www.dbxsn.com",
        "http://www.yetianlian.net",
        "https://www.wxsck.com",
        "http://www.xianqihaotianmi.org/"
    ]
    
    private func isCuratedNew(_ source: BookSource) -> Bool {
        source.displayGroupTag == "新增精选" || Self.curatedNewURLs.contains(source.bookSourceUrl)
    }
    
    private var filteredSources: [BookSource] {
        let base: [BookSource]
        switch selectedFilter {
        case .all:
            base = storage.bookSources
        case .enabled:
            base = storage.bookSources.filter { $0.enabled ?? true }
        case .curatedNew:
            base = storage.bookSources.filter { isCuratedNew($0) }
        case .fastVerified:
            base = storage.bookSources.filter { ($0.respondTime ?? 99999) < 90000 }
        }
        let query = searchSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(query) ||
            $0.bookSourceUrl.localizedCaseInsensitiveContains(query) ||
            ($0.displayGroupTag?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top Summary Dashboard Card
                VStack(spacing: 12) {
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("已启用 \(storage.bookSources.filter { $0.enabled ?? true }.count) / \(storage.bookSources.count) 个书源")
                                .font(.system(size: 16, weight: .bold, design: .serif))
                            Text(speedTestStatus.isEmpty ? "内置 \(storage.bundledSourceCount) 个精选书源（含 5 个新增实测源），支持非破坏性升级与一键测速" : speedTestStatus)
                                .font(.system(size: 11))
                                .foregroundColor(isTestingSpeed ? .indigo : .secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    
                    // Quick Metric Chips
                    HStack(spacing: 8) {
                        let compatibleCount = storage.bookSources.filter { SourceSearchPolicy.unsupportedReason($0) == nil }.count
                        let newCuratedCount = storage.bookSources.filter { isCuratedNew($0) }.count
                        let verifiedFastCount = storage.bookSources.filter { ($0.respondTime ?? 99999) < 90000 }.count
                        
                        dashboardStatChip(title: "搜索兼容", value: "\(compatibleCount) 源", color: .indigo)
                        dashboardStatChip(title: "新增精选", value: "\(newCuratedCount) 源", color: .orange)
                        dashboardStatChip(title: "测速通过", value: verifiedFastCount > 0 ? "\(verifiedFastCount) 源" : "待测速", color: .teal)
                    }
                    
                    if isTestingSpeed {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.07))
                                    .frame(height: 4)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.indigo, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(12, geo.size.width * min(1.0, speedTestFraction)), height: 4)
                            }
                        }
                        .frame(height: 4)
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
                            .padding(.vertical, 8.5)
                            .background(
                                LinearGradient(
                                    colors: [Color.indigo, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        
                        Button {
                            cancelValidation()
                            let added = storage.loadDefaultSources()
                            speedTestStatus = added > 0
                                ? "已补充 \(added) 个缺失的内置精选书源"
                                : "内置 \(storage.bundledSourceCount) 个精选书源已齐全，保留自定义设置"
                        } label: {
                            Text("补充内置源")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8.5)
                                .background(Color.indigo.opacity(0.12))
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
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.indigo)
                                .frame(minWidth: 32, minHeight: 36)
                        }
                        .accessibilityLabel("书源重置与恢复")
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.indigo.opacity(0.14), lineWidth: 0.8)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                
                // Search Bar & Category Filter Pills
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.indigo)
                            .font(.system(size: 14, weight: .semibold))
                        TextField("搜索书源名称、域名或分组...", text: $searchSourceText)
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
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SourceFilterCategory.allCases) { filter in
                                let active = (selectedFilter == filter)
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedFilter = filter
                                    }
                                } label: {
                                    Text(filter.rawValue)
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5.5)
                                        .background(active ? Color.indigo : Color(.secondarySystemGroupedBackground))
                                        .foregroundColor(active ? .white : .secondary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                
                // Source List
                List {
                    ForEach(filteredSources) { source in
                        HStack(spacing: 12) {
                            Circle()
                                .fill((source.enabled ?? true) ? Color.green : Color.gray.opacity(0.4))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(source.bookSourceName)
                                        .font(.system(size: 15, weight: .bold, design: .serif))
                                        .lineLimit(1)
                                    
                                    if isCuratedNew(source) {
                                        Text("新增精选")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.16))
                                            .foregroundColor(.orange)
                                            .clipShape(Capsule())
                                    } else if let group = source.displayGroupTag {
                                        Text(group)
                                            .font(.system(size: 9, weight: .medium))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.indigo.opacity(0.10))
                                            .foregroundColor(.indigo)
                                            .clipShape(Capsule())
                                    }
                                    
                                    if let ms = source.respondTime {
                                        speedBadge(ms: ms)
                                    }
                                }
                                
                                HStack(spacing: 6) {
                                    Text(source.hostDisplayName)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    
                                    if SourceSearchPolicy.unsupportedReason(source) == nil {
                                        Text("规则完备")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.teal)
                                    } else {
                                        Text("脚本受限")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.orange)
                                    }
                                }
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
                        .padding(.vertical, 3)
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
    private func dashboardStatChip(title: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.secondary)
            Spacer(minLength: 2)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(color)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        speedTestFraction = 0.04
        speedTestStatus = "正在测试实际搜索结果..."
        validationTask = Task {
            do {
                let tested = try await SourceValidationPolicy.validate(sources: sources) { done, total in
                    guard validationID == id else { return }
                    speedTestFraction = Double(done) / Double(max(1, total))
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
