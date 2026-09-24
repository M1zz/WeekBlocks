//
//  SegmentActions.swift
//  WeekBlocks
//
//  **시간 자 위의 한 구간을 옮기고, 빼고, 되살리는 일.**
//
//  한 주 시간축(요일마다 가로 한 줄)과 일간(하루를 세로로)이 같은 일정을 서로 다른 방향으로
//  그린다. 끄는 방향만 다를 뿐 **무엇을 어디에 적는지는 같아야** 한다 — 한쪽에서 옮긴 시각이
//  다른 쪽에서 딴 데 서 있으면 두 화면 중 하나는 거짓말이다. 그래서 적는 자리를 여기 한 곳에 둔다.
//

import SwiftUI
import SwiftData

struct SegmentActions {
    let context: ModelContext
    let day: DayOfWeek
    let weekStart: Date
    /// 이 요일의 고정 루틴.
    let routines: [Routine]
    let quotaRoutines: [Routine]
    /// 이 요일·주의 고정 루틴 배치 (위치 override 저장처).
    let occurrences: [RoutineOccurrence]
    /// 이 요일·주의 끼니 위치 저장처.
    let quotaPlacements: [QuotaPlacement]

    /// **이만큼 끌면 몇 시에 놓이는가.** 15분 격자에 붙이고 하루 밖으로 나가지 않게 가둔다.
    ///
    /// 끄는 동안 보여 주는 시각과 손을 뗐을 때 적히는 시각은 **같은 셈에서 나와야** 한다.
    /// 두 자리에서 따로 재던 때는 화면이 14:15을 가리키고 14:30에 놓여서, 원하는 시각에
    /// 세우려면 놓아 보고 다시 끄는 일을 몇 번씩 반복해야 했다.
    static func landingHour(_ seg: TimeSegment, deltaHours: Double) -> Double {
        let snapped = ((seg.logicalStart + deltaHours) / 0.25).rounded() * 0.25
        // 고정 루틴(수면 등)은 자정을 넘겨도 되므로 시작만 하루 범위로, 나머지는 길이만큼 여유를 둬 자정 넘김 방지.
        let maxStart: Double
        if case .fixedRoutine = seg.source { maxStart = 23.75 } else { maxStart = max(0, 24 - seg.logicalDuration) }
        return min(max(snapped, 0), maxStart)
    }

    /// 끌기를 마친 구간의 새 시작 시각을 원본 모델에 적는다 (15분 스냅).
    /// - Parameter newDay: 다른 요일로 옮겼다면 그 요일. 계획 블록에만 적용된다.
    func move(_ seg: TimeSegment, deltaHours: Double, toDay newDay: DayOfWeek? = nil) {
        // 단순 클릭은 무시. 다만 요일만 바꾼(시각은 안 움직인) 드래그는 살려야 한다.
        guard abs(deltaHours) > 0.001 || newDay != nil else { return }
        let newStart = Self.landingHour(seg, deltaHours: deltaHours)

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
        // 놓은 자리에서 15분 격자로 **통** 붙는 그 한 걸음 — 눈에는 출렁임으로, 손끝에는 딸깍으로.
        Haptic.snap()
        withAnimation(Motion.squish) { try? context.save() }
    }

    /// 구간 하나를 뺀다. 종류별로 다르게 반영된다.
    /// - 계획 블록: PlanBlock 삭제
    /// - 끼니(쿼터): 그 주·요일·회차만 숨김 (루틴 정의는 유지)
    /// - 고정 루틴: 그 주·요일만 숨김 (루틴 자체·다른 요일은 유지)
    func delete(_ seg: TimeSegment) {
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
        Haptic.tick()
        withAnimation(Motion.squish) { try? context.save() }
    }

    /// 끼니 하나의 **지금 시각을 매일의 기본으로** 올린다 (→ Routine.sessionStartsRaw).
    ///
    /// 시간표에서 끄는 것은 그 주 그 요일만 바꾼다. 점심을 12시로 두려고 일곱 날을 끌어도 다음 주면
    /// 도로 13시였다. 한 날 옮겨 보고 마음에 들면 이것으로 모든 날의 기본을 바꾼다.
    /// 이 날 이 회차를 따로 옮겨 둔 기록은 이제 기본과 같으므로 지운다(숨긴 것이면 둔다).
    /// 다른 날 따로 옮겨 둔 것은 그대로 — 그날만 다르게 둔 뜻이 있다.
    func makeDailyDefault(_ seg: TimeSegment) {
        guard case .quotaSession(let name, let index) = seg.source,
              let r = quotaRoutines.first(where: { $0.name == name }) else { return }
        var starts = (0..<r.quotaPieces).map { r.defaultSessionStart($0) }
        guard index < starts.count else { return }
        starts[index] = seg.logicalStart
        r.setSessionStarts(starts)
        if let p = quotaPlacements.first(where: { $0.routineName == name && $0.sessionIndex == index }), !p.hidden {
            context.delete(p)
        }
        Haptic.snap()
        withAnimation(Motion.squish) { try? context.save() }
    }

