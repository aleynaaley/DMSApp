import SwiftUI
import AVFoundation

struct DriveView: View {
    @EnvironmentObject var auth: LocalAuthService
    @StateObject private var service = FatigueDetectionService()
    @State private var showEndAlert = false
    @State private var driveDuration: TimeInterval = 0
    @State private var driveTimer: Timer?
    @State private var showSavedBanner = false

    var body: some View {
        ZStack {
            CameraPreviewView(previewLayer: service.previewLayer)
                .ignoresSafeArea().background(Color(hex: "#060D1A"))

            VStack(spacing: 0) {
                TopInfoBar(isRunning: service.isRunning, duration: driveDuration, faceDetected: service.detectionState.faceDetected)
                Spacer()
                if service.isRunning { AlertIndicator(state: service.detectionState).transition(.opacity) }
                Spacer()
                if service.isRunning {
                    MetricsPanel(state: service.detectionState).padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                ControlButton(isRunning: service.isRunning, onStart: startDrive, onStop: { showEndAlert = true })
                    .padding(.bottom, 36)
            }

            if service.detectionState.isAlarmActive { AlarmFlashOverlay() }

            if showSavedBanner {
                VStack {
                    Spacer()
                    Text("Sürüş kaydedildi ✓").font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10).background(GTheme.Color.primary).cornerRadius(20)
                        .padding(.bottom, 100)
                    Spacer()
                }.transition(.opacity)
            }

            if service.cameraPermissionDenied {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill").font(.system(size: 40)).foregroundColor(.white)
                    Text("Kamera izni gerekli").font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    Text("Ayarlar → Gözcü → Kamera").font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: service.isRunning)
        .onAppear {
            service.setupCamera()
            service.onDriveEnded = { session in
                Task { await auth.saveDrivingSession(session) }
                withAnimation { showSavedBanner = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation { showSavedBanner = false }
                }
            }
        }
        .confirmationDialog("Sürüşü Bitir", isPresented: $showEndAlert, titleVisibility: .visible) {
            Button("Bitir ve Kaydet", role: .destructive) { stopDrive() }
            Button("İptal", role: .cancel) { }
        } message: {
            Text("Sürüş \(formatDuration(driveDuration)) sürdü.")
        }
    }

    private func startDrive() {
        service.startDrive()
        driveDuration = 0
        driveTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in driveDuration += 1 }
    }

