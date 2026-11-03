import SwiftUI

/// 처음 켠 사람에게 **움직이는 그림 네 장으로** 앱을 건넨다.
///
/// 글로 된 안내는 읽히지 않는다. 이 앱이 하는 일은 결국 한 손짓 — 할 일을 적고, 요일 칸에 끌어다 놓는 것 —
/// 이라서, 그 손짓을 눈앞에서 한 번 보여 준다. 나머지 기능은 여기서 설명하지 않는다.
/// 쓰다 보면 하나씩 열린다 (→ FeatureStage.swift).
///
/// 움직임 줄이기를 켠 사람에게는 각 장의 끝 그림만 보여 준다.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var pageForward = true

    private static let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0:
                    scene(TutorialWeekScene(),
                          title: "한 주를 블록으로 짭니다",
                          detail: "이번 주에 할 일을 요일 칸에 놓아 두면, 언제 무엇을 할지가 한눈에 보입니다.")
                        .transition(.pageSlide(forward: pageForward))
                case 1:
                    scene(TutorialTypeScene(),
                          title: "할 일을 한 줄 적고",
                          detail: "화면 아래 '할 일'에 적습니다. 언제 할지는 아직 정하지 않아도 됩니다.")
                        .transition(.pageSlide(forward: pageForward))
                case 2:
                    scene(TutorialDragScene(),
                          title: "요일 칸으로 끌어다 놓으면 끝",
                          detail: "카드를 잡아 요일 칸에 떨어뜨리면 그날의 계획이 됩니다. 놓은 뒤에도 다른 요일로 옮길 수 있습니다.")
                        .transition(.pageSlide(forward: pageForward))
                default:
                    scene(TutorialUnlockScene(),
                          title: "나머지는 쓰다 보면 하나씩 열립니다",
                          detail: "처음에는 이 두 가지만 있습니다. 블록을 놓을수록 고정 루틴, 일간, 타이머 같은 기능이 차례로 나타납니다.")
                        .transition(.pageSlide(forward: pageForward))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
            footer
        }
        .frame(minWidth: 600, minHeight: 540)
    }

    private func scene(_ art: some View, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 22) {
            art
                .frame(width: 480, height: 270)
                .background(Color.primary.opacity(0.035), in: .soft(Corner.card))
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title)
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }
        }
        .padding(28)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("건너뛰기") { finish() }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 6) {
                ForEach(0...Self.lastPage, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: i == page ? 18 : 7, height: 7)
                }
            }
            .animation(Motion.screen, value: page)

            Spacer()

            if page > 0 {
                Button("이전") { go(-1) }
                    .buttonStyle(.bordered)
                    .transition(.control)
            }
            Button(page == Self.lastPage ? "시작하기" : "다음") {
                if page == Self.lastPage { finish() } else { go(1) }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .animation(Motion.screen, value: page)
    }

    private func go(_ delta: Int) {
        pageForward = delta > 0
        withAnimation(Motion.screen) { page += delta }
    }

    /// 다시 묻지 않는다. 메뉴 막대의 도움말과 설정에서 언제든 다시 볼 수 있다.
    private func finish() {
        Telemetry.record(.onboardingFinished)
        UserDefaults.standard.set(true, forKey: RoutineOnboarding.shownKey)
        dismiss()
    }
}

// MARK: - 그림에 쓰는 조각

private enum TutorialArt {
    static let columnWidth: CGFloat = 52
    static let columnGap: CGFloat = 8
    static let columnHeight: CGFloat = 150

    /// 요일 머리글 — 사람이 정한 한 주의 시작과 로케일을 따른다. 그림이라 글자는 따로 번역하지 않는다.
    static var weekdaySymbols: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols   // 일요일부터
        return WeekStartSetting.sundayFirst ? symbols : Array(symbols[1...]) + [symbols[0]]
    }

    static var gridWidth: CGFloat { columnWidth * 7 + columnGap * 6 }

    static func column(_ label: String, highlighted: Bool = false) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            RoundedRectangle.soft(Corner.segment)
                .fill(Color.primary.opacity(highlighted ? 0.10 : 0.05))
                .overlay(
                    RoundedRectangle.soft(Corner.segment)
                        .strokeBorder(highlighted ? Color.accentColor : Color.primary.opacity(0.08),
                                      lineWidth: highlighted ? 2 : 1)
                )
                .frame(width: columnWidth, height: columnHeight)
        }
    }

    static func card(_ title: String, compact: Bool = false) -> some View {
        Text(title)
            .font(.body.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 4 : 12)
            .padding(.vertical, compact ? 6 : 9)
            .frame(width: compact ? columnWidth - 6 : nil)
            .background(Color.accentColor.gradient, in: .soft(Corner.segment))
    }

    static var sampleTodo: String { String(localized: "기획서 초안 작성", comment: "샘플 할 일") }
}

