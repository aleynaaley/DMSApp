import Foundation

// MARK: - Baseline
// Kalibrasyon aşamasında hesaplanan kişiye özel referans değerler.
// UserDefaults'ta saklanır — kişi bazlı yüklenir/kaydedilir.
struct Baseline: Codable {
    var ear  : Double = 0.28
    var mar  : Double = 0.12
    var pitch: Double = 0.0
    var yaw  : Double = 0.0
    var roll : Double = 0.0

    /// Göz kapalı eşiği: EAR_RATIO < 0.75
    /// Kaynak: Soukupova & Cech (2016), Real-Time Eye Blink Detection
    /// using Facial Landmarks. CVWW 2016.
    var earCloseThreshold: Double { ear * 0.75 }

    /// Yawn eşiği: MAR > baseline * 2.5 ve min 800ms sürmeli
    /// Kaynak: Abtahi M. et al. (2014), YawDD dataset paper.
    var marYawnThreshold: Double { mar * 2.5 }

    static let `default` = Baseline()
}

// MARK: - FeatureBuffer
// Gerçek zamanlı sliding window feature hesaplama.
// train.py (features_temporal.csv) pipeline ile AYNI sıra ve formül.
// 51 feature, window_size=30 frame @ ~30fps

class FeatureBuffer {

    private let maxLen: Int
    private let fps   : Double

    // Ham sinyaller
    private var ears    : [Double] = []
    private var mars    : [Double] = []
    private var pitches : [Double] = []
    private var yaws    : [Double] = []
    private var rolls   : [Double] = []

    // Normalize değerler
    private var earRatios      : [Double] = []
    private var earDiffs       : [Double] = []
    private var marRatios      : [Double] = []
    private var marDiffs       : [Double] = []
    private var deltaPitches   : [Double] = []
    private var deltaYaws      : [Double] = []
    private var deltaRolls     : [Double] = []
    private var absDeltaPitch  : [Double] = []
    private var absDeltaYaw    : [Double] = []

    // Göz/blink
    private var eyeCloseds  : [Double] = []
    private var blinkStarts : [Double] = []

    // Velocity
    private var earVels   : [Double] = []
    private var pitchVels : [Double] = []
    private var yawVels   : [Double] = []

    // Önceki değerler
    private var prevEar   : Double? = nil
    private var prevDPitch: Double? = nil
    private var prevDYaw  : Double? = nil
    private var prevEyeCl : Double  = 0

    // Yawn state (min 800ms)
    private var yawnFrameCount: Int    = 0
    private var isYawActive   : Bool   = false
    var yawnCount             : Int    = 0

    init(fps: Double = 30.0, maxSec: Double = 35.0) {
        self.fps    = fps
        self.maxLen = Int(fps * maxSec)
    }

    func reset() {
        ears=[]; mars=[]; pitches=[]; yaws=[]; rolls=[]
        earRatios=[]; earDiffs=[]; marRatios=[]; marDiffs=[]
        deltaPitches=[]; deltaYaws=[]; deltaRolls=[]
        absDeltaPitch=[]; absDeltaYaw=[]
        eyeCloseds=[]; blinkStarts=[]
        earVels=[]; pitchVels=[]; yawVels=[]
        prevEar=nil; prevDPitch=nil; prevDYaw=nil; prevEyeCl=0
        yawnFrameCount=0; isYawActive=false; yawnCount=0
    }

    // MARK: - Frame Push
    func push(ear: Double, mar: Double,
              pitch: Double, yaw: Double, roll: Double,
              baseline: Baseline) {

        let bEar = max(baseline.ear, 1e-7)
        let bMar = max(baseline.mar, 1e-7)

        let eRatio = ear / bEar
        let eDiff  = ear - baseline.ear
        let mRatio = mar / bMar
        let mDiff  = mar - baseline.mar
        let dPitch = angleDiff(pitch, baseline.pitch)
        let dYaw   = angleDiff(yaw,   baseline.yaw)
        let dRoll  = angleDiff(roll,   baseline.roll)

        // Göz kapalı mı? (train.py EAR_RATIO_CLOSED_THR = 0.75)
        let eyeCl  : Double = eRatio < 0.75 ? 1.0 : 0.0
        let blinkSt: Double = (eyeCl == 1 && prevEyeCl == 0) ? 1.0 : 0.0

        // Velocity
        let eVel  = prevEar    != nil ? abs(ear    - prevEar!)    : 0.0
        let pVel  = prevDPitch != nil ? abs(dPitch - prevDPitch!) : 0.0
        let yVel  = prevDYaw   != nil ? abs(dYaw   - prevDYaw!)   : 0.0

        // Yawn state machine (min 800ms = fps*0.8 frame)
        let yawnMinFrames = Int(fps * 0.8)
        if mar > baseline.marYawnThreshold {
            yawnFrameCount += 1
            if yawnFrameCount >= yawnMinFrames && !isYawActive {
                isYawActive = true
                yawnCount  += 1
            }
        } else {
            yawnFrameCount = 0
            isYawActive    = false
        }

        app(&ears,   ear);   app(&mars,   mar)
        app(&pitches,pitch); app(&yaws,   yaw);   app(&rolls,   roll)
        app(&earRatios, eRatio); app(&earDiffs, eDiff)
        app(&marRatios, mRatio); app(&marDiffs, mDiff)
        app(&deltaPitches, dPitch); app(&deltaYaws, dYaw); app(&deltaRolls, dRoll)
        app(&absDeltaPitch, abs(dPitch)); app(&absDeltaYaw, abs(dYaw))
        app(&eyeCloseds, eyeCl); app(&blinkStarts, blinkSt)
        app(&earVels, eVel); app(&pitchVels, pVel); app(&yawVels, yVel)

        prevEar = ear; prevDPitch = dPitch; prevDYaw = dYaw; prevEyeCl = eyeCl
    }

