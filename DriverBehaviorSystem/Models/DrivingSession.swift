import SwiftUI

struct DrivingSession: Identifiable, Codable {
    var id           = UUID()
    var name         : String
    var date         : Date
    var duration     : TimeInterval
    var safetyScore  : Int
    var alertCount   : Int
    var yawnCount    : Int
    var microsleeps  : Int

    var durationString: String {
        let h = Int(duration) / 3600
        let m = Int(duration) % 3600 / 60
        return String(format: "%dh %02dm", h, m)
    }

    var scoreColor: Color {
        switch safetyScore {
        case 85...100: return .vGreen
        case 60...84:  return .yellow
        default:       return .red
        }
    }

    var scoreIcon: String {
        switch safetyScore {
        case 85...100: return "road.lanes"
        case 60...84:  return "moon.fill"
        default:       return "building.2"
        }
    }

    static let samples: [DrivingSession] = [
        DrivingSession(
            name: "Highway Commute",
            date: Date().addingTimeInterval(-86400),
            duration: 6312, safetyScore: 98,
            alertCount: 0, yawnCount: 2, microsleeps: 0
        ),
        DrivingSession(
            name: "Night Freight Route",
            date: Date().addingTimeInterval(-259200),
            duration: 14832, safetyScore: 94,
            alertCount: 1, yawnCount: 6, microsleeps: 0
        ),
        DrivingSession(
            name: "City Transit Pulse",
            date: Date().addingTimeInterval(-604800),
            duration: 3480, safetyScore: 82,
            alertCount: 3, yawnCount: 11, microsleeps: 1
        ),
    ]
}
