import SwiftUI

// MARK: - 요일별 하루 24시간 타임라인
//
// 고정 루틴은 정해진 시각 그대로 그린다(자정을 넘기면 22~24 / 0~6 처럼 나눠서).
// 계획 블록은 정확한 시각이 없으므로 시간대 시작 근처의 빈 구간에 통째로,
// 루틴·다른 계획과 겹치지 않게 채운다. 남는 구간 = 자유 시간.

/// 세그먼트의 원본 — 드래그로 옮길 때 어느 모델의 시작 시각을 바꿔야 하는지 식별.
enum SegmentSource {
    case none
    case fixedRoutine(name: String)            // 위치는 RoutineOccurrence.startHourOverride 에 저장
    case planBlock(PlanBlock)                  // 위치는 PlanBlock.startHour 에 저장(자유·루틴 안 공용)
    case quotaSession(name: String, index: Int) // 위치는 QuotaPlacement 에 저장

    var isQuota: Bool {
        if case .quotaSession = self { return true }
        return false
    }
}

/// 타임라인에 실제로 그릴 시간 범위. 기본은 하루 전체(0–24).
/// 수면을 숨기면 양끝의 수면 시간을 잘라내 남은 시간이 더 넓게 그려진다.
struct HourWindow: Equatable {
    var start: Double = 0
    var end: Double = 24

    static let full = HourWindow()

    var span: Double { max(1, end - start) }
    var isFullDay: Bool { start <= 0 && end >= 24 }

    /// 시각 → 가로 위치.
    func x(_ hour: Double, width: CGFloat) -> CGFloat {
        CGFloat((hour - start) / span) * width
    }

    /// 가로 위치 → 시각. `x(_:width:)`의 역이다.
    /// 떨어뜨린 자리를 30분 단위로 맞춘다 — 픽셀 하나까지 지키게 하면 손이 떨린다.
    func hour(atX x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return start }
        let raw = start + Double(x / width) * span
        let snapped = (raw * 2).rounded() / 2
        return min(max(snapped, start), end)
    }

    /// 창 밖으로 나간 부분을 잘라낸다. 완전히 벗어나면 nil.
    func clamp(_ s: Double, _ e: Double) -> (start: Double, end: Double)? {
        let cs = max(s, start), ce = min(e, end)
        return ce - cs > 0.0001 ? (cs, ce) : nil
    }

    /// 축에 숫자를 찍을 시각들 — 창의 양끝 + 그 사이 3시간 배수.
    var axisHours: [Int] {
        let lo = Int(start.rounded(.up)), hi = Int(end.rounded(.down))
        var hours = [lo]
        hours += stride(from: lo, through: hi, by: 1).filter { $0 % 3 == 0 && $0 != lo && $0 != hi }
        if hi != lo { hours.append(hi) }
        return hours
    }

    /// 세로 격자를 그릴 시각들 (창 안쪽 정시).
    var gridHours: [Int] {
        let lo = Int(start.rounded(.down)) + 1, hi = Int(end.rounded(.up)) - 1
        guard lo <= hi else { return [] }
        return Array(lo...hi)
    }
}

struct TimeSegment: Identifiable {
    let id: String                 // 재계산해도 같은 출처면 같은 id (드래그 중 안정성)
    let start: Double      // 0...24
    let end: Double
    let color: Color
    let title: String
    let isRoutine: Bool
    var isFlexible: Bool = false   // 주간 쿼터(시간 유연) → 점선·반투명
    var isNested: Bool = false     // 루틴 시간 안의 일정 → 루틴 위에 겹쳐(인셋) 표시
    var source: SegmentSource = .none
    var logicalStart: Double = 0   // 자정을 넘겨 나뉘어도 원본의 '진짜' 시작 시각(드래그 기준)
    var logicalDuration: Double = 0
    var isGhost: Bool = false       // 삭제(숨김)된 블록 — 흐릿하게 그려 '되살리기'만 가능, 시간엔 영향 없음
}

