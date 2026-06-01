import Foundation

// MARK: - Fatigue Engine (Python v8'in birebir Swift portu)
//
// Mimari:
//   Göz kapanma / PERCLOS / Microsleep → %100 MediaPipe blink_score
//   Yawning episode                    → %100 SqueezeNet yawn_prob

final class FatigueEngine {

    // MARK: - Literatür tabanlı eşikler
    static let blinkMaxSec: Double = 0.40
    static let msWarnSec: Double = 0.50
    static let msCritSec: Double = 2.00
    static let blinkThreshold: Double = 0.35
    static let perclosWindowSec: Double = 30.0
    static let perclosWarn: Double      = 0.15
    static let perclosCrit: Double      = 0.30

    // Yawning (Vural 2018, ortalama esneme 4s / 6s — Neuromorphic 2023, Wikipedia)
    static let minYawnDurationSec: Double = 2.0
    static let yawnWindowSec: Double      = 300.0
    static let yawnWarn: Int              = 2
    static let yawnCrit: Int              = 3
    static let yawnProbThreshold: Double  = 0.40
    static let smoothWindowSize: Int      = 10   // büyük pencere → anlık 0.00'lar erir

    // Debug yazdırma (test bitince false yap)
    static let debugYawn: Bool = true

    // MARK: - State
    private let fps: Double
    private var eyeClosedBuffer: [Int] = []
    private var perclosMaxSize: Int
    private var yawnSmoothBuffer: [Double] = []
    private var eyeClosedSince: Double?
    private(set) var consecEyeClosed: Int = 0
    private var yawnEpisodeTimes: [Double] = []
    private var yawnStartTs: Double?
    private var inYawnEpisode: Bool = false
    private var yawnCounted: Bool = false
    private var yawnGapFrames: Int = 0
    private let yawnMaxGapFrames: Int = 30      // ~1s kesintiye tolerans

    // İstatistik
    private(set) var dangerFromMP: Int    = 0
    private(set) var dangerFromModel: Int = 0
    private(set) var frameCount: Int      = 0
    private(set) var safeFrames: Int      = 0
    private(set) var warningFrames: Int   = 0
    private(set) var dangerFrames: Int    = 0
    private(set) var maxPerclos: Double   = 0

    var personalBlinkThreshold: Double?

    init(fps: Double = 30.0) {
        self.fps = fps
        self.perclosMaxSize = max(1, Int(Self.perclosWindowSec * fps))
    }

    func reset() {
        eyeClosedBuffer.removeAll()
        yawnSmoothBuffer.removeAll()
        eyeClosedSince = nil
        consecEyeClosed = 0
        yawnEpisodeTimes.removeAll()
        yawnStartTs = nil
        inYawnEpisode = false
        yawnCounted = false
        yawnGapFrames = 0
        dangerFromMP = 0
        dangerFromModel = 0
        frameCount = 0
        safeFrames = 0
        warningFrames = 0
        dangerFrames = 0
        maxPerclos = 0
    }

    struct EngineResult {
        var alertLevel: AlertLevel
        var perclos: Double
        var yawnCount: Int
        var eyeClosed: Bool
        var smoothYawn: Double
        var msLevel: Int
        var closedDuration: Double
        var alertReason: String
    }

