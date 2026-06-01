import SwiftUI

struct ReportsView: View {
    @EnvironmentObject var auth: LocalAuthService
    @State private var selected: DrivingSession?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: "#F4F8FF").ignoresSafeArea()
                if auth.drivingSessions.isEmpty {
                    EmptyReportsView()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            SummaryCard().padding(.horizontal, 20).padding(.top, 8)
                            ForEach(auth.drivingSessions) { session in
                                SessionCard(session: session).padding(.horizontal, 20)
                                    .onTapGesture { selected = session }
                            }
                        }.padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Sürüş Geçmişi")
            .navigationBarTitleDisplayMode(.large)
            .sheet(item: $selected) { SessionDetailView(session: $0) }
        }
    }
}

private struct SummaryCard: View {
    @EnvironmentObject var auth: LocalAuthService
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Genel Özet").font(.system(size: 15, weight: .semibold)).foregroundColor(GTheme.Color.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "shield.fill").font(.system(size: 12))
                    Text("\(auth.overallSafetyScore)").font(.system(size: 14, weight: .bold))
                }
                .foregroundColor(scoreColor(auth.overallSafetyScore))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(scoreColor(auth.overallSafetyScore).opacity(0.12)).cornerRadius(12)
            }
            HStack(spacing: 0) {
                SumItem(icon: "car.fill", value: "\(auth.totalDrives)", label: "Sürüş")
                SumItem(icon: "clock.fill", value: String(format: "%.1f sa", auth.totalDriveHours), label: "Toplam")
                SumItem(icon: "exclamationmark.triangle.fill", value: String(format: "%.0f%%", auth.averageDangerPercent), label: "Ort. Tehlike", color: auth.averageDangerPercent > 10 ? GTheme.Color.danger : GTheme.Color.safe)
            }
        }.gCard()
    }
}

private struct SumItem: View {
    let icon, value, label: String
    var color: Color = GTheme.Color.primary
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 18)).foregroundColor(color)
            Text(value).font(.system(size: 17, weight: .bold)).foregroundColor(GTheme.Color.textPrimary)
            Text(label).font(.system(size: 11)).foregroundColor(GTheme.Color.textSecondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct SessionCard: View {
    let session: DrivingSession
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.startTime, style: .date).font(.system(size: 14, weight: .semibold)).foregroundColor(GTheme.Color.textPrimary)
                    Text(session.startTime, style: .time).font(.system(size: 12)).foregroundColor(GTheme.Color.textSecondary)
                }
                Spacer()
                Text(fmt(session.durationSeconds)).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(GTheme.Color.textSecondary)
                if session.dangerCount > 0 {
                    Text("\(session.dangerCount) tehlike").font(.system(size: 11, weight: .semibold)).foregroundColor(GTheme.Color.danger)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(GTheme.Color.danger.opacity(0.1)).cornerRadius(10)
                }
            }
            SafetyBar(safe: session.safePercent, warning: session.warningPercent, danger: session.dangerPercent)
            HStack(spacing: 16) {
                MiniMetric(icon: "eye.slash", value: "\(session.yawnEpisodes)", label: "Esneme")
                MiniMetric(icon: "waveform.path.ecg", value: String(format: "%.0f%%", session.maxPerclos * 100), label: "Maks PERCLOS")
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(GTheme.Color.textSecondary)
            }
        }.gCard()
    }
    private func fmt(_ t: Double) -> String {
        let h = Int(t)/3600, m = (Int(t)%3600)/60
        return h > 0 ? "\(h) sa \(m) dk" : "\(m) dk"
    }
}

private struct MiniMetric: View {
    let icon, value, label: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(GTheme.Color.textSecondary)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(GTheme.Color.textPrimary)
            Text(label).font(.system(size: 11)).foregroundColor(GTheme.Color.textSecondary)
        }
    }
}

struct SafetyBar: View {
    let safe, warning, danger: Double
    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2).fill(GTheme.Color.safe).frame(width: max(2, geo.size.width * (safe/100)))
                RoundedRectangle(cornerRadius: 2).fill(GTheme.Color.warning).frame(width: max(2, geo.size.width * (warning/100)))
                RoundedRectangle(cornerRadius: 2).fill(GTheme.Color.danger).frame(width: max(2, geo.size.width * (danger/100)))
            }
        }.frame(height: 6)
    }
}

