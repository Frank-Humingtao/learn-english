import AVFoundation
import Foundation
import Lexicon
import Observation
import StudyComposer

/// Drives one study session: shows cards, flips them, stores each rating as a review Observation
/// the moment it is given, and recomputes the profile at the end (so a card whose word became
/// Mastered is paused from the next session on).
@Observable @MainActor
final class StudyFlowModel {
    private(set) var session: StudySession
    private(set) var flipped = false
    private(set) var errorMessage: String?
    /// Ratings recorded in this flow (also used as a view identity per card showing).
    private(set) var recorded = 0

    private weak var app: AppModel?
    let lexicon: Lexicon
    private var shownAt = Date()
    private let speaker = Speaker()

    init(app: AppModel, lexicon: Lexicon, session: StudySession) {
        self.app = app
        self.lexicon = lexicon
        self.session = session
    }

    var phase: StudySession.Phase { session.phase }

    func entry(_ lemma: String) -> LexiconEntry? { lexicon.entry(lemma: lemma) }

    func note(_ lemma: String) -> String? { session.plan?.note(for: lemma) }

    /// Interval under each button, computed for "now".
    func intervals() -> [Grade: TimeInterval] { session.intervals(at: Date()) }

    func flip() { flipped = true }

    func rate(_ grade: Grade) {
        guard flipped, session.current != nil else { return }
        let now = Date()
        let rt = Int(now.timeIntervalSince(shownAt) * 1000)
        guard let o = session.rate(grade, rtMs: rt, at: now) else { return }
        do {
            try app?.record(o)
            recorded += 1
        } catch {
            errorMessage = "保存失败：\(error)"
        }
        flipped = false
        shownAt = Date()
    }

    func startNewCards() {
        session.startNewCards()
        shownAt = Date()
    }

    /// Stop here (at the separator, or ✕ mid-session). Ratings so far are already saved.
    func finish() {
        session.finish()
    }

    func close() {
        let app = app
        app?.dismissFlow()
        Task { await app?.recomputeProfile() }
    }

    func speak(_ lemma: String) {
        speaker.play(word: lemma, audio: entry(lemma)?.audio ?? "")
    }

    #if DEBUG
    /// `LE_AUTOPLAY=1`: flips and rates every card through the same methods as the buttons.
    /// The first new card is rated 太简单 (to show the replacement); the rest 想起, with one 忘了.
    func autoplayIfRequested() async {
        guard ProcessInfo.processInfo.environment["LE_AUTOPLAY"] != nil else { return }
        let pause = Duration.milliseconds(Int(ProcessInfo.processInfo.environment["LE_AUTOPLAY_MS"] ?? "") ?? 400)
        var newRated = 0
        while true {
            try? await Task.sleep(for: pause)
            switch phase {
            case .review:
                flip()
                try? await Task.sleep(for: pause)
                rate(recorded == 1 ? .again : .good)
            case .separator:
                if ProcessInfo.processInfo.environment["LE_AUTOPLAY_STOP_AT_SEPARATOR"] != nil { return }
                startNewCards()
            case .newCard:
                flip()
                try? await Task.sleep(for: pause)
                newRated += 1
                rate(newRated == 1 ? .easy : .good)
            case .done:
                return
            }
        }
    }
    #endif
}

/// Wiktextract recording when the word has one, otherwise iOS text-to-speech.
@MainActor
final class Speaker {
    private var player: AVPlayer?
    private var failObserver: NSObjectProtocol?
    private let synthesizer = AVSpeechSynthesizer()

    func play(word: String, audio: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        guard let url = URL(string: audio), !audio.isEmpty else { return speak(word) }
        let item = AVPlayerItem(url: url)
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        failObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.speak(word) }
        }
        player = AVPlayer(playerItem: item)
        player?.play()
    }

    private func speak(_ word: String) {
        let u = AVSpeechUtterance(string: word)
        u.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(u)
    }
}
