import Foundation
import Combine
import AVFoundation
import CoreML
import Vision
import UIKit
import MediaPipeTasksVision

// MARK: - Fatigue Detection Service
// Kamera → MediaPipe (blink) + SqueezeNet (yawn) → FatigueEngine → UI

final class FatigueDetectionService: NSObject, ObservableObject {

    @Published var detectionState = DetectionState()
    @Published var isRunning: Bool = false
    @Published var cameraPermissionDenied: Bool = false
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    private let engine   = FatigueEngine(fps: 30)
    let alertMgr = AlertManager()

    private var captureSession: AVCaptureSession?
    private var faceLandmarker: FaceLandmarker?
    private var yawnMLModel: VNCoreMLModel?

    private var frameIndex: Int = 0
    private let processingQueue = DispatchQueue(label: "gozcu.detection", qos: .userInteractive)

    private var sessionStartTime: Date?
    private var lastAlertLevel: AlertLevel = .safe
    private var alertEvents: [AlertEvent] = []
    var onDriveEnded: ((DrivingSession) -> Void)?

    override init() {
        super.init()
        setupMediaPipe()
        setupCoreML()
    }

    // MARK: - MediaPipe
    private func setupMediaPipe() {
        guard let path = Bundle.main.path(forResource: "face_landmarker", ofType: "task") else {
            print("⚠️ face_landmarker.task bulunamadı")
            return
        }
        do {
            let options = FaceLandmarkerOptions()
            options.baseOptions.modelAssetPath = path
            options.outputFaceBlendshapes = true
            options.numFaces = 1
            options.minFaceDetectionConfidence = 0.5
            options.minFacePresenceConfidence = 0.5
            options.minTrackingConfidence = 0.5
            faceLandmarker = try FaceLandmarker(options: options)
            print("✅ MediaPipe hazır")
        } catch {
            print("❌ MediaPipe: \(error)")
        }
    }

