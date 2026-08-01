import Foundation
import SwiftData

// 색상 헬퍼(displayColor / paletteColor / routineColorOptions)는 SwiftUI에 의존하므로
// Theme.swift(macOS 전용)로 분리했다. 이 파일은 순수 데이터 모델만 담아 iOS 타깃에도 공유 가능하다.

@Model
final class Routine {
    var name: String = ""
    var iconName: String = "calendar"
    var kindRaw: String = RoutineKind.fixed.rawValue
    var colorName: String = "blue"

    // For .fixed
    var dayMask: Int = 0
    var startHour: Double = 0
    var durationHours: Double = 1

    // For .quota
    var weeklyHours: Double = 0
    /// 쿼터 루틴의 하루 횟수(끼니·세션). 0 = 미설정. 회당 시간 계산에 사용.
    var sessionsPerDay: Int = 0

    var sortIndex: Int = 0
    var createdAt: Date = Date()

    // Planning fields
    var executionNotes: String = ""
    var premortemFailScenario: String = ""
    var premortemPrevention: String = ""

    init(name: String,
         iconName: String = "calendar",
         kind: RoutineKind,
         colorName: String = "blue",
         dayMask: Int = 0,
         startHour: Double = 0,
         durationHours: Double = 1,
         weeklyHours: Double = 0,
         sessionsPerDay: Int = 0,
         sortIndex: Int = 0)
    {
        self.name = name
        self.iconName = iconName
        self.kindRaw = kind.rawValue
        self.colorName = colorName
        self.dayMask = dayMask
        self.startHour = startHour
        self.durationHours = durationHours
        self.weeklyHours = weeklyHours
        self.sessionsPerDay = sessionsPerDay
        self.sortIndex = sortIndex
        self.createdAt = Date()
    }

    var kind: RoutineKind {
        get { RoutineKind(rawValue: kindRaw) ?? .fixed }
        set { kindRaw = newValue.rawValue }
    }

    var selectedDays: Set<DayOfWeek> {
        get { Set(DayOfWeek.allCases.filter { dayMask & (1 << $0.rawValue) != 0 }) }
        set { dayMask = newValue.reduce(0) { $0 | (1 << $1.rawValue) } }
    }

    var totalWeeklyHours: Double {
        switch kind {
        case .fixed:
            let count = (0..<7).filter { dayMask & (1 << $0) != 0 }.count
            return Double(count) * durationHours
        case .quota:
            return weeklyHours
        }
    }

    /// 쿼터 루틴의 하루 평균 시간 (주간 합계 ÷ 7).
    var dailyQuotaHours: Double { weeklyHours / 7 }

    /// 수면 루틴인가 — 타임라인에서 '수면 시간 숨기기'가 잘라낼 대상.
    /// 별도 플래그 대신 이름으로 판별해 기존 데이터도 설정 없이 그대로 동작한다.
    var isSleepRoutine: Bool {
        guard kind == .fixed else { return false }
        let n = name.lowercased().replacingOccurrences(of: " ", with: "")
        return ["수면", "잠", "취침", "sleep"].contains { n.contains($0) }
    }

    var scheduleDescription: String {
        switch kind {
        case .fixed:
            let days = DayOfWeek.allCases
                .filter { dayMask & (1 << $0.rawValue) != 0 }
                .map(\.shortLabel)
                .joined(separator: "·")
            let start = formatHour(startHour)
            let end = formatHour(startHour + durationHours)
            return days.isEmpty ? "요일 미지정" : "\(days) \(start)–\(end)"
        case .quota:
            var s = String(format: "주 %.1fh · 일 평균 ", weeklyHours) + formatDuration(dailyQuotaHours)
            if sessionsPerDay > 0 {
                s += " · 회당 약 " + formatDuration(dailyQuotaHours / Double(sessionsPerDay))
            }
            return s
        }
    }
}
