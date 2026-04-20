import Foundation
import CoreML
import AVFoundation
import AudioToolbox
import SwiftUI
import Combine

// MARK: - DrowsinessEngine
class DrowsinessEngine: ObservableObject {

    // MARK: - Published (UI)
    @Published var smoothedScore   : Double      = 0.0
    @Published var decision        : RuleDecision = .init(shouldAlert: false, level: .safe, reason: "")
    @Published var alertFired      : Bool         = false
    @Published var blinkRate       : Double       = 0.0
    @Published var perclos         : Double       = 0.0
    @Published var closureSec      : Double       = 0.0
    @Published var yawnCount       : Int          = 0
    @Published var sessionDuration : TimeInterval = 0
    @Published var microsleepTotal : Int          = 0
    @Published var driverMissing   : Bool         = false  // UI için
    @Published var yawAccumSec     : Double       = 0.0    // UI için

    // Kalibrasyon
    @Published var isCalibrating   : Bool         = false
    @Published var calibPhase      : Int          = 0
    @Published var calibProgress   : Double       = 0.0
    @Published var modelLoaded: Bool = true

    // MARK: - Private
    private var mlModel        : MLModel?
    private var trainMean      : [Float]  = []
    private var trainStd       : [Float]  = []
    private var nFeatures      : Int      = 51
    private var windowSize     : Int      = 30
    private var modelInputKey  : String   = "sequence"
    private var modelOutputKey : String   = "drowsiness_prob"

    private var featureBuf   = FeatureBuffer()
    private var ruleEngine   = RuleEngine()
    private var sequenceBuf  : [[Float]] = []
    private var scoreHistory : [Double]  = []

    private var baseline     = Baseline.default
    private var sessionStart = Date()
    private var fps          = 30.0
    private var frameId      = 0

    private var calibStart   = Date()
    private var calibEars    : [Double] = []
    private var calibMars    : [Double] = []
    private var calibPitches : [Double] = []
    private var calibYaws    : [Double] = []
    private var calibRolls   : [Double] = []

    // MARK: - Alert
    private var alertDismissTimer : Timer?
    private var alertRepeatTimer  : Timer?
    private var audioPlayer       : AVAudioPlayer?

    // MARK: - Init
    init() { loadModel() }

    // MARK: - Model Yükleme
    private func loadModel() {
        var found: [URL] = []
        for ext in ["mlpackage", "mlmodelc", "mlmodel"] {
            let urls = Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            found.append(contentsOf: urls)
        }
        print("🔍 Bundle ML dosyaları (\(found.count) adet):")
        found.forEach { print("   · \($0.lastPathComponent)") }

        guard let url = found.first(where: {
            $0.lastPathComponent.lowercased().contains("drowsiness")
        }) ?? found.first else {
            print("❌ Model bulunamadı!")
            return
        }
        print("🎯 Yükleniyor: \(url.lastPathComponent)")

        do {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            mlModel = try MLModel(contentsOf: url, configuration: cfg)

            let inputs  = mlModel!.modelDescription.inputDescriptionsByName
            let outputs = mlModel!.modelDescription.outputDescriptionsByName
            print("📥 Inputs : \(inputs.keys.sorted().joined(separator: ", "))")
            print("📤 Outputs: \(outputs.keys.sorted().joined(separator: ", "))")

            modelInputKey  = inputs.keys.first ?? "sequence"
            modelOutputKey = outputs.keys.contains("drowsiness_prob")
                             ? "drowsiness_prob"
                             : (outputs.keys.first ?? "drowsiness_prob")

            let meta = mlModel!.modelDescription.metadata[
                MLModelMetadataKey.creatorDefinedKey] as? [String: String] ?? [:]
            if let ws = meta["window_size"], let v = Int(ws) { windowSize = v }
            if let nf = meta["n_features"],  let v = Int(nf) { nFeatures  = v }
            if let sm = meta["train_mean"],
               let a  = try? JSONDecoder().decode([Float].self, from: Data(sm.utf8)) { trainMean = a }
            if let ss = meta["train_std"],
               let a  = try? JSONDecoder().decode([Float].self, from: Data(ss.utf8)) { trainStd  = a }

            print("✅ Model hazır — window=\(windowSize) features=\(nFeatures) input='\(modelInputKey)' output='\(modelOutputKey)'")
        } catch {
            print("❌ Model hatası: \(error.localizedDescription)")
        }
    }

