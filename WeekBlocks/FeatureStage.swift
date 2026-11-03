import SwiftUI
import SwiftData
import Observation

// MARK: - 기능을 하나씩 건네기

/// 처음 쓰는 사람에게 **기능을 하나씩** 건넨다.
///
/// 처음 켠 화면에 단추 여섯 개 · 판 네 개 · 배너 여러 줄이 한꺼번에 서 있으면, 무엇부터 해야 하는지
/// 아무도 말해 주지 않는다. 그래서 빈 한 주와 '할 일' 하나로 시작한다 — 할 일을 적고 요일 칸에 놓는 것.
/// 그 손짓을 몇 번 해 본 뒤에야 다음 기능이 하나씩 나타난다.
///
/// ⚠️ **이미 쓰던 사람은 건드리지 않는다.** 이 기능 전에 쓰던 사람(처음 안내를 이미 봤거나, 이 기기에서
///    처음 켜기 전에 만든 기록이 있는 사람)은 곧바로 `.all`이다. 손에 익은 단추를 감추면 뺏는 것이다.
enum FeatureLevel: Int, Comparable, CaseIterable {
    /// 빈 한 주 + 할 일 적기 · 요일 칸에 놓기.
    case start = 0
    /// 고정 루틴.
    case routines = 1
    /// 일간 · 시간축 · 요약 · 타이머.
    case views = 2
    /// 나머지 전부 (무지개 · 회고 · 더 보기 · 할 일 판의 정리 도구).
    case all = 3

    static func < (a: FeatureLevel, b: FeatureLevel) -> Bool { a.rawValue < b.rawValue }

    /// 이 단계에 오르려면 **직접 놓은** 블록이 몇 개 있어야 하는가 (캘린더에서 들어온 것은 안 센다).
    var blocksNeeded: Int {
        switch self {
        case .start: 0
        case .routines: 1
        case .views: 3
        case .all: 5
        }
    }

    static func earned(placedBlocks: Int) -> FeatureLevel {
        allCases.last { placedBlocks >= $0.blocksNeeded } ?? .start
    }

    var unlockTitle: String {
        switch self {
        case .start: ""
        case .routines: String(localized: "고정 루틴이 열렸어요")
        case .views: String(localized: "일간 · 시간축 · 타이머가 열렸어요")
        case .all: String(localized: "모든 기능이 열렸어요")
        }
    }

    var unlockDetail: String {
        switch self {
        case .start: ""
        case .routines:
            String(localized: "잠·일처럼 빼놓을 수 없는 시간을 깔아 두면, 남는 자리가 이번 주에 실제로 쓸 수 있는 시간이 됩니다. 아래 '고정 루틴'에서 세워 보세요.")
        case .views:
            String(localized: "날짜 줄 맨 앞에서 하루와 한 주를 바꾸고, 오른쪽에서 시간축과 요약을 봅니다. 지금 하는 일에 남은 시간은 타이머가 셉니다.")
        case .all:
            String(localized: "무지개로 한 주가 얼마나 찼는지, 회고로 지난 주를 봅니다. 캘린더 가져오기와 장기 플랜은 '더 보기'에 있습니다.")
        }
    }

    var unlockIcons: [String] {
        switch self {
        case .start: []
        case .routines: ["lock"]
        case .views: ["calendar.day.timeline.left", "chart.bar.xaxis", "timer"]
        case .all: ["rainbow", "checklist", "ellipsis.circle"]
        }
    }
}

@MainActor
@Observable
final class FeatureStage {
    static let shared = FeatureStage()

    private static let levelKey = "featureLevel"
    private static let guidedKey = "featureLevel.guided"
    private static let startedKey = "featureLevel.startedAt"

    /// 지금 열려 있는 단계. 내려가지 않는다.
    private(set) var level: FeatureLevel {
        didSet { UserDefaults.standard.set(level.rawValue, forKey: Self.levelKey) }
    }

    /// 처음 쓰는 사람으로 시작했는가.
    /// 이 사람은 고정 루틴 없이도 할 일을 적을 수 있고, '다음 한 걸음'이 할 일부터 말한다.
    private(set) var isGuided: Bool {
        didSet { UserDefaults.standard.set(isGuided, forKey: Self.guidedKey) }
    }

    /// 막 열린 단계 — 화면 위에 알림 줄을 세운다. 닫으면 nil.
    var justUnlocked: FeatureLevel?

    /// 이 기기에서 처음 쓰는 사람으로 시작한 때. 그 전에 만든 기록이 내려오면 이미 쓰던 사람이다.
    private let startedAt: Date

