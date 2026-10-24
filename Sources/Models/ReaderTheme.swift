import SwiftUI

public enum ReaderBackgroundTheme: String, CaseIterable, Codable {
    case white = "默认白"
    case sepia = "羊皮纸"
    case eyeGreen = "护眼绿"
    case darkGray = "深灰"
    case pureBlack = "纯黑"
    
    public var backgroundColor: Color {
        switch self {
        case .white:
            return Color(red: 0.98, green: 0.98, blue: 0.98)
        case .sepia:
            return Color(red: 0.94, green: 0.90, blue: 0.81)
        case .eyeGreen:
            return Color(red: 0.86, green: 0.93, blue: 0.86)
        case .darkGray:
            return Color(red: 0.18, green: 0.18, blue: 0.18)
        case .pureBlack:
            return Color.black
        }
    }
    
    public var textColor: Color {
        switch self {
        case .white, .sepia, .eyeGreen:
            return Color(red: 0.15, green: 0.15, blue: 0.15)
        case .darkGray, .pureBlack:
            return Color(red: 0.85, green: 0.85, blue: 0.85)
        }
    }
}

public struct ReaderConfig: Codable, Equatable {
    public var fontSize: CGFloat
    public var lineSpacing: CGFloat
    public var theme: ReaderBackgroundTheme
    public var isScrollMode: Bool
    
    public static let `default` = ReaderConfig(
        fontSize: 18,
        lineSpacing: 8,
        theme: .sepia,
        isScrollMode: true
    )
}
