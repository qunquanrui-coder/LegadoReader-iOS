import SwiftUI

public struct ReaderSettingsSheet: View {
    @ObservedObject var storage = StorageManager.shared
    @State private var newPurifyWord = ""
    
    public init() {}
    
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
                                Text("iPhone Duo 展开内屏自动双页对开")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("合上 5.4\" 外屏单页阅读，展开 7.6\" 内屏自动切换实体书左右双页")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
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
                
                // 4. Font Size & Line Spacing
                VStack(spacing: 14) {
                    HStack {
                        Label("字号大小", systemImage: "textformat.size")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        HStack(spacing: 16) {
                            Button {
                                if storage.readerConfig.fontSize > 13 {
                                    storage.readerConfig.fontSize -= 1
                                    storage.saveConfig()
                                }
                            } label: {
                                Text("A-")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 48, height: 36)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            Text("\(Int(storage.readerConfig.fontSize))")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 32)
                            
                            Button {
                                if storage.readerConfig.fontSize < 34 {
                                    storage.readerConfig.fontSize += 1
                                    storage.saveConfig()
                                }
                            } label: {
                                Text("A+")
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 48, height: 36)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    
                    HStack {
                        Label("段落行距", systemImage: "arrow.up.and.down.text.horizontal")
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        HStack(spacing: 16) {
                            Button {
                                if storage.readerConfig.lineSpacing > 4 {
                                    storage.readerConfig.lineSpacing -= 2
                                    storage.saveConfig()
                                }
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 48, height: 36)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            Text("\(Int(storage.readerConfig.lineSpacing))")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 32)
                            
                            Button {
                                if storage.readerConfig.lineSpacing < 26 {
                                    storage.readerConfig.lineSpacing += 2
                                    storage.saveConfig()
                                }
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 48, height: 36)
                                    .background(Color(.secondarySystemGroupedBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                
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
}
