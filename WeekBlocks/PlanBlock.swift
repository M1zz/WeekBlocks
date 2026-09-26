import Foundation
import SwiftData

@Model
final class PlanBlock {
    var dayRaw: Int = DayOfWeek.mon.rawValue
    var timeBandRaw: String = TimeBand.evening.rawValue
    var durationHours: Double = 1
    var title: String = ""
    var successCriteria: String = ""
    var deliverable: String = ""

    /// Monday 00:00 of this block's week.
    var weekStartDate: Date = Date.currentWeekStart

    /// Whether the user passed the concreteness check at save time.
    var concreteVerified: Bool = false

    /// 회사일 같은 기존 루틴 시간 *안에서* 진행되는 일정인지.
    /// true면 자유 시간을 추가로 소비하지 않고, 타임라인에서 루틴 위에 겹쳐 표시한다.
    var withinRoutine: Bool = false
    /// 정확한 시작 시각(h). -1 = 미설정(시간대 기반 배치). 루틴 내부 일정에서 사용.
    var startHour: Double = -1

    var createdAt: Date = Date()

    /// 맥 캘린더에서 온 블록이면 그 일정을 가리키는 이름 (→ CalendarImport.swift).
    /// nil이면 사람이 직접 세운 블록이라 가져오기가 절대 건드리지 않는다.
    ///
    /// ⚠️ **CloudKit 스키마가 늘어나는 필드다.** 옵셔널이라 기존 레코드는 그대로 열리지만,
    ///    출시 전에 Development → Production 스키마 배포를 빠뜨리면 이 필드를 모르는
    ///    서버가 미러링 초기화 자체를 실패시킨다 (→ WeekBlocks.entitlements의 경고).
    var calendarEventID: String? = nil


    // MARK: - 함께 쓰는 것인가 (→ TodoSharing.swift)
    //
    // 할 일과 같은 규칙을 계획·루틴에도 건다. 동기화 엔진은 골라서 안 올리는 것을
    // 못 하므로, **올라가게 두고 받는 쪽에서 안 그린다.** 그 판단에 필요한 것이
    // 레코드에 같이 실려 가야 한다 — 받는 쪽은 상대가 그때 샀는지를 알 길이 없다.

    /// 상대 기기에도 보여도 되는가. 잠긴 기기에서 만든 것은 false로 찍힌다.
    var isShared: Bool = true

    /// 이것이 난 자리(앱 설치본). 잠긴 기기의 스토어에는 자기 것과 상대 것이 섞여 있어서,
    /// 감출 것을 고르려면 누가 만들었는지를 알아야 한다.
    /// 비어 있으면 이 기능이 생기기 전에 만든 것이고, 그때는 내 것으로 본다.
    var originInstallID: String = ""

    /// **다음 첫 동작.** 이 일을 멈출 때 "돌아오면 무엇부터 하면 되는지"를 한 줄로 남긴다.
    ///
    /// 끊긴 일로 돌아올 때 가장 비싼 것은 시간이 아니라 **다시 올라오는 일**이다 — 어디까지
    /// 했는지, 무엇부터 손대야 하는지를 기억에서 다시 지어내야 한다. 그 한 줄을 멈추는 사람이
    /// 적어 두면(그때가 가장 잘 아는 때다) 돌아온 사람은 읽기만 하면 된다 (→ TimerView).
    ///
    /// ⚠️ **CloudKit 스키마가 늘어나는 필드다.** 옵셔널이라 기존 레코드는 그대로 열리지만,
    ///    ① iOS '욕망의 무지개'에도 **같이** 넣어야 하고(한쪽만 알면 다른 쪽이 못 읽는다),
    ///    ② 출시 전에 Development → Production 스키마 배포를 해야 한다
    ///       (→ CloudSchemaPrimer.swift가 이 칸에 표본 값을 채워 올린다).
    var nextAction: String? = nil

    /// **알약 아이콘** (SF Symbol 이름). nil 이면 만든 시각에서 늘 같은 하나를 뽑아 그린다
    /// (→ `symbol`). 일간 시간표에서 알약 아이콘을 누르면 새로 뽑아 여기 적는다.
    ///
    /// ⚠️ **CloudKit 스키마가 늘어나는 필드다.** 맥·아이폰 PlanBlock 양쪽에 같이 있어야 하고,
    ///    출시 전 Development → Production 스키마 배포에 실려 가야 한다 (→ CloudSchemaPrimer).
    var iconName: String? = nil

    // Review (populated after the day passes)
    var reviewStatusRaw: String? = nil
    var reviewNote: String? = nil
    var reviewedAt: Date? = nil

