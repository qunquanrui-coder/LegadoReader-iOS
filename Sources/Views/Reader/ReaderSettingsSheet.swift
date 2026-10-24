import SwiftUI

public struct ReaderSettingsSheet: View {
    @ObservedObject var storage = StorageManager.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
            
            // 1. Themes
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
                                            .frame(width: 46, height: 46)
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
            
            // 2. Font Design
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
            
            // 3. Font Size & Line Spacing
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
            
            Spacer()
        }
        .presentationDetents([.height(380)])
    }
}
