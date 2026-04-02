
import SwiftUI

struct UserProfile: Identifiable, Codable {
    var id            = UUID()
    var name          : String
    var riskLevel     : RiskLevel
    var restHours     : Double
    var totalSessions : Int
    var avgSafetyScore: Int

    enum RiskLevel: String, CaseIterable, Codable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"

        var color: Color {
            switch self {
            case .low:
                return Color.vGreen
            case .medium:
                return .yellow
            case .high:
                return .red
            }
        }
    }

    static let demo = UserProfile(
        name: "Aley",
        riskLevel: .low,
        restHours: 8.4,
        totalSessions: 47,
        avgSafetyScore: 94
    )
}
