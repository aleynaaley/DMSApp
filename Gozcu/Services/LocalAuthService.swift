import Foundation
import Combine

@MainActor
final class LocalAuthService: ObservableObject {

    static let shared = LocalAuthService()

    @Published var currentUser: User?
    @Published var userProfile: UserProfile?
    @Published var drivingSessions: [DrivingSession] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let fm = FileManager.default
    private lazy var docsURL = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
        loadCurrentUser()
    }

    // MARK: - Auth
    func signUp(name: String, email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        if defaults.value(forKey: "user_\(email)_pwd") != nil {
            errorMessage = "Bu e-posta zaten kayıtlı."
            throw NSError(domain: "auth", code: -1)
        }
        defaults.set(hash(password), forKey: "user_\(email)_pwd")

        let profile = UserProfile(uid: UUID().uuidString, name: name, email: email, createdAt: Date())
        try saveProfile(profile)
        setCurrent(profile)
        errorMessage = nil
    }

    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        guard let stored = defaults.value(forKey: "user_\(email)_pwd") as? String,
              stored == hash(password) else {
            errorMessage = "E-posta veya şifre hatalı."
            throw NSError(domain: "auth", code: -1)
        }
        let profile = try loadProfile(email: email)
        setCurrent(profile)
        try loadSessions(uid: profile.uid)
        errorMessage = nil
    }

    func signOut() {
        defaults.removeObject(forKey: "current_uid")
        defaults.removeObject(forKey: "current_email")
        currentUser = nil
        userProfile = nil
        drivingSessions = []
    }

    private func setCurrent(_ profile: UserProfile) {
        currentUser = User(uid: profile.uid, email: profile.email)
        userProfile = profile
        defaults.set(profile.uid, forKey: "current_uid")
        defaults.set(profile.email, forKey: "current_email")
    }

    private func loadCurrentUser() {
        guard let uid = defaults.string(forKey: "current_uid"),
              let email = defaults.string(forKey: "current_email") else { return }
        currentUser = User(uid: uid, email: email)
        do {
            userProfile = try loadProfile(email: email)
            try loadSessions(uid: uid)
        } catch {
            print("Profil yüklenemedi: \(error)")
        }
    }

    // MARK: - Profile
    private func saveProfile(_ p: UserProfile) throws {
        let data = try JSONEncoder().encode(p)
        try data.write(to: docsURL.appendingPathComponent("profile_\(p.uid).json"))
    }

    private func loadProfile(email: String) throws -> UserProfile {
        let files = try fm.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
        for f in files where f.lastPathComponent.hasPrefix("profile_") {
            let data = try Data(contentsOf: f)
            let p = try JSONDecoder().decode(UserProfile.self, from: data)
            if p.email == email { return p }
        }
        throw NSError(domain: "auth", code: 404)
    }

    func updateBlinkBaseline(_ baseline: Double) {
        guard var p = userProfile else { return }
        p.blinkBaseline = baseline
        userProfile = p
        try? saveProfile(p)
    }

    // MARK: - Sessions
    func saveDrivingSession(_ session: DrivingSession) async {
        guard let uid = userProfile?.uid else { return }
        var s = session
        s.userId = uid
        do {
            let data = try JSONEncoder().encode(s)
            try data.write(to: docsURL.appendingPathComponent("session_\(uid)_\(s.id).json"))
            drivingSessions.insert(s, at: 0)
        } catch {
            errorMessage = "Sürüş kaydedilemedi."
        }
    }

    private func loadSessions(uid: String) throws {
        let files = try fm.contentsOfDirectory(at: docsURL, includingPropertiesForKeys: nil)
        var sessions: [DrivingSession] = []
        for f in files where f.lastPathComponent.hasPrefix("session_\(uid)_") {
            let data = try Data(contentsOf: f)
            sessions.append(try JSONDecoder().decode(DrivingSession.self, from: data))
        }
        drivingSessions = sessions.sorted { $0.startTime > $1.startTime }
    }

    // MARK: - Stats
    var totalDrives: Int { drivingSessions.count }
    var totalDriveHours: Double { drivingSessions.reduce(0) { $0 + $1.durationSeconds } / 3600 }
    var averageDangerPercent: Double {
        guard !drivingSessions.isEmpty else { return 0 }
        return drivingSessions.reduce(0) { $0 + $1.dangerPercent } / Double(drivingSessions.count)
    }
    var overallSafetyScore: Int {
        let avgW = drivingSessions.isEmpty ? 0 :
            drivingSessions.reduce(0) { $0 + $1.warningPercent } / Double(drivingSessions.count)
        return max(0, min(100, Int(100 - averageDangerPercent - avgW * 0.3)))
    }

    // MARK: - Helper
    private func hash(_ s: String) -> String {
        (s.data(using: .utf8) ?? Data()).map { String(format: "%02x", $0) }.joined()
    }
}
