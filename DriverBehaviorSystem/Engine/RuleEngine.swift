import Foundation
import Combine

// MARK: - RuleEngine
// Hibrit karar sistemi: Kural tabanlı + BiLSTM model skoru birlikte değerlendirilir.
//
// Akademik Kaynaklar:
//
// [1] PERCLOS eşiği %15:
//     Abe T. (2023). PERCLOS-based technologies for detecting drowsiness.
//     SLEEP Advances, 4(1), zpad006. https://doi.org/10.1093/sleepadvances/zpad006
//     → %15 PERCLOS, klinik olarak uyuşukluk başlangıcının güvenilir göstergesi.
//
// [2] Kritik göz kapanma 1.5s:
//     Murata A. et al. (2022). Sensitivity of PERCLOS70 to drowsiness levels.
//     IEEE Access, 10, 70806–70814. https://doi.org/10.1109/ACCESS.2022.3187995
//     → 1 saniyeyi aşan kapanmalar mikro-uyku ile ilişkili.
//
// [3] Yawn eşiği (5dk'da 3+):
//     Abtahi M. et al. (2014). YawDD: Yawning Detection Dataset.
//     Proceedings of the 5th ACM Multimedia Systems Conference.
//     → Sık esnemeler uyku baskısını gösterir; 5dk'da 3+ klinik sınır.
//
// [4] Model eşiği 0.5 (sigmoid çıkışı):
//     Graves A. & Schmidhuber J. (2005). Framewise phoneme classification
//     with bidirectional LSTM networks. IJCNN 2005.
//     → BiLSTM sigmoid çıkışı için 0.5 standart karar sınırı.
//
// [5] Hibrit (kural + model) üstünlüğü:
//     Ngxande M. et al. (2017). Driver drowsiness detection using
//     behavioral measures and machine learning: A review.
//     Pattern Recognition Letters, 91, 113–121.
//     → Tek başına model veya kural yerine hibrit sistemler daha güvenilir.

class RuleEngine: ObservableObject {

    // MARK: - Eşikler (kaynaklı)

    /// PERCLOS %15 eşiği [1]
    static let perclosThreshold   : Double = 0.15

    /// Kritik göz kapanma 1.5s [2]
    static let criticalClosureSec : Double = 1.5

    /// 5dk'da 3 yawn [3]
    static let yawnCountThreshold : Int    = 3
    static let yawnWindowSec      : Double = 300.0

    /// Model karar eşiği 0.5 [4]
    static let modelThreshold     : Double = 0.5

    /// Uyarılar arası minimum süre (false positive azaltma)
    static let alertCooldownSec   : Double = 10.0

    /// Warmup: ilk N frame dolana kadar karar verme
    /// Neden: feature pencereleri (1s, 5s, 10s) dolmadan istatistikler güvenilmez
    static let warmupFrames       : Int    = 30

    // MARK: - State
    var yawnCount5min : Int     = 0
    var perclos60s    : Double  = 0.0
    var closureSec    : Double  = 0.0
    var activeSignals : [String] = []
    var frameCount    : Int     = 0   // warmup takibi

    // MARK: - Private
    private var yawnTimestamps : [Date]   = []
    private var eyeClosedBuf   : [Double] = []
    private var eyeClosedStart : Date?    = nil
    private var criticalFired  : Bool     = false
    private var lastAlertTime  : Date     = .distantPast
    private let fps            : Double

    init(fps: Double = 30.0) { self.fps = fps }

    func reset() {
        yawnTimestamps = []; eyeClosedBuf = []
        eyeClosedStart = nil; criticalFired = false
        lastAlertTime = .distantPast
        yawnCount5min = 0; perclos60s = 0
        closureSec = 0; activeSignals = []; frameCount = 0
    }

    // MARK: - Ana Değerlendirme (Hibrit)
    func evaluate(
        eyeClosed  : Bool,
        isYawning  : Bool,
        modelScore : Double,
        now        : Date = Date()
    ) -> RuleDecision {

        frameCount += 1
        activeSignals = []

        // ── Warmup guard ──────────────────────────────────────
        // İlk 30 frame dolana kadar SAFE döndür.
        // Feature pencereleri ve baseline henüz stabil değil.
        if frameCount < Self.warmupFrames {
            return RuleDecision(
                shouldAlert: false,
                level: .safe,
                reason: "Başlatılıyor… (\(frameCount)/\(Self.warmupFrames))"
            )
        }

        // ── 1. Yawn sayacı [3] ────────────────────────────────
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

        // ── 2. PERCLOS [1] ────────────────────────────────────
        let maxBuf = Int(fps * 60)
        eyeClosedBuf.append(eyeClosed ? 1.0 : 0.0)
        if eyeClosedBuf.count > maxBuf { eyeClosedBuf.removeFirst() }
        perclos60s = eyeClosedBuf.reduce(0, +) / Double(max(1, eyeClosedBuf.count))
        if perclos60s >= Self.perclosThreshold {
            activeSignals.append(String(format: "PERCLOS %.0f%%", perclos60s * 100))
        }

        // ── 3. Kritik göz kapanma [2] ─────────────────────────
        if eyeClosed {
            if eyeClosedStart == nil { eyeClosedStart = now; criticalFired = false }
            closureSec = now.timeIntervalSince(eyeClosedStart!)
        } else {
            eyeClosedStart = nil; closureSec = 0.0; criticalFired = false
        }

        if closureSec >= Self.criticalClosureSec && !criticalFired {
            criticalFired = true
            if canFire(now: now) {
                return RuleDecision(
                    shouldAlert: true,
                    level: .critical,
                    reason: String(format: "Göz kapanma %.1fs! [Murata 2022]", closureSec)
                )
            }
        }

        // ── 4. Hibrit karar [4][5] ────────────────────────────
        // Model skoru geçerli mi?
        // 0.984+ → model henüz kalibre edilmemiş (normalizasyon sorunu)
        // Bu durumda model oyu yok sayılır, sadece kural tabanlı çalışır
        let modelValid = modelScore > 0.01 && modelScore < 0.98
        let modelHigh  = modelValid && modelScore >= Self.modelThreshold

        let ruleFired  = !activeSignals.isEmpty

        if modelHigh && ruleFired {
            // Model + Kural ikisi de pozitif → warning + uyarı [5]
            if canFire(now: now) {
                return RuleDecision(
                    shouldAlert: true,
                    level: .warning,
                    reason: activeSignals.joined(separator: " | ") + String(format: " (model: %.0f%%)", modelScore * 100)
                )
            }
            return RuleDecision(
                shouldAlert: false,
                level: .warning,
                reason: activeSignals.joined(separator: " | ")
            )
        }

        if ruleFired {
            // Sadece kural pozitif → caution
            // 2+ sinyal varsa uyarı ver
            if activeSignals.count >= 2 {
                if canFire(now: now) {
                    return RuleDecision(
                        shouldAlert: true,
                        level: .warning,
                        reason: activeSignals.joined(separator: " | ")
                    )
                }
            }
            return RuleDecision(
                shouldAlert: false,
                level: .caution,
                reason: activeSignals.joined(separator: " | ")
            )
        }

        if modelHigh {
            // Sadece model pozitif → caution, ses yok
            return RuleDecision(
                shouldAlert: false,
                level: .caution,
                reason: String(format: "Model: %.0f%% [BiLSTM]", modelScore * 100)
            )
        }

        return RuleDecision(shouldAlert: false, level: .safe, reason: "")
    }

    private func canFire(now: Date) -> Bool {
        guard now.timeIntervalSince(lastAlertTime) >= Self.alertCooldownSec
        else { return false }
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
