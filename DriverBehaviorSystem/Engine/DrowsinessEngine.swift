import Foundation
import CoreML
import AVFoundation
import AudioToolbox
import SwiftUI
import Combine


// MARK: - DrowsinessEngine
// CoreML inference + Feature hesaplama + Kural motoru.
// ViewModel olarak çalışır — View'lar @ObservedObject ile bağlanır.

class DrowsinessEngine: ObservableObject {

    // MARK: - Published (UI)
    @Published var smoothedScore  : Double = 0.0
    @Published var decision       : RuleDecision = .init(shouldAlert: false, level: .safe, reason: "")
    @Published var alertFired     : Bool   = false
    @Published var blinkRate      : Double = 0.0
    @Published var perclos        : Double = 0.0
    @Published var closureSec     : Double = 0.0
    @Published var yawnCount      : Int    = 0
    @Published var sessionDuration: TimeInterval = 0
    @Published var microsleepTotal: Int    = 0

    // Kalibrasyon
    @Published var isCalibrating  : Bool   = false
    @Published var calibPhase     : Int    = 0
    @Published var calibProgress  : Double = 0.0

    // MARK: - Private
    private var mlModel      : MLModel?
    private var trainMean    : [Float] = []
    private var trainStd     : [Float] = []
    private var nFeatures    : Int    = 51
    private var windowSize   : Int    = 30

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

    // MARK: - Init
    init() { loadModel() }

    // MARK: - Model Yükleme
    private func loadModel() {
        guard let url = Bundle.main.url(
            forResource: "DrowsinessModel", withExtension: "mlpackage"
        ) else { print("⚠️ DrowsinessModel.mlpackage bulunamadı!"); return }

        do {
            mlModel = try MLModel(contentsOf: url)
            let meta = mlModel!.modelDescription.metadata[
                MLModelMetadataKey.creatorDefinedKey] as? [String:String] ?? [:]

            if let ws = meta["window_size"], let v = Int(ws)    { windowSize = v }
            if let nf = meta["n_features"],  let v = Int(nf)    { nFeatures  = v }
            if let sm = meta["train_mean"],
               let a  = try? JSONDecoder().decode([Float].self,
                              from: sm.data(using:.utf8)!)       { trainMean  = a }
            if let ss = meta["train_std"],
               let a  = try? JSONDecoder().decode([Float].self,
                              from: ss.data(using:.utf8)!)       { trainStd   = a }
            print("✅ Model: \(nFeatures) feature, window=\(windowSize)")
        } catch { print("❌ Model hatası: \(error)") }
    }

    // MARK: - Kalibrasyon
    func startCalibration(fps: Double = 30.0, profileId: String? = nil) {
        self.fps = fps
        calibPhase = 1; calibProgress = 0
        calibStart = Date()
        calibEars=[]; calibMars=[]; calibPitches=[]; calibYaws=[]; calibRolls=[]
        isCalibrating = true

        if let pid = profileId, let saved = loadBaseline(for: pid) {
            baseline = saved
        }
        featureBuf  = FeatureBuffer(fps: fps)
        ruleEngine  = RuleEngine(fps: fps)
        sequenceBuf = []; scoreHistory = []; frameId = 0
    }

    func feedCalibFrame(ear: Double, mar: Double,
                        pitch: Double, yaw: Double, roll: Double) {
        guard isCalibrating else { return }
        let elapsed = Date().timeIntervalSince(calibStart)
        DispatchQueue.main.async { self.calibProgress = min(1.0, elapsed/5.0) }

        switch calibPhase {
        case 1:
            calibEars.append(ear); calibMars.append(mar)
            calibPitches.append(pitch); calibYaws.append(yaw); calibRolls.append(roll)
            if elapsed >= 5.0 {
                DispatchQueue.main.async {
                    self.calibPhase = 2
                    self.calibProgress = 0
                }
                calibStart = Date()
            }
        case 2:
            calibPitches.append(pitch); calibYaws.append(yaw)
            if elapsed >= 5.0 { finalizeCalibration() }
        default: break
        }
    }

