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

    /// 끌기를 마친 구간의 새 시작 시각을 원본 모델에 적는다 (15분 스냅).
    /// - Parameter newDay: 다른 요일로 옮겼다면 그 요일. 계획 블록에만 적용된다.
    func move(_ seg: TimeSegment, deltaHours: Double, toDay newDay: DayOfWeek? = nil) {
        // 단순 클릭은 무시. 다만 요일만 바꾼(시각은 안 움직인) 드래그는 살려야 한다.
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
        // 놓은 자리에서 15분 격자로 붙는 그 한 걸음. 결이 없으면 손을 뗀 순간 띠가 튄다.
        withAnimation(Motion.timeline) { try? context.save() }
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
        withAnimation(Motion.card) { try? context.save() }
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
        withAnimation(Motion.card) { try? context.save() }
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

    func deleteLabel(on day: DayOfWeek) -> String {
        switch source {
        case .fixedRoutine: String(localized: "이번 주 \(day.longLabel)에서 빼기")
        case .quotaSession: String(localized: "이 끼니 빼기 (이번 주 \(day.shortLabel))")
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