    // MARK: - Audio
    private func activateAudio() {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, options: [.mixWithOthers, .duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func playAlertSound(level: RuleDecision.AlertLevel) {
        activateAudio()
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        AudioServicesPlaySystemSound(level == .critical ? 1005 : 1003)
        for url in [Bundle.main.url(forResource: "alert", withExtension: "wav"),
                    Bundle.main.url(forResource: "alert", withExtension: "mp3"),
                    URL(fileURLWithPath: "/System/Library/Audio/UISounds/alarm.caf")].compactMap({ $0 }) {
            if let p = try? AVAudioPlayer(contentsOf: url) {
                audioPlayer = p; p.volume = 1.0; p.play(); break
            }
        }
    }

    private func stopSound() { audioPlayer?.stop(); audioPlayer = nil }

    // MARK: - Alert (otomatik — sürücü müdahalesi yok)
    private func fireAlert(level: RuleDecision.AlertLevel) {
        guard !alertFired else { return }
        alertFired = true
        if level == .critical { microsleepTotal += 1 }
        playAlertSound(level: level)
        alertDismissTimer?.invalidate()
        alertDismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            DispatchQueue.main.async { self?.autoDismiss() }
        }
    }

    private func autoDismiss() {
        alertFired = false
        stopSound()
        alertDismissTimer?.invalidate()
        alertRepeatTimer?.invalidate()
        alertRepeatTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let s = self else { return }
                if s.decision.level == .warning || s.decision.level == .critical {
                    s.fireAlert(level: s.decision.level)
                }
            }
        }
    }

    func resetAlert() {
        alertFired = false
        [alertDismissTimer, alertRepeatTimer].forEach { $0?.invalidate() }
        alertDismissTimer = nil; alertRepeatTimer = nil
        stopSound()
    }

    // MARK: - Yüz Yok / Var Bildirimleri
    /// Kamerada yüz bulunamadığında CameraManager çağırır.
    /// 3s sonra driverMissing = true, ses çalmaz.
    func reportNoFace(now: Date = Date()) {
        ruleEngine.reportNoFace(now: now)
        DispatchQueue.main.async {
            self.driverMissing = self.ruleEngine.driverMissing
            // Yüz yokken caution kararı ver — ses yok
            if self.ruleEngine.driverMissing {
                let dec = RuleDecision(shouldAlert: false, level: .caution,
                                       reason: "⚠️ Sürücü kameradan çıktı")
                self.decision = dec
                self.objectWillChange.send()
            }
        }
    }

    func reportFaceFound() {
        ruleEngine.reportFaceFound()
        DispatchQueue.main.async {
            self.driverMissing = false
            self.objectWillChange.send()
        }
    }

    // MARK: - forceStart
    func forceStart(baseline: Baseline, fps: Double = 30.0) {
        self.baseline = baseline; self.fps = fps
        featureBuf = FeatureBuffer(fps: fps); ruleEngine = RuleEngine(fps: fps)
        sequenceBuf = []; scoreHistory = []; frameId = 0; sessionStart = Date()
        DispatchQueue.main.async { self.isCalibrating = false; self.calibPhase = 0 }
        print("✅ forceStart")
    }

    // MARK: - Kalibrasyon
    func startCalibration(fps: Double = 30.0, profileId: String? = nil) {
        self.fps = fps; calibPhase = 1; calibProgress = 0; calibStart = Date()
        calibEars=[]; calibMars=[]; calibPitches=[]; calibYaws=[]; calibRolls=[]
        isCalibrating = true
        if let pid = profileId, let saved = loadBaseline(for: pid) { baseline = saved }
        featureBuf = FeatureBuffer(fps: fps); ruleEngine = RuleEngine(fps: fps)
        sequenceBuf = []; scoreHistory = []; frameId = 0
    }

    func feedCalibFrame(ear: Double, mar: Double,
                        pitch: Double, yaw: Double, roll: Double) {
        guard isCalibrating else { return }
        let elapsed = Date().timeIntervalSince(calibStart)
        DispatchQueue.main.async { self.calibProgress = min(1.0, elapsed / 5.0) }
        switch calibPhase {
        case 1:
            calibEars.append(ear); calibMars.append(mar)
            calibPitches.append(pitch); calibYaws.append(yaw); calibRolls.append(roll)
            if elapsed >= 5.0 {
                DispatchQueue.main.async { self.calibPhase = 2; self.calibProgress = 0 }
                calibStart = Date()
            }
        case 2:
            calibMars.append(mar)  // Faz 2: sadece MAR topla (konuşma referansı)
            calibPitches.append(pitch); calibYaws.append(yaw)
            if elapsed >= 5.0 { finalizeCalibration() }
        default: break
        }
    }

    private func finalizeCalibration() {
        func med(_ a: [Double]) -> Double {
            guard !a.isEmpty else { return 0 }
            let s = a.sorted(); return s[s.count / 2]
        }
        // Faz 1'den EAR, Faz 1+2'den MAR (konuşma MAR'ı daha yüksek olacak)
        let allMars = calibMars
        baseline = Baseline(
            ear  : med(calibEars),
            mar  : med(allMars),
            pitch: med(calibPitches),
            yaw  : med(calibYaws),
            roll : med(calibRolls)
        )
        DispatchQueue.main.async { self.isCalibrating = false; self.calibPhase = 0 }
        sessionStart = Date()
        print("✅ Baseline — EAR=\(String(format:"%.4f",baseline.ear)) MAR=\(String(format:"%.4f",baseline.mar)) yawnEşik=\(String(format:"%.4f",baseline.marYawnThreshold))")
    }

    func saveBaseline(for id: String) {
        if let d = try? JSONEncoder().encode(baseline) {
            UserDefaults.standard.set(d, forKey: "baseline_\(id)")
        }
    }
    func loadBaseline(for id: String) -> Baseline? {
        guard let d = UserDefaults.standard.data(forKey: "baseline_\(id)"),
              let b = try? JSONDecoder().decode(Baseline.self, from: d) else { return nil }
        return b
    }

    // MARK: - Frame İşleme
    func processFrame(ear: Double, mar: Double,
                      pitch: Double, yaw: Double, roll: Double) {
        guard !isCalibrating else { return }
        let now = Date()

        // Yüz geldi — no-face timer sıfırla
        reportFaceFound()

        featureBuf.push(ear: ear, mar: mar, pitch: pitch,
                        yaw: yaw, roll: roll, baseline: baseline)

        let eyeClosed = ear < baseline.earCloseThreshold
        let isYawning = featureBuf.currentIsYawning

        // Debug log — her 5 saniyede
        if frameId % Int(fps * 5) == 0 {
            print("📊 Buffer:\(sequenceBuf.count)/\(windowSize) score:\(String(format:"%.3f",smoothedScore))")
            print("👄 MAR=\(String(format:"%.4f",mar)) baseline=\(String(format:"%.4f",baseline.mar)) eşik=\(String(format:"%.4f",baseline.marYawnThreshold)) yawn=\(isYawning)")
            print("👁️ EAR=\(String(format:"%.4f",ear)) eşik=\(String(format:"%.4f",baseline.earCloseThreshold)) closed=\(eyeClosed)")
            print("📐 pitch=\(String(format:"%.1f",pitch)) yaw=\(String(format:"%.1f",yaw)) yawAccum=\(String(format:"%.1f",ruleEngine.yawAccumSec))s")
        }

        if let fv = featureBuf.computeFeatureVector(baseline: baseline) {
            var norm = fv
            if !trainMean.isEmpty && !trainStd.isEmpty {
                for i in 0..<min(norm.count, trainMean.count) {
                    norm[i] = (norm[i] - trainMean[i]) / max(trainStd[i], 1e-6)
                }
            }
            sequenceBuf.append(norm)
            if sequenceBuf.count > windowSize { sequenceBuf.removeFirst() }
            if sequenceBuf.count == windowSize { runInference() }
        }

        let dec = ruleEngine.evaluate(
            eyeClosed  : eyeClosed,
            isYawning  : isYawning,
            modelScore : smoothedScore,
            pitch      : pitch,
            yaw        : yaw,
            now        : now
        )

        let bRate  = featureBuf.blinkRate5s
        let perc   = featureBuf.perclos10s
        let cSec   = ruleEngine.closureSec
        let yCnt   = ruleEngine.yawnCount5min
        let dur    = now.timeIntervalSince(sessionStart)
        let yawAcc = ruleEngine.yawAccumSec

        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            s.decision        = dec
            s.blinkRate       = bRate
            s.perclos         = perc
            s.closureSec      = cSec
            s.yawnCount       = yCnt
            s.sessionDuration = dur
            s.yawAccumSec     = yawAcc

            if dec.shouldAlert && !s.alertFired { s.fireAlert(level: dec.level) }
            s.objectWillChange.send()
        }
        frameId += 1
    }

    // MARK: - CoreML Inference
    private func runInference() {
        guard let model = mlModel else { return }
        let flat  = sequenceBuf.flatMap { $0 }
        let shape : [NSNumber] = [1, NSNumber(value: windowSize), NSNumber(value: nFeatures)]
        guard let arr = try? MLMultiArray(shape: shape, dataType: .float32) else { return }
        flat.enumerated().forEach { arr[$0.offset] = NSNumber(value: $0.element) }

        guard let inp = try? MLDictionaryFeatureProvider(dictionary: [modelInputKey: arr]),
              let out = try? model.prediction(from: inp) else {
            print("❌ Inference başarısız")
            return
        }

        var raw: Double = 0
        if let mv = out.featureValue(for: modelOutputKey)?.multiArrayValue {
            raw = Double(truncating: mv[0])
        } else if let fk = model.modelDescription.outputDescriptionsByName.keys.first,
                  let mv = out.featureValue(for: fk)?.multiArrayValue {
            raw = Double(truncating: mv[0])
        }

        scoreHistory.append(raw)
        if scoreHistory.count > Int(fps * 30) { scoreHistory.removeFirst() }
        let smoothed = scoreHistory.reduce(0, +) / Double(scoreHistory.count)
        print("🧠 Model → raw=\(String(format:"%.3f",raw)) smooth=\(String(format:"%.3f",smoothed))")

        DispatchQueue.main.async {
            self.smoothedScore = smoothed
            self.objectWillChange.send()
        }
    }

    func currentSessionStats(name: String = "Aktif Sürüş") -> DrivingSession {
        DrivingSession(
            name: name, date: sessionStart, duration: sessionDuration,
            safetyScore: Int(max(0, min(100, 100 - smoothedScore * 100))),
            alertCount: microsleepTotal, yawnCount: yawnCount, microsleeps: microsleepTotal
        )
    }
}