    // MARK: - 51 Feature Vektörü
    // sequence_config.json feature_columns ile AYNI SIRA
    func computeFeatureVector(baseline: Baseline) -> [Float]? {
        guard ears.count >= 2 else { return nil }

        let w1  = max(1, Int(fps * 1.0))
        let w5  = max(1, Int(fps * 5.0))
        let w10 = max(1, Int(fps * 10.0))

        let bc5 = rSum(blinkStarts, w5)

        let v: [Double] = [
            ears.last!,                          // 0  ear
            mars.last!,                          // 1  mar
            pitches.last!,                       // 2  pitch
            yaws.last!,                          // 3  yaw
            rolls.last!,                         // 4  roll
            baseline.ear,                        // 5  baseline_ear
            baseline.mar,                        // 6  baseline_mar
            baseline.pitch,                      // 7  baseline_pitch
            baseline.yaw,                        // 8  baseline_yaw
            baseline.roll,                       // 9  baseline_roll
            earRatios.last!,                     // 10 ear_ratio
            earDiffs.last!,                      // 11 ear_diff
            marRatios.last!,                     // 12 mar_ratio
            marDiffs.last!,                      // 13 mar_diff
            deltaPitches.last!,                  // 14 delta_pitch
            deltaYaws.last!,                     // 15 delta_yaw
            deltaRolls.last!,                    // 16 delta_roll
            absDeltaPitch.last!,                 // 17 abs_delta_pitch
            absDeltaYaw.last!,                   // 18 abs_delta_yaw
            eyeCloseds.last!,                    // 19 eye_closed
            rMean(ears, w1),                     // 20 ear_mean_1s
            rMean(ears, w5),                     // 21 ear_mean_5s
            rMean(ears, w10),                    // 22 ear_mean_10s
            rMean(mars, w1),                     // 23 mar_mean_1s
            rMean(mars, w5),                     // 24 mar_mean_5s
            rMean(mars, w10),                    // 25 mar_mean_10s
            rMean(pitches, w1),                  // 26 pitch_mean_1s
            rMean(pitches, w5),                  // 27 pitch_mean_5s
            rMean(pitches, w10),                 // 28 pitch_mean_10s
            rMean(yaws, w1),                     // 29 yaw_mean_1s
            rMean(yaws, w5),                     // 30 yaw_mean_5s
            rMean(yaws, w10),                    // 31 yaw_mean_10s
            rMean(rolls, w1),                    // 32 roll_mean_1s
            rMean(rolls, w5),                    // 33 roll_mean_5s
            rMean(rolls, w10),                   // 34 roll_mean_10s
            rMean(absDeltaPitch, w1),            // 35 abs_delta_pitch_mean_1s
            rMean(absDeltaPitch, w5),            // 36 abs_delta_pitch_mean_5s
            rMean(absDeltaPitch, w10),           // 37 abs_delta_pitch_mean_10s
            rMean(absDeltaYaw, w1),              // 38 abs_delta_yaw_mean_1s
            rMean(absDeltaYaw, w5),              // 39 abs_delta_yaw_mean_5s
            rMean(absDeltaYaw, w10),             // 40 abs_delta_yaw_mean_10s
            rMean(eyeCloseds, w5),               // 41 perclos_5s
            rMean(eyeCloseds, w10),              // 42 perclos_10s
            blinkStarts.last!,                   // 43 blink_start
            bc5,                                 // 44 blink_count_5s
            bc5 / 5.0,                           // 45 blink_rate_5s
            rStd(ears, w5),                      // 46 ear_std_5s
            rStd(mars, w5),                      // 47 mar_std_5s
            earVels.last!,                       // 48 ear_velocity
            pitchVels.last!,                     // 49 pitch_velocity
            yawVels.last!,                       // 50 yaw_velocity
        ]
        assert(v.count == 51)
        return v.map { Float($0) }
    }

    // MARK: - Anlık metrikler (UI için)
    var currentEyeClosed: Bool { (eyeCloseds.last ?? 0) > 0.5 }
    var currentIsYawning: Bool { isYawActive }
    var perclos10s: Double { rMean(eyeCloseds, max(1, Int(fps*10))) }
    var blinkRate5s: Double {
        let w = max(1, Int(fps*5))
        return rSum(blinkStarts, w) / 5.0
    }

    // MARK: - Helpers
    private func app(_ arr: inout [Double], _ v: Double) {
        arr.append(v)
        if arr.count > maxLen { arr.removeFirst() }
    }
    private func rMean(_ a: [Double], _ n: Int) -> Double {
        guard !a.isEmpty else { return 0 }
        let s = Array(a.suffix(n))
        return s.reduce(0,+) / Double(s.count)
    }
    private func rStd(_ a: [Double], _ n: Int) -> Double {
        guard a.count > 1 else { return 0 }
        let s = Array(a.suffix(n))
        let m = s.reduce(0,+) / Double(s.count)
        return sqrt(s.map{($0-m)*($0-m)}.reduce(0,+) / Double(s.count))
    }
    private func rSum(_ a: [Double], _ n: Int) -> Double {
        guard !a.isEmpty else { return 0 }
        return Array(a.suffix(n)).reduce(0,+)
    }
    private func angleDiff(_ a: Double, _ b: Double) -> Double {
        let d = a - b
        return (d + 180.0).truncatingRemainder(dividingBy: 360.0) - 180.0
    }
}
