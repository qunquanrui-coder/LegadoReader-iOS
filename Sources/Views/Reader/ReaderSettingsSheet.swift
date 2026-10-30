import SwiftUI

public struct ReaderSettingsSheet: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var newPurifyWord = ""
    @State private var typographyProfile: ReaderViewportProfile
    
    public init(initialTypographyProfile: ReaderViewportProfile = .compact) {
        _typographyProfile = State(initialValue: initialTypographyProfile)
    }
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 10)
                
                // 1. Page Turn Mode & Chinese Conversion
                VStack(alignment: .leading, spacing: 12) {
                    Text("翻页模式与 iPhone Duo 双屏适配")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        ForEach(ReaderPageTurnMode.allCases, id: \.self) { mode in
                            let isSelected = storage.readerConfig.effectivePageTurnMode == mode
                            let iconName = mode == .verticalScroll
                                ? "arrow.up.and.down.square"
                                : (mode == .horizontalSlide ? "rectangle.portrait.arrowtriangle.2.outward" : "book.pages.fill")
                            Button {
                                storage.readerConfig.effectivePageTurnMode = mode
                                storage.saveConfig()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: iconName)
                                        .font(.system(size: 12))
                                    Text(mode.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(isSelected ? Color.indigo.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                                .foregroundColor(isSelected ? .indigo : .primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(isSelected ? Color.indigo : Color.clear, lineWidth: 1.5)
                                )
                            }
                        }
                    }
                    
                    Toggle(isOn: Binding(
                        get: { storage.readerConfig.effectiveAutoDuoSpread },
                        set: { val in
                            storage.readerConfig.effectiveAutoDuoSpread = val
                            storage.saveConfig()
                        }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: "rectangle.split.2x1.fill")
                                .foregroundColor(.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("空间充足时自动双页阅读")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("根据当前窗口宽度切换；折叠或缩小窗口时使用单页")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .tint(.indigo)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    Toggle(isOn: Binding(
                        get: { storage.readerConfig.effectiveShowDuoSpine },
                        set: { val in
                            storage.readerConfig.effectiveShowDuoSpine = val
                            storage.saveConfig()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("双页书脊装饰")
                                .font(.system(size: 13, weight: .semibold))
                            Text("默认使用简洁分隔；开启后显示仿书脊阴影")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .tint(.indigo)
                    .padding(10)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 10) {
                        ForEach(ChineseConversionMode.allCases, id: \.self) { conv in
                            let isSelected = storage.readerConfig.effectiveChineseConversion == conv
                            Button {
                                storage.readerConfig.effectiveChineseConversion = conv
                                storage.saveConfig()
                            } label: {
                                Text(conv.rawValue)
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(isSelected ? Color.indigo.opacity(0.15) : Color(.secondarySystemGroupedBackground))
                                    .foregroundColor(isSelected ? .indigo : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(isSelected ? Color.indigo : Color.clear, lineWidth: 1.5)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)

                tapModeSettings
                
                // 2. Themes
                VStack(alignment: .leading, spacing: 10) {
                    Text("背景主题")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(ReaderBackgroundTheme.allCases, id: \.self) { theme in
                                Button {
                                    storage.readerConfig.theme = theme
                                    storage.saveConfig()
                                } label: {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            Circle()
                                                .fill(theme.backgroundColor)
                                                .frame(width: 44, height: 44)
                                                .overlay(
                                                    Circle()
                                                        .stroke(
                                                            storage.readerConfig.theme == theme ? Color.indigo : Color.gray.opacity(0.25),
                                                            lineWidth: storage.readerConfig.theme == theme ? 3 : 1
                                                        )
                                                )
                                            Text("文")
                                                .font(.system(size: 15, weight: .bold, design: .serif))
                                                .foregroundColor(theme.textColor)
                                        }
                                        Text(theme.rawValue)
                                            .font(.system(size: 11, weight: storage.readerConfig.theme == theme ? .bold : .regular))
                                            .foregroundColor(storage.readerConfig.theme == theme ? .indigo : .primary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal, 20)
                
                // 3. Font Design
                VStack(alignment: .leading, spacing: 10) {
                    Text("字体排版")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        ForEach(ReaderFontDesign.allCases, id: \.self) { design in
                            Button {
                                storage.readerConfig.fontDesign = design
                                storage.saveConfig()
                            } label: {
                                Text(design.rawValue)
                                    .font(.system(size: 14, weight: .semibold, design: design.swiftUIDesign))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(
                                        storage.readerConfig.fontDesign == design
                                        ? Color.indigo.opacity(0.15)
                                        : Color(.secondarySystemGroupedBackground)
                                    )
                                    .foregroundColor(storage.readerConfig.fontDesign == design ? .indigo : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(storage.readerConfig.fontDesign == design ? Color.indigo : Color.clear, lineWidth: 1.5)
                                    )
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
                typographySettings
                
                // 5. Custom Text Purification Rules
                VStack(alignment: .leading, spacing: 10) {
                    Text("正文广告净化（自定义屏蔽词）")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        TextField("输入要过滤的网站水印或广告词...", text: $newPurifyWord)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        Button {
                            let clean = newPurifyWord.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !clean.isEmpty && !storage.readerConfig.effectivePurifyRules.contains(clean) {
                                storage.readerConfig.effectivePurifyRules.append(clean)
                                storage.saveConfig()
                                newPurifyWord = ""
                            }
                        } label: {
                            Text("添加")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.indigo)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                    
                    if !storage.readerConfig.effectivePurifyRules.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(storage.readerConfig.effectivePurifyRules, id: \.self) { rule in
                                    HStack(spacing: 4) {
                                        Text(rule)
                                            .font(.system(size: 11))
                                        Button {
                                            storage.readerConfig.effectivePurifyRules.removeAll(where: { $0 == rule })
                                            storage.saveConfig()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .presentationDetents([.height(540), .large])
    }

    private var typographySettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("字号与行距")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Picker("正在编辑的窗口", selection: $typographyProfile) {
                ForEach(ReaderViewportProfile.allCases, id: \.self) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.segmented)
            Text("两种窗口分别记忆；调整当前选项不会改变另一种窗口的字号和行距。")
                .font(.caption)
                .foregroundColor(.secondary)
            typographyControl(title: "字号大小", symbol: "textformat.size", value: selectedTypography.fontSize,
                              decrease: { adjustTypography(fontDelta: -1) }, increase: { adjustTypography(fontDelta: 1) })
            typographyControl(title: "段落行距", symbol: "arrow.up.and.down.text.horizontal", value: selectedTypography.lineSpacing,
                              decrease: { adjustTypography(lineDelta: -2) }, increase: { adjustTypography(lineDelta: 2) })
        }
        .padding(.horizontal, 20)
    }

    private var selectedTypography: ReaderTypography { storage.readerConfig.typography(for: typographyProfile) }

    private func adjustTypography(fontDelta: CGFloat = 0, lineDelta: CGFloat = 0) {
        let current = selectedTypography
        let typography = ReaderTypography(fontSize: fontDelta == 0 ? current.fontSize : min(34, max(13, current.fontSize + fontDelta)),
                                          lineSpacing: lineDelta == 0 ? current.lineSpacing : min(26, max(4, current.lineSpacing + lineDelta)))
        storage.readerConfig.setTypography(typography, for: typographyProfile)
        storage.saveConfig()
    }

    private func typographyControl(title: String, symbol: String, value: CGFloat,
                                   decrease: @escaping () -> Void, increase: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .medium))
            Spacer()
            HStack(spacing: 12) {
                Button(action: decrease) { Image(systemName: "minus").frame(width: 42, height: 36) }
                    .accessibilityLabel("减小\(title)")
                Text("\(Int(value))").font(.system(size: 16, weight: .bold)).frame(width: 30)
                Button(action: increase) { Image(systemName: "plus").frame(width: 42, height: 36) }
                    .accessibilityLabel("增大\(title)")
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var tapModeSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("点击翻页区域")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            Picker("点击翻页区域", selection: Binding(
                get: { storage.readerConfig.effectiveTapMode },
                set: { storage.readerConfig.effectiveTapMode = $0; storage.saveConfig() }
            )) {
                ForEach(ReaderTapMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(storage.readerConfig.effectiveTapMode.explanation)
                .font(.caption)
                .foregroundColor(.secondary)
            Text("用于单页和双页点击翻页；滑动翻页仍按原方向操作。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
    }
}
