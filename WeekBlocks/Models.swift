import Foundation

enum DayOfWeek: Int, Codable, CaseIterable, Identifiable {
    case mon = 0, tue, wed, thu, fri, sat, sun
    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .mon: "월"; case .tue: "화"; case .wed: "수"
        case .thu: "목"; case .fri: "금"; case .sat: "토"
        case .sun: "일"
        }
    }
    var longLabel: String { shortLabel + "요일" }
}

enum TimeBand: String, Codable, CaseIterable, Identifiable {
    case morning = "morning"
    case afternoon = "afternoon"
    case evening = "evening"
    case night = "night"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: "아침 (06–12시)"
        case .afternoon: "오후 (12–18시)"
        case .evening: "저녁 (18–23시)"
        case .night: "심야 (23시 이후)"
        }
    }

    var shortLabel: String {
        switch self {
        case .morning: "아침"
        case .afternoon: "오후"
        case .evening: "저녁"
        case .night: "심야"
        }
    }
}

enum RoutineKind: String, Codable, CaseIterable, Identifiable {
    case fixed   // specific days/times each week
    case quota   // weekly hour total, time flexible
    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: "고정 시간대"
        case .quota: "주간 쿼터 (시간 유연)"
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
        case .done: "달성"
        case .partial: "부분 달성"
        case .skipped: "건너뜀"
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
}

/// Format an hour like 7.5 -> "07:30"
func formatHour(_ value: Double) -> String {
    let total = Int((value * 60).rounded())
    let h = (total / 60) % 24
    let m = total % 60
    return String(format: "%02d:%02d", h, m)
}

/// 소요시간(단위 h) → 사람이 읽는 한국어 표기. 예: 2.5 → "2시간 30분", 0.83 → "50분", 3 → "3시간"
func formatDuration(_ hours: Double) -> String {
    let total = Int((hours * 60).rounded())
    let h = total / 60
    let m = total % 60
    if h > 0 && m > 0 { return "\(h)시간 \(m)분" }
    if h > 0 { return "\(h)시간" }
    return "\(m)분"
}
