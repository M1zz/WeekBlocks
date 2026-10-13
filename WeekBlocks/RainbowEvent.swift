//
//  RainbowEvent.swift
//  욕망의 무지개 · 무지개 공방 (두 앱이 같은 파일을 쓴다)
//
//  **무지개 일정을 맥과 아이폰이 함께 쓰는 자리.**
//
//  아이폰의 무지개 일정(`Event`)은 이 기기에만 있는 스토어에 산다. 맥에는 그걸 읽을 길이 없어서,
//  아이폰에서 적은 일정과 할 일 기한이 맥에는 하나도 안 보였다.
//
//  그렇다고 `Event`를 통째로 CloudKit으로 옮기지 않는다. 그 스토어는 iCloud 사본이 없는 유일본이고,
//  옮기다 하나라도 어긋나면 되돌릴 곳이 없다. 대신 **함께 쓰는 사본**을 공용 스토어에 하나 더 둔다.
//   · 아이폰: `Event`가 원본 그대로 남고, 다리(→ RainbowBridge.swift)가 두 쪽을 맞춘다.
//   · 맥: 이 모델만 읽고 쓴다.
//
//  ⚠️ **지우지 않는다 — `deletedAt`을 찍는다.** 공용 스토어가 비어서 내려오는 일(미러 다시 받기,
//     다른 iCloud 계정)이 생겨도 그걸 '지웠다'로 읽어 아이폰 원본을 지우면 안 된다. 사람이 지운 것은
//     표가 남고, 표 없이 사라진 것은 아이폰 원본에서 다시 세운다.
//  ⚠️ 칸 이름 · 타입 · 기본값은 두 앱에서 **글자 하나까지 같아야 한다.** CloudKit 레코드 타입
//     `CD_RainbowEvent` 하나를 두 앱이 함께 쓴다. 출시 전에 Production 스키마 배포가 필요하다.
//

import Foundation
import SwiftData

@Model
final class RainbowEvent {
    /// 두 기기가 같은 일정을 부르는 이름. 만들 때 한 번 정하고 안 바꾼다.
    var uuid: String = UUID().uuidString
    var title: String = ""
    /// 시작일 (그날 0시).
    var startDate: Date = Date()
    /// 종료일 (그날 0시). `isInfinite`면 보지 않는다.
    var endDate: Date = Date()
    /// "#RRGGBB".
    var colorHex: String = "#FF3B30"
    var hoursPerDay: Double = 2.0
    /// 하는 요일 `[Int]` JSON (1=일 … 7=토). nil이면 매일.
    var selectedWeekdaysData: Data? = nil
    /// 5주 × 7일 = 35칸 `[Bool]` JSON. 있으면 요일보다 먼저 본다.
    var weeklyPatternData: Data? = nil
    /// **몇 주마다 하는가** — 1 = 매주, 2 = 격주. 시작일부터 7일씩 세어 그 주에만 요일이 선다.
    /// 35일 패턴은 5주마다 처음으로 돌아가 격주가 어긋난다 (1·3·5주 다음이 또 1주). 그래서 따로 둔다.
    /// 패턴이 있으면 보지 않는다. 기간(옅은 줄)은 그대로 이어지고 하는 날만 성기게 진해진다.
    var repeatWeeks: Int = 1
    /// 회차 `[RainbowSession]` JSON. 있으면 **이 날들만** 하는 날이다 — 요일 · 반복 · 패턴보다 먼저 본다.
    /// 자격증 과정처럼 회차마다 시간과 내용이 다른 일. 기간(옅은 줄)은 첫 회차부터 마지막 회차까지.
    var sessionsData: Data? = nil
    /// "high" · "medium" · "low".
    var importanceRaw: String = "medium"
    var isInfinite: Bool = false
    /// 빼 둔 날 `[Date]` JSON.
    var excludedDatesData: Data? = nil
    /// 이어진 할 일(BacklogItem)의 dragToken — 할 일의 기한이 이 일정이다.
    var todoToken: String? = nil
    var createdAt: Date = Date()
    /// 마지막으로 고친 때. 두 기기가 같은 일정을 따로 고쳤을 때 나중 것을 고른다.
    var updatedAt: Date = Date()
    /// 사람이 지웠다. 행은 남겨 둔다 (→ 파일 머리 주석).
    var deletedAt: Date? = nil
    /// 처음 만든 기기의 설치 id (→ TodoSharing.installID).
    var originInstallID: String = ""

    init(uuid: String = UUID().uuidString, title: String = "") {
        self.uuid = uuid
        self.title = title
    }

    /// '매주' · '격주' · 'N주마다' — 두 앱의 편집기와 정보 줄이 같은 말을 쓴다.
    static func repeatLabel(_ weeks: Int) -> String {
        switch weeks {
        case ...1: String(localized: "매주")
        case 2: String(localized: "격주")
        default: String(localized: "\(weeks)주마다")
        }
    }

    /// 사람이 지운 표가 있다. (`isDeleted`는 SwiftData가 쓰는 이름이라 피한다.)
    var isRemoved: Bool { deletedAt != nil }