/// 장면을 되풀이한다. 장을 떠나면 task가 취소되어 멎는다.
private func loopScene(reduceMotion: Bool, finalState: () -> Void, _ body: () async -> Void) async {
    if reduceMotion { finalState(); return }
    while !Task.isCancelled { await body() }
}

private func pause(_ seconds: Double) async {
    try? await Task.sleep(for: .seconds(seconds))
}

// MARK: 1. 빈 한 주가 펼쳐진다

private struct TutorialWeekScene: View {
    @State private var shown = 0
    @State private var filled: Set<Int> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let blocks: [(day: Int, top: CGFloat, height: CGFloat)] = [
        (0, 20, 40), (1, 70, 30), (2, 10, 50), (4, 40, 36), (5, 80, 44),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: TutorialArt.columnGap) {
            ForEach(0..<7, id: \.self) { i in
                TutorialArt.column(TutorialArt.weekdaySymbols[i])
                    .overlay(alignment: .top) {
                        ForEach(blocks.filter { $0.day == i }, id: \.top) { b in
                            RoundedRectangle.soft(Corner.segment)
                                .fill(Color.accentColor.gradient)
                                .frame(width: TutorialArt.columnWidth - 8, height: b.height)
                                .offset(y: 30 + b.top)
                                .scaleEffect(filled.contains(i) ? 1 : 0.3, anchor: .top)
                                .opacity(filled.contains(i) ? 1 : 0)
                        }
                    }
                    .opacity(shown > i ? 1 : 0)
                    .offset(y: shown > i ? 0 : 24)
            }
        }
        .task {
            await loopScene(reduceMotion: reduceMotion, finalState: {
                shown = 7; filled = Set(blocks.map(\.day))
            }) {
                shown = 0; filled = []
                await pause(0.3)
                for i in 1...7 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { shown = i }
                    await pause(0.07)
                }
                await pause(0.5)
                for b in blocks {
                    _ = withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { filled.insert(b.day) }
                    await pause(0.22)
                }
                await pause(2.4)
                withAnimation(.easeOut(duration: 0.3)) { shown = 0; filled = [] }
                await pause(0.4)
            }
        }
    }
}

// MARK: 2. 할 일을 적는다

private struct TutorialTypeScene: View {
    @State private var typed = 0
    @State private var cursorOn = true
    @State private var committed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var text: String { TutorialArt.sampleTodo }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 할 일 판의 머리글을 흉내 낸다.
            HStack(spacing: 8) {
                Text("할 일").font(.headline)
                Label("새 할 일", systemImage: "plus")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: Capsule())
                Spacer()
            }

            HStack(spacing: 0) {
                Text(String(text.prefix(typed)))
                    .font(.title3)
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 22)
                    .opacity(cursorOn && !committed ? 1 : 0)
                Spacer()
                Image(systemName: "return")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .opacity(typed == text.count && !committed ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.06), in: .soft(Corner.card))
            .overlay(RoundedRectangle.soft(Corner.card).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5))
            .opacity(committed ? 0.35 : 1)

            HStack {
                if committed {
                    TutorialArt.card(text)
                        .transition(.asymmetric(insertion: .scale(scale: 0.6, anchor: .topLeading).combined(with: .opacity),
                                                removal: .opacity))
                }
                Spacer()
            }
            .frame(height: 44)
        }
        .frame(width: 380)
        .task {
            await loopScene(reduceMotion: reduceMotion, finalState: {
                typed = text.count; committed = true
            }) {
                typed = 0; committed = false
                for _ in 0..<2 { cursorOn.toggle(); await pause(0.35) }
                cursorOn = true
                for i in 1...text.count {
                    typed = i
                    await pause(0.09)
                }
                await pause(0.6)
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { committed = true }
                await pause(2.2)
                withAnimation(.easeOut(duration: 0.3)) { committed = false; typed = 0 }
                await pause(0.4)
            }
        }
    }
}