    // MARK: - CoreML
    private func setupCoreML() {
        guard let url = Bundle.main.url(forResource: "FatigueDetector", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "FatigueDetector", withExtension: "mlpackage") else {
            print("⚠️ FatigueDetector model yok — yawn devre dışı")
            return
        }
        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            let mlModel = try MLModel(contentsOf: url, configuration: config)
            yawnMLModel = try VNCoreMLModel(for: mlModel)
            print("✅ CoreML hazır")
        } catch {
            print("❌ CoreML: \(error)")
        }
    }

    // MARK: - Camera
    func setupCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureCaptureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted { self?.configureCaptureSession() }
                    else { self?.cameraPermissionDenied = true }
                }
            }
        default:
            DispatchQueue.main.async { self.cameraPermissionDenied = true }
        }
    }

    private func configureCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .hd1280x720
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        output.setSampleBufferDelegate(self, queue: processingQueue)
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.connection(with: .video)?.videoOrientation = .portrait

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        captureSession = session
        DispatchQueue.main.async { self.previewLayer = preview }
    }

    // MARK: - Start / Stop
    func startDrive() {
        guard !isRunning else { return }
        engine.reset()
        alertEvents.removeAll()
        sessionStartTime = Date()
        frameIndex = 0
        lastAlertLevel = .safe
        processingQueue.async { self.captureSession?.startRunning() }
        DispatchQueue.main.async { self.isRunning = true }
    }

    func stopDrive() {
        guard isRunning else { return }
        processingQueue.async { self.captureSession?.stopRunning() }
        DispatchQueue.main.async {
            self.isRunning = false
            self.alertMgr.update(alertLevel: .safe)  // alarmı kapat
            self.buildAndDeliverSession()
        }
    }

    private func buildAndDeliverSession() {
        guard let start = sessionStartTime else { return }
        let end = Date()
        let duration = end.timeIntervalSince(start)
        var dangerT = 0, warningT = 0
        var prev = AlertLevel.safe
        for e in alertEvents {
            if e.level == .danger && prev != .danger { dangerT += 1 }
            if e.level == .warning && prev != .warning { warningT += 1 }
            prev = e.level
        }
        let session = DrivingSession(
            userId: "",
            startTime: start,
            endTime: end,
            durationSeconds: duration,
            dangerCount: dangerT,
            warningCount: warningT,
            maxPerclos: engine.maxPerclos,
            yawnEpisodes: alertEvents.filter { $0.reason.contains("yawn") }.count,
            safePercent: engine.safePercent,
            warningPercent: engine.warningPercent,
            dangerPercent: engine.dangerPercent,
            alertEvents: alertEvents
        )
        onDriveEnded?(session)
    }

    // MARK: - Blink (MediaPipe)
    private func extractBlinkScore(from result: FaceLandmarkerResult) -> (Double, Bool) {
        let allFaces = result.faceBlendshapes
        guard !allFaces.isEmpty else { return (0, false) }
        var left = 0.0, right = 0.0
        for cat in allFaces[0].categories {
            if cat.categoryName == "eyeBlinkLeft"  { left = Double(cat.score) }
            if cat.categoryName == "eyeBlinkRight" { right = Double(cat.score) }
        }
        return ((left + right) / 2.0, true)
    }

    private let ciContext = CIContext()

    // MARK: - Face crop (MediaPipe landmarks) — v8 eye(üst%60)+mouth(alt%45) birleştirme
    private func extractFaceCrop(from pixelBuffer: CVPixelBuffer, result: FaceLandmarkerResult) -> CGImage? {
        let allLandmarks = result.faceLandmarks
        guard !allLandmarks.isEmpty else { return nil }
        let landmarks = allLandmarks[0]
        let w = Double(CVPixelBufferGetWidth(pixelBuffer))
        let h = Double(CVPixelBufferGetHeight(pixelBuffer))
        let xs = landmarks.map { Double($0.x) }
        let ys = landmarks.map { Double($0.y) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else { return nil }
        let pad = 0.20
        let dx = (maxX - minX) * pad
        let dy = (maxY - minY) * pad
        let x1 = max(0, minX - dx) * w
        let y1 = max(0, minY - dy) * h
        let x2 = min(1, maxX + dx) * w
        let y2 = min(1, maxY + dy) * h
        guard x2 > x1, y2 > y1 else { return nil }

        let rect = CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1)
        let ci = CIImage(cvPixelBuffer: pixelBuffer).cropped(to: rect)
        guard let faceCrop = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return composeEyeMouth(faceCrop)
    }

    // v8: eye = üst %60 → (224×134), mouth = alt %45 → (224×90), dikey birleştir = 224×224
    private func composeEyeMouth(_ face: CGImage) -> CGImage? {
        let ch = CGFloat(face.height)
        let cw = CGFloat(face.width)

        let eyeRect   = CGRect(x: 0, y: 0, width: cw, height: ch * 0.60)
        let mouthRect = CGRect(x: 0, y: ch * 0.55, width: cw, height: ch * 0.45)

        guard let eyeCrop   = face.cropping(to: eyeRect),
              let mouthCrop = face.cropping(to: mouthRect) else { return nil }

        let size = CGSize(width: 224, height: 224)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 224, height: 224,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CGContext koordinatı alttan başlar → mouth alta (y=0), eye üste (y=90)
        ctx.draw(mouthCrop, in: CGRect(x: 0, y: 0,   width: 224, height: 90))
        ctx.draw(eyeCrop,   in: CGRect(x: 0, y: 90,  width: 224, height: 134))
        return ctx.makeImage()
    }

    // MARK: - Yawn (CoreML) — ham tensör + softmax
    private func predictYawn(from cgImage: CGImage) -> Double {
        guard let model = yawnMLModel else { return 0 }
        var prob = 0.0
        let request = VNCoreMLRequest(model: model) { req, _ in
            // Çıktı ham tensör (TensorType) → VNCoreMLFeatureValueObservation
            guard let obs = req.results?.first as? VNCoreMLFeatureValueObservation,
                  let arr = obs.featureValue.multiArrayValue else { return }
            // 3 sınıf: [awake, microsleep, yawning] → softmax
            let n = arr.count
            var logits = [Double](repeating: 0, count: n)
            for i in 0..<n { logits[i] = arr[i].doubleValue }
            let maxL = logits.max() ?? 0
            let exps = logits.map { Foundation.exp($0 - maxL) }
            let sum  = exps.reduce(0, +)
            if sum > 0, n >= 3 {
                prob = exps[2] / sum   // index 2 = yawning
            }
        }
        request.imageCropAndScaleOption = .scaleFill
        try? VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
        return prob
    }

    // MARK: - Result handling
    private func handleResult(_ result: FatigueEngine.EngineResult) {
        if result.alertLevel != lastAlertLevel {
            if result.alertLevel != .safe {
                alertEvents.append(AlertEvent(
                    timestamp: Date(),
                    level: result.alertLevel,
                    perclos: result.perclos,
                    reason: result.alertReason))
            }
            lastAlertLevel = result.alertLevel
        }

        alertMgr.update(alertLevel: result.alertLevel)

        var s = DetectionState()
        s.alertLevel = result.alertLevel
        s.perclos = result.perclos
        s.yawnCount = result.yawnCount
        s.eyeClosed = result.eyeClosed
        s.closedDuration = result.closedDuration
        s.msLevel = result.msLevel
        s.smoothYawn = result.smoothYawn
        s.faceDetected = result.eyeClosed || result.smoothYawn > 0.05 || result.perclos > 0
        s.isAlarmActive = alertMgr.isAlarmPlaying

        DispatchQueue.main.async { self.detectionState = s }
    }
}

// MARK: - Camera delegate
extension FatigueDetectionService: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRunning, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameIndex += 1
        let timestamp = Double(frameIndex) / 30.0

        guard let landmarker = faceLandmarker else { return }
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        let uiImage = UIImage(cgImage: cg)
        guard let mpImage = try? MPImage(uiImage: uiImage) else { return }
        guard let result = try? landmarker.detect(image: mpImage) else { return }

        let (blinkScore, faceDetected) = extractBlinkScore(from: result)

        var yawnProb = 0.0
        if let crop = extractFaceCrop(from: pixelBuffer, result: result) {
            yawnProb = predictYawn(from: crop)
        }

        let engineResult = engine.update(
            yawnProb: yawnProb,
            blinkScore: blinkScore,
            faceDetected: faceDetected,
            timestamp: timestamp)

        handleResult(engineResult)
    }
}