    init(day: DayOfWeek,
         timeBand: TimeBand,
         durationHours: Double,
         title: String,
         successCriteria: String,
         deliverable: String,
         weekStartDate: Date,
         concreteVerified: Bool = false,
         withinRoutine: Bool = false,
         startHour: Double = -1)
    {
        self.dayRaw = day.rawValue
        self.timeBandRaw = timeBand.rawValue
        self.durationHours = durationHours
        self.title = title
        self.successCriteria = successCriteria
        self.deliverable = deliverable
        self.weekStartDate = weekStartDate
        self.concreteVerified = concreteVerified
        self.withinRoutine = withinRoutine
        self.startHour = startHour
        self.createdAt = Date()
        // ⚠️ **여기서 찍는다.** 만드는 자리가 여섯 곳이라 부르는 쪽에 맡기면 언젠가
        //    한 곳을 빠뜨리고, 빠뜨린 것은 '잠긴 기기에서 만든 게 상대에게 보인다'는
        //    조용한 구멍이 된다. CloudKit이 내려준 레코드는 init을 거치지 않으므로
        //    남의 값이 덮이지 않는다.
        TodoSharing.stamp(self)
    }

    var day: DayOfWeek {
        get { DayOfWeek(rawValue: dayRaw) ?? .mon }
        set { dayRaw = newValue.rawValue }
    }

    var timeBand: TimeBand {
        get { TimeBand(rawValue: timeBandRaw) ?? .evening }
        set { timeBandRaw = newValue.rawValue }
    }

    /// 하루 일정 흐름대로 정렬하기 위한 대표 시작 시각.
    /// 정확한 시각이 있으면 그 값을, 없으면 시간대(아침/오후/저녁/심야)의 시작 시각을 쓴다.
    var sortHour: Double {
        if isAllDay { return -1 }
        if startHour >= 0 { return startHour }
        switch timeBand {
        case .morning: return 6
        case .afternoon: return 12
        case .evening: return 18
        case .night: return 23
        }
    }

    var reviewStatus: ReviewStatus? {
        get { reviewStatusRaw.flatMap(ReviewStatus.init(rawValue:)) }
        set {
            reviewStatusRaw = newValue?.rawValue
            reviewedAt = newValue == nil ? nil : Date()
        }
    }
}


// MARK: - 종일

extension PlanBlock {
    /// `startHour`에 적는 '종일' 표시.
    ///
    /// 캘린더의 기념일·마감일 같은 종일 일정은 '이 날의 일'이지 '하루 중 한 시간을 쓰는 일'이
    /// 아니다. 예전에는 한 시간짜리로 들여서 그 한 시간이 자유 시간에서 빠졌다 (레딧 피드백).
    ///
    /// ⚠️ **필드를 늘리지 않고 기존 칸에 적는다.** 새 필드는 아이폰 '욕망의 무지개'와 CloudKit
    ///    스키마까지 걸린다. -1(시각 미정)보다 작은 값이라 이 표시를 모르는 쪽(아이폰)은
    ///    '시각 없음'으로 읽고, 길이가 0이라 어디서도 시간을 차지하지 않는다.
    static let allDayHour: Double = -2

    /// 시간을 차지하지 않고 그날 맨 위에 서는 블록인가. 루틴 안 일정은 늘 시각을 갖는다.
    var isAllDay: Bool { startHour <= Self.allDayHour + 0.5 && !withinRoutine }

    /// 시각이 정해진 블록은 시각을, 종일은 '종일'을, 아니면 시간대를.
    var whenLabel: String {
        if isAllDay { return String(localized: "종일") }
        return startHour >= 0 ? formatHour(startHour) : timeBand.shortLabel
    }

    /// 종일로 만든다 — 시각은 비우고 길이는 0.
    func makeAllDay() {
        startHour = Self.allDayHour
        durationHours = 0
    }

    /// 종일 블록을 하루 어느 시각에 세울 때. 길이가 0이면 자 위에 설 폭이 없으니 한 시간을 준다.
    func leaveAllDay(defaultHours: Double = 1) {
        guard isAllDay else { return }
        startHour = -1
        if durationHours <= 0 { durationHours = defaultHours }
    }
}

// MARK: - 끌어 옮기기

extension PlanBlock {
    /// 요일 칸·시간 자가 함께 쓰는 드래그 식별자.
    /// 두 화면이 같은 규칙으로 만들고 읽어야 어디서 집어 어디에 놓든 같은 블록에 닿는다.
    var dragToken: String { "block:" + String(describing: persistentModelID) }

    /// 드래그 토큰이 가리키는 블록. 블록 토큰이 아니거나 찾지 못하면 nil.
    static func matching(dragToken token: String, in blocks: [PlanBlock]) -> PlanBlock? {
        guard token.hasPrefix("block:") else { return nil }
        return blocks.first { $0.dragToken == token }
    }
}


// MARK: - 점검하는 줄과 아닌 줄

