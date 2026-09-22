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
    /// 쿼터 루틴의 **회차별 기본 시작 시각** — "7,12.5,19" 꼴(시, 소수). nil 이면 하루 활동 구간에
    /// 고르게 나눈 계산값을 쓴다(맥 `Routine.defaultSessionStart`). 요일마다 옮긴 것(QuotaPlacement)이 이보다 먼저다.
    /// ⚠️ CloudKit 스키마가 늘어나는 필드다 — 맥·아이폰 양쪽에 같이 있어야 한다 (→ README).
    var sessionStartsRaw: String? = nil

    var sortIndex: Int = 0
    var createdAt: Date = Date()


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
        // PlanBlock과 같은 이유로 여기서 찍는다 (→ TodoSharing.swift).
        TodoSharing.stamp(self)
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
        return ["수면", "잠", "취침", "sleep", "bedtime", "nap"].contains { n.contains($0) }
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
            return days.isEmpty ? String(localized: "요일 미지정") : "\(days) \(start)–\(end)"
        case .quota:
            let weekly = String(format: "%.1f", weeklyHours)
            var s = String(localized: "주 \(weekly)h · 일 평균 \(formatDuration(dailyQuotaHours))")
            if sessionsPerDay > 0 {
                s += String(localized: " · 회당 약 \(formatDuration(dailyQuotaHours / Double(sessionsPerDay)))")
            }
            return s
        }
    }
}

// MARK: - 쿼터 회차의 기본 시각

extension Routine {
    /// 끼니가 고르게 놓이는 하루 활동 구간 (회차 가운데가 이 사이에 고르게 선다).
    static let quotaWindow: (start: Double, end: Double) = (7.5, 19.5)

    /// 회차 수 — 미설정(0)이면 하루 한 번으로 본다.
    var quotaPieces: Int { max(1, sessionsPerDay) }

    /// 한 회차의 길이.
    var sessionLength: Double { (weeklyHours / 7) / Double(quotaPieces) }

    /// 저장해 둔 회차별 시각. 비었거나 읽을 수 없는 칸은 빠진다(그 회차는 계산값을 쓴다).
    var storedSessionStarts: [Double] {
        (sessionStartsRaw ?? "").split(separator: ",").compactMap { Double($0) }
    }

    /// **고르게 나눈** 기본 시각 — 저장된 것이 없을 때 쓴다. 15분 격자에 붙인다
    /// (옮긴 뒤 다시 기본 자리로 끌어 돌아올 수 있게).
    static func evenSessionStart(index i: Int, pieces: Int, length each: Double) -> Double {
        let (lo, hi) = quotaWindow
        let center = pieces == 1 ? (lo + hi) / 2 : lo + (hi - lo) * Double(i) / Double(pieces - 1)
        let snapped = ((center - each / 2) / 0.25).rounded() * 0.25
        return min(max(snapped, 0), max(0, 24 - each))
    }

    /// i번째 회차의 기본 시작 시각. 저장해 둔 것이 있으면 그것, 없으면 고르게 나눈 값.
    /// 시간표(→ TimelineLayout)와 루틴 편집기가 **같은 값**을 본다 — 편집기에 뜬 시각이 곧 자 위의 시각이다.
    func defaultSessionStart(_ i: Int) -> Double {
        let each = sessionLength
        let stored = storedSessionStarts
        if i < stored.count { return min(max(stored[i], 0), max(0, 24 - each)) }
        return Self.evenSessionStart(index: i, pieces: quotaPieces, length: each)
    }

    /// 회차별 시각을 적는다. nil 이면 지워서 다시 고르게 나눈다.
    func setSessionStarts(_ starts: [Double]?) {
        guard let starts, !starts.isEmpty else { sessionStartsRaw = nil; return }
        sessionStartsRaw = starts.map { String(format: "%g", ($0 * 4).rounded() / 4) }.joined(separator: ",")
    }
}
