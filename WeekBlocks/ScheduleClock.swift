//
//  ScheduleClock.swift
//  무지개 공방
//
//  "지금 무엇을 하고 있고, 거기 얼마 남았는가."
//
//  아무 버튼도 누르지 않아도 답이 나와야 한다. 수면이 23:00–07:00으로 적혀 있고
//  지금이 23:29라면, 타이머는 이미 7시간 31분을 세고 있는 중이어야 한다 —
//  타이머를 켠 시각이 아니라 **일정에 적힌 시각**이 기준이다.
//
//  그래서 이 파일은 시간을 재지 않는다. 이미 그려져 있는 하루(→ TimelineLayout.segments)를
//  그대로 읽어, 지금이 어느 조각 안인지 답할 뿐이다. 화면에 보이는 것과 어긋날 수 없다.
//

import Foundation

/// 하루에 그려진 한 조각을 **절대 시각**으로 옮긴 것.
/// 자정을 넘기는 수면 때문에 0–24 소수 시간으로는 "지금 그 안인가"를 물을 수 없다.
struct ScheduleSlot: Identifiable, Equatable {
    /// 타이머가 쓰는 열쇠와 같다 (→ TaskTimer). 같은 일을 두 자리에서 같은 이름으로 부른다.
    let id: String
    let title: String
    let iconName: String
    let colorName: String?
    /// 어느 요일 칸에 그려진 조각인가. 같은 이름의 루틴이 이레 내내 서 있으므로,
    /// 요일까지 알아야 "그 칸의 그것"을 가리킬 수 있다.
    let day: DayOfWeek
    /// 그 요일 칸에서의 시작 시각(0–24). 자정을 넘겨 두 조각으로 그려진 잠을
    /// 앞 조각 하나에만 붙이기 위해 쓴다.
    let startHourInDay: Double
    let start: Date
    let end: Date
    /// 시간이 유연한 것(끼니 등) — 그 자리는 앱이 임의로 놓은 것이라 단정을 조금 낮춘다.
    let isFlexible: Bool

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var hours: Double { duration / 3600 }

    func contains(_ date: Date) -> Bool { date >= start && date < end }
    func remaining(at date: Date) -> TimeInterval { end.timeIntervalSince(date) }
    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }
}

enum ScheduleClock {

    /// 지금을 둘러싼 사흘(어제·오늘·내일)의 조각들.
    ///
    /// **어제까지 보는 이유**: 수면 23:00+8h는 어제 줄에서 시작해 오늘 07:00에 끝난다.
    /// 오늘만 보면 새벽 두 시에 "지금 아무것도 없다"고 답하게 된다.
    /// **내일까지 보는 이유**: '다음 일정'은 자정을 넘어 있을 수 있다.
    static func slots(routines: [Routine],
                      blocks: [PlanBlock],
                      occurrences: [RoutineOccurrence],
                      placements: [QuotaPlacement],
                      around now: Date = Date()) -> [ScheduleSlot] {
        let cal = Calendar.current
        return (-1...1).flatMap { offset -> [ScheduleSlot] in
            guard let date = cal.date(byAdding: .day, value: offset, to: now) else { return [] }
            return slots(on: date, routines: routines, blocks: blocks,
                         occurrences: occurrences, placements: placements)
        }
    }

    /// 지금 하고 있는 것. 겹쳐 있으면 **가장 짧은 것**을 고른다 —
    /// 09:00–18:00 회사 안의 13:00 식사라면, 지금 하고 있는 일은 식사다.
    static func current(_ slots: [ScheduleSlot], at now: Date = Date()) -> ScheduleSlot? {
        slots.filter { $0.contains(now) }
            .min { $0.duration < $1.duration }
    }

    /// 다음에 올 것. 지금 하는 것이 없을 때 "그럼 언제부터"에 답한다.
    static func next(_ slots: [ScheduleSlot], at now: Date = Date()) -> ScheduleSlot? {
        slots.filter { $0.start > now }.min { $0.start < $1.start }
    }

    /// 그 날 하루에 그려지는 조각들. 요일 칸·시간 자가 그리는 것과 같은 계산을 쓴다.
    static func slots(on date: Date,
                      routines: [Routine],
                      blocks: [PlanBlock],
                      occurrences: [RoutineOccurrence],
                      placements: [QuotaPlacement]) -> [ScheduleSlot] {
        let iso = Calendar(identifier: .iso8601)
        let day = DayOfWeek.of(date)
        let week = date.weekStart()

        let occs = occurrences.filter {
            $0.day == day && iso.isDate($0.weekStartDate, inSameDayAs: week)
        }
        let hiddenNames = Set(occs.filter(\.hidden).map(\.routineName))
        var override: [String: Double] = [:]
        for o in occs where o.startHourOverride >= 0 { override[o.routineName] = o.startHourOverride }

        let places = placements.filter {
            $0.day == day && iso.isDate($0.weekStartDate, inSameDayAs: week)
        }
        var placeMap: [String: [Int: Double]] = [:]
        for p in places { placeMap[p.routineName, default: [:]][p.sessionIndex] = p.startHour }
        var quotaHidden: [String: Set<Int>] = [:]
        for p in places where p.hidden { quotaHidden[p.routineName, default: []].insert(p.sessionIndex) }

        let fixed = routines.filter {
            $0.kind == .fixed && $0.selectedDays.contains(day) && !hiddenNames.contains($0.name)
        }
        let quota = routines.filter { $0.kind == .quota }
        let dayBlocks = blocks.filter {
            $0.day == day && iso.isDate($0.weekStartDate, inSameDayAs: week)
        }

        let segs = TimelineLayout.segments(routines: fixed, blocks: dayBlocks, quota: quota,
                                           routineStartOverride: override,
                                           quotaPlacement: placeMap,
                                           quotaHidden: quotaHidden)

        let midnight = Calendar.current.startOfDay(for: date)
        var seen = Set<String>()
        var result: [ScheduleSlot] = []

        for seg in segs where !seg.isGhost {
            guard let info = identity(of: seg, fixed: fixed, quota: quota) else { continue }
            // 자정을 넘겨 두 조각으로 잘린 것은 하나로 되돌린다 — 사람이 하는 일은 하나다.
            let key = "\(info.token)@\(seg.logicalStart)"
            guard seen.insert(key).inserted else { continue }
            let start = midnight.addingTimeInterval(seg.logicalStart * 3600)
            result.append(ScheduleSlot(id: info.token,
                                       title: seg.title,
                                       iconName: info.iconName,
                                       colorName: info.colorName,
                                       day: day,
                                       startHourInDay: seg.logicalStart,
                                       start: start,
                                       end: start.addingTimeInterval(seg.logicalDuration * 3600),
                                       isFlexible: seg.isFlexible))
        }
        return result
    }

    /// 조각이 가리키는 원본에서 열쇠·아이콘·색을 꺼낸다.
    private static func identity(of seg: TimeSegment, fixed: [Routine], quota: [Routine])
    -> (token: String, iconName: String, colorName: String?)? {
        switch seg.source {
        case .planBlock(let blk):
            return (blk.dragToken, "square.stack.3d.up", nil)
        case .fixedRoutine(let name):
            guard let r = fixed.first(where: { $0.name == name }) else { return nil }
            return (TaskTimer.token(for: r), r.iconName, r.colorName)
        case .quotaSession(let name, let index):
            guard let r = quota.first(where: { $0.name == name }) else { return nil }
            return ("\(TaskTimer.token(for: r)):\(index)", r.iconName, r.colorName)
        case .none:
            return nil
        }
    }
}
