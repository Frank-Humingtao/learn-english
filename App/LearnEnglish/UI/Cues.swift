import AVFoundation
import UIKit

/// Sound and haptic cues of the answer screen.
///
/// Sounds are short synthesized tones played through an `.ambient` audio session, so they follow
/// the ring/silent switch and mix with whatever else is playing. Haptics are the system feedback
/// generators.
@MainActor
final class Cues {
    enum Cue: CaseIterable {
        /// A real word answered (card swiped away).
        case tap
        /// A pseudoword rejected or a meaning chosen correctly.
        case correct
        /// A pseudoword accepted or a wrong meaning.
        case wrong
        /// A progress segment filled.
        case segment
        /// The test finished.
        case finish
    }

    static let shared = Cues()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private var ready = false

    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let notify = UINotificationFeedbackGenerator()

    private init() {}

    /// Sets up the audio session and engine; call when a test opens.
    func prepare() {
        light.prepare()
        notify.prepare()
        guard !ready else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            for cue in Cue.allCases { buffers[cue] = Self.render(cue, format: format) }
            try engine.start()
            ready = true
        } catch {
            ready = false
        }
    }

    func play(_ cue: Cue) {
        switch cue {
        case .tap: light.impactOccurred()
        case .correct: notify.notificationOccurred(.success)
        case .wrong: notify.notificationOccurred(.error)
        case .segment: medium.impactOccurred()
        case .finish: notify.notificationOccurred(.success)
        }
        guard ready, let buffer = buffers[cue] else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    // MARK: synthesis

    private struct Note { var freq: Double; var wave: Wave }
    private enum Wave { case sine, triangle, square }

    private static func render(_ cue: Cue, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let (notes, step, gain): ([Note], Double, Double) = switch cue {
        case .tap: ([Note(freq: 520, wave: .triangle)], 0.05, 0.25)
        case .correct: ([Note(freq: 660, wave: .sine), Note(freq: 990, wave: .sine)], 0.07, 0.35)
        case .wrong: ([Note(freq: 180, wave: .square), Note(freq: 140, wave: .square)], 0.10, 0.12)
        case .segment: ([523, 659, 784].map { Note(freq: $0, wave: .sine) }, 0.06, 0.3)
        case .finish: ([523, 659, 784, 1047].map { Note(freq: $0, wave: .sine) }, 0.08, 0.3)
        }
        let rate = format.sampleRate
        let decay = step * 1.6
        let total = Int((Double(notes.count - 1) * step + decay) * rate) + 1
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let out = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)
        for i in 0..<total { out[i] = 0 }
        for (n, note) in notes.enumerated() {
            let start = Int(Double(n) * step * rate)
            let length = Int(decay * rate)
            for i in 0..<length where start + i < total {
                let t = Double(i) / rate
                let phase = (t * note.freq).truncatingRemainder(dividingBy: 1)
                let v: Double = switch note.wave {
                case .sine: sin(2 * .pi * phase)
                case .triangle: 4 * abs(phase - 0.5) - 1
                case .square: phase < 0.5 ? 1 : -1
                }
                // Short attack, exponential decay (like the prototype's gain ramp).
                let envelope = min(1, t / 0.004) * exp(-t / (decay / 5))
                out[start + i] += Float(v * envelope * gain)
            }
        }
        return buffer
    }
}