enum TimelineLayout {
    /// 하루(0~24h)에 대한 색칠 구간 목록을 계산.
    /// - routineStartOverride: 이 요일만 따로 옮긴 고정 루틴 시작 시각(이름 → 시각).
    /// - quotaPlacement: 이 요일에서 옮긴 식사 등 유연 블록 위치(이름 → [회차: 시각]).
    static func segments(routines: [Routine], blocks: [PlanBlock], quota: [Routine] = [],
                         routineStartOverride: [String: Double] = [:],
                         quotaPlacement: [String: [Int: Double]] = [:],
                         quotaHidden: [String: Set<Int>] = [:],
                         hiddenRoutines: [Routine] = []) -> [TimeSegment] {
        var segs: [TimeSegment] = []
        var occupied: [(Double, Double)] = []

        func resolvedStart(_ r: Routine) -> Double { routineStartOverride[r.name] ?? r.startHour }

        // 1) 고정 루틴 — 정해진 시각(요일별 override 우선) 그대로. 자정을 넘기면 [s,24] / [0,e-24] 로 나눠 그린다.
        //    (예: 수면 22:00+8h → 22~24 와 0~6)
        for r in routines.sorted(by: { resolvedStart($0) < resolvedStart($1) }) {
            let start = resolvedStart(r)
            var piece = 0
            for (a, b) in splitAtMidnight(start, start + r.durationHours) {
                segs.append(TimeSegment(id: "routine:\(r.name):\(piece)", start: a, end: b,
                                        color: r.displayColor, title: r.name, isRoutine: true,
                                        source: .fixedRoutine(name: r.name),
                                        logicalStart: start, logicalDuration: r.durationHours))
                occupied.append((a, b)); piece += 1
            }
        }

        // 1.5) 숨긴 고정 루틴 — 유령 블록으로 그 자리에 흐릿하게(시간엔 영향 없음, 되살리기용).
        for r in hiddenRoutines {
            let start = resolvedStart(r)
            for (a, b) in splitAtMidnight(start, start + r.durationHours) {
                segs.append(TimeSegment(id: "ghostroutine:\(r.name):\(a)", start: a, end: b,
                                        color: r.displayColor, title: r.name, isRoutine: true,
                                        source: .fixedRoutine(name: r.name),
                                        logicalStart: start, logicalDuration: r.durationHours, isGhost: true))
            }
        }

        var free = subtract([(0, 24)], occupied)
        func place(desired: Double, _ dur: Double) -> (Double, Double)? {
            let d = min(max(dur, 0), 24)
            guard d > 0 else { return nil }
            var best: (dist: Double, start: Double)? = nil
            for slot in free where slot.1 - slot.0 >= d - 1e-9 {
                let cs = min(max(desired, slot.0), slot.1 - d)
                let dist = abs(cs - desired)
                if best == nil || dist < best!.dist { best = (dist, cs) }
            }
            guard let b = best else { return nil }
            free = subtract(free, [(b.start, b.start + d)])
            return (b.start, b.start + d)
        }

        let freeBlocks = blocks.filter { !$0.withinRoutine }

        // 2a) 시각이 지정된(드래그된) 계획 블록 — 그 자리에 그대로 둔다(겹쳐도 됨).
        for blk in freeBlocks where blk.startHour >= 0 {
            let color: Color = blk.concreteVerified ? .accentColor : .orange
            let s = blk.startHour
            var piece = 0
            for (a, b) in splitAtMidnight(s, s + blk.durationHours) {
                segs.append(TimeSegment(id: "block:\(blockID(blk)):\(piece)", start: a, end: b,
                                        color: color, title: blk.title, isRoutine: false,
                                        source: .planBlock(blk), logicalStart: s, logicalDuration: blk.durationHours))
                free = subtract(free, [(a, b)]); piece += 1
            }
        }

        // 2b) 시각 미지정 계획 블록 — 시간대 시작 근처 빈 구간에 통째로(겹치지 않게) 자동 배치.
        let bandStart: [TimeBand: Double] = [.morning: 6, .afternoon: 12, .evening: 18, .night: 23]
        for band in [TimeBand.morning, .afternoon, .evening, .night] {
            for blk in freeBlocks.filter({ $0.startHour < 0 && $0.timeBand == band }).sorted(by: { $0.durationHours > $1.durationHours }) {
                let color: Color = blk.concreteVerified ? .accentColor : .orange
                if let (s, e) = place(desired: bandStart[band] ?? 12, blk.durationHours) {
                    segs.append(TimeSegment(id: "block:\(blockID(blk)):0", start: s, end: e,
                                            color: color, title: blk.title, isRoutine: false,
                                            source: .planBlock(blk), logicalStart: s, logicalDuration: blk.durationHours))
                }
            }
        }

        // 3) 주간 쿼터(시간 유연) — 끼니/세션 수만큼 하루 활동 구간(아침~저녁)에 분산.
        //    저장된 위치(드래그)가 있으면 그 자리에, 없으면 기본 위치에. 회사 등 다른 블록과 겹쳐도 되며,
        //    겹친 시간은 자유 시간을 깎지 않는다 — 남은 시간 계산은 구간 합집합으로 처리.
        let winStart = 7.5, winEnd = 19.5   // 끼니가 놓이는 하루 활동 구간
        for q in quota where q.weeklyHours > 0 {
            let pieces = max(1, q.sessionsPerDay)
            let each = (q.weeklyHours / 7) / Double(pieces)
            guard each > 0.05 else { continue }
            let hiddenSessions = quotaHidden[q.name] ?? []
            for i in 0..<pieces {
                let center = pieces == 1
                    ? (winStart + winEnd) / 2
                    : winStart + (winEnd - winStart) * Double(i) / Double(pieces - 1)
                // 기본 위치도 드래그 격자(15분)에 맞춰, 옮긴 뒤 다시 기본 자리로 드래그해 돌아올 수 있게 한다.
                let snappedDefault = ((center - each / 2) / 0.25).rounded() * 0.25
                let defaultStart = min(max(snappedDefault, 0), 24 - each)
                let s = min(max(quotaPlacement[q.name]?[i] ?? defaultStart, 0), 24 - each)
                // 숨긴 끼니는 유령 블록으로(시간엔 영향 없음, 되살리기용).
                segs.append(TimeSegment(id: "quota:\(q.name):\(i)", start: s, end: s + each,
                                        color: q.displayColor, title: q.name, isRoutine: false,
                                        isFlexible: true, source: .quotaSession(name: q.name, index: i),
                                        logicalStart: s, logicalDuration: each, isGhost: hiddenSessions.contains(i)))
            }
        }

        // 4) 루틴 안 일정 — 정확한 시각에 루틴 위로 겹쳐(인셋) 그린다. 빈 구간/자유 시간엔 영향 없음.
        for blk in blocks where blk.withinRoutine {
            let start = blk.startHour >= 0 ? blk.startHour : 9
            var piece = 0
            for (a, b) in splitAtMidnight(start, start + blk.durationHours) {
                segs.append(TimeSegment(id: "nested:\(blockID(blk)):\(piece)", start: a, end: b,
                                        color: .accentColor, title: blk.title, isRoutine: false,
                                        isNested: true, source: .planBlock(blk),
                                        logicalStart: start, logicalDuration: blk.durationHours))
                piece += 1
            }
        }
        return segs
    }

