import SwiftUI
import UIKit

/// Oriental Xuan-Paper & Gilded-Ink Design System (东方宣纸金墨视觉系统)
/// Adapts seamlessly between warm rice-paper Light Mode and deep obsidian-ink Dark Mode.
public enum AppPalette {
    /// Warm Xuan-paper canvas in Light Mode, deep obsidian-ink in Dark Mode.
    public static let canvasBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.082, green: 0.088, blue: 0.112, alpha: 1.0)
            : UIColor(red: 0.966, green: 0.957, blue: 0.938, alpha: 1.0)
    })
    
    /// Elevated ivory card surface in Light Mode, slate-ink card in Dark Mode.
    public static let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.132, green: 0.140, blue: 0.172, alpha: 1.0)
            : UIColor(red: 0.996, green: 0.993, blue: 0.986, alpha: 1.0)
    })
    
    /// Subtle warm tinted surface for chips, inputs, and secondary pills.
    public static let subtleSurface = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.175, green: 0.184, blue: 0.222, alpha: 1.0)
            : UIColor(red: 0.942, green: 0.930, blue: 0.906, alpha: 1.0)
    })
    
    /// Hairline border for editorial cards.
    public static let cardBorder = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.85, green: 0.82, blue: 0.74, alpha: 0.12)
            : UIColor(red: 0.42, green: 0.34, blue: 0.24, alpha: 0.11)
    })
    
    /// Primary ink indigo accent (黛青靛蓝).
    public static let inkAccent = Color(red: 0.31, green: 0.30, blue: 0.74)
    /// Royal plum companion for gradients (烟紫).
    public static let plumAccent = Color(red: 0.48, green: 0.29, blue: 0.68)
    /// Cinnabar seal vermilion (朱砂印红).
    public static let vermilion = Color(red: 0.82, green: 0.27, blue: 0.22)
    /// Gilded gold amber (描金琥珀).
    public static let gildedAmber = Color(red: 0.84, green: 0.56, blue: 0.16)
    /// Celadon jade green (青瓷翠绿).
    public static let celadon = Color(red: 0.13, green: 0.56, blue: 0.47)
    
    public static var primaryGradient: LinearGradient {
        LinearGradient(
            colors: [inkAccent, plumAccent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    public static var warmGoldGradient: LinearGradient {
        LinearGradient(
            colors: [gildedAmber, vermilion],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// Soft atmospheric radial glow behind navigation headers for editorial depth.
public struct AppAmbientBackdrop: View {
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .top) {
            AppPalette.canvasBackground
            
            LinearGradient(
                colors: [
                    AppPalette.inkAccent.opacity(0.08),
                    AppPalette.gildedAmber.opacity(0.045),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: 260)
            .ignoresSafeArea(edges: .top)
        }
        .ignoresSafeArea()
    }
}
