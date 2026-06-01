import SwiftUI

enum GTheme {
    enum Color {
        static let primary      = SwiftUI.Color(hex: "#1565C0")
        static let primaryLight = SwiftUI.Color(hex: "#1E88E5")
        static let accent       = SwiftUI.Color(hex: "#82B1FF")
        static let background    = SwiftUI.Color(hex: "#F4F8FF")
        static let driveBackground = SwiftUI.Color(hex: "#060D1A")
        static let cardBackground = SwiftUI.Color.white
        static let cardDark      = SwiftUI.Color(hex: "#0D1929")
        static let safe    = SwiftUI.Color(hex: "#00C853")
        static let warning = SwiftUI.Color(hex: "#FFD600")
        static let danger  = SwiftUI.Color(hex: "#FF1744")
        static let textPrimary   = SwiftUI.Color(hex: "#0A1628")
        static let textSecondary = SwiftUI.Color(hex: "#546E8A")
    }

    static func color(for level: AlertLevel) -> SwiftUI.Color {
        switch level {
        case .safe:    return Color.safe
        case .warning: return Color.warning
        case .danger:  return Color.danger
        }
    }

    enum Radius {
        static let small: CGFloat  = 8
        static let medium: CGFloat = 14
        static let large: CGFloat  = 22
        static let card: CGFloat   = 18
    }
}

extension View {
    func gCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(GTheme.Color.cardBackground)
            .cornerRadius(GTheme.Radius.card)
            .shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}