    private func finalizeCalibration() {
        func med(_ a: [Double]) -> Double {
            guard !a.isEmpty else { return 0 }
            let s = a.sorted(); return s[s.count/2]
        }
        baseline = Baseline(
            ear  : med(calibEars),
            mar  : med(calibMars),
            pitch: med(calibPitches),
            yaw  : med(calibYaws),
            roll : med(calibRolls)
        )
        DispatchQueue.main.async {
            self.isCalibrating = false
            self.calibPhase    = 0
        }
        sessionStart = Date()
        print("✅ Baseline: EAR=\(String(format:"%.4f",baseline.ear)) MAR=\(String(format:"%.4f",baseline.mar))")
    }

    // MARK: - Kalibrasyon Kaydet/Yükle
    func saveBaseline(for profileId: String) {
        if let data = try? JSONEncoder().encode(baseline) {
            UserDefaults.standard.set(data, forKey: "baseline_\(profileId)")
        }
    }
    func loadBaseline(for profileId: String) -> Baseline? {
        guard let data = UserDefaults.standard.data(forKey: "baseline_\(profileId)"),
              let b = try? JSONDecoder().decode(Baseline.self, from: data) else { return nil }
        return b
    }

    // MARK: - Frame İşleme
    func processFrame(ear: Double, mar: Double,
                      pitch: Double, yaw: Double, roll: Double) {
        guard !isCalibrating else { return }

        let now = Date()
        DispatchQueue.main.async { self.sessionDuration = now.timeIntervalSince(self.sessionStart) }

        featureBuf.push(ear: ear, mar: mar, pitch: pitch,
                        yaw: yaw, roll: roll, baseline: baseline)

        let eyeClosed = ear < baseline.earCloseThreshold
        let isYawning = featureBuf.currentIsYawning

        // Feature vektörü + normalize
        if let fv = featureBuf.computeFeatureVector(baseline: baseline) {
            var norm = fv
            for i in 0..<min(norm.count, trainMean.count) {
                norm[i] = (norm[i] - trainMean[i]) / max(trainStd[i], 1e-6)
            }
            sequenceBuf.append(norm)
            if sequenceBuf.count > windowSize { sequenceBuf.removeFirst() }
            if sequenceBuf.count == windowSize { runInference() }
        }

        // Kural motoru
        let dec = ruleEngine.evaluate(
            eyeClosed: eyeClosed, isYawning: isYawning,
            modelScore: smoothedScore, now: now
        )

        DispatchQueue.main.async { [weak self] in
            guard let s = self else { return }
            s.decision    = dec
            s.blinkRate   = s.featureBuf.blinkRate5s
            s.perclos     = s.featureBuf.perclos10s
            s.closureSec  = s.ruleEngine.closureSec
            s.yawnCount   = s.ruleEngine.yawnCount5min

            if dec.shouldAlert && !s.alertFired {
                s.alertFired = true
                if dec.level == .critical { s.microsleepTotal += 1 }
                AudioServicesPlayAlertSound(SystemSoundID(1322))
            }
        }
        frameId += 1
    }

    // MARK: - CoreML Inference
    private func runInference() {
        guard let model = mlModel else { return }
        let flat  = sequenceBuf.flatMap { $0 }
        let shape : [NSNumber] = [1, NSNumber(value: windowSize),
                                  NSNumber(value: nFeatures)]
        guard let arr = try? MLMultiArray(shape: shape, dataType: .float32) else { return }
        for (i, v) in flat.enumerated() { arr[i] = NSNumber(value: v) }

        guard let inp = try? MLDictionaryFeatureProvider(dictionary: ["sequence": arr]),
              let out = try? model.prediction(from: inp),
              let prob = out.featureValue(for: "drowsiness_prob")?.multiArrayValue
        else { return }

        let score = Double(truncating: prob[0])
        scoreHistory.append(score)
        // 30 saniyelik yumuşatma penceresi
        let maxHist = Int(fps * 30)
        if scoreHistory.count > maxHist { scoreHistory.removeFirst() }
        let smoothed = scoreHistory.reduce(0,+) / Double(scoreHistory.count)

        DispatchQueue.main.async { self.smoothedScore = smoothed }
    }

    func resetAlert() { alertFired = false }

    func currentSessionStats(name: String = "Aktif Sürüş") -> DrivingSession {
        DrivingSession(
            name: name, date: sessionStart,
            duration: sessionDuration,
            safetyScore: Int(max(0, min(100, 100 - smoothedScore * 100))),
            alertCount: microsleepTotal,
            yawnCount: yawnCount,
            microsleeps: microsleepTotal
        )
    }
}
