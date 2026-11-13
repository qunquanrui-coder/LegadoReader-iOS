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

public enum ReaderViewportProfile: String, Codable, CaseIterable {
    case compact, wide

    public var title: String { self == .compact ? "窄窗口" : "宽窗口" }
}

public struct ReaderTypography: Codable, Equatable {
    public var fontSize: CGFloat
    public var lineSpacing: CGFloat

    public init(fontSize: CGFloat, lineSpacing: CGFloat) {
        self.fontSize = fontSize.isFinite ? min(80, max(8, fontSize)) : 19
        self.lineSpacing = lineSpacing.isFinite ? min(80, max(0, lineSpacing)) : 10
    }
}

public enum ReaderPageTapRegion: Equatable {
    case backward, center, forward
}

public enum ReaderTapMode: String, Codable, CaseIterable {
    case balanced, rightHanded, leftHanded

    public var title: String {
        switch self {
        case .balanced: return "均衡"
        case .rightHanded: return "右手"
        case .leftHanded: return "左手"
        }
    }

    public var explanation: String {
        switch self {
        case .balanced: return "左侧上一页，中间菜单，右侧下一页"
        case .rightHanded: return "左侧 15% 上一页、其后 20% 菜单，右侧 65% 下一页"
        case .leftHanded: return "左侧 65% 下一页、其后 20% 菜单，右侧 15% 上一页"
        }
    }