    /// 드래그 중 재계산해도 안정적인 PlanBlock 식별자.
    private static func blockID(_ blk: PlanBlock) -> String { String(describing: blk.persistentModelID) }

    /// 자정을 넘기는 구간을 [s,24] 와 [0,e-24] 로 나눈다.
    private static func splitAtMidnight(_ s: Double, _ e: Double) -> [(Double, Double)] {
        let start = max(0, s)
        if e <= 24 { return [(start, e)] }
        return [(start, 24), (0, min(e - 24, 24))]
    }

    static let bands: [TimeBand] = [.morning, .afternoon, .evening, .night]

    static func bandIntervals(_ b: TimeBand) -> [(Double, Double)] {
        switch b {
        case .morning:   return [(6, 12)]
        case .afternoon: return [(12, 18)]
        case .evening:   return [(18, 23)]
        case .night:     return [(23, 24), (0, 6)]
        }
    }

    /// 고정 루틴과 기존 계획을 피해 가장 여유가 많은 시간대를 추천. (새 계획 블록 기본 배정)
    static func suggestedBand(routines: [Routine], blocks: [PlanBlock]) -> TimeBand {
        var occ: [(Double, Double)] = []
        for r in routines {
            occ.append(contentsOf: splitAtMidnight(r.startHour, r.startHour + r.durationHours))
        }
        func length(_ ranges: [(Double, Double)]) -> Double { ranges.reduce(0) { $0 + ($1.1 - $1.0) } }

        var best: (band: TimeBand, free: Double)? = nil
        for b in bands {
            let routineFree = length(subtract(bandIntervals(b), occ))
            let blockHrs = blocks.filter { $0.timeBand == b }.reduce(0) { $0 + $1.durationHours }
            let free = max(0, routineFree - blockHrs)
            if best == nil || free > best!.free + 1e-9 { best = (b, free) }
        }
        return best?.band ?? .afternoon
    }

    /// 수면을 숨겼을 때 실제로 그릴 시간 범위.
    ///
    /// 하루 양끝(0시에서 이어지는 / 24시에 닿는)의 수면만 잘라낸다. 한가운데 낮잠은 자르지 않는데,
    /// 가운데를 도려내면 시간 축이 끊겨서 앞뒤 시각을 읽을 수 없기 때문이다.
    /// 잘라낸 구간에 수면이 아닌 일정이 하나라도 걸치면 그 일정이 보이도록 창을 도로 넓힌다.
    static func visibleWindow(fixedRoutines: [Routine],
                              blocks: [PlanBlock],
                              hideSleep: Bool) -> HourWindow
    {
        guard hideSleep else { return .full }

        var sleep: [(Double, Double)] = []
        var protected: [(Double, Double)] = []
        for r in fixedRoutines {
            let parts = splitAtMidnight(r.startHour, r.startHour + r.durationHours)
            if r.isSleepRoutine { sleep.append(contentsOf: parts) } else { protected.append(contentsOf: parts) }
        }
        // 시각이 정해진 계획만 보호 대상. 시각이 없는 계획은 빈 구간(=수면 밖)에 배치되므로 안전하다.
        for b in blocks where b.startHour >= 0 {
            protected.append(contentsOf: splitAtMidnight(b.startHour, b.startHour + b.durationHours))
        }
        guard !sleep.isEmpty else { return .full }

        var start = 0.0, end = 24.0
        var moved = true
        while moved {                       // 0시에서 이어지는 수면을 앞에서 밀어낸다
            moved = false
            for (s, e) in sleep where s <= start + 1e-6 && e > start + 1e-6 { start = e; moved = true }
        }
        moved = true
        while moved {                       // 24시에 닿는 수면을 뒤에서 당긴다
            moved = false
            for (s, e) in sleep where e >= end - 1e-6 && s < end - 1e-6 { end = s; moved = true }
        }

        for (s, e) in protected {           // 다른 일정을 자르지 않는다
            if s < start { start = s }
            if e > end { end = e }
        }

        // 너무 좁아지면(수면이 비정상적으로 길게 잡혀 있으면) 그냥 하루 전체를 보여준다.
        // 이 검사는 아래 안전 클램프보다 **먼저** 와야 한다. 클램프가 창을 넓히기 때문에
        // 순서가 바뀌면 4시간짜리 이상한 창이 10시간으로 부풀려져 검사를 통과해 버린다.
        guard end - start >= 6 else { return .full }

        // 정오는 언제나 보이게 (판별이 어긋나도 하루 한복판은 잘리지 않는다).
        start = max(0, min(start, 12))
        end = min(24, max(end, 12))
        return HourWindow(start: start.rounded(.down), end: end.rounded(.up))
    }

