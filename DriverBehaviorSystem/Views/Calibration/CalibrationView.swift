import SwiftUI

struct CalibrationView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var engine = DrowsinessEngine()
    @StateObject private var camera = CameraManager()

    var body: some View {
        ZStack {
            Color.vBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button { store.appState = .welcome } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(Color(white: 0.5))
                            .font(.system(size: 16))
                    }
                    Spacer()
                    HStack(spacing: 4) {
                        Text("VIGILANCE")
                            .font(.mono(14, weight: .bold))
                            .foregroundColor(.vGreen)
                        Text("• CALIBRATION MODE")
                            .font(.mono(10))
                            .foregroundColor(Color(white: 0.4))
                    }
                    Spacer()
                    Color.clear.frame(width: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Progress
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("STEP \(engine.calibPhase == 0 ? 2 : engine.calibPhase) OF 2")
                            .font(.mono(11, weight: .bold))
                            .foregroundColor(Color(white: 0.5))
                        Spacer()
                        Text("\(Int(engine.calibProgress * 100))%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.vGreen)
                    }

                    Text(engine.calibPhase == 1 ? "Face Alignment" : "Read Aloud")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.vBorder).frame(height: 4)
                            Capsule().fill(Color.vGreen)
                                .frame(width: geo.size.width * engine.calibProgress, height: 4)
                                .animation(.linear(duration: 0.1), value: engine.calibProgress)
                        }
                    }
                    .frame(height: 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

                // Kamera önizleme
                ZStack {
                    CameraPreviewView(camera: camera)
                        .frame(height: 240)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.vGreen.opacity(0.5), lineWidth: 1.5)
                        )

                    // Yüz hizalama göstergesi
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            HStack(spacing: 6) {
                                Circle().fill(Color.vGreen).frame(width: 8, height: 8)
                                Text("POSITION OPTIMAL")
                                    .font(.mono(9, weight: .bold))
                                    .foregroundColor(Color.vGreen)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                            Spacer()
                        }
                        .padding(.bottom, 12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // Talimatlar
                VStack(spacing: 10) {
                    if engine.calibPhase == 1 {
                        InstructionRow(icon: "sun.max",
                                       title: "Ensure good lighting",
                                       sub: "Avoid direct sunlight hitting the camera")
                        InstructionRow(icon: "eye",
                                       title: "Keep a neutral gaze",
                                       sub: "Look straight ahead as watching the road")
                    } else {
                        VStack(spacing: 10) {
                            Text("READ ALOUD:")
                                .font(.mono(10, weight: .bold))
                                .foregroundColor(Color(white: 0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Araç sürücü destek sistemi\nkalibrasyon aşamasında.\nHazır olduğunuzda devam edin.")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(Color.vGreen)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(16)
                                .background(Color.vCard)
                                .cornerRadius(12)
                                .overlay(RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.vGreen.opacity(0.3), lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // CTA
                Button {
                    if engine.calibPhase == 0 {
                        engine.saveBaseline(for: store.currentProfile.id.uuidString)
                        store.appState = .driving
                    }
                } label: {
                    Text(engine.calibPhase == 0 ? "Start Monitoring" : "Confirm Position")
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background(engine.calibPhase == 0 ? Color.vGreen : Color.vBorder)
                        .foregroundColor(engine.calibPhase == 0 ? .black : Color(white: 0.5))
                        .fontWeight(.semibold)
                        .cornerRadius(12)
                }
                .disabled(engine.calibPhase != 0)
                .padding(.horizontal, 20)

                Button("Skip for now") {
                    store.appState = .driving
                }
                .font(.system(size: 14))
                .foregroundColor(Color(white: 0.4))
                .padding(.vertical, 16)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            camera.start()
            engine.startCalibration(fps: 30,
                                    profileId: store.currentProfile.id.uuidString)
            camera.onFrame = { ear, mar, pitch, yaw, roll in
                engine.feedCalibFrame(ear: ear, mar: mar,
                                      pitch: pitch, yaw: yaw, roll: roll)
            }
        }
        .onDisappear { camera.stop() }
    }
}

// MARK: - Instruction Row
struct InstructionRow: View {
    let icon, title, sub: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .foregroundColor(.vGreen)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(sub)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.5))
            }
            Spacer()
        }
        .padding(14)
        .cardStyle()
    }
}