    /// Fractions refer to the whole reading area, including both pages in a spread.
    public func region(at fraction: CGFloat) -> ReaderPageTapRegion {
        guard fraction.isFinite else { return .center }
        let x = min(1, max(0, fraction))
        switch self {
        case .balanced:
            return x < 1.0 / 3 ? .backward : (x > 2.0 / 3 ? .forward : .center)
        case .rightHanded:
            return x < 0.15 ? .backward : (x < 0.35 ? .center : .forward)
        case .leftHanded:
            return x < 0.65 ? .forward : (x < 0.85 ? .center : .backward)
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
    public var showDuoSpine: Bool? = nil
    public var compactTypography: ReaderTypography? = nil
    public var wideTypography: ReaderTypography? = nil
    public var tapMode: ReaderTapMode? = nil

    public func typography(for profile: ReaderViewportProfile) -> ReaderTypography {
        let saved = profile == .compact ? compactTypography : wideTypography
        return ReaderTypography(fontSize: saved?.fontSize ?? fontSize,
                                lineSpacing: saved?.lineSpacing ?? lineSpacing)
    }

    public mutating func setTypography(_ typography: ReaderTypography, for profile: ReaderViewportProfile) {
        let normalized = ReaderTypography(fontSize: typography.fontSize, lineSpacing: typography.lineSpacing)
        if profile == .compact { compactTypography = normalized }
        else { wideTypography = normalized }
    }

    public func applyingTypography(for profile: ReaderViewportProfile) -> ReaderConfig {
        var copy = self
        let selected = typography(for: profile)
        copy.fontSize = selected.fontSize
        copy.lineSpacing = selected.lineSpacing
        return copy
    }

    public var effectiveTapMode: ReaderTapMode {
        get { tapMode ?? .balanced }
        set { tapMode = newValue }
    }
    
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
    
    public var effectiveShowDuoSpine: Bool {
        get { showDuoSpine ?? false }
        set { showDuoSpine = newValue }
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
    public var badgeText: String? = nil
    
    public init(
        title: String,
        author: String,
        coverUrl: String?,
        width: CGFloat? = nil,
        height: CGFloat? = nil,
        cornerRadius: CGFloat = 8,
        badgeText: String? = nil
    ) {
        self.title = title
        self.author = author
        self.coverUrl = coverUrl
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.badgeText = badgeText
    }
    
    private var palette: [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.16, green: 0.24, blue: 0.37), Color(red: 0.09, green: 0.13, blue: 0.22)], // 黛蓝织锦
            [Color(red: 0.49, green: 0.18, blue: 0.20), Color(red: 0.27, green: 0.09, blue: 0.11)], // 朱砂胭脂
            [Color(red: 0.16, green: 0.33, blue: 0.28), Color(red: 0.09, green: 0.19, blue: 0.16)], // 苍松翠竹
            [Color(red: 0.39, green: 0.27, blue: 0.19), Color(red: 0.21, green: 0.14, blue: 0.10)], // 沉香紫檀
            [Color(red: 0.28, green: 0.21, blue: 0.41), Color(red: 0.15, green: 0.11, blue: 0.25)], // 暮山烟紫
            [Color(red: 0.20, green: 0.30, blue: 0.35), Color(red: 0.11, green: 0.17, blue: 0.21)]  // 天青汝釉
        ]
        let hash = abs(title.hashValue)
        return palettes[hash % palettes.count]
    }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
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
                                .transition(.opacity.animation(.easeOut(duration: 0.2)))
                        default:
                            artisticFallbackCover
                        }
                    }
                } else {
                    artisticFallbackCover
                }
                
                // Realistic Book Spine Crease & Silk Sheen Overlay
                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.black.opacity(0.26),
                            Color.white.opacity(0.14),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 11)
                    Spacer()
                }
                
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear,
                        Color.black.opacity(0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .allowsHitTesting(false)
            }
            
            if let badgeText, !badgeText.isEmpty {
                Text(badgeText)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(Color(red: 0.98, green: 0.94, blue: 0.85))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.66))
                            .overlay(
                                Capsule()
                                    .stroke(Color(red: 0.90, green: 0.78, blue: 0.56).opacity(0.45), lineWidth: 0.6)
                            )
                    )
                    .padding(5)
            }
        }
        .frame(width: width, height: height)
        .aspectRatio(width == nil ? 0.72 : nil, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color(red: 0.88, green: 0.78, blue: 0.60).opacity(0.22),
                            Color.black.opacity(0.20)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
        .shadow(color: Color.black.opacity(0.20), radius: 7, x: 0, y: 4)
    }
    
    private var isCompactCover: Bool {
        (width ?? 100) < 75
    }
    
    private var artisticFallbackCover: some View {
        ZStack {
            LinearGradient(
                colors: palette,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Traditional Thread-Bound Binding Marks on Left Spine
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { _ in
                        Spacer()
                        Rectangle()
                            .fill(Color(red: 0.90, green: 0.82, blue: 0.68).opacity(0.26))
                            .frame(width: 6, height: 1)
                    }
                    Spacer()
                }
                .frame(width: 8)
                Spacer()
            }
            
            // Subtle Double Gold-Leaf Inner Frame (描金内框)
            RoundedRectangle(cornerRadius: max(4, cornerRadius - 3))
                .stroke(Color(red: 0.90, green: 0.80, blue: 0.62).opacity(0.38), lineWidth: 0.9)
                .padding(5)
            
            VStack(spacing: 5) {
                // Classic Xuan-Paper Bookplate (宣纸藏书签)
                VStack(spacing: 3) {
                    Rectangle()
                        .fill(Color(red: 0.72, green: 0.24, blue: 0.20).opacity(0.65))
                        .frame(width: isCompactCover ? 16 : 24, height: 1.2)
                        .padding(.top, 5)
                    
                    Text(title)
                        .font(.system(size: isCompactCover ? 10.5 : 13, weight: .bold, design: .serif))
                        .foregroundColor(Color(red: 0.15, green: 0.13, blue: 0.11))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .padding(.horizontal, 5)
                        .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.98, green: 0.96, blue: 0.91),
                                    Color(red: 0.94, green: 0.90, blue: 0.83)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                                .stroke(Color(red: 0.76, green: 0.64, blue: 0.48).opacity(0.45), lineWidth: 0.6)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 2.5, x: 0, y: 1.5)
                )
                .padding(.horizontal, isCompactCover ? 8 : 10)
                .padding(.top, isCompactCover ? 9 : 12)
                
                Spacer()
                
                Text(author.isEmpty ? "风读典藏" : author)
                    .font(.system(size: isCompactCover ? 8.5 : 9.5, weight: .medium, design: .serif))
                    .foregroundColor(Color(red: 0.93, green: 0.86, blue: 0.73).opacity(0.92))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.bottom, isCompactCover ? 7 : 10)
            }
        }
    }
}