extension PlanBlock {
    /// **루틴에서 온 줄인가.**
    ///
    /// 루틴은 '했는지'를 묻지 않는다. 수면·끼니·출근은 달성하는 것이 아니라 지켜지는 것이고,
    /// 그것까지 체크 줄에 세우면 정작 돌아봐야 할 것이 그 사이에 묻힌다.
    ///
    /// 둘 중 하나면 루틴으로 본다.
    /// - `withinRoutine` — '기존 루틴 시간 안에서 진행'으로 적어 둔 것.
    /// - 제목이 루틴 이름과 같은 것 — 루틴을 요일에 끌어 올리면 그 **이름 그대로** 계획 블록이
    ///   된다 (→ ContentView.dropBacklogItem의 `routine:` 갈래).
    ///
    /// ⚠️ 모델에 표시를 더하지 않고 **이름으로 가린다.** 필드를 늘리면 같은 CloudKit 그릇을 쓰는
    ///    아이폰 '욕망의 무지개'까지 스키마가 걸린다. 이름이 겹치는 일은 드물고, 겹쳐도 잃는 것은
    ///    '점검 줄에서 빠진다'뿐이다.
    func isRoutineKind(_ routineNames: Set<String>) -> Bool {
        withinRoutine || routineNames.contains(title)
    }

    /// 지나간 날인데 아직 안 찍은 줄인가. 오지 않은 날은 세지 않는다 — 나무랄 수 없다.
    /// 같은 **보이는 주** 안에서 요일만 옮긴다.
    /// 일요일 시작 화면의 일요일은 앞 ISO 주에 적혀 있어서, 그 칸을 오가면 요일과 함께 주도 바뀐다
    /// (→ WeekStartSetting). 요일만 바꾸면 한 주 뒤의 일요일로 사라진다.
    func move(to newDay: DayOfWeek, sundayFirst: Bool = WeekStartSetting.sundayFirst) {
        guard newDay != day else { return }
        let shown = DayOfWeek.shownWeek(of: day, storedWeek: weekStartDate, sundayFirst: sundayFirst)
        day = newDay
        weekStartDate = DayOfWeek.storedWeek(of: newDay, shownWeek: shown, sundayFirst: sundayFirst)
    }

    func isUnreviewedPast(weekStart: Date, routineNames: Set<String>, now: Date = Date()) -> Bool {
        guard reviewStatus == nil, !isRoutineKind(routineNames) else { return false }
        let cal = Calendar(identifier: .iso8601)
        guard let d = cal.date(byAdding: .day, value: day.rawValue, to: weekStart) else { return false }
        return cal.startOfDay(for: d) < cal.startOfDay(for: now)
    }
}

// MARK: - 알약 아이콘

extension PlanBlock {
    /// 뽑을 수 있는 아이콘. 할 일의 성격을 짐작하지 않는 두루 쓰이는 것들이다 —
    /// 제목을 보고 고르면 틀리는 순간 거슬리고, 무작위는 틀릴 일이 없다. 마음에 안 들면 누르면 된다.
    static let symbolChoices: [String] = [
        "star.fill", "leaf.fill", "flame.fill", "bolt.fill", "book.fill", "pencil",
        "paintbrush.fill", "hammer.fill", "cup.and.saucer.fill", "fork.knife", "figure.walk",
        "dumbbell.fill", "music.note", "gamecontroller.fill", "laptopcomputer", "phone.fill",
        "envelope.fill", "cart.fill", "house.fill", "car.fill", "airplane", "heart.fill",
        "brain.head.profile", "lightbulb.fill", "graduationcap.fill", "briefcase.fill",
        "calendar", "checklist", "paperplane.fill", "camera.fill", "gift.fill", "pawprint.fill",
        "sparkles", "moon.fill", "sun.max.fill", "drop.fill", "globe.asia.australia.fill",
        "puzzlepiece.fill", "wrench.and.screwdriver.fill", "chart.bar.fill", "scissors",
        "tshirt.fill", "bicycle", "tram.fill", "film.fill", "headphones", "mic.fill",
        "bubble.left.fill", "person.2.fill", "cloud.fill",
    ]

    /// 그릴 아이콘. 정해 둔 것이 없으면 **만든 시각**에서 늘 같은 하나를 뽑는다.
    ///
    /// ⚠️ 씨앗으로 `dragToken`(= persistentModelID)을 쓰지 않는다. 저장 전후로 바뀌고 기기마다
    ///    달라서, 같은 블록이 맥과 아이폰에서, 저장하기 전과 후에 다른 아이콘이 된다.
    ///    Swift 의 `hashValue` 도 안 쓴다 — 실행할 때마다 달라진다. 그래서 FNV-1a 로 직접 섞는다.
    var symbol: String {
        if let iconName, !iconName.isEmpty { return iconName }
        let ms = UInt64(max(0, createdAt.timeIntervalSince1970 * 1000))
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: ms.littleEndian) { bytes in
            for b in bytes { h ^= UInt64(b); h &*= 0x0000_0100_0000_01b3 }
        }
        return Self.symbolChoices[Int(h % UInt64(Self.symbolChoices.count))]
    }

    /// 지금 것과 다른 아이콘을 새로 뽑아 적는다.
    func shuffleSymbol() {
        let current = symbol
        iconName = Self.symbolChoices.filter { $0 != current }.randomElement() ?? current
    }
}
