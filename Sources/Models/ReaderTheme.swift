import SwiftUI

public enum ReaderBackgroundTheme: String, CaseIterable, Codable {
    case sepia = "羊皮卷"
    case white = "宣纸白"
    case eyeGreen = "竹林绿"
    case blossom = "樱花粉"
    case darkGray = "暮光灰"
    case pureBlack = "曜石黑"
    
    public var backgroundColor: Color {
        switch self {
        case .sepia:
            return Color(red: 0.95, green: 0.91, blue: 0.84)
        case .white:
            return Color(red: 0.98, green: 0.975, blue: 0.96)
        case .eyeGreen:
            return Color(red: 0.87, green: 0.93, blue: 0.88)
        case .blossom:
            return Color(red: 0.97, green: 0.92, blue: 0.925)
        case .darkGray:
            return Color(red: 0.12, green: 0.13, blue: 0.15)
        case .pureBlack:
            return Color.black
        }
    }
    
    public var textColor: Color {
        switch self {
        case .sepia:
            return Color(red: 0.18, green: 0.14, blue: 0.11)
        case .white:
            return Color(red: 0.12, green: 0.12, blue: 0.13)
        case .eyeGreen:
            return Color(red: 0.11, green: 0.18, blue: 0.13)
        case .blossom:
            return Color(red: 0.22, green: 0.13, blue: 0.14)
        case .darkGray:
            return Color(red: 0.78, green: 0.80, blue: 0.84)
        case .pureBlack:
            return Color(red: 0.65, green: 0.65, blue: 0.68)
        }
    }
    
    public var isDark: Bool {
        self == .darkGray || self == .pureBlack
    }
}

public enum ReaderFontDesign: String, CaseIterable, Codable {
    case serif = "书宋衬线"
    case system = "系统黑体"
    case rounded = "温润圆体"
    
    public var swiftUIDesign: Font.Design {
        switch self {
        case .serif: return .serif
        case .system: return .default
        case .rounded: return .rounded
        }
    }
}

public enum ReaderPageTurnMode: String, CaseIterable, Codable {
    case verticalScroll = "上下滚动"
    case horizontalSlide = "左右翻页"
    case duoSpread = "Duo 双页书本"
}

public enum ChineseConversionMode: String, CaseIterable, Codable {
    case original = "原文"
    case toSimplified = "繁转简"
    case toTraditional = "简转繁"
    
    public func convert(_ text: String) -> String {
        switch self {
        case .original:
            return text
        case .toSimplified:
            return text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        case .toTraditional:
            return text.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? text
        }
    }
}

public struct ReaderConfig: Codable, Equatable {
    public var fontSize: CGFloat
    public var lineSpacing: CGFloat
    public var theme: ReaderBackgroundTheme
    public var fontDesign: ReaderFontDesign
    public var pageTurnMode: ReaderPageTurnMode?
    public var chineseConversion: ChineseConversionMode?
    public var customPurifyRules: [String]?
    public var autoDuoBookSpread: Bool?
    
    public static var isDuoEditionBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "IS_IPHONE_DUO_EDITION") as? Bool) ?? false
    }
    
    public var effectivePageTurnMode: ReaderPageTurnMode {
        get { pageTurnMode ?? .verticalScroll }
        set { pageTurnMode = newValue }
    }
    
    public var effectiveAutoDuoSpread: Bool {
        get { autoDuoBookSpread ?? Self.isDuoEditionBuild }
        set { autoDuoBookSpread = newValue }
    }
    
    public var effectiveChineseConversion: ChineseConversionMode {
        get { chineseConversion ?? .original }
        set { chineseConversion = newValue }
    }
    
    public var effectivePurifyRules: [String] {
        get { customPurifyRules ?? [] }
        set { customPurifyRules = newValue }
    }
    
    public static let `default` = ReaderConfig(
        fontSize: 19,
        lineSpacing: 10,
        theme: .sepia,
        fontDesign: .serif,
        pageTurnMode: .verticalScroll,
        chineseConversion: .original,
        customPurifyRules: [],
        autoDuoBookSpread: true
    )
}

// MARK: - Artistic 3D Book Cover Component
public struct BookCoverView: View {
    public let title: String
    public let author: String
    public let coverUrl: String?
    public var width: CGFloat? = nil
    public var height: CGFloat? = nil
    public var cornerRadius: CGFloat = 8
    
    public init(title: String, author: String, coverUrl: String?, width: CGFloat? = nil, height: CGFloat? = nil, cornerRadius: CGFloat = 8) {
        self.title = title
        self.author = author
        self.coverUrl = coverUrl
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.18, green: 0.25, blue: 0.38), Color(red: 0.10, green: 0.14, blue: 0.24)], // 黛蓝
            [Color(red: 0.48, green: 0.19, blue: 0.20), Color(red: 0.28, green: 0.10, blue: 0.12)], // 胭脂红
            [Color(red: 0.18, green: 0.34, blue: 0.29), Color(red: 0.10, green: 0.20, blue: 0.17)], // 松石绿
            [Color(red: 0.38, green: 0.27, blue: 0.20), Color(red: 0.22, green: 0.15, blue: 0.11)], // 檀木棕
            [Color(red: 0.29, green: 0.22, blue: 0.42), Color(red: 0.16, green: 0.12, blue: 0.26)], // 暮山紫
            [Color(red: 0.22, green: 0.31, blue: 0.35), Color(red: 0.12, green: 0.18, blue: 0.22)]  // 苍青
        ]
        let hash = abs(title.hashValue)
        return palettes[hash % palettes.count]
    }
    
    public var body: some View {
        ZStack {
            if let coverUrl = coverUrl,
               !coverUrl.isEmpty,
               let url = URL(string: coverUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    default:
                        artisticFallbackCover
                    }
                }
            } else {
                artisticFallbackCover
            }
            
            // Realistic Book Spine Crease & Inner Highlight Overlay
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.25),
                        Color.black.opacity(0.22),
                        Color.white.opacity(0.12),
                        Color.clear
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 10)
                Spacer()
            }
        }
        .frame(width: width, height: height)
        .aspectRatio(width == nil ? 0.72 : nil, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 4)
    }
    
    private var artisticFallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Subtle inner vintage frame
            RoundedRectangle(cornerRadius: max(4, cornerRadius - 3))
                .stroke(Color(red: 0.88, green: 0.78, blue: 0.62).opacity(0.35), lineWidth: 1)
                .padding(6)
            
            VStack(spacing: 6) {
                // Classic white/cream book plate
                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: (width ?? 100) < 75 ? 11 : 13, weight: .bold, design: .serif))
                        .foregroundColor(Color(red: 0.16, green: 0.14, blue: 0.12))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(red: 0.96, green: 0.94, blue: 0.89))
                        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                )
                .padding(.horizontal, 10)
                .padding(.top, 12)
                
                Spacer()
                
                Text(author)
                    .font(.system(size: 9, weight: .medium, design: .serif))
                    .foregroundColor(Color(red: 0.92, green: 0.85, blue: 0.72).opacity(0.9))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
            }
        }
    }
}
