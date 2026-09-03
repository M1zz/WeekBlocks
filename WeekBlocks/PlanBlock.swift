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
