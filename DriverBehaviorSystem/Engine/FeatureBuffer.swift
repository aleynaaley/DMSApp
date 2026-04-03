import Foundation

// MARK: - Baseline
struct Baseline: Codable {
    var ear  : Double = 0.28
    var mar  : Double = 0.12
    var pitch: Double = 0.0
    var yaw  : Double = 0.0
    var roll : Double = 0.0

    /// Göz kapalı eşiği: EAR_RATIO < 0.75
    /// /// Kaynak: Soukupova & Cech (2016), Real-Time Eye Blink Detection
    /// using Facial Landmarks. CVWW 2016.
    var earCloseThreshold: Double { ear * 0.75 }

    /// Yawn eşiği: MAR > baseline * 1.8 (eski 2.5 çok yüksekti, kaçırıyordu)
    /// + minimum 600ms sürmeli (eski 800ms)
    /// /// Yawn eşiği: MAR > baseline * 2.5 ve min 800ms sürmeli
    /// Kaynak: Abtahi M. et al. (2014), YawDD dataset paper.
    var marYawnThreshold: Double { max(mar * 1.8, 0.18) }

    static let `default` = Baseline()
}

// MARK: - FeatureBuffer
class FeatureBuffer {

    private let maxLen: Int
    private let fps   : Double

    private var ears    : [Double] = []
    private var mars    : [Double] = []
    private var pitches : [Double] = []
    private var yaws    : [Double] = []
    private var rolls   : [Double] = []

    private var earRatios      : [Double] = []
    private var earDiffs       : [Double] = []
    private var marRatios      : [Double] = []
    private var marDiffs       : [Double] = []
    private var deltaPitches   : [Double] = []
    private var deltaYaws      : [Double] = []
    private var deltaRolls     : [Double] = []
    private var absDeltaPitch  : [Double] = []
    private var absDeltaYaw    : [Double] = []

    private var eyeCloseds  : [Double] = []
    private var blinkStarts : [Double] = []

    private var earVels   : [Double] = []
    private var pitchVels : [Double] = []
    private var yawVels   : [Double] = []

    private var prevEar   : Double? = nil
    private var prevDPitch: Double? = nil
    private var prevDYaw  : Double? = nil
    private var prevEyeCl : Double  = 0

    // Yawn state — eşik düşürüldü: 600ms (eski 800ms)
    private var yawnFrameCount: Int  = 0
    private var isYawActive   : Bool = false
    var yawnCount             : Int  = 0

    // Yawn cooldown — aynı yawn'u tekrar sayma
    private var yawnCooldownFrames: Int = 0

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
        yawnFrameCount=0; isYawActive=false; yawnCount=0; yawnCooldownFrames=0
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

        let eyeCl  : Double = eRatio < 0.75 ? 1.0 : 0.0
        let blinkSt: Double = (eyeCl == 1 && prevEyeCl == 0) ? 1.0 : 0.0

        let eVel  = prevEar    != nil ? abs(ear    - prevEar!)    : 0.0
        let pVel  = prevDPitch != nil ? abs(dPitch - prevDPitch!) : 0.0
        let yVel  = prevDYaw   != nil ? abs(dYaw   - prevDYaw!)   : 0.0

        // Yawn state machine
        // Eşik: marYawnThreshold
        // Minimum süre: 600ms
        let yawnMinFrames = Int(fps * 0.6)  // 600ms (eski 800ms)

        if yawnCooldownFrames > 0 { yawnCooldownFrames -= 1 }

        if mar > baseline.marYawnThreshold {
            yawnFrameCount += 1
            if yawnFrameCount >= yawnMinFrames && !isYawActive {
                isYawActive = true
                if yawnCooldownFrames == 0 {
                    yawnCount += 1
                    // 3 saniye cooldown — aynı yawn'u tekrar sayma
                    yawnCooldownFrames = Int(fps * 3.0)
                    print("Esneme tespit edildi! Toplam: \(yawnCount), MAR=\(String(format:"%.3f",mar)), eşik=\(String(format:"%.3f",baseline.marYawnThreshold))")
                }
            }
        } else {
            // Ağız kapandı
            if yawnFrameCount > 0 && yawnFrameCount < yawnMinFrames {
                // Çok kısa açılma — yawn değil, sıfırla
                print("Kısa ağız hareketi yawn sayılmadı (\(yawnFrameCount) frame)")
            }
            yawnFrameCount = 0
            isYawActive    = false
        }

        app(&ears,   ear);   app(&mars,   mar)
        app(&pitches,pitch); app(&yaws,   yaw);   app(&rolls, roll)
        app(&earRatios, eRatio); app(&earDiffs, eDiff)
        app(&marRatios, mRatio); app(&marDiffs, mDiff)
        app(&deltaPitches, dPitch); app(&deltaYaws, dYaw); app(&deltaRolls, dRoll)
        app(&absDeltaPitch, abs(dPitch)); app(&absDeltaYaw, abs(dYaw))
        app(&eyeCloseds, eyeCl); app(&blinkStarts, blinkSt)
        app(&earVels, eVel); app(&pitchVels, pVel); app(&yawVels, yVel)

        prevEar = ear; prevDPitch = dPitch; prevDYaw = dYaw; prevEyeCl = eyeCl
    }

    // MARK: - 51 Feature Vektörü
    func computeFeatureVector(baseline: Baseline) -> [Float]? {
        guard ears.count >= 2 else { return nil }

        let w1  = max(1, Int(fps * 1.0))
        let w5  = max(1, Int(fps * 5.0))
        let w10 = max(1, Int(fps * 10.0))

        let bc5 = rSum(blinkStarts, w5)

        let v: [Double] = [
            ears.last!,
            mars.last!,
            pitches.last!,
            yaws.last!,
            rolls.last!,
            baseline.ear,
            baseline.mar,
            baseline.pitch,
            baseline.yaw,
            baseline.roll,
            earRatios.last!,
            earDiffs.last!,
            marRatios.last!,
            marDiffs.last!,
            deltaPitches.last!,
            deltaYaws.last!,
            deltaRolls.last!,
            absDeltaPitch.last!,
            absDeltaYaw.last!,
            eyeCloseds.last!,
            rMean(ears, w1),
            rMean(ears, w5),
            rMean(ears, w10),
            rMean(mars, w1),
            rMean(mars, w5),
            rMean(mars, w10),
            rMean(pitches, w1),
            rMean(pitches, w5),
            rMean(pitches, w10),
            rMean(yaws, w1),
            rMean(yaws, w5),
            rMean(yaws, w10),
            rMean(rolls, w1),
            rMean(rolls, w5),
            rMean(rolls, w10),
            rMean(absDeltaPitch, w1),
            rMean(absDeltaPitch, w5),
            rMean(absDeltaPitch, w10),
            rMean(absDeltaYaw, w1),
            rMean(absDeltaYaw, w5),
            rMean(absDeltaYaw, w10),
            rMean(eyeCloseds, w5),
            rMean(eyeCloseds, w10),
            blinkStarts.last!,
            bc5,
            bc5 / 5.0,
            rStd(ears, w5),
            rStd(mars, w5),
            earVels.last!,
            pitchVels.last!,
            yawVels.last!,
        ]
        assert(v.count == 51)
        return v.map { Float($0) }
    }

    // MARK: - Anlık metrikler
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
