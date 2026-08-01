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

    // Review (populated after the day passes)
    var reviewStatusRaw: String? = nil
    var reviewNote: String? = nil
    var reviewedAt: Date? = nil

    // MARK: - 전파 계약
    //
    // 백로그 항목을 요일에 드롭하면 이 블록이 되고 항목은 삭제된다.
    // 그때 계약이 함께 넘어오지 않으면 대상·두 날짜·이미 보낸 시점 기록이 전부 사라진다.
    // 필드 구성과 의미는 BacklogItem과 같고, 접근자는 BroadcastContractHolder가 공용으로 제공한다.
    // CloudKit 라이트웨이트 마이그레이션을 위해 전부 기본값 또는 옵셔널이다.

    var needsBroadcast: Bool = false
    var deadline: Date? = nil
    var broadcastAudienceRaw: String = "decisionMaker"
    var broadcastRecipient: String = ""
    var handoffForm: String = ""
    var earliestDate: Date? = nil
    var latestDate: Date? = nil
    var broadcastConfidenceRaw: String = "medium"
    var openVariable: String = ""
    var variableResolveDate: Date? = nil
    var noSignalRuleAgreed: Bool = false
    var broadcastContractVerified: Bool = false
    var sentCheckpointsRaw: String = ""

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

// 전파 계약 접근자는 BroadcastContract.swift의 프로토콜 익스텐션이 제공한다
// (BacklogItem과 같은 구현을 쓴다).
extension PlanBlock: BroadcastContractHolder { }
