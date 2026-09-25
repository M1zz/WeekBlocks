import Foundation

enum DayOfWeek: Int, Codable, CaseIterable, Identifiable {
    case mon = 0, tue, wed, thu, fri, sat, sun
    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .mon: String(localized: "월", comment: "요일 한 글자")
        case .tue: String(localized: "화", comment: "요일 한 글자")
        case .wed: String(localized: "수", comment: "요일 한 글자")
        case .thu: String(localized: "목", comment: "요일 한 글자")
        case .fri: String(localized: "금", comment: "요일 한 글자")
        case .sat: String(localized: "토", comment: "요일 한 글자")
        case .sun: String(localized: "일", comment: "요일 한 글자")
        }
    }

    /// ⚠️ 짧은 이름에 '요일'을 붙여 만들지 않는다. 영어는 "Mon" + 무언가가 아니라
    ///    "Monday"라는 다른 낱말이라, 이어 붙이면 번역이 불가능해진다.
    var longLabel: String {
        switch self {
        case .mon: String(localized: "월요일")
        case .tue: String(localized: "화요일")
        case .wed: String(localized: "수요일")
        case .thu: String(localized: "목요일")
        case .fri: String(localized: "금요일")
        case .sat: String(localized: "토요일")
        case .sun: String(localized: "일요일")
        }
    }

    /// 그 날이 무슨 요일인가. 이 앱의 한 주는 월요일에서 시작한다.
    static func of(_ date: Date) -> DayOfWeek {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let weekday = cal.component(.weekday, from: date)   // 1=일 … 7=토
        return DayOfWeek(rawValue: (weekday + 5) % 7) ?? .mon
    }

    /// 오늘이 무슨 요일인가.
    static var today: DayOfWeek { of(Date()) }

    /// 화면에 세우는 차례. 일요일 시작이면 일요일이 맨 앞으로 온다 (→ WeekStartSetting).
    static func displayOrder(sundayFirst: Bool) -> [DayOfWeek] {
        sundayFirst ? [.sun] + allCases.dropLast() : allCases
    }

    /// 보이는 주(그 주 **월요일**로 부른다)에서 이 요일 칸의 기록이 **어느 ISO 주에 적혀 있는가.**
    ///
    /// 일요일 시작이면 맨 앞 일요일은 그 월요일의 전날이라, ISO로는 앞 주의 일요일이다.
    static func storedWeek(of day: DayOfWeek, shownWeek: Date, sundayFirst: Bool) -> Date {
        guard sundayFirst, day == .sun else { return shownWeek }
        return Calendar(identifier: .iso8601).date(byAdding: .day, value: -7, to: shownWeek) ?? shownWeek
    }

    /// `storedWeek`의 거꾸로 — 이 요일이 이 ISO 주에 적혀 있으면 화면에서는 어느 주에 서는가.
    static func shownWeek(of day: DayOfWeek, storedWeek: Date, sundayFirst: Bool) -> Date {
        guard sundayFirst, day == .sun else { return storedWeek }
        return Calendar(identifier: .iso8601).date(byAdding: .day, value: 7, to: storedWeek) ?? storedWeek
    }
}

/// **한 주를 무슨 요일부터 보여 줄까.**
///
/// ⚠️ 보여 주는 차례만 바뀐다. 기록은 언제나 ISO 주(월요일 시작)에 적는다 — 아이폰 '욕망의 무지개'가
///    같은 기록을 iCloud로 함께 읽고, 이미 적힌 몇 달치 기록도 모두 월요일 주에 붙어 있다.
///    그래서 일요일 시작 화면의 맨 앞 일요일은 **앞 ISO 주의 일요일**을 읽고 쓴다 (→ DayOfWeek.storedWeek).
enum WeekStartSetting {
    static let key = "weekStartsOnSunday"
    /// 화면 밖(시트·모델 도우미)에서 읽을 때. 화면은 `@AppStorage(WeekStartSetting.key)`로 읽어 바로 따라 바뀐다.
    static var sundayFirst: Bool { UserDefaults.standard.bool(forKey: key) }
}