struct SessionDetailView: View {
    let session: DrivingSession
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text(session.startTime, style: .date).font(.system(size: 22, weight: .bold)).foregroundColor(GTheme.Color.textPrimary)
                        Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) — \(session.endTime?.formatted(date: .omitted, time: .shortened) ?? "?")").font(.system(size: 14)).foregroundColor(GTheme.Color.textSecondary)
                    }.frame(maxWidth: .infinity).padding(.top, 8)

                    VStack(spacing: 10) {
                        SafetyBar(safe: session.safePercent, warning: session.warningPercent, danger: session.dangerPercent)
                        HStack {
                            PercentBadge(label: "Güvenli", pct: session.safePercent, color: GTheme.Color.safe)
                            PercentBadge(label: "Dikkat", pct: session.warningPercent, color: GTheme.Color.warning)
                            PercentBadge(label: "Tehlike", pct: session.dangerPercent, color: GTheme.Color.danger)
                        }
                    }.gCard().padding(.horizontal, 20)

                    let cols = [GridItem(.flexible()), GridItem(.flexible())]
                    LazyVGrid(columns: cols, spacing: 12) {
                        DetailMetricCard(icon: "clock.fill", label: "Süre", value: fmt(session.durationSeconds), color: GTheme.Color.primary)
                        DetailMetricCard(icon: "exclamationmark.triangle", label: "Tehlike Anı", value: "\(session.dangerCount) kez", color: GTheme.Color.danger)
                        DetailMetricCard(icon: "waveform.path.ecg", label: "Maks PERCLOS", value: String(format: "%.0f%%", session.maxPerclos * 100), color: GTheme.Color.warning)
                        DetailMetricCard(icon: "mouth.fill", label: "Esneme", value: "\(session.yawnEpisodes) kez", color: GTheme.Color.safe)
                    }.padding(.horizontal, 20)

                    if !session.alertEvents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Uyarı Olayları").font(.system(size: 15, weight: .semibold)).foregroundColor(GTheme.Color.textPrimary)
                            ForEach(session.alertEvents) { e in
                                HStack(spacing: 12) {
                                    Circle().fill(GTheme.color(for: e.level)).frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(e.timestamp, style: .time).font(.system(size: 13, weight: .medium)).foregroundColor(GTheme.Color.textPrimary)
                                        Text(reason(e.reason)).font(.system(size: 11)).foregroundColor(GTheme.Color.textSecondary)
                                    }
                                    Spacer()
                                    Text(String(format: "PERCLOS %.0f%%", e.perclos * 100)).font(.system(size: 11, design: .monospaced)).foregroundColor(GTheme.Color.textSecondary)
                                }
                            }
                        }.gCard().padding(.horizontal, 20)
                    }
                }.padding(.bottom, 32)
            }
            .background(Color(hex: "#F4F8FF").ignoresSafeArea())
            .navigationTitle("Sürüş Detayı").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Kapat") { dismiss() } } }
        }
    }
    private func fmt(_ t: Double) -> String {
        let h = Int(t)/3600, m = (Int(t)%3600)/60
        return h > 0 ? "\(h) sa \(m) dk" : "\(m) dk"
    }
    private func reason(_ r: String) -> String {
        switch r {
        case "microsleep_crit": return "Uzun göz kapanması"
        case "microsleep_warn": return "Hafif göz kapanması"
        case "perclos_crit": return "Yüksek PERCLOS"
        case "perclos_warn": return "Artan PERCLOS"
        case "yawn_crit": return "Çok sayıda esneme"
        case "yawn_warn": return "Birkaç esneme"
        default: return r
        }
    }
}

private struct PercentBadge: View {
    let label: String; let pct: Double; let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.0f%%", pct)).font(.system(size: 16, weight: .bold)).foregroundColor(color)
            Text(label).font(.system(size: 11)).foregroundColor(GTheme.Color.textSecondary)
        }.frame(maxWidth: .infinity)
    }
}

private struct DetailMetricCard: View {
    let icon, label, value: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 20)).foregroundColor(color)
            Text(value).font(.system(size: 20, weight: .bold)).foregroundColor(GTheme.Color.textPrimary)
            Text(label).font(.system(size: 12)).foregroundColor(GTheme.Color.textSecondary)
        }.frame(maxWidth: .infinity, alignment: .leading).gCard()
    }
}

private struct EmptyReportsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "car.rear.road.lane.dashed").font(.system(size: 54)).foregroundColor(GTheme.Color.primary.opacity(0.4))
            Text("Henüz sürüş yok").font(.system(size: 18, weight: .semibold)).foregroundColor(GTheme.Color.textPrimary)
            Text("İlk sürüşünü başlatmak için\nSürüş sekmesine git.").font(.system(size: 14)).foregroundColor(GTheme.Color.textSecondary).multilineTextAlignment(.center)
        }
    }
}

func scoreColor(_ score: Int) -> Color {
    if score >= 80 { return GTheme.Color.safe }
    if score >= 50 { return GTheme.Color.warning }
    return GTheme.Color.danger
}