    private func stopDrive() {
        service.stopDrive()
        driveTimer?.invalidate(); driveTimer = nil
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t)/3600, m = (Int(t)%3600)/60, s = Int(t)%60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

private struct TopInfoBar: View {
    let isRunning: Bool; let duration: TimeInterval; let faceDetected: Bool
    var body: some View {
        HStack {
            if isRunning {
                Label(fmt(duration), systemImage: "timer")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 12).padding(.vertical, 6).background(.ultraThinMaterial).cornerRadius(20)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(faceDetected ? GTheme.Color.safe : GTheme.Color.warning).frame(width: 8, height: 8)
                Text(faceDetected ? "Yüz Algılandı" : "Yüz Bulunamadı").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(.ultraThinMaterial).cornerRadius(20)
        }
        .padding(.horizontal, 20).padding(.top, 56)
    }
    private func fmt(_ t: TimeInterval) -> String {
        let h = Int(t)/3600, m = (Int(t)%3600)/60, s = Int(t)%60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

private struct AlertIndicator: View {
    let state: DetectionState
    @State private var pulse = false
    var body: some View {
        let color = GTheme.color(for: state.alertLevel)
        VStack(spacing: 8) {
            ZStack {
                if state.alertLevel == .danger {
                    Circle().stroke(color.opacity(0.3), lineWidth: 2)
                        .frame(width: pulse ? 120 : 90, height: pulse ? 120 : 90)
                        .opacity(pulse ? 0 : 0.6)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)
                }
                Circle().fill(color.opacity(0.2)).frame(width: 90, height: 90)
                Text(state.alertLevel.emoji).font(.system(size: 36, weight: .bold)).foregroundColor(color)
            }
            .onAppear { pulse = true }
            Text(state.alertLevel.label).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(color)
            if state.alertLevel != .safe {
                Text(subtitle).font(.system(size: 13)).foregroundColor(.white.opacity(0.7))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: state.alertLevel)
    }
    private var subtitle: String {
        switch state.alertLevel {
        case .warning:
            if state.msLevel == 1 { return "Hafif göz kapanması" }
            if state.perclos > 0.15 { return String(format: "PERCLOS: %.0f%%", state.perclos * 100) }
            return "Esneme tespit edildi"
        case .danger:
            if state.msLevel == 2 { return String(format: "Göz %.1fs kapalı!", state.closedDuration) }
            if state.perclos >= 0.30 { return String(format: "Yüksek PERCLOS: %.0f%%", state.perclos * 100) }
            return "Sürüşü durdurun, dinlenin!"
        default: return ""
        }
    }
}

private struct MetricsPanel: View {
    let state: DetectionState
    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("PERCLOS").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.6)).tracking(1.5)
                    Spacer()
                    Text(String(format: "%.0f%%", state.perclos * 100)).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(perclosColor)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.12)).frame(height: 6)
                        Rectangle().fill(GTheme.Color.warning.opacity(0.6)).frame(width: 1.5, height: 10)
                            .offset(x: min(geo.size.width * 0.15 / 0.30, geo.size.width - 2))
                        RoundedRectangle(cornerRadius: 3).fill(perclosColor)
                            .frame(width: min(geo.size.width * (state.perclos / 0.30), geo.size.width), height: 6)
                    }
                }.frame(height: 10)
            }
            .padding(.horizontal, 20).padding(.top, 14)

            HStack(spacing: 0) {
                MetricItem(label: "ESNEME", value: "\(state.yawnCount) kez", icon: "mouth")
                Divider().frame(height: 30).background(.white.opacity(0.15))
                MetricItem(label: "GÖZ", value: msLabel, icon: "eye")
                Divider().frame(height: 30).background(.white.opacity(0.15))
                MetricItem(label: "ALARM", value: state.isAlarmActive ? "AKTİF" : "—", icon: "bell")
            }.padding(.bottom, 14)
        }
        .background(.ultraThinMaterial.opacity(0.85)).cornerRadius(GTheme.Radius.large).padding(.horizontal, 16)
    }
    private var perclosColor: Color {
        if state.perclos >= 0.30 { return GTheme.Color.danger }
        if state.perclos >= 0.15 { return GTheme.Color.warning }
        return GTheme.Color.safe
    }
    private var msLabel: String {
        switch state.msLevel { case 0: return "Normal"; case 1: return "Hafif"; case 2: return "Kritik"; default: return "—" }
    }
}

private struct MetricItem: View {
    let label, value, icon: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundColor(.white.opacity(0.5)).tracking(1)
            Text(value).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
    }
}

private struct ControlButton: View {
    let isRunning: Bool; let onStart: () -> Void; let onStop: () -> Void
    var body: some View {
        Button(action: isRunning ? onStop : onStart) {
            HStack(spacing: 10) {
                Image(systemName: isRunning ? "stop.circle.fill" : "play.circle.fill").font(.system(size: 22))
                Text(isRunning ? "Sürüşü Bitir" : "Sürüşü Başlat").font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 58)
            .background(isRunning ? LinearGradient(colors: [Color(hex: "#B71C1C"), Color(hex: "#E53935")], startPoint: .leading, endPoint: .trailing) : LinearGradient(colors: [Color(hex: "#1565C0"), Color(hex: "#1E88E5")], startPoint: .leading, endPoint: .trailing))
            .cornerRadius(GTheme.Radius.medium).shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        }
        .padding(.horizontal, 24).animation(.easeInOut(duration: 0.2), value: isRunning)
    }
}

private struct AlarmFlashOverlay: View {
    @State private var opacity: Double = 0
    var body: some View {
        Rectangle().fill(GTheme.Color.danger.opacity(0.18)).ignoresSafeArea().opacity(opacity)
            .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { opacity = 1 } }
            .allowsHitTesting(false)
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.backgroundColor = .black
        v.previewLayer = previewLayer
        return v
    }

    func updateUIView(_ v: PreviewUIView, context: Context) {
        v.previewLayer = previewLayer
    }
}

final class PreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let layer = previewLayer {
                layer.frame = bounds
                self.layer.addSublayer(layer)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
    }
}