enum TimeBand: String, Codable, CaseIterable, Identifiable {
    case morning = "morning"
    case afternoon = "afternoon"
    case evening = "evening"
    case night = "night"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: String(localized: "아침 (06–12시)")
        case .afternoon: String(localized: "오후 (12–18시)")
        case .evening: String(localized: "저녁 (18–23시)")
        case .night: String(localized: "심야 (23시 이후)")
        }
    }

    var shortLabel: String {
        switch self {
        case .morning: String(localized: "아침")
        case .afternoon: String(localized: "오후")
        case .evening: String(localized: "저녁")
        case .night: String(localized: "심야")
        }
    }

    /// 시각을 안 정해 둔 것을 정하기로 했을 때, 처음 세워 둘 시각.
    /// 시간대 한가운데가 아니라 **사람이 실제로 그 시간대에 일을 시작하는 때**로 둔다.
    var defaultStartHour: Double {
        switch self {
        case .morning: 9
        case .afternoon: 14
        case .evening: 19
        case .night: 23
        }
    }

    /// 그 시각이 속한 시간대. 시각을 옮기면 시간대도 따라와야 칩의 부제가 거짓말을 하지 않는다.
    static func containing(_ startHour: Double) -> TimeBand {
        switch startHour {
        case 6..<12: return .morning
        case 12..<18: return .afternoon
        case 18..<23: return .evening
        default: return .night
        }
    }
}

enum RoutineKind: String, Codable, CaseIterable, Identifiable {
    case fixed   // specific days/times each week
    case quota   // weekly hour total, time flexible
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: String(localized: "고정 시간대")
        case .quota: String(localized: "주간 쿼터 (시간 유연)")
        }
    }
}

enum ReviewStatus: String, Codable, CaseIterable, Identifiable {
    case done = "done"
    case partial = "partial"
    case skipped = "skipped"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .done: String(localized: "달성")
        case .partial: String(localized: "부분 달성")
        case .skipped: String(localized: "건너뜀")
        }
    }

    var systemImage: String {
        switch self {
        case .done: "checkmark.circle.fill"
        case .partial: "circle.lefthalf.filled"
        case .skipped: "xmark.circle.fill"
        }
    }
}

extension Date {
    /// Monday 00:00 of the week containing this date (ISO 8601 calendar).
    static var currentWeekStart: Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return cal.date(from: comps) ?? Date()
    }

    func weekStart() -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: comps) ?? self
    }

    /// 이 날짜가 **화면에서** 서는 주 — 그 주 월요일로 부른다.
    /// 일요일 시작이면 일요일은 다음 날(월요일)의 주 맨 앞에 선다.
    func shownWeekStart(sundayFirst: Bool) -> Date {
        guard sundayFirst, DayOfWeek.of(self) == .sun else { return weekStart() }
        return (Calendar(identifier: .iso8601).date(byAdding: .day, value: 1, to: self) ?? self).weekStart()
    }
}

/// Format an hour like 7.5 -> "07:30"
func formatHour(_ value: Double) -> String {
    let total = Int((value * 60).rounded())
    let h = (total / 60) % 24
    let m = total % 60
    return String(format: "%02d:%02d", h, m)
}

/// 소요시간(단위 h) → 사람이 읽는 표기. 예: 2.5 → "2시간 30분", 0.83 → "50분", 3 → "3시간"
///
/// ⚠️ "\(h)시간" + " " + "\(m)분"으로 잇지 않는다. 언어마다 사이에 무엇이 오는지가
///    다르므로, 세 경우를 각각 통째로 번역할 수 있게 둔다.
func formatDuration(_ hours: Double) -> String {
    let total = Int((hours * 60).rounded())
    let h = total / 60
    let m = total % 60
    if h > 0 && m > 0 { return String(localized: "\(h)시간 \(m)분") }
    if h > 0 { return String(localized: "\(h)시간") }
    return String(localized: "\(m)분")
}
