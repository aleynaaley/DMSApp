import Foundation
import Combine

// MARK: - RuleEngine
// Hibrit karar sistemi: BiLSTM model skoru + kural tabanlı doğrulama.
//
// Literatür:
//   Abe T. (2023). PERCLOS-based technologies for detecting drowsiness.
//   SLEEP Advances, 4(1). https://doi.org/10.1093/sleepadvances/zpad006
//
//   Murata A. et al. (2022). Sensitivity of PERCLOS70 to drowsiness.
//   IEEE Access, 10, 70806-70814. https://doi.org/10.1109/ACCESS.2022.3187995

class RuleEngine: ObservableObject {

    // MARK: - Kural Parametreleri

    /// PERCLOS eşiği: %15
    /// Kaynak: Abe T. (2023), SLEEP Advances — kapsamlı literatür review.
    static let perclosThreshold: Double = 0.15

    /// Kritik göz kapanma süresi: 1.5 saniye
    /// Kaynak: Murata A. et al. (2022), IEEE Access — 1s microsleep kritik nokta.
    static let criticalClosureSec: Double = 1.5

    /// Yawn sayacı: 5 dakikada 3+ yawn
    /// Kaynak: Abtahi M. et al. (2014), YawDD dataset.
    static let yawnCountThreshold: Int    = 3
    static let yawnWindowSec     : Double = 300.0

    /// Model eşiği
    static let modelThreshold: Double = 0.5

    /// Uyarılar arası minimum süre
    static let alertCooldownSec: Double = 10.0

    // MARK: - Published State
    var yawnCount5min : Int    = 0
    var perclos60s    : Double = 0.0
    var closureSec    : Double = 0.0
    var activeSignals : [String] = []

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
        lastAlertTime  = .distantPast
        yawnCount5min  = 0; perclos60s = 0.0
        closureSec     = 0.0; activeSignals = []
    }

    // MARK: - Ana Değerlendirme
    func evaluate(
        eyeClosed  : Bool,
        isYawning  : Bool,
        modelScore : Double,
        now        : Date = Date()
    ) -> RuleDecision {

        activeSignals = []

        // 1. Yawn sayacı
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

        // 2. PERCLOS
        let maxBuf = Int(fps * 60)
        eyeClosedBuf.append(eyeClosed ? 1.0 : 0.0)
        if eyeClosedBuf.count > maxBuf { eyeClosedBuf.removeFirst() }
        perclos60s = eyeClosedBuf.reduce(0,+) / Double(max(1, eyeClosedBuf.count))
        if perclos60s >= Self.perclosThreshold {
            activeSignals.append(String(format: "PERCLOS %.0f%%", perclos60s * 100))
        }

        // 3. Kritik göz kapanma
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
                    shouldAlert: true, level: .critical,
                    reason: String(format: "Göz kapanma %.1fs!", closureSec)
                )
            }
        }

        // 4. Model + Kural birleşimi
        let ruleFired = !activeSignals.isEmpty
        let modelHigh = modelScore >= Self.modelThreshold

        if modelHigh && ruleFired {
            if canFire(now: now) {
                return RuleDecision(
                    shouldAlert: true, level: .warning,
                    reason: activeSignals.joined(separator: " | ")
                )
            }
            return RuleDecision(shouldAlert: false, level: .warning,
                                reason: activeSignals.joined(separator: " | "))
        }
        if ruleFired {
            return RuleDecision(shouldAlert: false, level: .caution,
                                reason: activeSignals.joined(separator: " | "))
        }
        if modelHigh {
            return RuleDecision(shouldAlert: false, level: .caution,
                                reason: "Model skoru yüksek")
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
