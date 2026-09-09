//
//  Telemetry.swift
//  WeekBlocks (무지개 공방)
//
//  **얼마나 쓰이는지를 익명으로 세는 자리.** 수집은 전부 LeeoKit의
//  `LeeoUsageReporter`가 하고, 이 파일은 **무엇을 셀지와 언제 멈출지**만 정한다.
//
//  가는 곳은 피드백과 같은 허브다 — `iCloud.com.Ysoup.FeedbackHub` 의 공개 DB.
//  앱 구분은 `WeekBlocksSpec.feedback.appIdentifier`(= 번들 ID)로 한다.
//  두 종류가 올라간다:
//    · `UsageSnapshot` — 설치마다 **한 줄**. 켤 때마다 덮어쓴다. 설치 수·버전 분포·
//      얼마나 오래 쓰는지를 여기서 본다. 앱 고유 숫자(할 일 수 등)는 `metrics` 한 칸에 담는다.
//    · `UsageEvent`  — 의미 있는 행동 한 건. 아래 `Milestone` 목록이 전부다.
//
//  ⚠️ **사람을 식별하지 않는다.** 붙는 것은 설치할 때 만든 무작위 UUID 하나뿐이고
//     (`LeeoUsageReporter.installID`), 애플 계정·기기 ID·이름·적은 내용은 **아무것도**
//     따라가지 않는다. 지우고 다시 깔면 남남이 된다.
//
//  ⚠️ **끌 수 있어야 보내도 되는 것이다.** 설정에 스위치를 두고(→ SettingsView),
//     끈 사람에게는 스냅샷도 이벤트도 나가지 않는다. LeeoKit 안에서 저절로 발화하는
//     페이월·리뷰 이벤트까지 막으려고 분석 싱크 자체를 이 스위치로 감쌌다
//     (→ `WeekBlocksAnalytics`). 스위치를 앱 안에만 두고 싱크를 안 감싸면
//     "껐는데도 페이월 이벤트는 간다"가 된다.
//
//  ⚠️ **드물게 보낸다.** 공개 DB 쓰기라 값이 든다. 스냅샷은 12시간에 한 번(LeeoKit 기본),
//     이벤트는 같은 이름당 하루 한 번으로 줄인다. '할 일 추가' 같은 잦은 행동은
//     한 건씩 남기면 허브가 그 앱 하나로 가득 찬다 — 횟수는 `LeeoEngagement`가
//     기기 안에서 세고, 그 합계만 스냅샷에 실려 하루 한 번 올라간다.
//

import Foundation
import LeeoKit

// MARK: - 이벤트 목록

/// 허브에 한 줄로 남길 만한 행동. **여기 없는 것은 안 보낸다.**
///
/// 고르는 기준은 "이 앱이 무엇으로 쓰이는지"를 가르는 갈래인가다. 잦기만 한 행동은
/// 여기 넣지 말고 `Telemetry.signal()`로 횟수만 센다.
enum Milestone: String {
    /// 처음 안내를 끝까지 봤다 — 여기까지 온 사람과 첫 화면에서 나간 사람을 가른다.
    case onboardingFinished = "onboarding_finished"
    /// 할 일을 적었다.
    case todoAdded = "todo_added"
    /// 할 일을 끝냈다 — 적기만 하고 안 끝내는지, 실제로 도는지.
    case todoCompleted = "todo_completed"
    /// 주간 계획에 블록을 놓았다.
    case planBlockAdded = "plan_block_added"
    /// 고정 루틴을 만들었다.
    case routineAdded = "routine_added"
    /// 맥 캘린더에서 일정을 가져왔다.
    case calendarImported = "calendar_imported"
    /// 타이머가 0에 닿았다 — 재기만 한 것과 끝까지 간 것은 다르다.
    case timerFinished = "timer_finished"
    /// 주간 일정을 다른 사람에게 공유하기 시작했다.
    case scheduleShared = "schedule_shared"
}

// ⚠️ 구매 퍼널(paywall_shown → purchase_started → completed/failed → restored)은 여기 없다.
//    그쪽은 `LeeoAnalyticsCenter`로 흐른다 — 하루 한 번 상한에 걸리면 안 되고,
//    페이월을 연 것을 '만족한 행동'으로 세면 안 되기 때문이다. 노출만 앱이 손으로
//    남기고(→ PaywallView) 나머지는 `LeeoStore`가 알아서 낸다 (→ MacEntitlement.swift).

// MARK: - 수집

enum Telemetry {

