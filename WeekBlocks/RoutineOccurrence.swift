import Foundation
import SwiftData

/// 특정 주에 고정 루틴이 어느 요일에 배치되었는지를 저장한다.
/// 첫 주: dayMask + startHour 기반으로 자동 생성.
/// 이후 주: 직전 주의 배치를 그대로 복사.
@Model
final class RoutineOccurrence {
    var routineName: String = ""
    var dayRaw: Int = 0
    var weekStartDate: Date = Date.currentWeekStart

    /// 타임라인에서 이 요일만 따로 드래그해 옮긴 시작 시각(h). -1 = 미설정(루틴 기본 startHour 사용).
    var startHourOverride: Double = -1

    /// 이 주·요일에서만 이 고정 루틴을 숨겼는지. (occurrence를 지우면 reconcile이 되살리므로 플래그로 처리.)
    /// 루틴 편집에서 해당 요일을 껐다 켜면 occurrence가 새로 만들어져 다시 보인다.
    var hidden: Bool = false

    init(routineName: String, day: DayOfWeek, weekStartDate: Date) {
        self.routineName = routineName
        self.dayRaw = day.rawValue
        self.weekStartDate = weekStartDate
    }

    var day: DayOfWeek {
        get { DayOfWeek(rawValue: dayRaw) ?? .mon }
        set { dayRaw = newValue.rawValue }
    }
}

/// 유연 쿼터(식사 등) 블록을 특정 주·요일·회차에서 드래그해 옮긴 위치를 저장한다.
/// 저장이 없으면 타임라인이 기본 위치(활동 구간에 균등 분산)로 그린다.
@Model
final class QuotaPlacement {
    var routineName: String = ""
    var dayRaw: Int = 0
    var weekStartDate: Date = Date.currentWeekStart
    var sessionIndex: Int = 0
    var startHour: Double = 0

    /// 이 주·요일·회차의 끼니를 숨겼는지(타임라인에서 한 끼만 삭제).
    var hidden: Bool = false

    init(routineName: String, day: DayOfWeek, weekStartDate: Date, sessionIndex: Int, startHour: Double) {
        self.routineName = routineName
        self.dayRaw = day.rawValue
        self.weekStartDate = weekStartDate
        self.sessionIndex = sessionIndex
        self.startHour = startHour
    }

    var day: DayOfWeek {
        get { DayOfWeek(rawValue: dayRaw) ?? .mon }
        set { dayRaw = newValue.rawValue }
    }
}
