//
//  DayScheduleView.swift
//  WeekBlocks
//
//  **하루를 세로로 넓게 편다.**
//
//  한 주 시간축은 일곱 요일을 한눈에 견주는 자리라 하루가 28pt 한 줄에 눌려 있다.
//  오늘 무엇을 몇 시에 하는지 정하려면 그 하루만 크게 펴 놓고 봐야 한다 — 시각이 위에서
//  아래로 흐르고, 겹치는 일정은 옆으로 나란히 선다(캘린더의 일 보기와 같은 결).
//
//  무엇을 어디에 적는지는 한 주 시간축과 같다 (→ SegmentActions). 방향만 세로다.
//

import SwiftUI
import SwiftData
import AppKit

struct DayScheduleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let day: DayOfWeek
    let date: Date
    /// 이 요일의 고정 루틴.
    let routines: [Routine]
    /// 이 요일의 계획 블록.
    let blocks: [PlanBlock]
    var quotaRoutines: [Routine] = []
    /// 이 요일·주에서 숨긴 고정 루틴 (유령으로 그려 되살리기).
    var hiddenRoutines: [Routine] = []
    var occurrences: [RoutineOccurrence] = []
    var quotaPlacements: [QuotaPlacement] = []
    var weekStart: Date = .currentWeekStart
    /// 그릴 시간 범위. 수면을 숨기면 양끝이 잘린 창이 들어온다.
    var window: HourWindow = .full
    var canPlan: Bool = true

    
    /// 할 일 카드·블록을 떨어뜨렸다. (드래그 토큰, 떨어뜨린 시각)
    var onDropBacklog: (String, Double) -> Void = { _, _ in }
    var onEditBlock: (PlanBlock) -> Void = { _ in }
    var onEditRoutine: (Routine) -> Void = { _ in }
    var onEditRoutineSchedule: (Routine) -> Void = { _ in }

    /// 한 시간의 키. 할 일과 나란히 서는 반쪽 폭이라 **쫀쫀하게** — 하루 대부분이 한 화면에
    /// 들어오고, 30분짜리에도 제목 한 줄이 들어갈 만큼.
    static let hourHeight: CGFloat = 30
    /// 왼쪽 시각 글씨가 서는 폭.
    private static let gutter: CGFloat = 42

    @State private var dragId: String?
    @State private var dragPy: CGFloat = 0
    @State private var hoverId: String?
    @State private var dropTargeted = false
    /// 일정이 다 드러났는가. 하루가 설 때 위에서부터 채워진다.
    @State private var drawn = false

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    private var actions: SegmentActions {
        SegmentActions(context: context, day: day, weekStart: weekStart,
                       routines: routines, quotaRoutines: quotaRoutines,
                       occurrences: occurrences, quotaPlacements: quotaPlacements)
    }

    private var segments: [TimeSegment] {
        var startOverride: [String: Double] = [:]
        for o in occurrences where o.startHourOverride >= 0 { startOverride[o.routineName] = o.startHourOverride }
        var placement: [String: [Int: Double]] = [:]
        var hidden: [String: Set<Int>] = [:]
        for p in quotaPlacements {
            placement[p.routineName, default: [:]][p.sessionIndex] = p.startHour
            if p.hidden { hidden[p.routineName, default: []].insert(p.sessionIndex) }
        }
        return TimelineLayout.segments(routines: routines, blocks: blocks, quota: quotaRoutines,
                                       routineStartOverride: startOverride,
                                       quotaPlacement: placement, quotaHidden: hidden,
                                       hiddenRoutines: hiddenRoutines)
    }

    var body: some View {
        let segs = segments
        // 남은 시간은 한 주 시간축과 같은 셈이다 — 겹친 시간은 한 번만, 루틴 안 일정은 빼고.
        let free = max(0, 24 - TimelineLayout.unionLength(
            segs.filter { !$0.isNested && !$0.isGhost }.map { ($0.start, $0.end) }))
        let overbooked = routines.reduce(0) { $0 + $1.durationHours }
            + blocks.filter { !$0.withinRoutine }.reduce(0) { $0 + $1.durationHours } > 24.0001

        VStack(alignment: .leading, spacing: 10) {
            header(free: free, overbooked: overbooked)
            timeline(segs)
        }
        .onAppear {
            if reduceMotion { drawn = true; return }
            withAnimation(Motion.chart.delay(0.05)) { drawn = true }
        }
    }

    // MARK: 머리

    private func header(free: Double, overbooked: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(day.longLabel)
                .font(.headline)
                .foregroundStyle(isToday ? Color.red : .primary)
            Text("남은 시간 \(fmtHours(free))h")
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(overbooked ? .red : .secondary)
                .contentTransition(.numericText())
                .animation(Motion.number, value: free)
            Spacer()
            // '블록 추가' 단추는 두지 않는다 — 요일에 일을 올리는 건 주간이 하는 일이다.
            // 여기서는 이미 올린 것을 실제로 한 시각으로 옮기는 것까지만 한다.
        }
    }

    // MARK: 하루

    private func timeline(_ segs: [TimeSegment]) -> some View {
        // 나란히 설 칸을 나누는 건 루틴·계획 블록뿐이다. 루틴 안 일정과 다른 일정 위에 겹친
        // 끼니는 칸을 따로 갖지 않고 얹힌다 — 회사 9시간이 끼니 한 번 때문에 반쪽이 되지 않게.
        let laned = segs.filter { !$0.isNested && !$0.isGhost && !$0.isFlexible }
        let lanes = Self.lanes(laned)

        return GeometryReader { geo in
            let trackWidth = max(40, geo.size.width - Self.gutter)
            ZStack(alignment: .topLeading) {
                hourGrid(width: geo.size.width)

                ZStack(alignment: .topLeading) {
                    ForEach(segs) { seg in
                        if let frame = frame(for: seg, lanes: lanes, laned: laned, trackWidth: trackWidth) {
                            segmentView(seg, size: frame.size)
                                .offset(x: Self.gutter + frame.minX,
                                        y: frame.minY + (seg.id == dragId ? dragPy : 0))
                                .zIndex(seg.id == dragId ? 3 : (seg.isGhost ? 0 : (seg.isNested || seg.isFlexible ? 2 : 1)))
                                // 놓는 순간 15분 격자로 붙는 한 걸음만 결을 준다. 끄는 동안에는 손을 바로 따른다.
                                .animation(seg.id == dragId ? nil : Motion.timeline, value: frame)
                                .transition(.card)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // 하루가 위에서부터 채워진다 — 시간 줄은 먼저 서 있고 일정만 드러난다.
                .mask(alignment: .top) {
                    Rectangle().frame(height: drawn ? geo.size.height : 0)
                }
                .animation(Motion.card, value: segs.map(\.id))

                if isToday { nowLine }
            }
        }
        .frame(height: CGFloat(window.span) * Self.hourHeight)
        .contentShape(Rectangle())
        // 할 일 카드를 하루 위에 바로 떨어뜨린다 — 떨어뜨린 높이가 곧 시작 시각이다.
        .dropDestination(for: String.self) { items, location in
            guard canPlan, let token = items.first else { return false }
            onDropBacklog(token, hour(atY: location.y))
            return true
        } isTargeted: { targeted in
            withAnimation(Motion.target) { dropTargeted = targeted && canPlan }
        }
        .overlay {
            RoundedRectangle.soft(Corner.card)
                .strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 2 : 0)
                .padding(-6)
                .allowsHitTesting(false)
        }
    }

    /// 정시마다 가는 선, 3시간마다 조금 더 진하게. 왼쪽에 시각.
    private func hourGrid(width: CGFloat) -> some View {
        let lo = Int(window.start.rounded(.up)), hi = Int(window.end.rounded(.down))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: lo, through: hi, by: 1)), id: \.self) { h in
                HStack(spacing: 8) {
                    Text(formatHour(Double(h)))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.gutter - 8, alignment: .trailing)
                    Rectangle()
                        .fill(Color.secondary.opacity(h % 3 == 0 ? 0.22 : 0.1))
                        .frame(height: h % 3 == 0 ? 1 : 0.5)
                }
                .offset(y: y(Double(h)) - 6)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// 지금 — 오늘이면 붉은 가로선 하나. 하루 어디까지 왔는지가 이 한 줄로 읽힌다.
    private var nowLine: some View {
        TimelineView(.everyMinute) { ctx in
            let h = DayTimelineRow.hourOfDay(ctx.date)
            ZStack(alignment: .topLeading) {
                if h >= window.start, h <= window.end {
                    HStack(spacing: 0) {
                        Text(formatHour(h))
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red, in: Capsule())
                            .frame(width: Self.gutter - 4, alignment: .trailing)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 6, height: 6)
                            .padding(.leading, 2)
                        Rectangle()
                            .fill(Color.red)
                            .frame(height: 1.5)
                    }
                    .offset(y: y(h) - 6)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .zIndex(4)
    }

    // MARK: 한 구간

    @ViewBuilder
    private func segmentView(_ seg: TimeSegment, size: CGSize) -> some View {
        let shape = RoundedRectangle.soft(Corner.chip)
        let dragging = seg.id == dragId
        let hovering = hoverId == seg.id
        // 옮길 수 있는 곳이 가장 넓은 것(계획 블록)은 떠 있다 — 요일 칸·한 주 시간축과 같은 약속.
        let lifted = seg.isPlanBlock && !seg.isGhost

        let title = Text(seg.title)
            .font(.system(size: 11.5, weight: .semibold))
            .strikethrough(seg.isGhost, color: seg.color.opacity(0.5))
        // 넉넉하면 두 줄(제목 / 시각), 좁으면 한 줄에 제목과 시작 시각을 나란히 — 쫀쫀한 키에서도
        // 30분짜리까지 무엇인지와 몇 시인지가 함께 읽힌다.
        let tall = size.height >= 38

        Group {
            if tall {
                VStack(alignment: .leading, spacing: 0) {
                    title.lineLimit(size.height >= 54 ? 2 : 1)
                    Text(timeRange(seg))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .opacity(0.75)
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 4) {
                    title.lineLimit(1)
                    Spacer(minLength: 2)
                    if size.width >= 110 {
                        Text(formatHour(seg.logicalStart))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .opacity(0.7)
                    }
                }
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .padding(.vertical, tall ? 3 : 0)
        .frame(width: size.width, height: size.height, alignment: tall ? .topLeading : .leading)
        .foregroundStyle(seg.isGhost ? seg.color.opacity(0.55) : seg.color)
        .background {
            if seg.isGhost {
                shape.fill(seg.color.opacity(0.05))
                shape.strokeBorder(seg.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else if lifted {
                ZStack {
                    shape.fill(Color.surface)
                    shape.fill(seg.color.opacity(0.2))
                }
                .compositingGroup()
                .shadow(color: seg.color.opacity(dragging || hovering ? 0.34 : 0.22),
                        radius: dragging ? 8 : (hovering ? 6 : 2.5),
                        y: dragging ? 4 : (hovering ? 3 : 1.5))
            } else if seg.isFlexible {
                // 루틴 위에 얹혀도 글씨가 읽히게 밑에 불투명한 바탕을 깐다. 유연함은 점선이 말한다.
                shape.fill(Color.surface)
                shape.fill(seg.color.opacity(hovering ? 0.2 : 0.14))
                shape.strokeBorder(seg.color.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            } else {
                shape.fill(seg.color.opacity(hovering ? 0.2 : 0.14))
            }
        }
        // 왼쪽 가장자리의 색 막대 — 무슨 일정인지가 색으로 먼저 읽힌다.
        .overlay(alignment: .leading) {
            if !seg.isGhost {
                Capsule()
                    .fill(seg.color.opacity(0.85))
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.leading, 4)
            }
        }
        .offset(y: lifted && hovering && !dragging ? -1 : 0)
        .contentShape(shape)
        .onHover { hoverId = $0 ? seg.id : (hoverId == seg.id ? nil : hoverId) }
        .grabCursor(enabled: !seg.isGhost)
        .animation(Motion.hover, value: hovering)
        // 누르기와 끌기를 한 제스처가 맡는다 (→ DayTimelineRow.segmentView 와 같은 까닭).
        .highPriorityGesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { v in
                    guard !seg.isGhost, moved(v.translation) else { return }
                    dragId = seg.id
                    dragPy = v.translation.height
                    NSCursor.closedHand.set()
                }
                .onEnded { v in
                    defer {
                        dragId = nil
                        dragPy = 0
                    }
                    guard !seg.isGhost else { return }
                    guard moved(v.translation) else {
                        edit(seg)
                        return
                    }
                    actions.move(seg, deltaHours: Double(v.translation.height / Self.hourHeight))
                }
        )
        .contextMenu {
            if seg.isGhost {
                Button { actions.restore(seg) } label: {
                    Label(seg.restoreLabel, systemImage: "arrow.uturn.backward")
                }
            } else {
                Button { edit(seg) } label: {
                    Label(seg.editLabel, systemImage: "pencil")
                }
                if case .fixedRoutine(let name) = seg.source,
                   let r = routines.first(where: { $0.name == name }) {
                    Button { onEditRoutineSchedule(r) } label: {
                        Label("요일·시각 수정…", systemImage: "calendar.badge.clock")
                    }
                }
                Divider()
                if let target = actions.timerTarget(seg) {
                    TimerMenuItems(token: target.token, title: target.title, hours: target.hours,
                                   iconName: target.iconName, colorName: target.colorName)
                    Divider()
                }
                Button(role: .destructive) { actions.delete(seg) } label: {
                    Label(seg.deleteLabel(on: day), systemImage: "trash")
                }
            }
        }
        .help(seg.isGhost
              ? String(localized: "\(seg.title) — 삭제됨 · 우클릭으로 되살리기")
              : String(localized: "\(seg.title) — 눌러서 보기·수정 · 위아래로 끌어 시각 이동(15분 단위) · 우클릭으로 더 보기"))
    }

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

    /// 손이 떨린 정도인가, 정말 끈 것인가. 2pt를 넘어야 끌기로 본다.
    private func moved(_ translation: CGSize) -> Bool {
        abs(translation.width) > 2 || abs(translation.height) > 2
    }

    /// "09:00–18:00 · 9h". 자정을 넘기는 잠은 끝 시각을 다음 날 시각으로 적는다.
    private func timeRange(_ seg: TimeSegment) -> String {
        let end = (seg.logicalStart + seg.logicalDuration).truncatingRemainder(dividingBy: 24)
        return "\(formatHour(seg.logicalStart))–\(formatHour(end)) · \(shortHours(seg.logicalDuration))"
    }

    // MARK: 자리 셈

    private func y(_ hour: Double) -> CGFloat {
        CGFloat(hour - window.start) * Self.hourHeight
    }

    /// 세로 위치 → 시각. 15분 격자에 붙인다.
    private func hour(atY y: CGFloat) -> Double {
        let raw = window.start + Double(y / Self.hourHeight)
        return min(max((raw * 4).rounded() / 4, window.start), window.end)
    }

    private func frame(for seg: TimeSegment, lanes: [String: Lane], laned: [TimeSegment],
                       trackWidth w: CGFloat) -> CGRect? {
        guard let vis = window.clamp(seg.start, seg.end) else { return nil }
        let top = y(vis.start) + 1
        let height = max(14, y(vis.end) - y(vis.start) - 2)
        let right: CGFloat = 4

        // 루틴 안 일정, 다른 일정 위에 겹친 끼니는 칸을 따로 갖지 않고 오른쪽에 얹는다.
        let overlaysOther = seg.isNested
            || (seg.isFlexible && laned.contains { $0.start < seg.end - 1e-6 && seg.start < $0.end - 1e-6 })
        if overlaysOther {
            let x = w * 0.4
            return CGRect(x: x, y: top, width: max(20, w - x - right), height: height)
        }
        guard let lane = lanes[seg.id], lane.count > 1 else {
            return CGRect(x: 0, y: top, width: w - right, height: height)
        }
        let gap: CGFloat = 3
        let columnWidth = (w - right - gap * CGFloat(lane.count - 1)) / CGFloat(lane.count)
        return CGRect(x: CGFloat(lane.index) * (columnWidth + gap), y: top, width: columnWidth, height: height)
    }

    struct Lane {
        let index: Int
        let count: Int
    }

    /// 겹치는 일정은 옆으로 나란히 세운다. id → (몇 번째 칸, 모두 몇 칸).
    ///
    /// 서로 이어 겹치는 **묶음마다** 칸 수를 따로 센다 — 오전에 둘이 겹쳤다고 오후 일정까지
    /// 반쪽이 되지 않게.
    static func lanes(_ segs: [TimeSegment]) -> [String: Lane] {
        var result: [String: Lane] = [:]
        var cluster: [(id: String, lane: Int)] = []
        var laneEnds: [Double] = []
        var clusterEnd = -Double.infinity

        func flush() {
            for item in cluster { result[item.id] = Lane(index: item.lane, count: laneEnds.count) }
            cluster = []
            laneEnds = []
        }

        for seg in segs.sorted(by: { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }) {
            if seg.start >= clusterEnd - 1e-6 {
                flush()
                clusterEnd = -Double.infinity
            }
            let lane: Int
            if let open = laneEnds.firstIndex(where: { $0 <= seg.start + 1e-6 }) {
                laneEnds[open] = seg.end
                lane = open
            } else {
                laneEnds.append(seg.end)
                lane = laneEnds.count - 1
            }
            cluster.append((seg.id, lane))
            clusterEnd = max(clusterEnd, seg.end)
        }
        flush()
        return result
    }
}
