import Foundation
import Combine
import AVFoundation
import AudioToolbox

// MARK: - Alert Manager
// Döngü:
//   DANGER'a gir → 5sn bekle → hâlâ DANGER ise alarm 5sn çal → dur
//   → 5sn bekle → hâlâ DANGER ise tekrar 5sn çal → ...
//   Durum DANGER'dan çıkarsa → döngü tamamen sıfırlanır

final class AlertManager: NSObject, ObservableObject {

    @Published private(set) var isAlarmPlaying: Bool = false

    private enum Phase {
        case idle              // DANGER yok
        case waitingToStart    // DANGER, 5sn bekleniyor
        case alarmPlaying      // alarm çalıyor (5sn)
        case waitingToRepeat   // alarm bitti, 5sn bekleniyor
    }
    private var phase: Phase = .idle

    private var phaseTimer: Timer?
    private var audioPlayer: AVAudioPlayer?

    private let waitBeforeAlarmSec: TimeInterval = 5.0
    private let alarmDurationSec: TimeInterval   = 5.0
    private let waitBetweenSec: TimeInterval     = 5.0

    override init() {
        super.init()
        setupAudio()
    }

    private func setupAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("AudioSession hatası: \(error)")
        }
        if let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") {
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.numberOfLoops = -1  // alarm süresince loop
        }
    }

    // Her frame'de çağrılır
    func update(alertLevel: AlertLevel) {
        switch alertLevel {
        case .safe, .warning:
            if phase != .idle { resetCycle() }
        case .danger:
            if phase == .idle { enterDanger() }
        }
    }

    // MARK: - Döngü
    private func enterDanger() {
        phase = .waitingToStart
        schedule(after: waitBeforeAlarmSec) { [weak self] in self?.startAlarm() }
    }

    private func startAlarm() {
        guard phase == .waitingToStart else { return }
        phase = .alarmPlaying
        isAlarmPlaying = true
        playAlarm()
        schedule(after: alarmDurationSec) { [weak self] in self?.stopAlarmAndWait() }
    }

    private func stopAlarmAndWait() {
        guard phase == .alarmPlaying else { return }
        stopAlarm()
        isAlarmPlaying = false
        phase = .waitingToRepeat
        schedule(after: waitBetweenSec) { [weak self] in self?.repeatAlarm() }
    }

    private func repeatAlarm() {
        guard phase == .waitingToRepeat else { return }
        phase = .alarmPlaying
        isAlarmPlaying = true
        playAlarm()
        schedule(after: alarmDurationSec) { [weak self] in self?.stopAlarmAndWait() }
    }

    private func resetCycle() {
        phaseTimer?.invalidate()
        phaseTimer = nil
        stopAlarm()
        isAlarmPlaying = false
        phase = .idle
    }

    private func schedule(after interval: TimeInterval, block: @escaping () -> Void) {
        phaseTimer?.invalidate()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { _ in
            DispatchQueue.main.async { block() }
        }
    }

    // MARK: - Ses
    private func playAlarm() {
        if let player = audioPlayer {
            player.currentTime = 0
            player.play()
        } else {
            // alarm.mp3 yoksa sistem sesi
            AudioServicesPlaySystemSound(1005)
        }
    }

    private func stopAlarm() {
        audioPlayer?.stop()
    }

    deinit { resetCycle() }
}
