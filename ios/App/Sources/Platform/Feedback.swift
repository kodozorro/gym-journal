import AVFoundation
import UIKit

/// Сигнал конца отдыха и удержание экрана включённым.
///
/// Звук идёт как обычный звук приложения: в беззвучном режиме телефона его не слышно, музыку он
/// не прерывает. Конец отдыха всегда виден на экране: звук и вибрация — дополнение.
final class Feedback {
    private var player: AVAudioPlayer?

    /// Готовит звук заранее, чтобы сигнал не опоздал.
    func prime() {
        guard player == nil else { return }
        player = try? AVAudioPlayer(data: Feedback.tone)
        player?.prepareToPlay()
    }

    /// Три коротких сигнала.
    func beep() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient)
        try? session.setActive(true)
        prime()
        player?.currentTime = 0
        player?.play()
    }

    func vibrate() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    /// Просит телефон не гасить экран или отпускает его.
    func keepAwake(_ wanted: Bool) {
        if UIApplication.shared.isIdleTimerDisabled != wanted {
            UIApplication.shared.isIdleTimerDisabled = wanted
        }
    }

    // MARK: Звук

    /// Три сигнала, как в веб-приложении: 880, 880 и 1175 Гц, каждый быстро нарастает и затухает.
    private static let tone: Data = {
        let rate = 44_100.0
        let total = Int(rate * 0.72)
        var samples = [Int16](repeating: 0, count: total)
        let beeps: [(start: Double, frequency: Double)] = [(0, 880), (0.24, 880), (0.48, 1175)]
        for beep in beeps {
            let first = Int(beep.start * rate)
            let count = Int(0.22 * rate)
            for offset in 0..<count where first + offset < total {
                let time = Double(offset) / rate
                var gain = 0.0
                if time < 0.02 {
                    gain = 0.0001 * pow(0.6 / 0.0001, time / 0.02)
                } else if time < 0.2 {
                    gain = 0.6 * pow(0.0001 / 0.6, (time - 0.02) / 0.18)
                }
                let value = sin(2 * Double.pi * beep.frequency * time) * gain
                samples[first + offset] = Int16(max(-1, min(1, value)) * 32_767)
            }
        }
        return Feedback.wave(samples, rate: 44_100)
    }()

    /// Файл WAV в памяти: один канал, 16 бит.
    private static func wave(_ samples: [Int16], rate: UInt32) -> Data {
        var data = Data()
        func text(_ value: String) {
            data.append(contentsOf: Array(value.utf8))
        }
        func number32(_ value: UInt32) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        func number16(_ value: UInt16) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let bytes = UInt32(samples.count * 2)
        text("RIFF")
        number32(36 + bytes)
        text("WAVE")
        text("fmt ")
        number32(16)
        number16(1)
        number16(1)
        number32(rate)
        number32(rate * 2)
        number16(2)
        number16(16)
        text("data")
        number32(bytes)
        for sample in samples {
            number16(UInt16(bitPattern: sample))
        }
        return data
    }
}
