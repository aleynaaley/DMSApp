import Foundation

// MARK: - Alert Level
enum AlertLevel: Int, Codable, Comparable {
    case safe    = 0
    case warning = 1
    case danger  = 2

    static func < (lhs: AlertLevel, rhs: AlertLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .safe:    return "GÜVENLİ"
        case .warning: return "DİKKAT"
        case .danger:  return "TEHLİKE"
        }
    }

    var emoji: String {
        switch self {
        case .safe:    return "✓"
        case .warning: return "⚠"
        case .danger:  return "!"
        }
    }
}

// MARK: - Driving Session
struct DrivingSession: Identifiable, Codable {
    var id: String = UUID().uuidString
    var userId: String
    var startTime: Date
    var endTime: Date?
    var durationSeconds: Double
    var dangerCount: Int
    var warningCount: Int
    var maxPerclos: Double
    var yawnEpisodes: Int
    var safePercent: Double
    var warningPercent: Double
    var dangerPercent: Double
    var alertEvents: [AlertEvent]
    var notes: String?
}

// MARK: - Alert Event
struct AlertEvent: Identifiable, Codable {
    var id: String = UUID().uuidString
    var timestamp: Date
    var level: AlertLevel
    var perclos: Double
    var reason: String
}

// MARK: - User Profile
struct UserProfile: Codable {
    var uid: String
    var name: String
    var email: String
    var blinkBaseline: Double?   // kalibrasyon için (ileride)
    var createdAt: Date
}

// MARK: - Detection State (UI'ya gönderilir)
struct DetectionState {
    var alertLevel: AlertLevel = .safe
    var perclos: Double        = 0
    var yawnCount: Int         = 0
    var eyeClosed: Bool        = false
    var closedDuration: Double = 0
    var msLevel: Int           = 0   // 0=normal, 1=hafif, 2=ciddi
    var faceDetected: Bool     = false
    var isAlarmActive: Bool    = false
    var blinkScore: Double     = 0
    var smoothYawn: Double     = 0
}

// MARK: - User (auth)
struct User: Codable {
    let uid: String
    let email: String
}