    private init() {
        let d = UserDefaults.standard
        if let raw = d.object(forKey: Self.levelKey) as? Int, let saved = FeatureLevel(rawValue: raw) {
            level = saved
            isGuided = d.bool(forKey: Self.guidedKey)
            startedAt = d.object(forKey: Self.startedKey) as? Date ?? .distantPast
        } else if RoutineOnboarding.wasShown || LaunchEnvironment.isUnderTest || Self.hasLocalRecords {
            // 이 기능 전부터 쓰던 사람 — 이 맥에 이미 기록이 있다.
            level = .all
            isGuided = false
            startedAt = .distantPast
            d.set(FeatureLevel.all.rawValue, forKey: Self.levelKey)
        } else {
            // 처음 켰다 — 아니면 다른 맥에서 쓰던 사람이 이 맥을 처음 켰다.
            // 뒤쪽은 기록이 내려온 뒤에 가린다 (→ adoptIfExistingUser).
            level = .start
            isGuided = true
            startedAt = Date()
            d.set(FeatureLevel.start.rawValue, forKey: Self.levelKey)
            d.set(true, forKey: Self.guidedKey)
            d.set(startedAt, forKey: Self.startedKey)
        }
    }

    /// 이 맥의 스토어에 이미 무엇이 있는가. 새로 깐 앱이면 비어 있다.
    private static var hasLocalRecords: Bool {
        let store = PlanStore.shared
        return !store.fetch(Routine.self).isEmpty
            || !store.fetch(PlanBlock.self).isEmpty
            || !store.fetch(BacklogItem.self).isEmpty
    }

    /// 쌓인 만큼 연다. 한 번에 여러 단계를 건너뛰면 알림은 맨 위 단계 하나만 세운다.
    func promote(placedBlocks: Int, hasRoutines: Bool) {
        var target = FeatureLevel.earned(placedBlocks: placedBlocks)
        if hasRoutines { target = max(target, .routines) }
        guard target > level else { return }
        level = target
        if isGuided { justUnlocked = target }
    }

    /// 설정의 '모든 기능 바로 열기'.
    func unlockAll() {
        guard level < .all else { return }
        level = .all
        justUnlocked = nil
    }

    /// **이 기기를 처음 켜기 전에** 만든 기록이 있으면 이미 쓰던 사람이다 — 모든 기능을 연다.
    /// CloudKit이 내려주기 전에는 화면이 비어 있어 처음 쓰는 사람처럼 보인다. 내려온 뒤에 부른다.
    @discardableResult
    func adoptIfExistingUser(in store: PlanStore) -> Bool {
        guard isGuided else { return level == .all }
        let cutoff = startedAt.addingTimeInterval(-60)
        let older = store.fetch(Routine.self).contains { $0.createdAt < cutoff }
            || store.fetch(PlanBlock.self).contains { $0.createdAt < cutoff }
            || store.fetch(BacklogItem.self).contains { $0.createdAt < cutoff }
        guard older else { return false }
        isGuided = false
        level = .all
        justUnlocked = nil
        return true
    }
}

// MARK: - 할 일 칸에 '새 할 일'을 열라는 부탁

/// 화면 위쪽(다음 한 걸음 줄)에서 아래 할 일 판의 빈 칸을 연다. 두 뷰 사이를 잇는 가운데 자리.
@MainActor
@Observable
final class BacklogAddRequest {
    static let shared = BacklogAddRequest()
    private init() { }

    private(set) var tick = 0

    func request() { tick += 1 }
}

// MARK: - 새 기능이 열렸다는 줄

struct FeatureUnlockBanner: View {
    let level: FeatureLevel
    var onClose: () -> Void = { }

    @State private var shownIcons = 0
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Array(level.unlockIcons.enumerated()), id: \.offset) { i, icon in
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.accentColor.gradient))
                        .scaleEffect(shownIcons > i ? 1 : 0.2)
                        .opacity(shownIcons > i ? 1 : 0)
                        .rotationEffect(.degrees(shownIcons > i ? 0 : -40))
                        .symbolEffect(.bounce, value: shownIcons > i)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(level.unlockTitle)
                    .font(.headline)
                Text(level.unlockDetail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("확인", action: onClose)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.10), in: .soft(Corner.card))
        .overlay(
            RoundedRectangle.soft(Corner.card)
                .strokeBorder(Color.accentColor.opacity(glow ? 0.55 : 0.15), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .task(id: level) {
            if reduceMotion {
                shownIcons = level.unlockIcons.count
                return
            }
            shownIcons = 0
            for i in 1...max(1, level.unlockIcons.count) {
                try? await Task.sleep(for: .milliseconds(i == 1 ? 250 : 160))
                withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { shownIcons = i }
            }
            withAnimation(.easeInOut(duration: 0.9).repeatCount(3, autoreverses: true)) { glow = true }
        }
    }
}