// MARK: 3. 요일 칸으로 끌어다 놓는다

private struct TutorialDragScene: View {
    private enum Phase { case resting, lifted, moving, dropped }

    @State private var phase: Phase = .resting
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 놓을 요일 칸 (0부터). 가운데쯤이라 손이 지나는 길이 잘 보인다.
    private let targetDay = 2

    private var gridOriginX: CGFloat { (480 - TutorialArt.gridWidth) / 2 }
    private var restPoint: CGPoint { CGPoint(x: gridOriginX + 70, y: 230) }
    private var dropPoint: CGPoint {
        CGPoint(x: gridOriginX + CGFloat(targetDay) * (TutorialArt.columnWidth + TutorialArt.columnGap)
                    + TutorialArt.columnWidth / 2,
                y: 100)
    }

    private var cardPoint: CGPoint {
        switch phase {
        case .resting, .lifted: restPoint
        case .moving, .dropped: dropPoint
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: TutorialArt.columnGap) {
                ForEach(0..<7, id: \.self) { i in
                    TutorialArt.column(TutorialArt.weekdaySymbols[i],
                                       highlighted: i == targetDay && phase == .moving)
                }
            }
            .padding(.top, 14)
            .frame(width: 480)

            // 끌려가는 카드. 놓이면 칸 너비로 줄어든다.
            TutorialArt.card(TutorialArt.sampleTodo, compact: phase == .dropped)
                .scaleEffect(phase == .lifted || phase == .moving ? 1.08 : 1)
                .shadow(color: .black.opacity(phase == .lifted || phase == .moving ? 0.25 : 0),
                        radius: 10, y: 6)
                .position(cardPoint)

            // 손. 카드를 잡고 함께 간다.
            Image(systemName: phase == .resting ? "hand.point.up.left.fill" : "hand.raised.fill")
                .font(.system(size: 30))
                .foregroundStyle(.primary)
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
                .position(x: cardPoint.x + 18, y: cardPoint.y + 22)
                .opacity(phase == .dropped ? 0 : 1)
        }
        .frame(width: 480, height: 270)
        .task {
            await loopScene(reduceMotion: reduceMotion, finalState: { phase = .dropped }) {
                phase = .resting
                await pause(0.9)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { phase = .lifted }
                await pause(0.4)
                withAnimation(.easeInOut(duration: 1.0)) { phase = .moving }
                await pause(1.2)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { phase = .dropped }
                await pause(2.2)
                withAnimation(.easeOut(duration: 0.25)) { phase = .resting }
                await pause(0.3)
            }
        }
    }
}

// MARK: 4. 기능이 하나씩 열린다

private struct TutorialUnlockScene: View {
    @State private var unlocked = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let features: [(icon: String, name: LocalizedStringKey)] = [
        ("lock", "고정 루틴"),
        ("calendar.day.timeline.left", "일간"),
        ("timer", "타이머"),
        ("rainbow", "무지개"),
        ("checklist", "회고"),
    ]

    var body: some View {
        VStack(spacing: 26) {
            // 지금 있는 두 가지.
            HStack(spacing: 10) {
                Label("할 일", systemImage: "square.and.pencil")
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                Label("요일 칸", systemImage: "calendar")
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.12), in: Capsule())

            HStack(spacing: 18) {
                ForEach(Array(features.enumerated()), id: \.offset) { i, f in
                    let open = unlocked > i
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(open ? AnyShapeStyle(Color.accentColor.gradient)
                                           : AnyShapeStyle(Color.primary.opacity(0.07)))
                                .frame(width: 56, height: 56)
                            Image(systemName: open ? f.icon : "lock.fill")
                                .font(.title2)
                                .foregroundStyle(open ? Color.white : Color.secondary)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .scaleEffect(open ? 1 : 0.9)
                        .symbolEffect(.bounce, value: open)
                        Text(f.name)
                            .font(.body)
                            .foregroundStyle(open ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 70)
                }
            }
        }
        .task {
            await loopScene(reduceMotion: reduceMotion, finalState: { unlocked = features.count }) {
                unlocked = 0
                await pause(0.8)
                for i in 1...features.count {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { unlocked = i }
                    await pause(0.6)
                }
                await pause(2.0)
                withAnimation(.easeOut(duration: 0.3)) { unlocked = 0 }
                await pause(0.4)
            }
        }
    }
}
