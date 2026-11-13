import SwiftUI
import TestEngine

/// Full-screen test flow (prototype #13, variant A): top bar with ✕, segmented progress and the
/// live number; a swipeable card; "不认识 / 认识" at the bottom. Answers are saved as they are given.
struct TestFlowView: View {
    let model: TestFlowModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingExit = false

    /// The item on screen. Lags behind `model.phase` while an answer is animating or its
    /// judgment is shown, so the old card can fly out before the next one flips in.
    @State private var shown: TestItem?
    @State private var cardID = 0
    @State private var busy = false
    @State private var reveal: Reveal?

    @State private var drag: CGFloat = 0
    @State private var fly: CGFloat = 0
    @State private var shakes = 0

    @State private var displayedEstimate: Int?
    @State private var delta: Int?
    @State private var deltaToken = 0
    @State private var pulse: Int?

    private struct Reveal {
        var feedback: Feedback
        /// Meaning check: the option tapped (nil = 不认识).
        var chosen: Int??
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            switch model.phase {
            case .result(let result) where !busy:
                TestResultView(result: result) { model.close() }
                    .transition(.opacity)
            case .failed(let message):
                ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
                    .overlay(alignment: .topLeading) { closeButton.padding() }
            default:
                answerScreen
            }
        }
        .animation(.easeOut(duration: 0.25), value: resultShown)
        .task {
            Cues.shared.prepare()
            await model.start()
            #if DEBUG
            await model.autoplayIfRequested()
            #endif
        }
        .onAppear { syncShown() }
        .onChange(of: model.recorded) { if !busy { syncShown() } }
        .onChange(of: phaseKey) { if !busy { syncShown() } }
        .onChange(of: model.liveEstimate) { old, new in estimateChanged(from: old, to: new) }
        .onChange(of: model.segmentsFilled) { old, new in
            guard new > old else { return }
            pulse = new - 1
            Cues.shared.play(.segment)
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                pulse = nil
            }
        }
        .onChange(of: resultShown) { _, shown in if shown { Cues.shared.play(.finish) } }
    }

    /// `LE_SLOW_FEEDBACK=<factor>` stretches the feedback timings for simulator screenshots (DEBUG only).
    private static let slowdown: Double = {
        #if DEBUG
        Double(ProcessInfo.processInfo.environment["LE_SLOW_FEEDBACK"] ?? "") ?? 1
        #else
        1
        #endif
    }()

    private var resultShown: Bool {
        if case .result = model.phase, !busy { return true }
        return false
    }

    private var phaseKey: Int {
        switch model.phase {
        case .preparing: 0
        case .question: 1
        case .computingResult: 2
        case .result: 3
        case .failed: 4
        }
    }

    // MARK: answer screen

    private var answerScreen: some View {
        VStack(spacing: 0) {
            topBar
            stage
                .frame(maxHeight: .infinity)
                .padding(.vertical, 12)
            answerButtons
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            closeButton
            SegmentedProgress(segments: TestFlowModel.segments, progress: model.progress, pulse: pulse)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let delta {
                    Text(delta.signed)
                        .font(Theme.number(13))
                        .foregroundStyle(delta >= 0 ? Theme.good : Theme.bad)
                        .transition(.opacity)
                }
                Text(displayedEstimate?.grouped ?? "–")
                    .font(Theme.number(17))
                    .contentTransition(.numericText(value: Double(displayedEstimate ?? 0)))
                    .accessibilityIdentifier("liveEstimate")
            }
            .fixedSize()
        }
        .alert("退出基线测试？", isPresented: $confirmingExit) {
            Button("退出") { model.close() }
                .accessibilityIdentifier("confirmExit")
            Button("继续", role: .cancel) {}
        }
    }

    private var closeButton: some View {
        Button {
            if model.confirmsExit { confirmingExit = true } else { model.close() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 34, height: 34)
                .background(Theme.surface, in: Circle())
        }
        .accessibilityLabel("退出测试")
        .accessibilityIdentifier("closeTest")
    }

    @ViewBuilder private var stage: some View {
        switch shown {
        case .yesNo(let item):
            WordCard(word: item.word, drag: drag, fly: fly, shakes: shakes, reveal: cardReveal)
                .id(cardID)
                .transition(reduceMotion ? .opacity : .flipIn)
                .gesture(swipe, including: busy ? .none : .all)
        case .meaningCheck(let item):
            MeaningCheckView(item: item, chosen: reveal?.chosen, disabled: busy) { answerMeaning($0) }
                .modifier(Shake(animatableData: CGFloat(shakes)))
                .id(cardID)
                .transition(reduceMotion ? .opacity : .flipIn)
        case nil:
            ProgressView()
        }
    }

    /// ✓ / ✗ overlay on a Yes/No card.
    private var cardReveal: WordCard.Overlay? {
        switch reveal?.feedback {
        case .correct: .correct
        case .wrong(.pseudoword): .wrong("假词")
        case .wrong(.meaning(let m)): .wrong(m)
        case .neutral, nil: nil
        }
    }

    private var answerButtons: some View {
        HStack(spacing: 14) {
            Button { answerYesNo(false) } label: {
                Text("不认识").frame(maxWidth: .infinity).padding(.vertical, 18)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityIdentifier("answerNo")
            Button { answerYesNo(true) } label: {
                Text("认识").frame(maxWidth: .infinity).padding(.vertical, 18)
                    .foregroundStyle(.white)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .accessibilityIdentifier("answerYes")
        }
        .font(.system(size: 18, weight: .bold))
        .buttonStyle(PressStyle())
        .disabled(busy || !isYesNo)
        .opacity(isMeaningCheck ? 0 : 1)
    }

    private var isYesNo: Bool { if case .yesNo = shown { true } else { false } }
    private var isMeaningCheck: Bool { if case .meaningCheck = shown { true } else { false } }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag = $0.translation.width }
            .onEnded { value in
                let dx = value.translation.width + (value.predictedEndTranslation.width - value.translation.width) * 0.2
                if abs(dx) > 90 {
                    answerYesNo(dx > 0)
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { drag = 0 }
                }
            }
    }

    // MARK: answering

    private func answerYesNo(_ yes: Bool) {
        guard !busy, case .yesNo = shown else { return }
        busy = true
        let feedback = model.answer(.yesNo(yes))
        switch feedback {
        case .neutral:
            Cues.shared.play(.tap)
            withAnimation(.easeIn(duration: 0.2)) { fly = yes ? 1 : -1 }
            after(0.2) { next() }
        case .correct, .wrong:
            // Pseudoword: the card starts to leave, comes back and shows the judgment.
            withAnimation(.easeIn(duration: 0.15)) { fly = yes ? 0.35 : -0.35 }
            after(0.15) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    fly = 0
                    drag = 0
                    reveal = Reveal(feedback: feedback)
                }
                judged(feedback)
            }
        }
    }

    private func answerMeaning(_ index: Int?) {
        guard !busy, case .meaningCheck = shown else { return }
        busy = true
        let feedback = model.answer(.meaning(index))
        withAnimation(.easeOut(duration: 0.15)) { reveal = Reveal(feedback: feedback, chosen: .some(index)) }
        judged(feedback)
    }

    private func judged(_ feedback: Feedback) {
        if case .correct = feedback {
            Cues.shared.play(.correct)
            after(0.45) { next() }
        } else {
            Cues.shared.play(.wrong)
            if !reduceMotion { withAnimation(.linear(duration: 0.4)) { shakes += 1 } }
            after(1.3) { next() }
        }
    }

    /// Shows whatever the model has now: the next card, or the result.
    private func next() {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            reveal = nil
            fly = 0
            drag = 0
        }
        withAnimation(.easeOut(duration: 0.32)) {
            syncShown()
            busy = false
        }
    }

    private func syncShown() {
        let item: TestItem? = if case .question(let item) = model.phase { item } else { nil }
        if item != nil || shown != nil { cardID += 1 }
        shown = item
        if displayedEstimate == nil { displayedEstimate = model.liveEstimate }
    }

    private func estimateChanged(from old: Int?, to new: Int?) {
        guard let new else { return }
        guard let old else { displayedEstimate = new; return }
        withAnimation(.easeOut(duration: 0.35)) { displayedEstimate = new }
        let d = new - old
        guard d != 0 else { return }
        deltaToken += 1
        let token = deltaToken
        withAnimation(.easeOut(duration: 0.2)) { delta = d }
        after(0.7) {
            if token == deltaToken { withAnimation(.easeIn(duration: 0.2)) { delta = nil } }
        }
    }

    private func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds * Self.slowdown))
            action()
        }
    }
}