    /// 구간들의 합집합 총 길이. 서로 겹치는 부분은 한 번만 센다.
    /// (유연 블록이 다른 일정과 겹치면 그만큼은 자유 시간을 깎지 않도록 하는 데 사용.)
    static func unionLength(_ intervals: [(Double, Double)]) -> Double {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var total = 0.0
        var curStart = -1.0, curEnd = -1.0
        for (s, e) in sorted {
            if s > curEnd {
                if curEnd > curStart { total += curEnd - curStart }
                curStart = s; curEnd = e
            } else {
                curEnd = max(curEnd, e)
            }
        }
        if curEnd > curStart { total += curEnd - curStart }
        return total
    }

    /// ranges에서 occ 구간들을 뺀 나머지(빈 구간).
    private static func subtract(_ ranges: [(Double, Double)], _ occ: [(Double, Double)]) -> [(Double, Double)] {
        var result: [(Double, Double)] = []
        for (rs, re) in ranges {
            var pieces = [(rs, re)]
            for (os, oe) in occ {
                var next: [(Double, Double)] = []
                for (ps, pe) in pieces {
                    if oe <= ps || os >= pe { next.append((ps, pe)); continue }
                    if os > ps { next.append((ps, os)) }
                    if oe < pe { next.append((oe, pe)) }
                }
                pieces = next
            }
            result.append(contentsOf: pieces)
        }
        return result.filter { $0.1 - $0.0 > 0.0001 }
    }
}

// MARK: - 한 요일 행

struct DayTimelineRow: View {
    @Environment(\.modelContext) private var context
    let day: DayOfWeek
    let date: Date
    let routines: [Routine]
    let blocks: [PlanBlock]
    var quotaRoutines: [Routine] = []
    var hiddenRoutines: [Routine] = []              // 이 요일·주에서 숨긴 고정 루틴(유령으로 표시·되살리기)
    var occurrences: [RoutineOccurrence] = []      // 이 요일·주의 고정 루틴 배치(위치 override 저장처)
    var quotaPlacements: [QuotaPlacement] = []      // 이 요일·주의 식사 등 위치 저장처
    var weekStart: Date = .currentWeekStart
    /// 그릴 시간 범위. 수면을 숨기면 양끝이 잘린 창이 들어온다.
    var window: HourWindow = .full
    /// 할 일 카드를 이 줄에 떨어뜨렸다. (드래그 토큰, 떨어뜨린 시각)
    /// 요일 칸과 달리 **몇 시인지까지** 함께 온다 — 자를 보면서 놓았기 때문이다.
    var onDropBacklog: (String, Double) -> Void = { _, _ in }

    /// 세로로 끌려 온 계획 블록이 지금 이 줄 위에 있다 — 놓으면 이 요일로 간다.
    var isDayDropTarget: Bool = false
    /// 화면(글로벌) 좌표 한 점이 어느 요일 줄 위인지 묻는다.
    /// 한 줄은 자기 자리만 알기에, 모든 줄의 자리를 아는 부모(주간 화면)가 답한다.
    var dayAtGlobalPoint: (CGPoint) -> DayOfWeek? = { _ in nil }
    /// 끌고 가는 동안 지나는 요일. 부모가 그 줄에 테두리를 세운다.
    var onDayTargetChange: (DayOfWeek?) -> Void = { _ in }

    // 자 위에서도 요일 칸과 똑같이 고칠 수 있어야 한다 — 같은 일정을 보는 두 창일 뿐이다.
    /// 계획 블록을 눌렀다 — 제목·시간·성공 기준을 고치는 편집기로.
    var onEditBlock: (PlanBlock) -> Void = { _ in }
    /// 루틴을 눌렀다 — 상세(정보·실행 전략·프리모템)로.
    var onEditRoutine: (Routine) -> Void = { _ in }
    /// 루틴의 요일·시각을 고치는 편집기로.
    var onEditRoutineSchedule: (Routine) -> Void = { _ in }

    // 드래그 중인 세그먼트와 이동량(px). 같은 행 안에서만 유효.
    @State private var dragId: String? = nil
    @State private var dragPx: CGFloat = 0
    /// 카드를 이 줄 위로 끌고 와 있는가. 받을 자리라는 것을 테두리로 말한다.
    @State private var dropTargeted = false
    /// 손이 올라가 있는 구간. 누를 수 있다는 것을 밝기로 말한다.
    @State private var hoverId: String? = nil