    /// 숨긴(유령) 구간을 다시 보이게 한다.
    func restore(_ seg: TimeSegment) {
        switch seg.source {
        case .fixedRoutine(let name):
            occurrences.first(where: { $0.routineName == name })?.hidden = false
        case .quotaSession(let name, let index):
            quotaPlacements.first(where: { $0.routineName == name && $0.sessionIndex == index })?.hidden = false
        default:
            return
        }
        Haptic.tick()
        withAnimation(Motion.squish) { try? context.save() }
    }

    struct TimerTarget {
        let token: String
        let title: String
        let hours: Double
        let iconName: String
        let colorName: String?
    }

    /// 이 구간을 타이머로 셀 수 있는가. 셀 수 있으면 무엇을 어떤 길이로 셀지.
    /// 자정을 넘겨 잘린 조각이어도 **원본의 길이**(logicalDuration)로 센다 — 사람이 하는 일은 하나다.
    func timerTarget(_ seg: TimeSegment) -> TimerTarget? {
        switch seg.source {
        case .planBlock(let blk):
            return TimerTarget(token: blk.dragToken, title: blk.title, hours: blk.durationHours,
                               iconName: "square.stack.3d.up", colorName: nil)
        case .fixedRoutine(let name):
            guard let r = routines.first(where: { $0.name == name }) else { return nil }
            return TimerTarget(token: TaskTimer.token(for: r), title: r.name, hours: r.durationHours,
                               iconName: r.iconName, colorName: r.colorName)
        case .quotaSession(let name, _):
            guard let r = quotaRoutines.first(where: { $0.name == name }) else { return nil }
            let sessions = max(1, r.sessionsPerDay)
            return TimerTarget(token: TaskTimer.token(for: r), title: r.name,
                               hours: r.dailyQuotaHours / Double(sessions),
                               iconName: r.iconName, colorName: r.colorName)
        case .none:
            return nil
        }
    }
}

extension SegmentActions {
    /// 루틴·끼니를 그날만 지우는 글자. 시간축·일간·블록으로 보기가 **같은 말**을 쓰도록 한 곳에 둔다.
    static func routineDeleteLabel(isMeal: Bool, on day: DayOfWeek, isToday: Bool) -> String {
        if isMeal {
            return isToday ? String(localized: "이 끼니 삭제 (오늘만)")
                           : String(localized: "이 끼니 삭제 (이번 주 \(day.shortLabel)만)")
        }
        return isToday ? String(localized: "이 루틴 삭제 (오늘만)")
                       : String(localized: "이 루틴 삭제 (이번 주 \(day.shortLabel)만)")
    }
}

extension TimeSegment {
    /// 요일까지 넘나들 수 있는 것(계획 블록)인가. 떠 있게 그릴지 여기서 정한다.
    var isPlanBlock: Bool {
        if case .planBlock = source { return true }
        return false
    }

    var editLabel: String {
        switch source {
        case .planBlock:    String(localized: "이 계획 수정…")
        case .fixedRoutine: String(localized: "이 루틴 보기·수정…")
        case .quotaSession: String(localized: "이 루틴 보기·수정…")
        case .none:         String(localized: "수정…")
        }
    }

    /// - Parameter isToday: 보고 있는 날이 오늘인가. 하루만 펴 놓고 보는 자리(일간)에서는
    ///   "이번 주 월만"보다 **"오늘만"**이 무슨 일이 일어나는지를 바로 말한다.
    ///   루틴을 하루만 뺀 것인지 루틴 자체를 지운 것인지는 되돌릴 수 있느냐가 걸린 물음이라,
    ///   글자가 한 번에 안 읽히면 사람은 아예 안 누른다.
    func deleteLabel(on day: DayOfWeek, isToday: Bool = false) -> String {
        switch source {
        // 루틴도 끼니도 **삭제**라고 부른다. 계획 블록과 같은 말이어야 같은 손짓인 줄 안다 —
        // "빼기"라고 적어 두었더니 지우는 단추를 따로 찾았고, 끼니만 '삭제'로 바꾸자 이번엔
        // 고정 루틴은 하루만 지울 수 없는 줄 알았다. 루틴 정의(다른 날)는 그대로라서
        // 뒤에 붙은 괄호가 그 범위를 말한다.
        case .fixedRoutine: SegmentActions.routineDeleteLabel(isMeal: false, on: day, isToday: isToday)
        case .quotaSession: SegmentActions.routineDeleteLabel(isMeal: true, on: day, isToday: isToday)
        case .planBlock:    String(localized: "이 계획 삭제")
        case .none:         String(localized: "삭제")
        }
    }

    var restoreLabel: String {
        switch source {
        case .fixedRoutine: String(localized: "\(title) 되살리기")
        case .quotaSession: String(localized: "이 끼니 되살리기")
        default:            String(localized: "되살리기")
        }
    }
}