    func update(
        yawnProb: Double,
        blinkScore: Double,
        faceDetected: Bool,
        timestamp: Double
    ) -> EngineResult {

        frameCount += 1
        let threshold = personalBlinkThreshold ?? Self.blinkThreshold

        // 1. Göz kapanma
        let eyeClosed = faceDetected && blinkScore > threshold
        eyeClosedBuffer.append(eyeClosed ? 1 : 0)
        if eyeClosedBuffer.count > perclosMaxSize { eyeClosedBuffer.removeFirst() }

        if eyeClosed {
            consecEyeClosed += 1
            if eyeClosedSince == nil { eyeClosedSince = timestamp }
        } else {
            consecEyeClosed = 0
            eyeClosedSince = nil
        }
        let closedDuration = eyeClosedSince.map { timestamp - $0 } ?? 0

        // 2. PERCLOS
        let perclos = eyeClosedBuffer.isEmpty ? 0 :
            Double(eyeClosedBuffer.reduce(0, +)) / Double(eyeClosedBuffer.count)
        maxPerclos = max(maxPerclos, perclos)

        // 3. Microsleep
        let msLevel: Int
        if closedDuration <= Self.blinkMaxSec      { msLevel = 0 }
        else if closedDuration <= Self.msWarnSec   { msLevel = 0 }
        else if closedDuration <= Self.msCritSec   { msLevel = 1 }
        else                                       { msLevel = 2 }

        // 4. Yawning episode
        yawnSmoothBuffer.append(yawnProb)
        if yawnSmoothBuffer.count > Self.smoothWindowSize { yawnSmoothBuffer.removeFirst() }
        let smoothYawn = yawnSmoothBuffer.reduce(0, +) / Double(yawnSmoothBuffer.count)
        let yawnVotes  = yawnSmoothBuffer.filter { $0 > Self.yawnProbThreshold }.count
        let isYawning  = faceDetected && yawnVotes >= 2

        if isYawning {
            yawnGapFrames = 0
            if !inYawnEpisode {
                inYawnEpisode = true
                yawnStartTs = timestamp
                yawnCounted = false
            }
            let duration = timestamp - (yawnStartTs ?? timestamp)
            if Self.debugYawn {
                print(String(format: "😮 ESNIYOR votes=%d/%d yawn=%.2f süre=%.2fs sayıldı=%@ toplam=%d",
                             yawnVotes, yawnSmoothBuffer.count, yawnProb, duration, yawnCounted ? "E":"H", yawnEpisodeTimes.count))
            }
            if duration >= Self.minYawnDurationSec && !yawnCounted {
                yawnEpisodeTimes.append(yawnStartTs ?? timestamp)
                yawnCounted = true
                if Self.debugYawn { print("✅✅✅ ESNEME SAYILDI! toplam=\(yawnEpisodeTimes.count)") }
            }
        } else if inYawnEpisode {
            yawnGapFrames += 1
            let duration = timestamp - (yawnStartTs ?? timestamp)
            if Self.debugYawn {
                print(String(format: "⏸️ kesinti gap=%d/%d yawn=%.2f süre=%.2fs", yawnGapFrames, yawnMaxGapFrames, yawnProb, duration))
            }
            if duration >= Self.minYawnDurationSec && !yawnCounted {
                yawnEpisodeTimes.append(yawnStartTs ?? timestamp)
                yawnCounted = true
                if Self.debugYawn { print("✅✅✅ ESNEME SAYILDI (gap'te)! toplam=\(yawnEpisodeTimes.count)") }
            }
            if yawnGapFrames > yawnMaxGapFrames {
                inYawnEpisode = false
                yawnStartTs = nil
                yawnCounted = false
                yawnGapFrames = 0
                if Self.debugYawn { print("🛑 episode bitti") }
            }
        }

        let cutoff = timestamp - Self.yawnWindowSec
        yawnEpisodeTimes.removeAll { $0 < cutoff }
        let yawnCount = yawnEpisodeTimes.count

        // 5. Alert
        let (alertLevel, reason) = computeAlert(perclos: perclos, msLevel: msLevel, yawnCount: yawnCount)

        // 6. İstatistik
        switch alertLevel {
        case .safe:    safeFrames += 1
        case .warning: warningFrames += 1
        case .danger:  dangerFrames += 1
        }
        if alertLevel == .danger {
            if msLevel == 2 || perclos >= Self.perclosCrit { dangerFromMP += 1 }
            else { dangerFromModel += 1 }
        }

        return EngineResult(
            alertLevel: alertLevel, perclos: perclos, yawnCount: yawnCount,
            eyeClosed: eyeClosed, smoothYawn: smoothYawn, msLevel: msLevel,
            closedDuration: closedDuration, alertReason: reason)
    }

    private func computeAlert(perclos: Double, msLevel: Int, yawnCount: Int) -> (AlertLevel, String) {
        if msLevel == 2              { return (.danger, "microsleep_crit") }
        if perclos >= Self.perclosCrit { return (.danger, "perclos_crit") }
        if yawnCount >= Self.yawnCrit  { return (.danger, "yawn_crit") }
        if msLevel == 1              { return (.warning, "microsleep_warn") }
        if perclos >= Self.perclosWarn { return (.warning, "perclos_warn") }
        if yawnCount >= Self.yawnWarn  { return (.warning, "yawn_warn") }
        return (.safe, "normal")
    }

    var totalFrames: Int { frameCount }
    var safePercent: Double { frameCount > 0 ? Double(safeFrames) / Double(frameCount) * 100 : 0 }
    var warningPercent: Double { frameCount > 0 ? Double(warningFrames) / Double(frameCount) * 100 : 0 }
    var dangerPercent: Double { frameCount > 0 ? Double(dangerFrames) / Double(frameCount) * 100 : 0 }
}
