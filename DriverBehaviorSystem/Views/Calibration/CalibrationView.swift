import SwiftUI

// MARK: - Kalibrasyon Akışı
// ready1  (3s) → Göz kalibrasyonu geliyor uyarısı
// phase1  (5s) → Göz kalibrasyonu — sessiz bak, EAR baseline
// ready2  (3s) → Ağız kalibrasyonu geliyor uyarısı
// phase2  (5s) → Ağız kalibrasyonu — metni oku, MAR baseline
// done         → Tamamlandı ekranı

// Kaynak (Faz 2): Abtahi M. et al. (2014). YawDD dataset.
// Normal konuşma MAR'ını baseline alarak yawn tespitini kişiselleştirir.

struct CalibrationView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var engine = DrowsinessEngine()
    @StateObject private var camera = CameraManager()

    // ── Akış durumu ──────────────────────────────────────────
    enum CalibStep { case ready1, phase1, ready2, phase2, done }
    @State private var step       : CalibStep = .ready1
    @State private var countdown  : Int       = 3      // hazırlık geri sayımı
    @State private var stepTimer  : Timer?    = nil
    @State private var textIndex  : Int       = 0
    @State private var textTimer  : Timer?    = nil

    // Faz 2 okunacak metinler
    private let readTexts = [
        "Araç sürücü destek sistemi\nkalibrasyonu başlatılıyor.",
        "Sistem ağız aralığını ölçmektedir,\nlütfen okumaya devam edin.",
        "Neredeyse bitti,\nteşekkür ederiz."
    ]

    // ── Body ─────────────────────────────────────────────────
    var body: some View {
        ZStack {
            Color.vBackground.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header (sabit) ───────────────────────────
                HStack {
                    Button { stopAll(); store.appState = .welcome } label: {
                        Image(systemName: "xmark")
                            .foregroundColor(Color(white: 0.5))
                            .font(.system(size: 16, weight: .medium))
                    }
                    Spacer()
                    Text("VIGILANCE • KALİBRASYON")
                        .font(.mono(12, weight: .bold))
                        .foregroundColor(Color.vGreen)
                    Spacer()
                    Color.clear.frame(width: 28)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                // ── Faz rozetleri (sabit) ────────────────────
                HStack(spacing: 10) {
                    PhaseChip(number: 1, label: "GÖZ",
                              active: step == .phase1,
                              done:   step == .ready2 || step == .phase2 || step == .done)
                    Rectangle()
                        .fill(Color.vBorder)
                        .frame(width: 24, height: 1)
                    PhaseChip(number: 2, label: "AĞIZ",
                              active: step == .phase2,
                              done:   step == .done)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                // ── Kamera önizleme (sabit yükseklik) ────────
                ZStack {
                    CameraPreviewView(camera: camera)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(cameraStrokeColor, lineWidth: 2)
                                .animation(.easeInOut(duration: 0.4), value: step)
                        )

                    // Sağ üst: CANLI badge
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

                    // Aktif fazda progress overlay — alt kısım
                    if step == .phase1 || step == .phase2 {
                        VStack {
                            Spacer()
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Color.black.opacity(0.4).frame(height: 4)
                                    (step == .phase1 ? Color.vGreen : Color.orange)
                                        .frame(width: geo.size.width * engine.calibProgress,
                                               height: 4)
                                        .animation(.linear(duration: 0.1),
                                                   value: engine.calibProgress)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
                .frame(height: 220)
                .padding(.horizontal, 20)

                // ── İçerik alanı (SABİT YÜKSEKLIK — kayma önlenir) ──
                ZStack {
                    // Her durum için aynı frame, sadece içerik değişir
                    Group {
                        switch step {
                        case .ready1:
                            readyCard(
                                icon: "eye.fill",
                                color: Color.vGreen,
                                title: "Göz Kalibrasyonu Başlıyor",
                                body: "Lütfen kameraya düz bakın.\nAğzınızı kapalı tutun, hareket etmeyin.",
                                countdown: countdown
                            )

                        case .phase1:
                            phase1Card()

                        case .ready2:
                            readyCard(
                                icon: "mouth.fill",
                                color: .orange,
                                title: "Ağız Kalibrasyonu Başlıyor",
                                body: "Ekrandaki metni normal sesle okuyun.\nBu aşamada sistem ağız aralığını hesaplar.",
                                countdown: countdown
                            )

                        case .phase2:
                            phase2Card()

                        case .done:
                            doneCard()
                        }
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)  // SABİT — içerik ne olursa olsun yükseklik değişmez
                .padding(.horizontal, 20)
                .padding(.top, 14)

                Spacer()

                // ── Alt buton (sabit) ─────────────────────────
                VStack(spacing: 0) {
                    Button {
                        if step == .done {
                            engine.saveBaseline(for: store.currentProfile.id.uuidString)
                            store.appState = .driving
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if step == .done {
                                Image(systemName: "play.fill")
                                Text("Sürüşe Başla")
                            } else {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(white: 0.5)))
                                    .scaleEffect(0.8)
                                Text(buttonLabel)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(step == .done ? Color.vGreen : Color.vCard)
                        .foregroundColor(step == .done ? .black : Color(white: 0.4))
                        .fontWeight(.semibold)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.vBorder, lineWidth: step == .done ? 0 : 1)
                        )
                    }
                    .disabled(step != .done)
                    .padding(.horizontal, 20)

                    Button("Şimdilik atla") {
                        stopAll()
                        store.appState = .driving
                    }
                    .font(.system(size: 13))
                    .foregroundColor(Color(white: 0.3))
                    .padding(.vertical, 14)
                }
            }
        }
        .onAppear { startFlow() }
        .onDisappear { stopAll() }
    }

    // MARK: - Alt Kartlar

    @ViewBuilder
    private func readyCard(icon: String, color: Color, title: String, body: String, countdown: Int) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 22))
                        .foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                    Text(body)
                        .font(.system(size: 12))
                        .foregroundColor(Color(white: 0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Geri sayım
            HStack(spacing: 6) {
                Text("Başlıyor")
                    .font(.mono(11, weight: .bold))
                    .foregroundColor(Color(white: 0.4))
                Spacer()
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.3), lineWidth: 3)
                        .frame(width: 40, height: 40)
                    Text("\(countdown)")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(color)
                }
            }
        }
        .padding(16)
        .background(Color.vCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.vBorder, lineWidth: 1))
    }

    @ViewBuilder
    private func phase1Card() -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill").foregroundColor(Color.vGreen)
                Text("GÖZE BAKIYOR — HAREKETSİZ KALIN")
                    .font(.mono(9, weight: .bold))
                    .foregroundColor(Color(white: 0.5))
                Spacer()
                Text("%\(Int(engine.calibProgress * 100))")
                    .font(.mono(11, weight: .bold))
                    .foregroundColor(Color.vGreen)
            }

            VStack(spacing: 8) {
                infoRow(icon: "eye", text: "Kameraya düz bakın")
                infoRow(icon: "mouth.fill", text: "Ağzınızı kapalı tutun")
                infoRow(icon: "figure.stand", text: "Başınızı hareket ettirmeyin")
            }
        }
        .padding(16)
        .background(Color.vCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.vGreen.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func phase2Card() -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mouth.fill").foregroundColor(.orange)
                Text("AĞIZ ÖLÇÜLÜYOR — OKUMAYA DEVAM EDİN")
                    .font(.mono(9, weight: .bold))
                    .foregroundColor(Color(white: 0.5))
                Spacer()
                Text("%\(Int(engine.calibProgress * 100))")
                    .font(.mono(11, weight: .bold))
                    .foregroundColor(.orange)
            }

            // Dönen metin kutusu
            Text(readTexts[textIndex])
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color.vBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1.5)
                )
                .animation(.easeInOut(duration: 0.35), value: textIndex)
        }
        .padding(16)
        .background(Color.vCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    @ViewBuilder
    private func doneCard() -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(Color.vGreen)
            Text("Kalibrasyon Tamamlandı")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(.white)
            VStack(spacing: 6) {
                doneRow(icon: "eye.fill",   color: Color.vGreen,  text: "Göz referansı kaydedildi")
                doneRow(icon: "mouth.fill", color: Color.orange,  text: "Ağız referansı kaydedildi")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color.vCard)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.vGreen.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Küçük Yardımcı View'lar

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(Color.vGreen)
                .frame(width: 18)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.7))
            Spacer()
        }
    }

    private func doneRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(color).frame(width: 18)
            Text(text).font(.system(size: 13)).foregroundColor(Color(white: 0.6))
            Spacer()
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundColor(color)
        }
    }

    // MARK: - Akış Yönetimi

    private var cameraStrokeColor: Color {
        switch step {
        case .phase1:          return Color.vGreen
        case .ready2, .phase2: return Color.orange
        case .done:            return Color.vGreen
        default:               return Color.vBorder
        }
    }

    private var buttonLabel: String {
        switch step {
        case .ready1:  return "Göz kalibrasyonu hazırlanıyor…"
        case .phase1:  return "Göz kalibrasyonu devam ediyor…"
        case .ready2:  return "Ağız kalibrasyonu hazırlanıyor…"
        case .phase2:  return "Ağız kalibrasyonu devam ediyor…"
        default:       return ""
        }
    }

    private func startFlow() {
        camera.start()

        // Kamera frame'lerini engine'e bağla — kalibrasyon fazında feedCalibFrame
        camera.onFrame = { ear, mar, pitch, yaw, roll in
            engine.feedCalibFrame(ear: ear, mar: mar,
                                  pitch: pitch, yaw: yaw, roll: roll)
        }

        // Akışı başlat: 3s hazırlık → Faz 1
        step      = .ready1
        countdown = 3
        runReadyCountdown {
            // Faz 1 başlat
            engine.startCalibration(fps: 30, profileId: store.currentProfile.id.uuidString)
            withAnimation { self.step = .phase1 }

            // Faz 1 biterken (engine.calibPhase == 2 olduğunda) ara ekrana geç
            self.watchForPhase2()
        }
    }

    /// 3s geri sayım — her saniye countdown azalır, bitince completion çağrılır
    private func runReadyCountdown(completion: @escaping () -> Void) {
        countdown = 3
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            DispatchQueue.main.async {
                if self.countdown > 1 {
                    self.countdown -= 1
                } else {
                    t.invalidate()
                    completion()
                }
            }
        }
    }

    /// Engine'in Faz 2'ye geçmesini izle (calibPhase == 2)
    private func watchForPhase2() {
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
            DispatchQueue.main.async {
                guard self.engine.calibPhase == 2 else { return }
                t.invalidate()

                // 3s ara ekranı → Faz 2
                withAnimation { self.step = .ready2 }
                self.runReadyCountdown {
                    withAnimation { self.step = .phase2 }
                    self.startTextRotation()
                    self.watchForDone()
                }
            }
        }
    }

    /// Engine'in tamamlanmasını izle (calibPhase == 0 ve isCalibrating == false)
    private func watchForDone() {
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { t in
            DispatchQueue.main.async {
                guard !self.engine.isCalibrating && self.engine.calibPhase == 0 else { return }
                t.invalidate()
                self.textTimer?.invalidate()
                withAnimation { self.step = .done }
            }
        }
    }

    private func startTextRotation() {
        textTimer?.invalidate()
        textIndex = 0
        textTimer = Timer.scheduledTimer(withTimeInterval: 1.7, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation { self.textIndex = (self.textIndex + 1) % self.readTexts.count }
            }
        }
    }

    private func stopAll() {
        stepTimer?.invalidate()
        textTimer?.invalidate()
        camera.stop()
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
                    .fill(done ? Color.vGreen : (active ? Color.vGreen.opacity(0.25) : Color.vCard))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(
                        done ? Color.vGreen : (active ? Color.vGreen : Color.vBorder),
                        lineWidth: 1.5))
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.black)
                } else {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(active ? Color.vGreen : Color(white: 0.4))
                }
            }
            Text(label)
                .font(.mono(9, weight: .bold))
                .foregroundColor(done ? Color.vGreen : (active ? Color.vGreen : Color(white: 0.4)))
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background((active || done) ? Color.vGreen.opacity(0.08) : Color.clear)
        .cornerRadius(20)
    }
}