    /// **끈 사람에게는 아무것도 안 보낸다.** 설정의 스위치가 이 값을 뒤집는다.
    ///
    /// ⚠️ 키가 '끄기'인 이유: `UserDefaults.bool`의 기본값이 false라, '보내기'로 두면
    ///    한 번도 설정을 연 적 없는 사람이 전부 '끔'이 되어 아무 데이터도 안 모인다.
    ///    반대로 '끄기'로 두면 기본이 '보냄'이고, 끈 사람만 true로 남는다.
    static let optOutKey = "usage.optOut"

    static var isEnabled: Bool { !UserDefaults.standard.bool(forKey: optOutKey) }

    /// 피드백과 같은 컨테이너·같은 appId를 쓴다 (→ WeekBlocksSpec.feedback).
    static let reporter = LeeoUsageReporter(spec: WeekBlocksSpec.self)

    // MARK: 설치 스냅샷

    /// 이 설치가 지금 어떤 모습인지를 한 줄로 갱신한다. 앱이 켜지고 스토어가 선 뒤 부른다.
    ///
    /// LeeoKit이 12시간 간격을 스스로 지키므로 자주 불러도 실제 쓰기는 드물다.
    /// 그래서 부르는 쪽은 타이밍을 재지 않아도 된다.
    @MainActor
    static func reportSnapshot() {
        guard isEnabled else { return }
        reporter.reportInBackground(metrics: metrics())
    }

    /// 스냅샷에 실을 앱 고유 숫자. **내용은 안 담고 개수만 담는다** —
    /// 할 일 제목 한 글자도 여기 들어가지 않는다.
    @MainActor
    private static func metrics() -> [String: Double] {
        let todos = TodoStore.shared.allItems()
        let done = todos.filter(\.isCompleted).count
        return [
            "todos": Double(todos.count),
            "todosDone": Double(done),
            "categories": Double(TodoStore.shared.categories().count),
            "planBlocks": Double(PlanStore.shared.fetch(PlanBlock.self).count),
            "routines": Double(PlanStore.shared.fetch(Routine.self).count),
        ]
    }

    // MARK: 행동

    /// 의미 있는 행동 한 건. 기기 안 카운터를 올리고, 하루 한 번까지만 허브에 남긴다.
    ///
    /// 카운터(`LeeoEngagement`)는 만족도·리뷰 프롬프트의 타이밍 근거이면서 다음 스냅샷에
    /// `eventCount`로 실려 나간다. 그래서 하루 상한에 걸려 이벤트가 안 나가도
    /// **횟수 자체는 잃지 않는다.**
    static func record(_ milestone: Milestone) {
        LeeoEngagement.shared.registerSignificantEvent()
        guard isEnabled, firstTimeToday(milestone.rawValue) else { return }
        reporter.logEventInBackground(milestone.rawValue)
    }

    /// 허브에 남길 만큼은 아니지만 "썼다"고는 세어야 하는 행동.
    /// 만족도 프롬프트가 이 숫자를 보고 뜬다.
    static func signal() {
        LeeoEngagement.shared.registerSignificantEvent()
    }

    /// 오늘 이 이름으로 처음인가. 맞으면 오늘 자로 도장을 찍고 true.
    ///
    /// ⚠️ 날짜 경계로 자른다(24시간 간격이 아니라). 자정 넘어 쓰는 사람의 하루를
    ///    이틀로 세지 않으려는 게 아니라, 그 반대다 — 새벽 2시와 오후 2시를 같은 날로
    ///    묶어 하루 한 줄을 지킨다.
    private static func firstTimeToday(_ name: String) -> Bool {
        let key = "usage.lastEvent.\(name)"
        let today = Calendar.current.startOfDay(for: Date())
        let last = UserDefaults.standard.object(forKey: key) as? Date
        guard last.map({ Calendar.current.startOfDay(for: $0) < today }) ?? true else { return false }
        UserDefaults.standard.set(Date(), forKey: key)
        return true
    }
}

// MARK: - 분석 싱크

/// LeeoKit 안에서 저절로 발화하는 이벤트(구매 시도·성공·실패·복원, 만족도, 리뷰, 피드백)를
/// 허브로 흘려보내는 싱크. **스위치를 여기서도 본다** — 앱이 부르는 자리만 막으면
/// LeeoKit이 스스로 부르는 자리가 새기 때문이다 (→ `Telemetry.isEnabled`).
///
/// ⚠️ 여기 오는 이벤트는 하루 상한을 안 건다. 구매 흐름은 하루에 몇 번 없고,
///    그중 하나를 잃으면 퍼널의 어느 칸이 비는지 알 수 없게 된다.
struct WeekBlocksAnalytics: LeeoAnalytics {
    private let hub = LeeoUsageAnalytics(spec: WeekBlocksSpec.self)

    func track(_ event: LeeoEvent) {
        #if DEBUG
        LeeoConsoleAnalytics().track(event)
        #endif
        guard Telemetry.isEnabled else { return }
        hub.track(event)
    }
}