    /// 그 시각을 0–24 소수 시간으로. (14:30 → 14.5)
    static func hourOfDay(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    private var routineStartOverride: [String: Double] {
        var d: [String: Double] = [:]
        for o in occurrences where o.startHourOverride >= 0 { d[o.routineName] = o.startHourOverride }
        return d
    }
    private var quotaPlacementMap: [String: [Int: Double]] {
        // 숨긴 끼니도 위치는 유지(유령을 원래 자리에 그리려고).
        var d: [String: [Int: Double]] = [:]
        for p in quotaPlacements { d[p.routineName, default: [:]][p.sessionIndex] = p.startHour }
        return d
    }
    private var quotaHiddenMap: [String: Set<Int>] {
        var d: [String: Set<Int>] = [:]
        for p in quotaPlacements where p.hidden { d[p.routineName, default: []].insert(p.sessionIndex) }
        return d
    }

    private var segments: [TimeSegment] {
        TimelineLayout.segments(routines: routines, blocks: blocks, quota: quotaRoutines,
                                routineStartOverride: routineStartOverride,
                                quotaPlacement: quotaPlacementMap,
                                quotaHidden: quotaHiddenMap,
                                hiddenRoutines: hiddenRoutines)
    }
    // 실제로 그려진 구간들의 합집합 = 차지한 시간.
    // 유연(식사) 블록이 회사 등과 겹치면 그 부분은 합집합에서 한 번만 세므로 자유 시간을 깎지 않는다.
    // '루틴 안' 일정은 이미 루틴 시간에 포함되므로 제외.
    private var occupied: Double {
        TimelineLayout.unionLength(segments.filter { !$0.isNested && !$0.isGhost }.map { ($0.start, $0.end) })
    }
    // 고정으로 반드시 잡아야 하는 시간(루틴 + 자유 계획)의 단순 합. 24h를 넘으면 초과 배정.
    private var hardOccupied: Double {
        routines.reduce(0) { $0 + $1.durationHours }
            + blocks.filter { !$0.withinRoutine }.reduce(0) { $0 + $1.durationHours }
    }
    private var freeHours: Double { max(0, 24 - occupied) }
    private var isOverbooked: Bool { hardOccupied > 24.0001 }
    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(day.shortLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isToday ? Color.red : .secondary)
                Text(dayNumber)
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.red : .primary)
            }
            .frame(width: 30)

            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))

                    // 시간 격자 — 3시간마다 굵은 선으로 시간대를 더 잘게 구분.
                    ForEach(window.gridHours, id: \.self) { h in
                        let isMajor = (h % 3 == 0)
                        Rectangle()
                            .fill(Color.secondary.opacity(isMajor ? 0.18 : 0.07))
                            .frame(width: isMajor ? 1 : 0.5)
                            .offset(x: window.x(Double(h), width: w))
                    }

                    // 활동 구간 — 창 밖은 그리지 않고, 걸친 것은 잘라서 그린다.
                    ForEach(segments) { seg in
                        if let vis = window.clamp(seg.start, seg.end) {
                            let x = window.x(vis.start, width: w)
                            let segW = window.x(vis.end, width: w) - x
                            let dragOffset = (seg.id == dragId) ? dragPx : 0
                            segmentView(seg, width: max(1, segW), rowWidth: w)
                                .offset(x: x + dragOffset)
                                .zIndex(seg.id == dragId ? 1 : 0)
                        }
                    }

                    // 지금 — 오늘 줄에만, 모든 구간 위에 붉은 선 하나.
                    // 하루 어디까지 왔는지가 이 한 줄로 읽힌다.
                    if isToday {
                        TimelineView(.everyMinute) { ctx in
                            let h = Self.hourOfDay(ctx.date)
                            ZStack(alignment: .leading) {
                                if h >= window.start, h <= window.end {
                                    Rectangle()
                                        .fill(Color.red)
                                        .frame(width: 1.5)
                                        .offset(x: window.x(h, width: w) - 0.75)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                        .allowsHitTesting(false)
                        .zIndex(2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    // 받을 자리 표시. 카드가 올라와 있는 동안에만 테두리가 선다.
                    // 다른 줄에서 계획 블록을 끌고 와도 같은 테두리로 "여기 놓으면 이 요일"이라고 말한다.
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.accentColor, lineWidth: (dropTargeted || isDayDropTarget) ? 2 : 0)
                }
                // 자 위에 바로 떨어뜨린다 — 떨어뜨린 가로 위치가 곧 시작 시각이다.
                .dropDestination(for: String.self) { items, location in
                    guard let token = items.first else { return false }
                    onDropBacklog(token, window.hour(atX: location.x, width: w))
                    return true
                } isTargeted: { targeted in
                    withAnimation(.easeOut(duration: 0.12)) { dropTargeted = targeted }
                }
            }
            .frame(height: 28)

            Text("남은 시간 \(fmtHours(freeHours))h")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(isOverbooked ? .red : .secondary)
                .frame(width: 96, alignment: .trailing)
        }
    }

    @ViewBuilder
    private func segmentView(_ seg: TimeSegment, width: CGFloat, rowWidth: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        let dragging = seg.id == dragId
        let ghost = seg.isGhost
        ZStack {
            if ghost {
                // 삭제(숨김)된 블록 — 아주 흐릿하게 점선으로 자리만 표시.
                shape.fill(seg.color.opacity(0.06))
                shape.strokeBorder(seg.color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else if seg.isFlexible {
                // 유연 쿼터(식사 등)는 고정 루틴 위에 겹쳐 그려질 수 있으므로,
                // 흰 테두리 링 + 진한 채움으로 아래 블록과 또렷이 구분되게 한다.
                shape.fill(seg.color.opacity(0.32))
                shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                shape.strokeBorder(seg.color, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else if seg.isNested {
                shape.fill(seg.color.opacity(0.95))
                shape.strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
            } else {
                shape.fill(seg.color.opacity(0.85))
            }
        }
        // 루틴 안 일정은 위아래로 살짝 인셋해 루틴 위에 '얹힌' 느낌을 준다.
        .padding(.vertical, seg.isNested ? 5 : 0)
        .frame(width: width)
        .overlay(alignment: .leading) {
            if width > 18 {
                Text(seg.title)
                    .font(.system(size: 11, weight: seg.isNested ? .semibold : .medium))
                    .foregroundStyle(ghost ? seg.color.opacity(0.55) : (seg.isFlexible ? seg.color : Color.white))
                    .strikethrough(ghost, color: seg.color.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 3)
                    .frame(width: width, alignment: .leading)
            }
        }
        .shadow(color: dragging ? .black.opacity(0.25) : .clear, radius: dragging ? 4 : 0, y: dragging ? 1 : 0)
        // 손이 올라가면 살짝 밝아진다. 색칠한 띠가 '누를 수 있는 것'으로 읽히도록.
        .brightness(hoverId == seg.id && !ghost ? 0.06 : 0)
        .contentShape(Rectangle())
        .onHover { hoverId = $0 ? seg.id : (hoverId == seg.id ? nil : hoverId) }
        // 좌표계는 .global — 블록을 offset으로 움직여도 translation이 흔들리지 않게(로컬이면 자기 자신을 쫓아 찐득해짐).
        // highPriorityGesture로 바깥 ScrollView의 스크롤보다 드래그를 우선. 유령 블록은 드래그 불가.
        //
        // **누르기도 이 제스처 안에서 처리한다.** 따로 `.onTapGesture`를 붙이면 높은 우선순위의
        // 이 드래그와 누가 마우스를 갖는지가 애매해진다. 최소 이동을 0으로 두고 끝났을 때
        // 움직였는지로 끌기와 누르기를 가르면, 한 제스처가 둘을 다 맡아 어긋날 자리가 없다.
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in
                    guard !seg.isGhost, moved(v.translation) else { return }
                    dragId = seg.id
                    dragPx = v.translation.width
                    // 위아래로도 끌 수 있다 — 지나는 요일 줄에 테두리가 선다.
                    onDayTargetChange(targetDay(seg, at: v.location))
                }
                .onEnded { v in
                    defer {
                        dragId = nil
                        dragPx = 0
                        onDayTargetChange(nil)
                    }
                    guard !seg.isGhost else { return }
                    // 움직이지 않았다 = 눌렀다. 요일 칸에서 칩을 누른 것과 같은 자리로 간다.
                    guard moved(v.translation) else {
                        edit(seg)
                        return
                    }
                    // 창이 좁아졌으면 같은 픽셀이 더 적은 시간을 의미한다.
                    let deltaHours = Double(v.translation.width / max(rowWidth, 1)) * window.span
                    commitDrag(seg, deltaHours: deltaHours, toDay: targetDay(seg, at: v.location))
                }
        )
        .contextMenu {
            if ghost {
                Button { restoreSegment(seg) } label: {
                    Label(restoreLabel(seg), systemImage: "arrow.uturn.backward")
                }
            } else {
                Button { edit(seg) } label: {
                    Label(editLabel(seg), systemImage: "pencil")
                }
                if case .fixedRoutine(let name) = seg.source,
                   let r = routines.first(where: { $0.name == name }) {
                    Button { onEditRoutineSchedule(r) } label: {
                        Label("요일·시각 수정…", systemImage: "calendar.badge.clock")
                    }
                }
                Divider()
                // 자 위에서도 바로 세기 시작한다 — 오늘 줄에서 지금 하는 것을 바로 집는 길 (→ TimerView.swift).
                if let target = timerTarget(seg) {
                    TimerMenuItems(token: target.token, title: target.title, hours: target.hours,
                                   iconName: target.iconName, colorName: target.colorName)
                    Divider()
                }
                Button(role: .destructive) { deleteSegment(seg) } label: {
                    Label(deleteLabel(seg), systemImage: "trash")
                }
            }
        }
        .help(dragHelp(seg))
    }

    /// 손이 떨린 정도인가, 정말 끈 것인가. 2pt를 넘어야 끌기로 본다.
    private func moved(_ translation: CGSize) -> Bool {
        abs(translation.width) > 2 || abs(translation.height) > 2
    }

    /// 자 위의 구간을 눌렀을 때 열리는 자리. 요일 칸의 칩을 누른 것과 같은 곳으로 간다.
    /// 유령(숨긴 것)은 고칠 게 없다 — 되살리기부터다.
    private func edit(_ seg: TimeSegment) {
        guard !seg.isGhost else { return }
        switch seg.source {
        case .planBlock(let blk):
            onEditBlock(blk)
        case .fixedRoutine(let name):
            if let r = routines.first(where: { $0.name == name }) { onEditRoutine(r) }
        case .quotaSession(let name, _):
            if let r = quotaRoutines.first(where: { $0.name == name }) { onEditRoutine(r) }
        case .none:
            break
        }
    }

    private func editLabel(_ seg: TimeSegment) -> String {
        switch seg.source {
        case .planBlock:    return "이 계획 수정…"
        case .fixedRoutine: return "이 루틴 보기·수정…"
        case .quotaSession: return "이 루틴 보기·수정…"
        case .none:         return "수정…"
        }
    }

    /// 이 블록으로 무엇을 할 수 있는지. 계획 블록만 요일을 넘나들 수 있으므로 안내도 다르다.
    private func dragHelp(_ seg: TimeSegment) -> String {
        if seg.isGhost { return "\(seg.title) — 삭제됨 · 우클릭으로 되살리기" }
        if case .planBlock = seg.source {
            return "\(seg.title) — 눌러서 수정 · 좌우로 끌어 시각 이동(15분 단위) · 위아래로 끌어 다른 요일로 · 우클릭으로 더 보기"
        }
        return "\(seg.title) — 눌러서 보기·수정 · 드래그해서 시각 이동(15분 단위) · 우클릭으로 더 보기"
    }

    /// 이 구간을 타이머로 셀 수 있는가. 셀 수 있으면 무엇을 어떤 길이로 셀지.
    /// 자정을 넘겨 잘린 조각이어도 **원본의 길이**(logicalDuration)로 센다 — 사람이 하는 일은 하나다.
    private func timerTarget(_ seg: TimeSegment) -> (token: String, title: String, hours: Double,
                                                     iconName: String, colorName: String?)? {
        switch seg.source {
        case .planBlock(let blk):
            return (blk.dragToken, blk.title, blk.durationHours, "square.stack.3d.up", nil)
        case .fixedRoutine(let name):
            guard let r = routines.first(where: { $0.name == name }) else { return nil }
            return (TaskTimer.token(for: r), r.name, r.durationHours, r.iconName, r.colorName)
        case .quotaSession(let name, _):
            guard let r = quotaRoutines.first(where: { $0.name == name }) else { return nil }
            let sessions = max(1, r.sessionsPerDay)
            return (TaskTimer.token(for: r), r.name, r.dailyQuotaHours / Double(sessions),
                    r.iconName, r.colorName)
        case .none:
            return nil
        }
    }

    private func deleteLabel(_ seg: TimeSegment) -> String {
        switch seg.source {
        case .fixedRoutine: return "이번 주 \(day.shortLabel)요일에서 빼기"
        case .quotaSession: return "이 끼니 빼기 (이번 주 \(day.shortLabel))"
        case .planBlock:    return "이 계획 삭제"
        case .none:         return "삭제"
        }
    }

    private func restoreLabel(_ seg: TimeSegment) -> String {
        switch seg.source {
        case .fixedRoutine: return "\(seg.title) 되살리기"
        case .quotaSession: return "이 끼니 되살리기"
        default:            return "되살리기"
        }
    }

    /// 숨긴(유령) 블록을 다시 보이게 한다.
    private func restoreSegment(_ seg: TimeSegment) {
        switch seg.source {
        case .fixedRoutine(let name):
            occurrences.first(where: { $0.routineName == name })?.hidden = false
        case .quotaSession(let name, let index):
            quotaPlacements.first(where: { $0.routineName == name && $0.sessionIndex == index })?.hidden = false
        default:
            return
        }
        try? context.save()
    }

    /// 타임라인에서 블록 하나를 삭제. 종류별로 다르게 반영되어 그리드·남은 시간 등에 즉시 적용된다.
    /// - 계획 블록: PlanBlock 삭제 → 그리드·지표에서 사라짐
    /// - 식사(쿼터): 그 주·요일·회차만 숨김 → 그날 남은 시간 늘어남(루틴 정의는 유지)
    /// - 고정 루틴: 그 주·요일만 숨김 → 그리드·타임라인에서 사라짐(루틴 자체·다른 요일은 유지)
    private func deleteSegment(_ seg: TimeSegment) {
        switch seg.source {
        case .planBlock(let blk):
            context.delete(blk)
        case .quotaSession(let name, let index):
            if let p = quotaPlacements.first(where: { $0.routineName == name && $0.sessionIndex == index }) {
                p.hidden = true
            } else {
                let p = QuotaPlacement(routineName: name, day: day, weekStartDate: weekStart,
                                       sessionIndex: index, startHour: seg.logicalStart)
                p.hidden = true
                context.insert(p)
            }
        case .fixedRoutine(let name):
            if let occ = occurrences.first(where: { $0.routineName == name }) {
                occ.hidden = true
            } else {
                let occ = RoutineOccurrence(routineName: name, day: day, weekStartDate: weekStart)
                occ.hidden = true
                context.insert(occ)
            }
        case .none:
            return
        }
        try? context.save()
    }

    /// 이 드래그가 옮겨 갈 다른 요일. 옆 줄로 넘어가지 않았으면 nil.
    ///
    /// 요일을 넘나드는 건 **계획 블록뿐**이다. 고정 루틴과 끼니는 요일이 루틴 정의에 매여 있어,
    /// 여기서 옮기면 정의와 이번 주 배치가 어긋난다 — 그건 루틴 편집기가 할 일이다.
    private func targetDay(_ seg: TimeSegment, at globalPoint: CGPoint) -> DayOfWeek? {
        guard case .planBlock = seg.source else { return nil }
        guard let target = dayAtGlobalPoint(globalPoint), target != day else { return nil }
        return target
    }

    /// 드래그를 끝낸 세그먼트의 새 시작 시각을 계산해 원본 모델에 저장(15분 스냅).
    /// - Parameter newDay: 세로로 끌어 다른 요일 줄에 놓았다면 그 요일. 계획 블록에만 적용된다.
    private func commitDrag(_ seg: TimeSegment, deltaHours: Double, toDay newDay: DayOfWeek? = nil) {
        // 단순 클릭은 무시. 다만 요일만 바꾼(가로로는 안 움직인) 드래그는 살려야 한다.
        guard abs(deltaHours) > 0.001 || newDay != nil else { return }
        var newStart = ((seg.logicalStart + deltaHours) / 0.25).rounded() * 0.25
        // 고정 루틴(수면 등)은 자정을 넘겨도 되므로 시작만 하루 범위로, 나머지는 길이만큼 여유를 둬 자정 넘김 방지.
        let maxStart: Double
        if case .fixedRoutine = seg.source { maxStart = 23.75 } else { maxStart = max(0, 24 - seg.logicalDuration) }
        newStart = min(max(newStart, 0), maxStart)

        switch seg.source {
        case .fixedRoutine(let name):
            if let occ = occurrences.first(where: { $0.routineName == name }) {
                occ.startHourOverride = newStart
            } else {
                let occ = RoutineOccurrence(routineName: name, day: day, weekStartDate: weekStart)
                occ.startHourOverride = newStart
                context.insert(occ)
            }
        case .planBlock(let blk):
            blk.startHour = newStart
            blk.timeBand = .containing(newStart)   // 요일 칸 칩의 '아침/오후/저녁'이 시각을 따라오게.
            if let newDay { blk.day = newDay }
        case .quotaSession(let name, let index):
            if let p = quotaPlacements.first(where: { $0.routineName == name && $0.sessionIndex == index }) {
                p.startHour = newStart
            } else {
                context.insert(QuotaPlacement(routineName: name, day: day, weekStartDate: weekStart,
                                              sessionIndex: index, startHour: newStart))
            }
        case .none:
            return
        }
        try? context.save()
    }

    private var dayNumber: String {
        let f = DateFormatter(); f.dateFormat = "d"
        return f.string(from: date)
    }
}

// MARK: - 시간 축 (0·6·12·18·24)

struct HourAxis: View {
    var window: HourWindow = .full

    var body: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 30)
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    ForEach(window.axisHours, id: \.self) { h in
                        Text("\(h)")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .offset(x: min(w - 14, max(0, window.x(Double(h), width: w))))
                    }

                    // 축에도 지금을 찍는다 — 줄마다 그은 선이 몇 시인지 여기서 읽는다.
                    TimelineView(.everyMinute) { ctx in
                        let h = DayTimelineRow.hourOfDay(ctx.date)
                        ZStack(alignment: .leading) {
                            if h >= window.start, h <= window.end {
                                Text(formatHour(h))
                                    .font(.system(size: 11, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red, in: Capsule())
                                    // 라벨 가운데가 지금에 오도록 당기고, 양끝에서는 잘리지 않게 잡아둔다.
                                    .offset(x: min(w - 34, max(0, window.x(h, width: w) - 17)))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(height: 14)
            Spacer().frame(width: 96)
        }
    }
}

func fmtHours(_ v: Double) -> String {
    v == v.rounded() ? String(format: "%.0f", v) : String(format: "%.1f", v)
}

// MARK: - 요일 줄의 자리

/// 요일 줄들이 각자 화면 어디에 서 있는지(요일 rawValue → 화면 좌표) 부모에게 올린다.
/// 한 줄은 자기 자리만 알기에, 계획 블록을 세로로 끌 때 "어느 요일 위인가"는 부모가 답한다.
struct DayRowFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
