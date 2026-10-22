import SwiftUI

/// Lotto3u 色系(2026-10-22 John 指定:背景石板藍、淡面板、深石板主鍵)
enum Theme {
    static let bg      = Color(hex: 0x6E7F8D)
    static let bgSoft  = Color(hex: 0x5C6B78)
    static let bgTop   = Color(hex: 0x7C8D9A)
    static let panel   = Color(hex: 0xE1EBF1)
    static let panel2  = Color(hex: 0xCED9E1)
    static let ink     = Color(hex: 0x161B1D)
    static let sub     = Color(hex: 0x3B454E)
    static let muted   = Color(hex: 0x4D5761)
    static let accent  = Color(hex: 0x3F4A54)
    static let accentHi = Color(hex: 0x4A5560)
    static let warn    = Color(hex: 0xFF6B5A)
    static let radius: CGFloat = 18

    /// Avenir Next(iOS 內建,等同 Lotto3u 的第二順位字體)
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .black, .heavy, .bold: name = "AvenirNext-Bold"
        case .semibold: name = "AvenirNext-DemiBold"
        case .medium: name = "AvenirNext-Medium"
        default: name = "AvenirNext-Regular"
        }
        return .custom(name, size: size)
    }

    static var background: some View {
        LinearGradient(colors: [bgTop, bg, bgSoft], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
