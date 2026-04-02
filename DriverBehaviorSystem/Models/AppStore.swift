import SwiftUI
import Combine

@MainActor
class AppStore: ObservableObject {
    @Published var currentProfile : UserProfile      = UserProfile.demo
    @Published var profiles       : [UserProfile]    = [UserProfile.demo]
    @Published var sessions       : [DrivingSession] = DrivingSession.samples
    @Published var appState       : AppState         = .welcome

    enum AppState { case welcome, calibration, driving, analytics }

    func addProfile(_ p: UserProfile) {
        profiles.append(p)
        saveProfiles()
    }

    func deleteProfile(id: UUID) {
        profiles.removeAll { $0.id == id }
        if currentProfile.id == id {
            currentProfile = profiles.first ?? .demo
        }
        saveProfiles()
    }

    func selectProfile(_ p: UserProfile) {
        currentProfile = p
        UserDefaults.standard.set(p.id.uuidString, forKey: "selectedProfileId")
    }

    func stopDriving(session: DrivingSession) {
        sessions.insert(session, at: 0)
        appState = .welcome
    }

    private func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: "profiles")
        }
    }

    func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: "profiles"),
              let arr  = try? JSONDecoder().decode([UserProfile].self, from: data)
        else { return }
        profiles = arr
        if let sid = UserDefaults.standard.string(forKey: "selectedProfileId"),
           let p   = arr.first(where: { $0.id.uuidString == sid }) {
            currentProfile = p
        }
    }
}
