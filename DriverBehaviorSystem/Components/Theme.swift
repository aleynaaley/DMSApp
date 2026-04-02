// ── Components/Theme.swift ──────────────────────────────────
import SwiftUI

extension Color {
    static let vGreen      = Color(red: 0.00, green: 0.93, blue: 0.58)
    static let vBackground = Color(red: 0.05, green: 0.07, blue: 0.06)
    static let vCard       = Color(red: 0.08, green: 0.11, blue: 0.09)
    static let vBorder     = Color(red: 0.15, green: 0.20, blue: 0.16)
}
extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.vCard)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.vBorder, lineWidth: 1))
    }
}
extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}
