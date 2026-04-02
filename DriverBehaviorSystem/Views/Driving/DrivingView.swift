import SwiftUI

struct DrivingView: View {
    @EnvironmentObject var store : AppStore
    @StateObject private var engine = DrowsinessEngine()
    @StateObject private var camera = CameraManager()
    @State private var showStopConfirm = false

    var body: some View {
        ZStack {
            Color.vBackground.ignoresSafeArea()

            VStack(spacing: 0) {
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
                .padding(.bottom, 12)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {

                        // Kamera
                        ZStack(alignment: .topLeading) {
                            CameraPreviewView(camera: camera)
                                .frame(height: 200)
                                .cornerRadius(16)
                                .clipped()

                            // Live badge
                            HStack(spacing: 5) {
                                Circle().fill(.red).frame(width: 8, height: 8)
                                Text("LIVE FEED • 1080P")
                                    .font(.mono(9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(10)

                            // İsim
                            VStack(alignment: .leading) {
                                Spacer()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("SUBJECT IDENTIFICATION")
                                        .font(.mono(8))
                                        .foregroundColor(Color(white: 0.6))
                                    Text(store.currentProfile.name.uppercased())
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .padding(10)
                            }
                        }
                        .padding(.horizontal, 20)

                        // Fatigue Level Bar
                        FatigueLevelBar(score: engine.smoothedScore,
                                        decision: engine.decision)
                            .padding(.horizontal, 20)

                        // Metrik kartları (2x2)
                        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())],
                                  spacing: 12) {
                            MetricCard(icon: "eye.fill",
                                       label: "BLINK RATE",
                                       value: String(format: "%.0f", engine.blinkRate * 60),
                                       unit: "bpm")
                            MetricCard(icon: "scope",
                                       label: "FOCUS",
                                       value: String(format: "%.0f",
                                                     max(0, 100 - engine.smoothedScore * 100)),
                                       unit: "")
                            MetricCard(icon: "arrow.up.left.and.arrow.down.right",
                                       label: "TILT ANGLE",
                                       value: String(format: "%.1f", engine.closureSec),
                                       unit: "s")
                            MetricCard(icon: "moon.zzz.fill",
                                       label: "MICRO-SLEEP",
                                       value: "\(engine.microsleepTotal)",
                                       unit: "detected",
                                       valueColor: engine.microsleepTotal > 0 ? .red : .white)
                        }
                        .padding(.horizontal, 20)

                        // Telemetri
                        TelemetryCard(engine: engine)
                            .padding(.horizontal, 20)

                        // Durdur
                        Button {
                            showStopConfirm = true
                        } label: {
                            Text("STOP MONITORING")
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .font(.mono(13, weight: .bold))
                                .foregroundColor(.red)
                                .background(Color.vCard)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.4), lineWidth: 1))
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                    .padding(.top, 8)
                }
            }

            // Uyarı overlay
            if engine.alertFired {
                AlertOverlayView(decision: engine.decision) {
                    engine.resetAlert()
                }
            }
        }
        .onAppear {
            camera.start()
            engine.startCalibration(fps: 30,
                                    profileId: store.currentProfile.id.uuidString)
            // Kalibrasyon atlanmışsa direkt analiz başlat
            // (CalibrationView'dan gelenler zaten kalibre)
            camera.onFrame = { ear, mar, pitch, yaw, roll in
                engine.processFrame(ear: ear, mar: mar,
                                    pitch: pitch, yaw: yaw, roll: roll)
            }
        }
        .onDisappear { camera.stop() }
        .confirmationDialog("Sürüşü bitirmek istiyor musunuz?",
                            isPresented: $showStopConfirm, titleVisibility: .visible) {
            Button("Sürüşü Bitir", role: .destructive) {
                let session = engine.currentSessionStats(
                    name: "\(store.currentProfile.name) Sürüşü")
                store.stopDriving(session: session)
            }
            Button("İptal", role: .cancel) {}
        }
    }
}