    var selectedWeekdays: [Int]? {
        get { selectedWeekdaysData.flatMap { try? JSONDecoder().decode([Int].self, from: $0) } }
        set { selectedWeekdaysData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var weeklyPattern: [Bool]? {
        get {
            guard let data = weeklyPatternData,
                  let p = try? JSONDecoder().decode([Bool].self, from: data), p.count == 35 else { return nil }
            return p
        }
        set {
            weeklyPatternData = (newValue?.count == 35) ? newValue.flatMap { try? JSONEncoder().encode($0) } : nil
        }
    }

    /// 회차들, 날짜 차례로. 비어 있으면 회차 없는 일정이다.
    var sessions: [RainbowSession] {
        get { RainbowSession.decode(sessionsData) }
        set { sessionsData = RainbowSession.encode(newValue) }
    }

    /// 이날의 회차.
    func session(on date: Date) -> RainbowSession? {
        let d = Calendar.current.startOfDay(for: date)
        return sessions.first { Self.day($0.date) == d }
    }

    /// 이 블록이 이 일정의 회차를 옮겨 적은 것인가 — 회차 날에 선, 일정 이름으로 시작하는 블록.
    /// 무지개는 둘 중 하나만 센다 (같은 일이 두 칸이 되지 않게).
    func carriesSession(blockTitle: String, on date: Date) -> Bool {
        sessionsData != nil && blockTitle.hasPrefix(title) && session(on: date) != nil
    }

    var excludedDates: Set<Date> {
        get {
            guard let data = excludedDatesData,
                  let dates = try? JSONDecoder().decode([Date].self, from: data) else { return [] }
            return Set(dates.map(RainbowEvent.day))
        }
        set {
            let days = newValue.map { Calendar.current.startOfDay(for: $0) }.sorted()
            excludedDatesData = try? JSONEncoder().encode(days)
        }
    }

    /// **적은 기기의 0시를 이 기기의 그날 0시로** 읽는다 — 가장 가까운 0시.
    ///
    /// 날짜는 적은 기기의 시간대로 0시가 되어 저장된다. 시간대가 다른 기기가 그 값을 그대로
    /// startOfDay에 넣으면 전날로 읽혀, 일정이 하루 당겨졌다. 저장 형식은 두 앱·옛 행과 같게 두고
    /// 읽을 때만 맞춘다. (시간대 차이가 12시간을 넘으면 여전히 하루 어긋날 수 있다)
    static func day(_ d: Date) -> Date {
        Calendar.current.startOfDay(for: d.addingTimeInterval(12 * 3600))
    }

    /// 무한 반복이면 시작일부터 365일 (아이폰 `Event.effectiveEndDate`와 같다).
    var effectiveEndDate: Date {
        isInfinite ? (Calendar.current.date(byAdding: .day, value: 365, to: startDate) ?? endDate) : endDate
    }

    /// 기간 안인가 — 시작일부터 종료일까지, 손으로 뺀 날만 빼고.
    func spans(_ date: Date) -> Bool {
        let d = Calendar.current.startOfDay(for: date)
        guard d >= Self.day(startDate), d <= Self.day(effectiveEndDate) else { return false }
        return !excludedDates.contains(d)
    }

    /// 이날 실제로 하는가 — 35일 패턴(없으면 요일 · N주마다) → 뺀 날 차례 (아이폰 `Event.occursOn`과 같다).
    func occurs(on date: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: date)
        let first = Self.day(startDate)
        guard d >= first, d <= Self.day(effectiveEndDate) else { return false }
        if sessionsData != nil, !sessions.isEmpty {
            return session(on: d) != nil && !excludedDates.contains(d)
        }
        if let pattern = weeklyPattern {
            let since = cal.dateComponents([.day], from: first, to: d).day ?? 0
            let i = since % 35
            if i >= 0, i < 35, !pattern[i] { return false }
        } else {
            if let days = selectedWeekdays, !days.isEmpty, !days.contains(cal.component(.weekday, from: d)) {
                return false
            }
            if repeatWeeks > 1 {
                let since = cal.dateComponents([.day], from: first, to: d).day ?? 0
                if (since / 7) % repeatWeeks != 0 { return false }
            }
        }
        return !excludedDates.contains(d)
    }
}

/// **장기 플랜의 한 회차** — 그날 · 몇 시간 · 이름 · 메모. 두 앱이 같은 꼴로 읽고 쓴다.
///
/// ⚠️ 칸을 늘릴 때는 옵셔널처럼 읽는다(`decodeIfPresent`). 옛 버전이 쓴 JSON에는 새 칸이 없다.
struct RainbowSession: Codable, Hashable, Identifiable {
    var id: String = UUID().uuidString
    /// 그날 0시 (적은 기기의). 읽을 때는 `RainbowEvent.day`로 이 기기의 그날에 맞춘다.
    var date: Date
    var hours: Double = 1
    /// "1세션"처럼 회차의 이름. 비면 "N회차".
    var title: String = ""
    var note: String = ""
    /// 맥이 이 회차를 계획 블록으로 옮겨 적었다. 다시 만들지 않는다 — 블록을 지웠으면 지운 뜻이다.
    var blockMade: Bool = false

    init(date: Date, hours: Double = 1, title: String = "", note: String = "") {
        self.date = date
        self.hours = hours
        self.title = title
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        date = try c.decode(Date.self, forKey: .date)
        hours = try c.decodeIfPresent(Double.self, forKey: .hours) ?? 1
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        blockMade = try c.decodeIfPresent(Bool.self, forKey: .blockMade) ?? false
    }

    /// 이름이 비었으면 "N회차" (N은 1부터).
    func displayTitle(index: Int) -> String {
        let t = title.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? String(localized: "\(index + 1)회차") : t
    }

    static func decode(_ data: Data?) -> [RainbowSession] {
        guard let data, let list = try? JSONDecoder().decode([RainbowSession].self, from: data) else { return [] }
        return list.sorted { $0.date < $1.date }
    }

    static func encode(_ list: [RainbowSession]) -> Data? {
        list.isEmpty ? nil : try? JSONEncoder().encode(list.sorted { $0.date < $1.date })
    }
}
