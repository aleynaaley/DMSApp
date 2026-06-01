import SwiftUI

@main
struct GozcuApp: App {
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(LocalAuthService.shared)
        }
    }
}

// MARK: - Root
struct RootView: View {
    @EnvironmentObject var auth: LocalAuthService
    @State private var showSplash = true
    var body: some View {
        Group {
            if showSplash {
                SplashView { withAnimation { showSplash = false } }
            } else if auth.currentUser == nil {
                AuthView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: auth.currentUser?.uid)
    }
}

// MARK: - Tab
struct MainTabView: View {
    @EnvironmentObject var auth: LocalAuthService
    var body: some View {
        TabView {
            DriveView().tabItem { Label("Sürüş", systemImage: "steeringwheel") }
            ReportsView().tabItem { Label("Raporlar", systemImage: "chart.bar.fill") }
            ProfileView().tabItem { Label("Profil", systemImage: "person.fill") }
        }
        .tint(GTheme.Color.primary)
    }
}

// MARK: - Profile
struct ProfileView: View {
    @EnvironmentObject var auth: LocalAuthService
    @State private var showSignOut = false
    init() {
        // Büyük (Large) başlığın rengi
        UINavigationBar.appearance().largeTitleTextAttributes = [.foregroundColor: UIColor(GTheme.Color.primary)]
        // Küçük (Inline) başlığın rengi (Sayfa yukarı kayınca)
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor(GTheme.Color.primary)]
    }
    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#F4F8FF").ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle().fill(LinearGradient(colors: [Color(hex: "#1565C0"), Color(hex: "#1E88E5")], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 80, height: 80)
                                Text(initials).font(.system(size: 28, weight: .bold)).foregroundColor(.white)
                            }
                            Text(auth.userProfile?.name ?? "Sürücü").font(.system(size: 20, weight: .bold)).foregroundColor(GTheme.Color.textPrimary)
                            Text(auth.userProfile?.email ?? "").font(.system(size: 14)).foregroundColor(GTheme.Color.textSecondary)
                        }
                        .frame(maxWidth: .infinity).gCard(padding: 24).padding(.horizontal, 20).padding(.top, 8)

                        VStack(spacing: 12) {
                            HStack { Text("Güvenlik Skoru").font(.system(size: 15, weight: .semibold)).foregroundColor(GTheme.Color.textPrimary); Spacer() }
                            ZStack {
                                Circle().stroke(Color(hex: "#E8F0FE"), lineWidth: 12).frame(width: 120, height: 120)
                                Circle().trim(from: 0, to: CGFloat(auth.overallSafetyScore)/100)
                                    .stroke(scoreColor(auth.overallSafetyScore), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                    .rotationEffect(.degrees(-90)).frame(width: 120, height: 120)
                                VStack(spacing: 0) {
                                    Text("\(auth.overallSafetyScore)").font(.system(size: 32, weight: .bold)).foregroundColor(scoreColor(auth.overallSafetyScore))
                                    Text("/ 100").font(.system(size: 12)).foregroundColor(GTheme.Color.textSecondary)
                                }
                            }
                        }.gCard().padding(.horizontal, 20)

                        HStack(spacing: 12) {
                            StatCard(icon: "car.fill", value: "\(auth.totalDrives)", label: "Toplam Sürüş", color: GTheme.Color.primary)
                            StatCard(icon: "clock.fill", value: String(format: "%.1f", auth.totalDriveHours), label: "Saat", color: GTheme.Color.safe)
                        }.padding(.horizontal, 20)

                        VStack(spacing: 0) {
                            InfoRow(icon: "envelope.fill", label: "E-posta", value: auth.userProfile?.email ?? "—")
                            Divider().padding(.horizontal, 16)
                            InfoRow(icon: "calendar", label: "Üyelik", value: auth.userProfile?.createdAt.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        }
                        .background(Color.white).cornerRadius(GTheme.Radius.card).shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2).padding(.horizontal, 20)

                        Button { showSignOut = true } label: {
                            HStack { Image(systemName: "rectangle.portrait.and.arrow.right"); Text("Çıkış Yap") }
                                .font(.system(size: 15, weight: .medium)).foregroundColor(GTheme.Color.danger)
                                .frame(maxWidth: .infinity).frame(height: 52).background(GTheme.Color.danger.opacity(0.08)).cornerRadius(GTheme.Radius.medium)
                        }.padding(.horizontal, 20).padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Profil").navigationBarTitleDisplayMode(.large)
            .confirmationDialog("Çıkış Yap", isPresented: $showSignOut) {
                Button("Çıkış Yap", role: .destructive) { auth.signOut() }
            } message: { Text("Hesabından çıkmak istediğine emin misin?") }
                
        }
    }
    private var initials: String {
        let n = auth.userProfile?.name ?? "?"
        return n.split(separator: " ").prefix(2).compactMap { $0.first }.map { String($0) }.joined().uppercased()
    }
}

private struct StatCard: View {
    let icon, value, label: String; let color: Color
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 22)).foregroundColor(color)
            Text(value).font(.system(size: 22, weight: .bold)).foregroundColor(GTheme.Color.textPrimary)
            Text(label).font(.system(size: 12)).foregroundColor(GTheme.Color.textSecondary)
        }.frame(maxWidth: .infinity).gCard()
    }
}

private struct InfoRow: View {
    let icon, label, value: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 15)).foregroundColor(GTheme.Color.primary).frame(width: 24)
            Text(label).font(.system(size: 14)).foregroundColor(GTheme.Color.textSecondary)
            Spacer()
            Text(value).font(.system(size: 14, weight: .medium)).foregroundColor(GTheme.Color.textPrimary).lineLimit(1)
        }.padding(.horizontal, 16).padding(.vertical, 14)
    }
}
