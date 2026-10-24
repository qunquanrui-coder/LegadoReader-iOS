import SwiftUI

public struct ReaderSettingsSheet: View {
    @ObservedObject var storage = StorageManager.shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 20) {
            Text("阅读设置")
                .font(.headline)
                .padding(.top, 16)
            
            // Themes
            VStack(alignment: .leading, spacing: 8) {
                Text("主题背景")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 12) {
                    ForEach(ReaderBackgroundTheme.allCases, id: \.self) { theme in
                        Button {
                            storage.readerConfig.theme = theme
                            storage.saveConfig()
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(theme.backgroundColor)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .stroke(storage.readerConfig.theme == theme ? Color.blue : Color.gray.opacity(0.3), lineWidth: storage.readerConfig.theme == theme ? 3 : 1)
                                    )
                                Text(theme.rawValue)
                                    .font(.system(size: 10))
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Font Size
            HStack {
                Text("字号")
                    .font(.subheadline)
                Spacer()
                Button {
                    if storage.readerConfig.fontSize > 12 {
                        storage.readerConfig.fontSize -= 1
                        storage.saveConfig()
                    }
                } label: {
                    Image(systemName: "textformat.size.smaller")
                        .padding(10)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }
                
                Text("\(Int(storage.readerConfig.fontSize))")
                    .font(.headline)
                    .frame(width: 40)
                
                Button {
                    if storage.readerConfig.fontSize < 36 {
                        storage.readerConfig.fontSize += 1
                        storage.saveConfig()
                    }
                } label: {
                    Image(systemName: "textformat.size.larger")
                        .padding(10)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            
            // Line Spacing
            HStack {
                Text("行距")
                    .font(.subheadline)
                Spacer()
                Button {
                    if storage.readerConfig.lineSpacing > 4 {
                        storage.readerConfig.lineSpacing -= 2
                        storage.saveConfig()
                    }
                } label: {
                    Image(systemName: "minus")
                        .padding(10)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }
                
                Text("\(Int(storage.readerConfig.lineSpacing))")
                    .font(.headline)
                    .frame(width: 40)
                
                Button {
                    if storage.readerConfig.lineSpacing < 24 {
                        storage.readerConfig.lineSpacing += 2
                        storage.saveConfig()
                    }
                } label: {
                    Image(systemName: "plus")
                        .padding(10)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .presentationDetents([.height(320)])
    }
}