// MARK: - Fatigue Level Bar
struct FatigueLevelBar: View {
    let score   : Double
    let decision: RuleDecision

    private var barColor: Color {
        switch decision.level {
        case .safe:     return .vGreen
        case .caution:  return .yellow
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("FATIGUE LEVEL")
                    .font(.mono(10, weight: .bold))
                    .foregroundColor(Color(white: 0.5))
                Spacer()
                Text(decision.level.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(barColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    LinearGradient(colors: [.vGreen, .yellow, .orange, .red],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(height: 8).cornerRadius(4).opacity(0.3)
                    // Dolgu
                    barColor.opacity(0.8)
                        .frame(width: geo.size.width * min(score, 1.0), height: 8)
                        .cornerRadius(4)
                        .animation(.spring(response: 0.4), value: score)
                    // İndikatör
                    Circle()
                        .fill(barColor)
                        .frame(width: 16, height: 16)
                        .offset(x: geo.size.width * min(score, 1.0) - 8)
                        .animation(.spring(response: 0.4), value: score)
                }
            }
            .frame(height: 16)

            HStack {
                Text("OPTIMAL").font(.mono(9)).foregroundColor(Color(white:0.4))
                Spacer()
                Text("MODERATE").font(.mono(9)).foregroundColor(Color(white:0.4))
                Spacer()
                Text("CRITICAL").font(.mono(9)).foregroundColor(Color(white:0.4))
            }
        }
        .padding(16)
        .cardStyle()
    }
}

// MARK: - Metric Card
struct MetricCard: View {
    let icon      : String
    let label     : String
    let value     : String
    let unit      : String
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.vGreen)
                .font(.system(size: 14))
            Text(label)
                .font(.mono(9, weight: .bold))
                .foregroundColor(Color(white: 0.5))
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(valueColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.4))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardStyle()
    }
}

// MARK: - Telemetry Card
struct TelemetryCard: View {
    @ObservedObject var engine: DrowsinessEngine

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t)/3600, m = Int(t)%3600/60, s = Int(t)%60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("DETAILED TELEMETRY")
                .font(.mono(10, weight: .bold))
                .foregroundColor(Color(white: 0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)

            TelRow(icon: "clock",
                   label: "Session Duration",
                   value: formatDuration(engine.sessionDuration))
            Divider().background(Color.vBorder)
            TelRow(icon: "eye.trianglebadge.exclamationmark",
                   label: "PERCLOS (10s)",
                   value: String(format: "%.1f%%", engine.perclos * 100))
            Divider().background(Color.vBorder)
            TelRow(icon: "mouth",
                   label: "Yawn Count (5min)",
                   value: "\(engine.yawnCount)")
            Divider().background(Color.vBorder)
            TelRow(icon: "bell",
                   label: "Last Alert",
                   value: engine.microsleepTotal > 0 ? "Detected" : "None")
        }
        .padding(16)
        .cardStyle()
    }
}

struct TelRow: View {
    let icon, label, value: String
    var body: some View {
        HStack {
            Image(systemName: icon).foregroundColor(.vGreen).frame(width: 20)
            Text(label).font(.system(size: 13)).foregroundColor(Color(white: 0.5))
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Alert Overlay
struct AlertOverlayView: View {
    let decision : RuleDecision
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.red.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.red)
                Text(decision.level.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                if !decision.reason.isEmpty {
                    Text(decision.reason)
                        .font(.system(size: 14))
                        .foregroundColor(Color(white: 0.8))
                        .multilineTextAlignment(.center)
                }
                Text("Lütfen güvenli bir yere çekip dinlenin.")
                    .font(.system(size: 14))
                    .foregroundColor(Color(white: 0.7))
                    .multilineTextAlignment(.center)
                Button("Anladım") { onDismiss() }
                    .frame(width: 200, height: 48)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .fontWeight(.bold)
                    .cornerRadius(12)
            }
            .padding(30)
            .background(Color.vCard.opacity(0.95))
            .cornerRadius(20)
            .padding(24)
        }
    }
}
