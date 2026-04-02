import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showProfileSheet = false
    @State private var showAddProfile   = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("VIGILANCE")
                    .font(.mono(16, weight: .bold))
                    .foregroundColor(Color.vGreen)
                Spacer()
                HStack(spacing: 6) {
                    Circle().fill(Color.vGreen).frame(width: 7, height: 7)
                    Text("SAFE MODE ACTIVE")
                        .font(.mono(9, weight: .bold))
                        .foregroundColor(Color.vGreen)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.vGreen.opacity(0.12))
                .cornerRadius(20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            Spacer()

            // Avatar
            ZStack {
                Circle()
                    .fill(Color.vCard)
                    .frame(width: 110, height: 110)
                    .overlay(Circle().stroke(Color.vBorder, lineWidth: 1))
                Image(systemName: "person.fill")
                    .font(.system(size: 50))
                    .foregroundColor(Color(white: 0.4))
            }
            .padding(.bottom, 24)

            // Greeting
            VStack(spacing: 6) {
                Text("Welcome back,")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                Text(store.currentProfile.name)
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Text("SYSTEM READY FOR DEPARTURE")
                    .font(.mono(11, weight: .medium))
                    .foregroundColor(Color(white: 0.5))
                    .padding(.top, 4)
            }

            Spacer()

            // Stats
            HStack(spacing: 12) {
                StatCard(label: "REST TIMER",
                         value: String(format: "%.1fh", store.currentProfile.restHours))
                StatCard(label: "RISK LEVEL",
                         value: store.currentProfile.riskLevel.rawValue,
                         valueColor: store.currentProfile.riskLevel.color)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)

            // Start button
            Button {
                store.appState = .calibration
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                    Text("Continue as \(store.currentProfile.name)")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.vGreen)
                .foregroundColor(.black)
                .cornerRadius(12)
            }
            .padding(.horizontal, 20)

            // Profil değiştir
            Button {
                showProfileSheet = true
            } label: {
                Text("Switch Profile")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.5))
            }
            .padding(.vertical, 16)

            // Tab bar boşluk
            Color.clear.frame(height: 60)
        }
        .background(Color.vBackground)
        // Profil seçim sheet
        .sheet(isPresented: $showProfileSheet) {
            ProfilePickerView(showAddProfile: $showAddProfile)
                .environmentObject(store)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
        // Profil ekleme sheet
        .sheet(isPresented: $showAddProfile) {
            AddProfileView()
                .environmentObject(store)
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Stat Card
struct StatCard: View {
    let label     : String
    let value     : String
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.mono(9, weight: .bold))
                .foregroundColor(Color(white: 0.5))
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
    }
}

// MARK: - Profil Seçim
struct ProfilePickerView: View {
    @EnvironmentObject var store: AppStore
    @Binding var showAddProfile: Bool
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Başlık
            HStack {
                Text("PROFİL SEÇ")
                    .font(.mono(14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button {
                    dismiss()
                    showAddProfile = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.vGreen)
                        .font(.system(size: 22))
                }
            }
            .padding(20)

            Divider().background(Color.vBorder)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(store.profiles) { profile in
                        ProfileRow(
                            profile: profile,
                            isSelected: profile.id == store.currentProfile.id
                        ) {
                            store.selectProfile(profile)
                            dismiss()
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .background(Color.vBackground)
    }
}

struct ProfileRow: View {
    let profile   : UserProfile
    let isSelected: Bool
    let onSelect  : () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.vGreen.opacity(0.2) : Color.vCard)
                    .frame(width: 44, height: 44)
                Image(systemName: "person.fill")
                    .foregroundColor(isSelected ? .vGreen : Color(white: 0.4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text("Risk: \(profile.riskLevel.rawValue) • \(profile.totalSessions) sürüş")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.5))
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.vGreen)
            }
        }
        .padding(14)
        .background(isSelected ? Color.vGreen.opacity(0.08) : Color.vCard)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(isSelected ? Color.vGreen.opacity(0.4) : Color.vBorder, lineWidth: 1))
        .onTapGesture { onSelect() }
    }
}

// MARK: - Profil Ekleme
struct AddProfileView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var name      = ""
    @State private var riskLevel = UserProfile.RiskLevel.low
    @State private var restHours = 8.0

    var body: some View {
        VStack(spacing: 20) {
            Text("YENİ PROFİL")
                .font(.mono(14, weight: .bold))
                .foregroundColor(.white)
                .padding(.top, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("İSİM").font(.mono(10, weight: .bold)).foregroundColor(Color(white:0.5))
                TextField("Sürücü adı", text: $name)
                    .padding(12)
                    .background(Color.vCard)
                    .cornerRadius(10)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("RİSK SEVİYESİ").font(.mono(10, weight: .bold)).foregroundColor(Color(white:0.5))
                Picker("Risk", selection: $riskLevel) {
                    ForEach(UserProfile.RiskLevel.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 20)

            VStack(alignment: .leading, spacing: 8) {
                Text("SON UYKU: \(String(format: "%.1f", restHours)) saat")
                    .font(.mono(10, weight: .bold))
                    .foregroundColor(Color(white:0.5))
                Slider(value: $restHours, in: 0...12, step: 0.5)
                    .tint(.vGreen)
            }
            .padding(.horizontal, 20)

            Spacer()

            Button {
                guard !name.isEmpty else { return }
                let p = UserProfile(name: name, riskLevel: riskLevel,
                                    restHours: restHours, totalSessions: 0,
                                    avgSafetyScore: 100)
                store.addProfile(p)
                store.selectProfile(p)
                dismiss()
            } label: {
                Text("PROFİL OLUŞTUR")
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(name.isEmpty ? Color.vBorder : Color.vGreen)
                    .foregroundColor(.black)
                    .fontWeight(.bold)
                    .cornerRadius(12)
            }
            .disabled(name.isEmpty)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color.vBackground)
    }
}
