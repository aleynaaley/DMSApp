import Foundation
import Combine

// MARK: - RuleEngine
// Hibrit karar sistemi: Kural tabanlı + BiLSTM model skoru.
//
// Akademik Kaynaklar:
// [1] PERCLOS %15: Abe T. (2023). SLEEP Advances, 4(1). doi:10.1093/sleepadvances/zpad006
// [2] Kritik kapanma 1.5s: Murata A. et al. (2022). IEEE Access, 10, 70806–70814.
// [3] Yawn 5dk'da 3+: Abtahi M. et al. (2014). YawDD. ACM MMSys.
// [4] Model eşiği 0.5: Graves & Schmidhuber (2005). IJCNN.
// [5] Hibrit üstünlüğü: Ngxande M. et al. (2017). Pattern Recognition Letters, 91.
// [6] Baş yönü / dikkat dağınıklığı:
//     Teyeb H. et al. (2017). Drowsy driver detection system based on new
//     eye tracking and head pose estimation techniques. IEEE ICCE 2017.
//     → Yaw >35° anlık bakış açısı dikkat dağınıklığı göstergesi.
//     Wierwille W.W. et al. (1994). Research on vehicle-based driver status/
//     performance monitoring. AAA Foundation for Traffic Safety.
//     → 120s birikimli yola bakmama kritik dikkat dağınıklığı sınırı.

class RuleEngine: ObservableObject {

    // MARK: - Eşikler

    /// PERCLOS %15 [1]
    static let perclosThreshold   : Double = 0.15
    /// Kritik göz kapanma 1.5s [2]
    static let criticalClosureSec : Double = 1.5
    /// 5dk'da 3 yawn [3]
    static let yawnCountThreshold : Int    = 3
    static let yawnWindowSec      : Double = 300.0
    /// Model eşiği [4]
    static let modelThreshold     : Double = 0.5
    /// Uyarılar arası cooldown
    static let alertCooldownSec   : Double = 10.0
    /// Warmup: ilk N frame SAFE döner
    static let warmupFrames       : Int    = 30
    /// Baş yönü — anlık yaw eşiği [6]
    static let yawAngleThreshold  : Double = 35.0
    /// Baş yönü — anlık pitch eşiği [6]
    static let pitchAngleThreshold: Double = 25.0
    /// Birikimli yola bakmama eşiği: 120s [6]
    static let yawAccumThreshold  : Double = 120.0

    // MARK: - Public State
    var yawnCount5min    : Int     = 0
    var perclos60s       : Double  = 0.0
    var closureSec       : Double  = 0.0
    var activeSignals    : [String] = []
    var frameCount       : Int     = 0
    /// Birikimli yola bakmama süresi (UI için)
    var yawAccumSec      : Double  = 0.0
    /// Sürücü kamerada yok mu
    var driverMissing    : Bool    = false

    // MARK: - Private
    private var yawnTimestamps  : [Date]   = []
    private var eyeClosedBuf    : [Double] = []
    private var eyeClosedStart  : Date?    = nil
    private var criticalFired   : Bool     = false
    private var lastAlertTime   : Date     = .distantPast
    private let fps             : Double

    // Baş yönü takibi
    private var highYawStart    : Date?    = nil   // anlık yaw >35° ne zaman başladı
    private var yawAccumTotal   : Double   = 0.0   // birikimli yola bakmama süresi (s)
    private var lastYawCheck    : Date?    = nil   // son frame zamanı (delta hesabı)

    // Yüz yok takibi
    private var noFaceStart     : Date?    = nil

    init(fps: Double = 30.0) { self.fps = fps }

    func reset() {
        yawnTimestamps = []; eyeClosedBuf = []
        eyeClosedStart = nil; criticalFired = false
        lastAlertTime = .distantPast
        yawnCount5min = 0; perclos60s = 0; closureSec = 0
        activeSignals = []; frameCount = 0
        yawAccumTotal = 0; yawAccumSec = 0
        highYawStart = nil; lastYawCheck = nil
        noFaceStart = nil; driverMissing = false
    }

    // MARK: - Yüz Yok Bildirimi (DrowsinessEngine çağırır)
    /// Kamerada yüz bulunamadığında çağrılır.
    /// 3s sonra driverMissing = true yapar, ses çalmaz.
    func reportNoFace(now: Date = Date()) {
        if noFaceStart == nil { noFaceStart = now }
        let elapsed = now.timeIntervalSince(noFaceStart!)
        if elapsed >= 3.0 { driverMissing = true }
    }

    func reportFaceFound() {
        noFaceStart   = nil
        driverMissing = false
    }

