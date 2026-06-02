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

    static let debug = true

    private enum Phase {
        case idle, waitingToStart, alarmPlaying, waitingToRepeat
    }
    private var phase: Phase = .idle

    private var phaseTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    private var beepTimer: Timer?   // sistem sesi için tekrar

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
            if Self.debug { print("🔊 AudioSession aktif") }
        } catch {
            print("🔊 AudioSession hatası: \(error)")
        }
        if let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") {
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.numberOfLoops = -1
            if Self.debug { print("🔊 alarm.mp3 yüklendi") }
        } else {
            if Self.debug { print("🔊 alarm.mp3 YOK → sistem sesi kullanılacak") }
        }
    }

    // Her frame'de çağrılır (arka plan thread'inden gelebilir → main'e al)
    func update(alertLevel: AlertLevel) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch alertLevel {
            case .safe, .warning:
                if self.phase != .idle {
                    if Self.debug { print("🔊 DANGER bitti → reset") }
                    self.resetCycle()
                }
            case .danger:
                if self.phase == .idle {
                    if Self.debug { print("🔊 DANGER başladı → 5sn bekleniyor") }
                    self.enterDanger()
                }
            }
        }
    }

    private func enterDanger() {
        phase = .waitingToStart
        schedule(after: waitBeforeAlarmSec) { [weak self] in self?.startAlarm() }
    }

    private func startAlarm() {
        guard phase == .waitingToStart else { return }
        phase = .alarmPlaying
        isAlarmPlaying = true
        if Self.debug { print("🔊🔊🔊 ALARM ÇALIYOR") }
        playAlarm()
        schedule(after: alarmDurationSec) { [weak self] in self?.stopAlarmAndWait() }
    }

    private func stopAlarmAndWait() {
        guard phase == .alarmPlaying else { return }
        stopAlarm()
        isAlarmPlaying = false
        if Self.debug { print("🔊 alarm durdu → 5sn bekle") }
        phase = .waitingToRepeat
        schedule(after: waitBetweenSec) { [weak self] in self?.repeatAlarm() }
    }

    private func repeatAlarm() {
        guard phase == .waitingToRepeat else { return }
        phase = .alarmPlaying
        isAlarmPlaying = true
        if Self.debug { print("🔊🔊🔊 ALARM TEKRAR") }
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
        // Ana thread + common mode → kamera çalışırken bile timer ateşlenir
        let timer = Timer(timeInterval: interval, repeats: false) { _ in
            block()
        }
        RunLoop.main.add(timer, forMode: .common)
        phaseTimer = timer
    }

    // MARK: - Ses
    private func playAlarm() {
        if let player = audioPlayer {
            player.currentTime = 0
            player.play()
        } else {
            // alarm.mp3 yoksa: 5 saniye boyunca her 0.6sn'de bir sistem sesi çal
            beepTimer?.invalidate()
            AudioServicesPlaySystemSound(1005)
            let t = Timer(timeInterval: 0.6, repeats: true) { _ in
                AudioServicesPlaySystemSound(1005)
            }
            RunLoop.main.add(t, forMode: .common)
            beepTimer = t
        }
    }

    private func stopAlarm() {
        audioPlayer?.stop()
        beepTimer?.invalidate()
        beepTimer = nil
    }

    deinit { resetCycle() }
}
