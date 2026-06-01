import Foundation

// MARK: - Fatigue Engine (Python v8'in birebir Swift portu)
//
// Mimari:
//   Göz kapanma / PERCLOS / Microsleep → %100 MediaPipe blink_score
//   Yawning episode                    → %100 SqueezeNet yawn_prob
//
// Tüm eşikler literatüre dayalıdır.

final class FatigueEngine {

    // MARK: - Literatür tabanlı eşikler

    // Kırpma filtresi: <400ms = normal kırpma (arXiv 2024, 2407.02222)
    static let blinkMaxSec: Double = 0.40

    // Microsleep: 500ms+ hafif (IOVS 2011), 2s+ ciddi (Williamson 2022)
    static let msWarnSec: Double = 0.50
    static let msCritSec: Double = 2.00

    // MediaPipe blendshape göz kapalı eşiği (Lin et al. 2022, Sensors 22(19))
    static let blinkThreshold: Double = 0.35

    // PERCLOS (Abe 2023, SLEEP Advances)
    static let perclosWindowSec: Double = 30.0
    static let perclosWarn: Double      = 0.15   // %15 → WARNING
    static let perclosCrit: Double      = 0.30   // %30 → DANGER

    // Yawning (Vural 2018 IEEE TNSRE, Zhang & Cheng 2020)
    static let minYawnDurationSec: Double = 2.0
    static let yawnWindowSec: Double      = 300.0
    static let yawnWarn: Int              = 2
    static let yawnCrit: Int              = 3
    static let yawnProbThreshold: Double  = 0.40
    static let smoothWindowSize: Int      = 5

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

    // İstatistik
    private(set) var dangerFromMP: Int    = 0
    private(set) var dangerFromModel: Int = 0
    private(set) var frameCount: Int      = 0
    private(set) var safeFrames: Int      = 0
    private(set) var warningFrames: Int   = 0
    private(set) var dangerFrames: Int    = 0
    private(set) var maxPerclos: Double   = 0

    // Kişisel kalibrasyon eşiği (nil ise global 0.35)
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
        dangerFromMP = 0
        dangerFromModel = 0
        frameCount = 0
        safeFrames = 0
        warningFrames = 0
        dangerFrames = 0
        maxPerclos = 0
    }

    // MARK: - Result
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

    // MARK: - Update (her frame)
    func update(
        yawnProb: Double,
        blinkScore: Double,
        faceDetected: Bool,
        timestamp: Double
    ) -> EngineResult {

        frameCount += 1

        let threshold = personalBlinkThreshold ?? Self.blinkThreshold

        // 1. Göz kapanma (MediaPipe)
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

        // 3. Microsleep seviyesi
        let msLevel: Int
        if closedDuration <= Self.blinkMaxSec      { msLevel = 0 }  // kırpma
        else if closedDuration <= Self.msWarnSec   { msLevel = 0 }  // sınırda
        else if closedDuration <= Self.msCritSec   { msLevel = 1 }  // hafif → WARNING
        else                                       { msLevel = 2 }  // ciddi → DANGER

        // 4. Yawning episode (model — majority vote)
        yawnSmoothBuffer.append(yawnProb)
        if yawnSmoothBuffer.count > Self.smoothWindowSize { yawnSmoothBuffer.removeFirst() }
        let smoothYawn = yawnSmoothBuffer.reduce(0, +) / Double(yawnSmoothBuffer.count)
        let yawnVotes  = yawnSmoothBuffer.filter { $0 > Self.yawnProbThreshold }.count
        let isYawning  = faceDetected && yawnVotes >= 2

        if isYawning && !inYawnEpisode {
            inYawnEpisode = true
            yawnStartTs = timestamp
        } else if !isYawning && inYawnEpisode {
            let duration = timestamp - (yawnStartTs ?? timestamp)
            if duration >= Self.minYawnDurationSec {
                yawnEpisodeTimes.append(yawnStartTs ?? timestamp)
            }
            inYawnEpisode = false
            yawnStartTs = nil
        }

        let cutoff = timestamp - Self.yawnWindowSec
        yawnEpisodeTimes.removeAll { $0 < cutoff }
        let yawnCount = yawnEpisodeTimes.count

        // 5. Alert seviyesi
        let (alertLevel, reason) = computeAlert(
            perclos: perclos, msLevel: msLevel, yawnCount: yawnCount)

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
            alertLevel: alertLevel,
            perclos: perclos,
            yawnCount: yawnCount,
            eyeClosed: eyeClosed,
            smoothYawn: smoothYawn,
            msLevel: msLevel,
            closedDuration: closedDuration,
            alertReason: reason
        )
    }

    // MARK: - Alert hesabı (v8 birebir)
    private func computeAlert(perclos: Double, msLevel: Int, yawnCount: Int) -> (AlertLevel, String) {
        // DANGER
        if msLevel == 2              { return (.danger, "microsleep_crit") }  // ≥2s (Williamson 2022)
        if perclos >= Self.perclosCrit { return (.danger, "perclos_crit") }   // ≥%30 (Abe 2023)
        if yawnCount >= Self.yawnCrit  { return (.danger, "yawn_crit") }       // ≥3 esneme (Vural 2018)
        // WARNING
        if msLevel == 1              { return (.warning, "microsleep_warn") }  // 500ms-2s (IOVS 2011)
        if perclos >= Self.perclosWarn { return (.warning, "perclos_warn") }   // ≥%15 (Abe 2023)
        if yawnCount >= Self.yawnWarn  { return (.warning, "yawn_warn") }      // ≥2 esneme (Vural 2018)
        return (.safe, "normal")
    }

    // MARK: - Özet
    var totalFrames: Int { frameCount }
    var safePercent: Double { frameCount > 0 ? Double(safeFrames) / Double(frameCount) * 100 : 0 }
    var warningPercent: Double { frameCount > 0 ? Double(warningFrames) / Double(frameCount) * 100 : 0 }
    var dangerPercent: Double { frameCount > 0 ? Double(dangerFrames) / Double(frameCount) * 100 : 0 }
}
