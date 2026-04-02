import UIKit
import AVFoundation
import Vision
import SwiftUI
import Combine

class CameraManager: NSObject, ObservableObject {

    var onFrame: ((Double, Double, Double, Double, Double) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.queue", qos: .userInteractive)
    private var faceRequest: VNDetectFaceLandmarksRequest!

    var previewLayer: AVCaptureVideoPreviewLayer?

    var captureSession: AVCaptureSession {
        session
    }

    override init() {
        super.init()
        setupFaceRequest()
        setupCamera()
    }

    private func setupFaceRequest() {
        faceRequest = VNDetectFaceLandmarksRequest { [weak self] req, err in
            guard let results = req.results as? [VNFaceObservation],
                  let face = results.first,
                  let lm = face.landmarks
            else { return }

            self?.processFace(face: face, landmarks: lm)
        }

        faceRequest.revision = VNDetectFaceLandmarksRequestRevision3
    }

    private func setupCamera() {
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }

        session.addInput(input)

        output.setSampleBufferDelegate(self, queue: queue)
        output.alwaysDiscardsLateVideoFrames = true

        if session.canAddOutput(output) {
            session.addOutput(output)
        }

        output.connections.first?.videoOrientation = .portrait
        session.commitConfiguration()
    }

    func start() {
        if !session.isRunning {
            session.startRunning()
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func processFace(face: VNFaceObservation,
                             landmarks: VNFaceLandmarks2D) {
        let box = face.boundingBox
        let W = CGFloat(1280)
        let H = CGFloat(720)

        func pts(_ region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
            guard let r = region else { return [] }
            return r.normalizedPoints.map {
                CGPoint(
                    x: $0.x * box.width * W + box.minX * W,
                    y: $0.y * box.height * H + box.minY * H
                )
            }
        }

        let leftEye = pts(landmarks.leftEye)
        let rightEye = pts(landmarks.rightEye)
        let outerLips = pts(landmarks.outerLips)

        let ear = (eyeAspectRatio(leftEye) + eyeAspectRatio(rightEye)) / 2.0
        let mar = mouthAspectRatio(outerLips)
        let (pitch, yaw, roll) = headPose(face: face, W: W, H: H)

        onFrame?(ear, mar, pitch, yaw, roll)
    }

    private func eyeAspectRatio(_ pts: [CGPoint]) -> Double {
        guard pts.count >= 6 else { return 0.3 }
        let A = dist(pts[1], pts[5])
        let B = dist(pts[2], pts[4])
        let C = dist(pts[0], pts[3])
        return (A + B) / (2.0 * C + 1e-7)
    }

    private func mouthAspectRatio(_ pts: [CGPoint]) -> Double {
        guard pts.count >= 12 else { return 0.1 }
        let top = pts[pts.count / 2]
        let bottom = pts[0]
        let left = pts[pts.count / 4]
        let right = pts[pts.count * 3 / 4]
        let vert = dist(top, bottom)
        let horiz = dist(left, right)
        return vert / (horiz + 1e-7)
    }

    private func headPose(face: VNFaceObservation,
                          W: CGFloat, H: CGFloat) -> (Double, Double, Double) {
        let roll = Double(face.roll?.doubleValue ?? 0) * 180.0 / .pi
        let cx = face.boundingBox.midX - 0.5
        let cy = face.boundingBox.midY - 0.5
        let yaw = cx * 60.0
        let pitch = cy * 40.0
        return (pitch, yaw, roll)
    }

    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .leftMirrored,
            options: [:]
        )

        try? handler.perform([faceRequest])
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let camera: CameraManager

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let layer = AVCaptureVideoPreviewLayer(session: camera.captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        camera.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            camera.previewLayer?.frame = uiView.bounds
        }
    }
}
