import SwiftUI

// MARK: - CalibrationView
// İki aşamalı kalibrasyon:
// Faz 1 (5s): Kişi sessizce kameraya bakar → EAR baseline
// Faz 2 (5s): Kişi ekrandaki metni okur → MAR baseline (konuşma referansı)
//
// Faz 2'nin amacı: Konuşma sırasındaki MAR değerini baseline olarak almak.
// Böylece normal konuşma/şarkı yawn olarak sayılmaz,
// sadece gerçek esnemeler (MAR > baseline*1.5) tespit edilir.
// Kaynak: Abtahi M. et al. (2014). YawDD dataset.

struct CalibrationView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var engine = DrowsinessEngine()
    @StateObject private var camera = CameraManager()

    // Faz 2 için okunacak metinler — doğal konuşma MAR'ı oluşturur
    private let readAloudTexts = [
        "Araç sürüş destek sistemi\nkalibrasyonu başlatılıyor.",
        "Lütfen normal sesle\nokumaya devam edin.",
        "Sistem hazırlanıyor,\nteşekkür ederiz."
    ]
    @State private var currentTextIndex = 0
    @State private var textTimer: Timer? = nil

    var body: some View {
        ZStack {
            Color.vBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ───────────────────────────────────
                HStack {
                    Button { store.appState = .welcome } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(Color(white: 0.5))
                            .font(.system(size: 16))
                    }
                    Spacer()
                    Text("VIGILANCE • KALİBRASYON")
                        .font(.mono(12, weight: .bold))
                        .foregroundColor(.vGreen)
                    Spacer()
                    Color.clear.frame(width: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // ── Faz göstergesi ───────────────────────────
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        // Faz rozetleri
                        HStack(spacing: 8) {
                            PhaseChip(number: 1, label: "GÖZ",
                                      active: engine.calibPhase == 1,
                                      done:   engine.calibPhase == 0 || engine.calibPhase == 2)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(Color(white: 0.3))
                            PhaseChip(number: 2, label: "AĞIZ",
                                      active: engine.calibPhase == 2,
                                      done:   engine.calibPhase == 0)
                        }
                        Spacer()
                        Text("\(Int(engine.calibProgress * 100))%")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.vGreen)
                    }

                    // Faz başlığı
                    Text(phaseTitle)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                        .animation(.easeInOut, value: engine.calibPhase)

                    // Progress bar
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
                .padding(.top, 20)

                // ── Kamera önizleme ──────────────────────────
                ZStack {
                    CameraPreviewView(camera: camera)
                        .frame(height: 220)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.vGreen.opacity(0.5), lineWidth: 1.5)
                        )

                    // Canlı gösterge
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                Circle().fill(.red).frame(width: 7, height: 7)
                                Text("CANLI")
                                    .font(.mono(9, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(20)
                            .padding(10)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // ── Faz içeriği ──────────────────────────────
                Group {
                    if engine.calibPhase == 1 {
                        // FAZ 1: Göz kalibrasyonu
                        VStack(spacing: 10) {
                            InstructionRow(
                                icon: "eye",
                                title: "Kameraya düz bakın",
                                sub: "Yüzünüz tam karşıya dönük olsun, göz kırpmayın"
                            )
                            InstructionRow(
                                icon: "sun.max",
                                title: "Işığı kontrol edin",
                                sub: "Yüzünüze direkt ışık gelmesin"
                            )
                            InstructionRow(
                                icon: "mouth.fill",
                                title: "Ağzınızı kapalı tutun",
                                sub: "Bu aşamada konuşmayın, normal nefes alın"
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    } else if engine.calibPhase == 2 {
                        // FAZ 2: Ağız kalibrasyonu — metin okuma
                        VStack(spacing: 12) {
                            HStack {
                                Image(systemName: "text.quote")
                                    .foregroundColor(.vGreen)
                                Text("AŞAĞIDAKİ METNİ YÜKSEK SESLE OKUYUN")
                                    .font(.mono(9, weight: .bold))
                                    .foregroundColor(Color(white: 0.5))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)

                            // Okunacak metin kutusu
                            Text(readAloudTexts[currentTextIndex])
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .lineSpacing(6)
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .background(Color.vCard)
                                .cornerRadius(14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(Color.vGreen.opacity(0.4), lineWidth: 1.5)
                                )
                                .padding(.horizontal, 20)
                                .animation(.easeInOut(duration: 0.4), value: currentTextIndex)

                            Text("Bu aşama ağız hareketlerinizi ölçer.\nNormal konuşma hızıyla okuyun.")
                                .font(.system(size: 12))
                                .foregroundColor(Color(white: 0.4))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                        .padding(.top, 14)

                    } else {
                        // FAZ 0: Kalibrasyon tamamlandı
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.vGreen)
                            Text("Kalibrasyon Tamamlandı")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            Text("Göz ve ağız referansları kaydedildi.\nSürüşe başlayabilirsiniz.")
                                .font(.system(size: 13))
                                .foregroundColor(Color(white: 0.5))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                    }
                }

                Spacer()

                // ── CTA Butonu ───────────────────────────────
                Button {
                    if engine.calibPhase == 0 {
                        engine.saveBaseline(for: store.currentProfile.id.uuidString)
                        store.appState = .driving
                    }
                } label: {
                    HStack(spacing: 8) {
                        if engine.calibPhase == 0 {
                            Image(systemName: "play.fill")
                        } else {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        }
                        Text(engine.calibPhase == 0 ? "Sürüşe Başla" : "Kalibrasyon devam ediyor…")
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(engine.calibPhase == 0 ? Color.vGreen : Color.vBorder)
                    .foregroundColor(engine.calibPhase == 0 ? .black : Color(white: 0.4))
                    .fontWeight(.semibold)
                    .cornerRadius(12)
                }
                .disabled(engine.calibPhase != 0)
                .padding(.horizontal, 20)

                Button("Şimdilik atla") {
                    store.appState = .driving
                }
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.35))
                .padding(.vertical, 14)
            }
        }
        .onAppear {
            camera.start()
            engine.startCalibration(fps: 30,
                                    profileId: store.currentProfile.id.uuidString)
            camera.onFrame = { ear, mar, pitch, yaw, roll in
                engine.feedCalibFrame(ear: ear, mar: mar,
                                      pitch: pitch, yaw: yaw, roll: roll)
            }
            startTextRotation()
        }
        .onDisappear {
            camera.stop()
            textTimer?.invalidate()
        }
        .onChange(of: engine.calibPhase) { phase in
            if phase == 2 { startTextRotation() }
        }
    }

    // MARK: - Helpers
    private var phaseTitle: String {
        switch engine.calibPhase {
        case 1: return "Faz 1 — Göz Referansı"
        case 2: return "Faz 2 — Ağız Referansı"
        default: return "Kalibrasyon Tamamlandı ✓"
        }
    }

    private func startTextRotation() {
        textTimer?.invalidate()
        textTimer = Timer.scheduledTimer(withTimeInterval: 1.7, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation {
                    currentTextIndex = (currentTextIndex + 1) % readAloudTexts.count
                }
            }
        }
    }
}

// MARK: - Phase Chip
struct PhaseChip: View {
    let number: Int
    let label : String
    let active: Bool
    let done  : Bool

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                Circle()
                    .fill(done ? Color.vGreen : (active ? Color.vGreen.opacity(0.3) : Color.vBorder))
                    .frame(width: 20, height: 20)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.black)
                } else {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(active ? .vGreen : Color(white: 0.4))
                }
            }
            Text(label)
                .font(.mono(9, weight: .bold))
                .foregroundColor(active || done ? .vGreen : Color(white: 0.4))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background((active || done) ? Color.vGreen.opacity(0.1) : Color.clear)
        .cornerRadius(20)
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
