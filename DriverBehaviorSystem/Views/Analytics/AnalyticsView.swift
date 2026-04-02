import SwiftUI

struct AnalyticsView: View {
    @EnvironmentObject var store: AppStore

    private var avgScore: Int {
        guard !store.sessions.isEmpty else { return 100 }
        return store.sessions.map(\.safetyScore).reduce(0,+) / store.sessions.count
    }

    var body: some View {
        ZStack {
            Color.vBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    // Header
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(Color(white: 0.5))
                        Spacer()
                        Text("VIGILANCE")
                            .font(.mono(14, weight: .bold))
                            .foregroundColor(.vGreen)
                        Spacer()
                        Circle()
                            .fill(Color.vCard)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Text(String(store.currentProfile.name.prefix(1)))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    // Safety Score Ring
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .stroke(Color.vBorder, lineWidth: 12)
                                .frame(width: 140, height: 140)
                            Circle()
                                .trim(from: 0, to: CGFloat(avgScore) / 100.0)
                                .stroke(Color.vGreen,
                                        style: StrokeStyle(lineWidth: 12, lineCap: .round))
                                .frame(width: 140, height: 140)
                                .rotationEffect(.degrees(-90))
                                .animation(.spring(), value: avgScore)
                            VStack(spacing: 2) {
                                Text("\(avgScore)")
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)
                                Text("SAFETY SCORE")
                                    .font(.mono(8, weight: .bold))
                                    .foregroundColor(Color(white: 0.5))
                            }
                        }

                        Text(avgScore >= 90 ? "ELITE DRIVER STATUS" :
                             avgScore >= 75 ? "GOOD DRIVER STATUS"  : "NEEDS IMPROVEMENT")
                            .font(.mono(11, weight: .bold))
                            .foregroundColor(.vGreen)

                        Text("LATEST UPDATE: \(store.sessions.first.map { relativeDate($0.date) } ?? "N/A")")
                            .font(.mono(9))
                            .foregroundColor(Color(white: 0.4))
                    }
                    .padding(.vertical, 8)

                    // Haftalık grafik
                    WeeklyChartView(sessions: store.sessions)
                        .padding(.horizontal, 20)

                    // Sistem ayarları
                    SystemConfigView()
                        .padding(.horizontal, 20)

                    // Son sürüşler
                    VStack(alignment: .leading, spacing: 10) {
                        Text("RECENT SESSIONS")
                            .font(.mono(10, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                            .padding(.horizontal, 20)

                        ForEach(store.sessions.prefix(5)) { session in
                            SessionRowView(session: session)
                                .padding(.horizontal, 20)
                        }

                        Button {
                            // Tam rapor
                        } label: {
                            Text("VIEW FULL ANALYSIS REPORT")
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .font(.mono(11, weight: .bold))
                                .foregroundColor(.vGreen)
                                .background(Color.vCard)
                                .cornerRadius(10)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.vBorder, lineWidth: 1))
                        }
                        .padding(.horizontal, 20)
                    }

                    Color.clear.frame(height: 70)
                }
                .padding(.top, 4)
            }
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let diff = Int(Date().timeIntervalSince(date))
        if diff < 3600  { return "\(diff/60)m ago" }
        if diff < 86400 { return "\(diff/3600)h ago" }
        return "\(diff/86400)d ago"
    }
}

// MARK: - Weekly Chart
struct WeeklyChartView: View {
    let sessions: [DrivingSession]
    private let days = ["MON","TUE","WED","THU","FRI","SAT","SUN"]

    private func scoreForDay(_ dayIdx: Int) -> Double {
        let cal  = Calendar.current
        let today = cal.component(.weekday, from: Date()) - 2
        let target = (dayIdx - today + 7) % 7
        let date  = Calendar.current.date(byAdding: .day, value: -target, to: Date())!

        let daySessions = sessions.filter {
            cal.isDate($0.date, inSameDayAs: date)
        }
        guard !daySessions.isEmpty else { return 0 }
        return Double(daySessions.map(\.safetyScore).reduce(0,+) / daySessions.count) / 100.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Fatigue Analysis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 6, height: 6)
                    Text("WEEKLY VIGILANCE METRIC")
                        .font(.mono(8))
                        .foregroundColor(Color(white: 0.4))
                }
            }

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let score = scoreForDay(i)
                    VStack(spacing: 4) {
                        if score > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(score >= 0.85 ? Color.vGreen :
                                      score >= 0.60 ? Color.yellow  : Color.red)
                                .frame(height: CGFloat(score) * 60)
                        } else {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.vBorder)
                                .frame(height: 4)
                        }
                        Text(days[i])
                            .font(.mono(8))
                            .foregroundColor(Color(white: 0.4))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 80)
        }
        .padding(16)
        .cardStyle()
    }
}

// MARK: - System Config
struct SystemConfigView: View {
    @AppStorage("camSensitivity") private var camSens   = true
    @AppStorage("audioAlerts")   private var audioAl   = true
    @AppStorage("nightVision")   private var nightVis  = false
    @AppStorage("alertThreshold") private var alertThr = 0.85

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape").foregroundColor(.vGreen)
                Text("SYSTEM CONFIGURATION")
                    .font(.mono(10, weight: .bold))
                    .foregroundColor(Color(white: 0.5))
            }
            .padding(.bottom, 14)

            ConfigToggle(title: "Camera Sensitivity",
                         sub: "AI-driven facial tracking depth",
                         value: $camSens)
            Divider().background(Color.vBorder)
            ConfigToggle(title: "Audio Alerts",
                         sub: "High-frequency fatigue rings",
                         value: $audioAl)
            Divider().background(Color.vBorder)
            ConfigToggle(title: "Night Vision Mode",
                         sub: "Auto infrared adaptation",
                         value: $nightVis)
            Divider().background(Color.vBorder)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Alert Threshold")
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                    Spacer()
                    Text("\(Int(alertThr * 100))% PRIORITY")
                        .font(.mono(10, weight: .bold))
                        .foregroundColor(.vGreen)
                }
                Slider(value: $alertThr, in: 0.5...0.95, step: 0.05)
                    .tint(.vGreen)
            }
            .padding(.top, 12)
        }
        .padding(16)
        .cardStyle()
    }
}

struct ConfigToggle: View {
    let title, sub: String
    @Binding var value: Bool
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14)).foregroundColor(.white)
                Text(sub).font(.system(size: 10)).foregroundColor(Color(white:0.5))
            }
            Spacer()
            Toggle("", isOn: $value).tint(.vGreen)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Session Row
struct SessionRowView: View {
    let session: DrivingSession

    private var icon: String {
        session.name.lowercased().contains("night") ? "moon.fill" :
        session.name.lowercased().contains("city")  ? "building.2" : "road.lanes"
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.vBackground)
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .foregroundColor(Color(white: 0.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("\(session.durationString.uppercased())")
                    .font(.mono(9))
                    .foregroundColor(Color(white: 0.4))
            }
            Spacer()
            Text("\(session.safetyScore)/100")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(session.scoreColor)
        }
        .padding(12)
        .cardStyle()
    }
}