// MARK: - pieces

/// The prototype's `.prog`: N thin segments; a segment pops when it fills.
private struct SegmentedProgress: View {
    let segments: Int
    let progress: Double
    let pulse: Int?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { i in
                let fill = min(1, max(0, progress * Double(segments) - Double(i)))
                GeometryReader { geo in
                    Capsule().fill(Theme.line)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.accent).frame(width: geo.size.width * fill)
                        }
                }
                .frame(height: 6)
                .scaleEffect(y: pulse == i ? 2 : 1)
                .animation(.easeOut(duration: 0.25), value: fill)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: pulse == i)
            }
        }
        .accessibilityElement()
        .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

/// The word card: follows the finger with tint and rotation; shows ✓ / ✗ after a judged answer.
private struct WordCard: View {
    enum Overlay: Equatable {
        case correct
        case wrong(String)
    }

    let word: String
    let drag: CGFloat
    /// -1 … 1: how far the card has flown off to the left / right.
    let fly: CGFloat
    let shakes: Int
    let reveal: Overlay?

    var body: some View {
        let dx = drag + fly * 420
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Theme.surface)
            .shadow(color: Color(red: 20 / 255, green: 30 / 255, blue: 60 / 255).opacity(0.10), radius: 15, y: 10)
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(dx > 0 ? Theme.good : Theme.bad)
                    .opacity(min(0.25, abs(drag) / 400))
            }
            .overlay {
                Text(word)
                    .font(.system(size: 44, weight: .bold))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("testWord")
            }
            .overlay { overlay }
            .aspectRatio(1 / 1.2, contentMode: .fit)
            .frame(maxWidth: 360)
            .modifier(Shake(animatableData: CGFloat(shakes)))
            .offset(x: dx)
            .rotationEffect(.degrees(Double(drag) / 18 + Double(fly) * 18))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
    }

    @ViewBuilder private var overlay: some View {
        if let reveal {
            let ok = reveal == .correct
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(ok ? Theme.goodSoft : Theme.badSoft)
                .overlay {
                    VStack(spacing: 10) {
                        Text(ok ? "✓" : "✗").font(.system(size: 64, weight: .heavy))
                            .foregroundStyle(ok ? Theme.good : Theme.bad)
                        if case .wrong(let answer) = reveal {
                            Text(answer).font(.system(size: 20, weight: .bold)).multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .transition(.opacity)
                .accessibilityIdentifier(ok ? "feedbackCorrect" : "feedbackWrong")
        }
    }
}

/// Meaning check: the word, four glosses and "不认识". Right answer turns green, a wrong tap red.
private struct MeaningCheckView: View {
    let item: MeaningCheckItem
    /// nil: not answered yet; .some(nil): 不认识; .some(i): option i.
    let chosen: Int??
    let disabled: Bool
    let onAnswer: (Int?) -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text(item.lemma)
                .font(.system(size: 32, weight: .bold))
                .minimumScaleFactor(0.5).lineLimit(1)
                .padding(.bottom, 10)
                .accessibilityIdentifier("testWord")
            ForEach(Array(item.options.enumerated()), id: \.offset) { i, option in
                Button { onAnswer(i) } label: {
                    Text(option)
                        .font(.system(size: 17))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 15).padding(.horizontal, 16)
                        .background(fill(i), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(stroke(i), lineWidth: 2)
                        }
                }
                .accessibilityIdentifier("meaningOption\(i)")
            }
            Button { onAnswer(nil) } label: {
                Text("不认识")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .accessibilityIdentifier("meaningUnknown")
        }
        .buttonStyle(PressStyle())
        .foregroundStyle(.primary)
        .disabled(disabled)
        .frame(maxHeight: .infinity)
    }

    private func state(_ i: Int) -> (right: Bool, wrong: Bool) {
        guard let chosen else { return (false, false) }
        return (i == item.correctIndex, chosen == i && i != item.correctIndex)
    }

    private func fill(_ i: Int) -> Color {
        let s = state(i)
        return s.right ? Theme.goodSoft : s.wrong ? Theme.badSoft : Theme.surface
    }

    private func stroke(_ i: Int) -> Color {
        let s = state(i)
        return s.right ? Theme.good : s.wrong ? Theme.bad : .clear
    }
}

/// Horizontal shake, one cycle per increment of `animatableData`.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Slight press-down for the answer buttons.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct FlipIn: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// The prototype's card entry: turns in from 80° around the vertical axis.
    static var flipIn: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: FlipIn(angle: 80, opacity: 0.2), identity: FlipIn(angle: 0, opacity: 1)),
            removal: .identity
        )
    }
}
