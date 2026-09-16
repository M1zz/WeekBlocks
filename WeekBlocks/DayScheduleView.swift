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

    /// 한 시간의 키. 알약과 글씨가 숨 쉴 자리가 있어야 말랑하게 읽힌다 —
    /// 30pt에 눌러 담았더니 30분짜리가 가는 띠가 되어 무엇인지보다 몇 칸인지가 먼저 보였다.
    static let hourHeight: CGFloat = 46
    /// 왼쪽 시각 글씨가 서는 폭.
    private static let gutter: CGFloat = 46
    /// 알약의 폭. 아이콘 하나가 가운데 들어가는 크기.
    private static let pillWidth: CGFloat = 34
    /// 한 줄(알약 + 시각·제목)이 차지하는 가장 작은 키. 15분짜리도 이만큼은 선다.
    private static let minRowHeight: CGFloat = 38

    @State private var dragId: String?
    @State private var dragPy: CGFloat = 0
    @State private var hoverId: String?
    @State private var dropTargeted = false
    /// 일정이 다 드러났는가. 하루가 설 때 위에서부터 하나씩 톡톡 선다.
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

        VStack(alignment: .leading, spacing: 14) {
            header(free: free, overbooked: overbooked)
            timeline(segs)
        }
        .onAppear {
            if reduceMotion { drawn = true; return }
            drawn = true
        }
    }

    // MARK: 머리

    private func header(free: Double, overbooked: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(day.longLabel)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(isToday ? Color.red : .primary)
            // 남은 시간은 말랑한 알약 하나 — 숫자가 표의 칸이 아니라 한마디로 읽힌다.
            HStack(spacing: 4) {
                Image(systemName: overbooked ? "exclamationmark.circle.fill" : "hourglass")
                    .font(.system(size: 10, weight: .bold))
                Text("남은 시간 \(fmtHours(free))h")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(overbooked ? Color.red : Color.accentColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background((overbooked ? Color.red : Color.accentColor).opacity(0.12), in: Capsule())
            .animation(Motion.number, value: free)
            Spacer()
            // '블록 추가' 단추는 두지 않는다 — 요일에 일을 올리는 건 주간이 하는 일이다.
            // 여기서는 이미 올린 것을 실제로 한 시각으로 옮기는 것까지만 한다.
        }
    }

    // MARK: 하루

    private func timeline(_ segs: [TimeSegment]) -> some View {
        // 나란히 설 칸을 나누는 건 루틴·계획 블록뿐이다. 루틴 안 일정과 다른 일정 위에 겹친
        // 끼니는 칸을 따로 갖지 않고 오른쪽에 얹힌다 — 회사 9시간이 끼니 한 번 때문에 반쪽이 되지 않게.
        let laned = segs.filter { !$0.isNested && !$0.isGhost && !$0.isFlexible }
        let lanes = Self.lanes(laned, minHours: Double(Self.minRowHeight / Self.hourHeight))
        let order = Dictionary(uniqueKeysWithValues: segs.sorted { $0.start < $1.start }
            .enumerated().map { ($1.id, $0) })

        return GeometryReader { geo in
            let trackWidth = max(40, geo.size.width - Self.gutter)
            ZStack(alignment: .topLeading) {
                hourGrid(width: geo.size.width)

                // 알약들을 잇는 등뼈. 하루가 한 줄로 흘러간다는 것이 선 하나로 읽힌다.
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 3, height: geo.size.height)
                    .offset(x: Self.gutter + Self.pillWidth / 2 - 1.5)
                    .allowsHitTesting(false)

                ForEach(segs) { seg in
                    if let frame = frame(for: seg, lanes: lanes, laned: laned, trackWidth: trackWidth) {
                        let i = order[seg.id] ?? 0
                        segmentView(seg, size: frame.size)
                            .offset(x: Self.gutter + frame.minX,
                                    y: frame.minY + (seg.id == dragId ? dragPy : 0))
                            .zIndex(seg.id == dragId ? 3 : (seg.isGhost ? 0 : (seg.isNested || seg.isFlexible ? 2 : 1)))
                            // 하루가 설 때 위에서부터 하나씩 톡톡 튀어 오른다.
                            .scaleEffect(drawn ? 1 : 0.6, anchor: .leading)
                            .opacity(drawn ? 1 : 0)
                            .animation(reduceMotion ? nil : Motion.squish.delay(Double(min(i, 16)) * 0.03), value: drawn)
                            // 놓는 순간 15분 격자로 **통** 붙는다. 끄는 동안에는 손을 바로 따른다.
                            .animation(seg.id == dragId ? nil : Motion.squish, value: frame)
                            .transition(.pop)
                    }
                }
                .animation(Motion.squish, value: segs.map(\.id))

                if isToday { nowLine }
            }
        }
        .frame(height: CGFloat(window.span) * Self.hourHeight + Self.minRowHeight / 2)
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
            RoundedRectangle.soft(Corner.panel)
                .fill(Color.accentColor.opacity(dropTargeted ? 0.05 : 0))
                .overlay(RoundedRectangle.soft(Corner.panel)
                    .strokeBorder(Color.accentColor.opacity(0.7),
                                  style: StrokeStyle(lineWidth: dropTargeted ? 2 : 0, dash: [6, 4])))
                .padding(-6)
                .allowsHitTesting(false)
        }
    }

    /// 정시마다 아주 옅은 선, 3시간마다 시각 글씨를 조금 더 또렷하게.
    private func hourGrid(width: CGFloat) -> some View {
        let lo = Int(window.start.rounded(.up)), hi = Int(window.end.rounded(.down))
        return ZStack(alignment: .topLeading) {
            ForEach(Array(stride(from: lo, through: hi, by: 1)), id: \.self) { h in
                HStack(spacing: 8) {
                    Text(formatHour(Double(h)))
                        .font(.system(size: 10, weight: h % 3 == 0 ? .semibold : .regular, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(h % 3 == 0 ? .secondary : .tertiary)
                        .frame(width: Self.gutter - 10, alignment: .trailing)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.07))
                        .frame(height: 1)
                        .padding(.leading, Self.pillWidth + 8)
                }
                .offset(y: y(Double(h)) - 6)
            }
        }
        .frame(width: width, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// 지금 — 오늘이면 붉은 선 하나와 둥근 시각 알약. 하루 어디까지 왔는지가 이 한 줄로 읽힌다.
    private var nowLine: some View {
        TimelineView(.everyMinute) { ctx in
            let h = DayTimelineRow.hourOfDay(ctx.date)
            ZStack(alignment: .topLeading) {
                if h >= window.start, h <= window.end {
                    HStack(spacing: 0) {
                        Text(formatHour(h))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            // 시각 칸이 좁아도 "14:35"가 두 줄로 꺾이지 않게 — 넘치면 왼쪽으로 삐져나간다.
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                            .shadow(color: .red.opacity(0.3), radius: 3, y: 1)
                            .frame(width: Self.gutter - 4, alignment: .trailing)
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(Color.surface, lineWidth: 2))
                            .padding(.leading, Self.pillWidth / 2 - 2)
                        Capsule()
                            .fill(Color.red.opacity(0.7))
                            .frame(height: 2)
                    }
                    .offset(y: y(h) - 7)
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .allowsHitTesting(false)
        .zIndex(4)
    }

    // MARK: 한 구간

    /// 알약 속 그림. 루틴은 저마다 고른 아이콘, 계획 블록은 제목 첫 글자.
    private func glyph(for seg: TimeSegment) -> (symbol: String?, letter: String) {
        let letter = seg.title.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "•"
        switch seg.source {
        case .fixedRoutine(let name):
            let r = routines.first { $0.name == name } ?? hiddenRoutines.first { $0.name == name }
            return (r?.iconName, letter)
        case .quotaSession(let name, _):
            return (quotaRoutines.first { $0.name == name }?.iconName, letter)
        default:
            return (nil, letter)
        }
    }

    private func planBlock(_ seg: TimeSegment) -> PlanBlock? {
        if case .planBlock(let blk) = seg.source { return blk }
        return nil
    }

    @ViewBuilder
    private func segmentView(_ seg: TimeSegment, size: CGSize) -> some View {
        let dragging = seg.id == dragId
        let hovering = hoverId == seg.id
        let block = planBlock(seg)
        let status = block?.reviewStatus
        let done = status == .done
        // 넓으면 알약 + 시각·제목 + 동그라미, 좁으면 알약 + 제목, 아주 좁으면 알약만.
        let showsText = size.width >= Self.pillWidth + 44
        let showsCheck = block != nil && !seg.isGhost && size.width >= Self.pillWidth + 120

        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 10) {
                pill(seg, height: size.height, dragging: dragging, hovering: hovering, done: done)

                if showsText {
                    VStack(alignment: .leading, spacing: 1) {
                        if size.width >= Self.pillWidth + 110 {
                            Text(timeRange(seg))
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(seg.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .strikethrough(done || seg.isGhost, color: .secondary)
                            .foregroundStyle(done || seg.isGhost ? .secondary : .primary)
                            .lineLimit(size.height >= 60 ? 2 : 1)
                    }
                    .padding(.top, 3)
                    .padding(.trailing, showsCheck ? 30 : 4)
                }
                Spacer(minLength: 0)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(alignment: .topLeading) {
                // 가리키면 줄 전체가 그 색으로 옅게 물든다 — 무엇을 잡으려는지가 손끝에서 읽힌다.
                RoundedRectangle.soft(Corner.card)
                    .fill(seg.color.opacity(hovering || dragging ? 0.09 : 0))
                    .frame(height: max(Self.minRowHeight, min(size.height, 56)))
                    .padding(.leading, -5)
                    .padding(.vertical, -3)
            }
            .contentShape(Rectangle())
            .onHover { hoverId = $0 ? seg.id : (hoverId == seg.id ? nil : hoverId) }
            .grabCursor(enabled: !seg.isGhost)
            // 누르기와 끌기를 한 제스처가 맡는다 (→ DayTimelineRow.segmentView 와 같은 까닭).
            // 동그라미 단추는 이 제스처 **밖**에 둔다 — 안에 두면 눌러도 편집 창이 열린다.
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

            if showsCheck, let block {
                checkButton(block, color: seg.color)
                    .padding(.top, 7)
                    .padding(.trailing, 2)
            }
        }
        .scaleEffect(dragging ? 1.03 : 1, anchor: .leading)
        .animation(Motion.squish, value: dragging)
        .animation(Motion.hover, value: hovering)
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

    /// **알약.** 길이가 곧 걸리는 시간이고, 색과 그림이 곧 무엇인지다.
    @ViewBuilder
    private func pill(_ seg: TimeSegment, height: CGFloat, dragging: Bool, hovering: Bool, done: Bool) -> some View {
        let g = glyph(for: seg)
        let shape = Capsule(style: .continuous)
        ZStack(alignment: .top) {
            if seg.isGhost {
                shape.fill(seg.color.opacity(0.06))
                shape.strokeBorder(seg.color.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
            } else if seg.isFlexible {
                // 시간이 유연한 끼니는 옅게 채우고 점선 — 옮겨도 된다는 뜻이 모양에 있다.
                shape.fill(Color.surface)
                shape.fill(seg.color.opacity(0.3))
                shape.strokeBorder(seg.color.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))
            } else {
                shape.fill(seg.color.gradient)
                    .opacity(done ? 0.55 : (seg.isRoutine ? 0.85 : 1))
            }

            Group {
                if let symbol = g.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .symbolEffect(.bounce, value: done)
                } else {
                    Text(g.letter)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .scaleEffect(done ? 0.9 : 1)
                }
            }
            .foregroundStyle(seg.isGhost || seg.isFlexible ? seg.color : .white)
            .frame(width: Self.pillWidth, height: Self.pillWidth)
            .scaleEffect(hovering && !dragging ? 1.12 : 1)
        }
        .frame(width: Self.pillWidth, height: max(Self.pillWidth, height))
        .shadow(color: seg.isGhost ? .clear : seg.color.opacity(dragging ? 0.45 : (hovering ? 0.35 : 0.22)),
                radius: dragging ? 9 : (hovering ? 6 : 3), y: dragging ? 5 : 2)
    }

    /// 오른쪽 동그라미 — 누르면 끝낸 것이 되고, 다시 누르면 풀린다 (→ ReflectionRow의 같은 손짓).
    /// 옆 회고 판과 같은 표시라 어느 쪽에서 눌러도 양쪽이 함께 바뀐다.
    private func checkButton(_ block: PlanBlock, color: Color) -> some View {
        let status = block.reviewStatus
        return Button {
            Haptic.tick()
            withAnimation(Motion.squish) {
                block.reviewStatus = status == nil ? .done : nil
            }
            try? context.save()
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(color.opacity(status == nil ? 0.55 : 0), lineWidth: 1.8)
                Circle()
                    .fill(checkTint(status, color))
                    .scaleEffect(status == nil ? 0.2 : 1)
                    .opacity(status == nil ? 0 : 1)
                Image(systemName: checkSymbol(status))
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(.white)
                    .scaleEffect(status == nil ? 0.3 : 1)
                    .opacity(status == nil ? 0 : 1)
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(.squish)
        .help(status == nil ? "끝냈다고 표시한다" : "표시를 지운다 (적어 둔 회고는 그대로 남습니다)")
    }

    private func checkSymbol(_ status: ReviewStatus?) -> String {
        switch status {
        case .partial: "circle.lefthalf.filled"
        case .skipped: "xmark"
        default: "checkmark"
        }
    }

    private func checkTint(_ status: ReviewStatus?, _ color: Color) -> Color {
        switch status {
        case .partial: .yellow
        case .skipped: .red.opacity(0.8)
        default: color
        }
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
        let top = y(vis.start)
        // 짧은 일도 알약 하나와 글씨 한 줄은 들어간다. 겹칠 몫은 칸 나누기가 미리 셌다.
        let height = max(Self.minRowHeight, y(vis.end) - y(vis.start) - 3)

        // 루틴 안 일정, 다른 일정 위에 겹친 끼니는 칸을 따로 갖지 않고 오른쪽에 얹는다.
        let overlaysOther = seg.isNested
            || (seg.isFlexible && laned.contains { $0.start < seg.end - 1e-6 && seg.start < $0.end - 1e-6 })
        if overlaysOther {
            let x = w * 0.45
            return CGRect(x: x, y: top, width: max(Self.pillWidth, w - x), height: height)
        }
        guard let lane = lanes[seg.id], lane.count > 1 else {
            return CGRect(x: 0, y: top, width: w, height: height)
        }
        let gap: CGFloat = 8
        let columnWidth = (w - gap * CGFloat(lane.count - 1)) / CGFloat(lane.count)
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
    /// - Parameter minHours: 짧은 일도 화면에서는 이만큼 차지한다. 시각으로는 안 겹쳐도
    ///   알약이 겹쳐 보이면 나란히 세운다.
    static func lanes(_ segs: [TimeSegment], minHours: Double = 0) -> [String: Lane] {
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
            let end = max(seg.end, seg.start + minHours)
            if let open = laneEnds.firstIndex(where: { $0 <= seg.start + 1e-6 }) {
                laneEnds[open] = end
                lane = open
            } else {
                laneEnds.append(end)
                lane = laneEnds.count - 1
            }
            cluster.append((seg.id, lane))
            clusterEnd = max(clusterEnd, end)
        }
        flush()
        return result
    }
}