    // MARK: - Ana Değerlendirme
    func evaluate(
        eyeClosed  : Bool,
        isYawning  : Bool,
        modelScore : Double,
        pitch      : Double = 0,
        yaw        : Double = 0,
        now        : Date   = Date()
    ) -> RuleDecision {

        frameCount += 1
        activeSignals = []

        // ── Warmup [ilk 30 frame SAFE] ────────────────────
        if frameCount < Self.warmupFrames {
            return RuleDecision(shouldAlert: false, level: .safe,
                                reason: "Başlatılıyor… (\(frameCount)/\(Self.warmupFrames))")
        }

        // ── Sürücü kamerada yok (ses yok) ─────────────────
        if driverMissing {
            return RuleDecision(shouldAlert: false, level: .caution,
                                reason: "⚠️ Sürücü kameradan çıktı")
        }

        // ── 1. Yawn sayacı [3] ────────────────────────────
        if isYawning,
           yawnTimestamps.isEmpty ||
           now.timeIntervalSince(yawnTimestamps.last!) > 3.0 {
            yawnTimestamps.append(now)
        }
        yawnTimestamps = yawnTimestamps.filter {
            now.timeIntervalSince($0) < Self.yawnWindowSec
        }
        yawnCount5min = yawnTimestamps.count
        if yawnCount5min >= Self.yawnCountThreshold {
            activeSignals.append("Yawn \(yawnCount5min)/5dk")
        }

        // ── 2. PERCLOS [1] ────────────────────────────────
        let maxBuf = Int(fps * 60)
        eyeClosedBuf.append(eyeClosed ? 1.0 : 0.0)
        if eyeClosedBuf.count > maxBuf { eyeClosedBuf.removeFirst() }
        perclos60s = eyeClosedBuf.reduce(0, +) / Double(max(1, eyeClosedBuf.count))
        if perclos60s >= Self.perclosThreshold {
            activeSignals.append(String(format: "PERCLOS %.0f%%", perclos60s * 100))
        }

        // ── 3. Kritik göz kapanma [2] ─────────────────────
        if eyeClosed {
            if eyeClosedStart == nil { eyeClosedStart = now; criticalFired = false }
            closureSec = now.timeIntervalSince(eyeClosedStart!)
        } else {
            eyeClosedStart = nil; closureSec = 0.0; criticalFired = false
        }
        if closureSec >= Self.criticalClosureSec && !criticalFired {
            criticalFired = true
            if canFire(now: now) {
                return RuleDecision(shouldAlert: true, level: .critical,
                                    reason: String(format: "Göz kapanma %.1fs! [Murata 2022]", closureSec))
            }
        }

        // ── 4. Baş yönü — pitch (öne düşme) [6] ──────────
        if abs(pitch) > Self.pitchAngleThreshold {
            activeSignals.append("Baş öne düşüyor")
        }

        // ── 5. Baş yönü — yaw birikimli (120s) [6] ───────
        // Anlık yaw >35° olan süreyi biriktirir.
        // 120s dolunca "Yola bakın" sinyali verilir.
        let frameDelta: Double
        if let last = lastYawCheck {
            frameDelta = min(now.timeIntervalSince(last), 0.5) // max 500ms delta
        } else {
            frameDelta = 1.0 / fps
        }
        lastYawCheck = now

        if abs(yaw) > Self.yawAngleThreshold {
            yawAccumTotal += frameDelta
        } else {
            // Yola bakınca yavaşça azalt (ceza yarıya iner)
            yawAccumTotal = max(0, yawAccumTotal - frameDelta * 0.5)
        }
        yawAccumSec = yawAccumTotal

        if yawAccumTotal >= Self.yawAccumThreshold {
            activeSignals.append(String(format: "Yola bakın (%.0fs)", yawAccumTotal))
            // Uyarı sonrası birikimi sıfırla — tekrar dolması gereksin
            yawAccumTotal = 0
        }

        // ── 6. Hibrit karar [4][5] ────────────────────────
        let modelValid = modelScore > 0.01 && modelScore < 0.98
        let modelHigh  = modelValid && modelScore >= Self.modelThreshold
        let ruleFired  = !activeSignals.isEmpty

        if modelHigh && ruleFired {
            if canFire(now: now) {
                return RuleDecision(shouldAlert: true, level: .warning,
                                    reason: activeSignals.joined(separator: " | ")
                                            + String(format: " (model: %.0f%%)", modelScore * 100))
            }
            return RuleDecision(shouldAlert: false, level: .warning,
                                reason: activeSignals.joined(separator: " | "))
        }
        if ruleFired {
            if activeSignals.count >= 2, canFire(now: now) {
                return RuleDecision(shouldAlert: true, level: .warning,
                                    reason: activeSignals.joined(separator: " | "))
            }
            return RuleDecision(shouldAlert: false, level: .caution,
                                reason: activeSignals.joined(separator: " | "))
        }
        if modelHigh {
            return RuleDecision(shouldAlert: false, level: .caution,
                                reason: String(format: "Model: %.0f%%", modelScore * 100))
        }
        return RuleDecision(shouldAlert: false, level: .safe, reason: "")
    }

    private func canFire(now: Date) -> Bool {
        guard now.timeIntervalSince(lastAlertTime) >= Self.alertCooldownSec else { return false }
        lastAlertTime = now
        return true
    }
}

// MARK: - RuleDecision
struct RuleDecision {
    let shouldAlert: Bool
    let level      : AlertLevel
    let reason     : String

    enum AlertLevel {
        case safe, caution, warning, critical

        var title: String {
            switch self {
            case .safe:     return "UYANIK"
            case .caution:  return "DİKKATLİ OL"
            case .warning:  return "YORGUNLUK"
            case .critical: return "KRİTİK!"
            }
        }
    }
}
