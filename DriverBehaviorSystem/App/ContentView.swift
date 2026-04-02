import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedTab: Int = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.vBackground.ignoresSafeArea()

            // İçerik
            Group {
                switch store.appState {
                case .welcome:
                    WelcomeView()
                case .calibration:
                    CalibrationView()
                case .driving:
                    DrivingView()
                case .analytics:
                    AnalyticsView()
                }
            }

            // Tab bar — sadece welcome ve analytics'te göster
            if store.appState == .welcome || store.appState == .analytics {
                VStack(spacing: 0) {
                    Divider().background(Color.vBorder)
                    HStack(spacing: 0) {
                        TabItem(icon: "eye.fill",      label: "MONITOR",
                                selected: selectedTab == 0) {
                            selectedTab = 0
                            store.appState = .welcome
                        }
                        TabItem(icon: "bell.fill",     label: "ALERTS",
                                selected: selectedTab == 1) {
                            selectedTab = 1
                        }
                        TabItem(icon: "chart.bar.fill", label: "ANALYSIS",
                                selected: selectedTab == 2) {
                            selectedTab = 2
                            store.appState = .analytics
                        }
                    }
                    .padding(.vertical, 10)
                    .background(Color.vCard)
                }
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

// MARK: - Tab Bar Item
struct TabItem: View {
    let icon    : String
    let label   : String
    let selected: Bool
    let action  : () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.mono(8, weight: .bold))
            }
            .foregroundColor(selected ? .vGreen : Color(white: 0.5))
            .frame(maxWidth: .infinity)
        }
    }
}
