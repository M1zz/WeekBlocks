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
import UniformTypeIdentifiers

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
    /// 빈 시간을 눌러 고를 수 있는 할 일 — 아직 요일을 안 정한 것.
    var candidates: [GapCandidate] = []
    /// 빈 시간에 새 블록을 세운다. (시작 시각, 빈 시간 길이 — **제안**이라 두 시간으로 깎인다)
    var onAddBlock: (Double, Double) -> Void = { _, _ in }
    /// 채우기 판에서 할 일을 골랐다. (드래그 토큰, 시작 시각, 정한 길이 — nil이면 할 일 제 길이)
    ///
    /// 끌어다 놓는 길(`onDropBacklog`)과 달리 **길이를 여기서 정할 수 있다.**
    /// 다섯 시간 빈자리에 두 시간짜리를 "오늘은 한 시간만" 넣는 일이 실제로 잦다.
    var onFillGap: (String, Double, Double?) -> Void = { _, _, _ in }
    /// 빈 시간을 위아래로 훑어 범위를 그렸다. (시작 시각, 그린 길이)
    ///
    /// 사람이 손으로 그은 길이라 **그대로 쓴다** — `onAddBlock`처럼 깎지 않는다.
    var onDrawBlock: (Double, Double) -> Void = { _, _ in }
    /// 시간표 **밖**의 받는 자리들 (오늘의 계획 판·할 일 목록). 계획 블록을 끌어 그 위에 놓을 수 있다.
    var zones: DayDragZones? = nil
    /// 블록을 할 일 목록에 놓았다 — 날짜를 무른다.
    var onReturnToBacklog: (PlanBlock) -> Void = { _ in }
    /// 블록을 오늘의 계획 판에 놓았다 — 시각만 무르고 그날에는 남긴다.
    var onClearTime: (PlanBlock) -> Void = { _ in }

    /// 한 시간의 키. 알약과 글씨가 숨 쉴 자리가 있어야 말랑하게 읽힌다 —
    /// 30pt에 눌러 담았더니 30분짜리가 가는 띠가 되어 무엇인지보다 몇 칸인지가 먼저 보였다.
    static let hourHeight: CGFloat = 46
    /// 왼쪽 시각 글씨가 서는 폭.
    private static let gutter: CGFloat = 46
    /// 알약의 폭. 아이콘 하나가 가운데 들어가는 크기.
    private static let pillWidth: CGFloat = 34
    /// 한 줄이 차지하는 가장 작은 키. 알약 하나와 한 줄 글씨가 들어가는 만큼이다.
    ///
    /// ⚠️ 한때 38pt였다. 30분짜리(23pt)를 38pt로 늘려 그리다 보니 **시각으로는 09:00에 끝나는
    ///    일이 화면에서는 09:09까지 뻗어** 다음 일정과 겹친 것으로 계산됐고, 겹치면 나란히
    ///    세우는 규칙에 걸려 둘이 반쪽씩 갈라졌다. 키를 줄이고, 나란히 세울지는 **시각만 보고** 정한다.
    private static let minRowHeight: CGFloat = 22
    /// 하루 시간표 안의 자. 손잡이를 끌 때 손이 몇 시에 있는지 이 자로 잰다 —
    /// 손잡이마다 제 칸 기준으로 재면 칸이 움직이는 동안 기준도 같이 흔들린다.
    private static let trackSpace = "dayTrack"

    @State private var dragId: String?
    @State private var dragPy: CGFloat = 0
    /// 계획 블록은 옆으로도 따라온다 — 시간표 밖(오늘의 계획·할 일)으로 끌어낼 수 있다.
    @State private var dragPx: CGFloat = 0
    @State private var hoverId: String?
    @State private var dropTargeted = false
    /// 끌고 오는 손의 높이. 그 아래 빈 시간을 밝힌다.
    @State private var dropY: CGFloat?
    /// 끄는 알약이 지금 붙어 있는 자석 자리(시작 시각). 바뀌는 순간 손끝에 딸깍.
    @State private var magnetHour: Double?
    /// 가리키고 있는 빈 시간, 눌러서 열어 둔 빈 시간.
    @State private var hoverGap: String?
    @State private var openGap: String?
    /// 빈 시간을 훑어 범위를 그리는 중.
    @State private var scrub: GapScrub?
    /// 훑어 **잡아 둔** 시간. 손을 떼어도 남아서 양끝을 다시 끌 수 있다 (→ GapSelection).
    @State private var selection: GapSelection?
    /// 잡아 둔 시간을 통째로 옮기는 중 — 끌기 시작할 때의 시작 시각.
    @State private var moveOrigin: Double?
    /// 채우기 판의 찾는 말. 하나 넣어 판이 다시 열려도 남는다 — 같은 말로 이어서 고른다.
    @State private var gapSearch = ""
    /// 하나 넣은 뒤 **이 시각을 품은 빈 시간**에서 판을 다시 연다.
    ///
    /// 빈 시간은 알약이 하나 들어서는 순간 둘로 갈라지고 이름(`Connector.id`)이 바뀐다.
    /// 열어 둔 이름만 붙들고 있으면 판이 툭 닫혀서, 다섯 시간을 셋으로 채우려면 세 번 열어야 했다.
    /// 이름 대신 **시각**을 붙들었다가 새로 그려진 빈 시간에서 그 시각을 찾아 다시 연다.
    @State private var reopenGapAt: Double?
    /// 방금 놓인 알약. 한 번 부풀었다 내려앉는다 (→ LandingTracker).
    @State private var landing = LandingTracker()
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
        // 다른 날로 넘어가면 잡아 둔 시간은 놓는다 — 그 빈자리의 경계였다.
        .onChange(of: date) { _, _ in selection = nil; openGap = nil }
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
        // 나란히 세우는 판단은 **시각만 본다** — 화면에서 몇 pt 스치는 것은 겹친 것이 아니다.
        let lanes = Self.lanes(laned)
        let order = Dictionary(uniqueKeysWithValues: segs.sorted { $0.start < $1.start }
            .enumerated().map { ($1.id, $0) })
        let conns = connectors(segs, laned: laned, lanes: lanes)

        return GeometryReader { geo in
            let trackWidth = max(40, geo.size.width - Self.gutter)
            ZStack(alignment: .topLeading) {
                hourGrid(width: geo.size.width)

                // **하루는 한 줄이다.** 알약과 알약 사이의 빈 시간은 앞 일정의 색에서 다음 일정의 색으로
                // 번지는 선으로 잇는다. 하루의 처음과 끝은 투명하게 스러진다.
                // 오늘이면 지금보다 위(이미 흘러간 빈 시간)는 흐리게 — 분마다 선이 내려간다.
                if isToday {
                    TimelineView(.everyMinute) { ctx in
                        connectorLayer(conns, trackWidth: trackWidth, now: DayTimelineRow.hourOfDay(ctx.date))
                    }
                } else {
                    connectorLayer(conns, trackWidth: trackWidth, now: nil)
                }

                ForEach(segs) { seg in
                    if let frame = frame(for: seg, lanes: lanes, laned: laned, trackWidth: trackWidth) {
                        let i = order[seg.id] ?? 0
                        segmentView(seg, size: frame.size)
                            .offset(x: Self.gutter + frame.minX + (seg.id == dragId ? dragPx : 0),
                                    y: frame.minY + (seg.id == dragId ? dragPy : 0))
                            .zIndex(seg.id == dragId ? 3 : (seg.isGhost ? 0 : (seg.isNested || seg.isFlexible ? 2 : 1)))
                            // 하루가 설 때 위에서부터 하나씩 톡톡 튀어 오른다.
                            .scaleEffect(drawn ? 1 : 0.92, anchor: .leading)
                            .opacity(drawn ? 1 : 0)
                            .animation(reduceMotion ? nil : Motion.squish.delay(Double(min(i, 16)) * 0.03), value: drawn)
                            // 놓는 순간 15분 격자로 **통** 붙는다. 끄는 동안에는 손을 바로 따른다.
                            .animation(seg.id == dragId ? nil : Motion.squish, value: frame)
                            .transition(.pop)
                            .landingBounce(landing.landed == seg.id)
                    }
                }
                .animation(Motion.squish, value: segs.map(\.id))
                // 새로 생긴 알약 하나가 그 자리에서 한 번 출렁인다 — 내가 여기 놓았다는 표시.
                .onChange(of: segs.map(\.id)) { _, ids in
                    guard landing.update(ids) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { landing.clear() }
                }
                .onAppear { _ = landing.update(segs.map(\.id)) }
                // **연달아 채우기.** 하나 넣으면 빈 시간이 둘로 갈라지고 이름이 바뀐다.
                // 붙들어 둔 시각(→ reopenGapAt)을 품은 새 빈 시간을 찾아 판을 도로 연다.
                // 방금 닫힌 팝오버와 한 판에 겹치면 둘 다 안 뜨므로 한 박자 뒤에 연다.
                .onChange(of: segs.map(\.id)) { _, _ in
                    guard let at = reopenGapAt else { return }
                    reopenGapAt = nil
                    guard let next = conns.first(where: {
                        at >= $0.startHour - 1e-6 && at < $0.endHour - 1e-6 && $0.hours >= 0.25
                    }) else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { openGap = next.id }
                }

                if isToday { nowLine }

                selectionLayer(trackWidth: trackWidth,
                               trackHeight: CGFloat(window.span) * Self.hourHeight)
            }
            .coordinateSpace(.named(Self.trackSpace))
        }
        .frame(height: CGFloat(window.span) * Self.hourHeight + Self.minRowHeight / 2)
        // 잡아 둔 시간은 Esc 로 놓는다.
        .onExitCommand { if selection != nil { selection = nil; moveOrigin = nil } }
        .contentShape(Rectangle())
        // 할 일 카드를 하루 위에 바로 떨어뜨린다 — 떨어뜨린 높이가 곧 시작 시각이다.
        // 끄는 동안 손이 어디에 있는지 알아야 그 빈 시간을 밝힐 수 있어서, 위치를 계속 알려 주는
        // 받는 자리(`DropDelegate`)를 쓴다.
        .onDrop(of: [.plainText], delegate: DayDropDelegate(
            canPlan: canPlan,
            targeted: $dropTargeted,
            location: $dropY,
            onDrop: { token, y in
                onDropBacklog(token, dropHour(atY: y, in: conns, token: token))
            }))
        .overlay {
            RoundedRectangle.soft(Corner.panel)
                .strokeBorder(Color.accentColor.opacity(0.5),
                              style: StrokeStyle(lineWidth: dropTargeted ? 1.5 : 0, dash: [6, 4]))
                .padding(-6)
                .allowsHitTesting(false)
        }
    }

    // MARK: 빈 시간

    /// 알약과 알약 사이를 잇는 선 한 토막.
    struct Connector: Identifiable {
        let id: String
        let top: CGFloat
        let bottom: CGFloat
        let from: Color
        let to: Color
        /// 빈 시간이 실제로 시작하는 시각 — 앞 일정이 끝나는 때.
        let startHour: Double
        /// 실제로 비어 있는 시간(h). 알약이 최소 키만큼 서서 화면의 길이와는 조금 다르다.
        let hours: Double
        /// 하루의 첫머리·끝머리 — 이어 줄 일정이 없는 쪽은 투명하게 스러진다.
        var fadesTop = false
        var fadesBottom = false

        var endHour: Double { startHour + hours }

        /// 빈 시간의 무게. 길이에 따라 선과 글씨가 달라진다.
        enum Size { case sliver, gap, open }
        var size: Size {
            if hours < 0.5 { return .sliver }     // 30분 미만 — 선만
            if hours < 2 { return .gap }          // 2시간 미만 — 선 + 옅은 글씨
            return .open                          // 2시간 이상 — 점선 + 또렷한 글씨: 쓸 수 있는 큰 자리
        }
    }

    /// **빈 시간을 훑어 그리는 중의 범위.**
    ///
    /// 붙잡은 곳(`anchor`)에서 지금 손이 있는 곳(`current`)까지 — 위로 올려 그어도 되게
    /// 두 시각을 그때그때 앞뒤로 세운다. 15분 격자에 붙이는 것은 손을 움직이는 쪽에서 한다.
    struct GapScrub {
        let gapId: String
        let anchor: Double
        var current: Double

        var start: Double { min(anchor, current) }
        var end: Double { max(anchor, current) }
        var hours: Double { end - start }
        /// 한 칸(15분)도 안 그었으면 그린 것으로 치지 않는다 — 그건 누른 것이다.
        var isDrawn: Bool { hours >= 0.25 - 1e-6 }
    }

    /// **훑어 잡아 둔 시간.**
    ///
    /// 손을 떼는 즉시 편집창을 열어 버리면 그은 범위를 다시 볼 수가 없다. 그래서 그은 자리가
    /// 그대로 남고, 위·아래 끝을 끌어 시각을 다듬고, 가운데를 끌어 통째로 옮긴 다음
    /// 그때 무엇을 넣을지 고른다 — 캘린더에서 빈 칸을 훑어 일정을 잡는 것과 같은 결이다.
    struct GapSelection {
        let gapId: String
        /// 이 빈자리의 경계. 잡은 시간은 여기서 못 벗어난다 — 앞뒤 일정 위로 넘치지 않는다.
        let low: Double
        let high: Double
        var start: Double
        var end: Double

        var hours: Double { max(0, end - start) }
        /// 가장 짧은 한 칸. 양끝이 이보다 가까워지지 않는다.
        static let minHours = 0.25
    }

    /// 등뼈 위에 서는 일정 사이의 빈자리를 찾는다.
    ///
    /// **등뼈 위에 그려지는 것과 같은 목록을 본다** (→ `frame(for:)`의 같은 규칙). 옆 칸으로
    /// 밀려난 겹친 일정과 루틴 위에 얹힌 일정만 빠진다 — 그것들은 이미 등뼈 위의 어떤 일정과
    /// 같은 시각에 있어 빈 시간이 아니다.
    ///
    /// ⚠️ 한때 칸 나누기 목록(`laned`)만 봤다가 **끼니를 빈 시간으로 셌다.** 시간이 유연한
    ///    일정은 칸을 나누지 않을 뿐(다른 일정 위에 얹힐 수 있어서) 혼자 서 있으면 등뼈 위에
    ///    그려진다. 07–08시 식사와 09시 회사 사이가 "빈 시간 2시간"으로 적혔던 까닭이다.
    private func connectors(_ segs: [TimeSegment], laned: [TimeSegment],
                            lanes: [String: Lane]) -> [Connector] {
        let spine = segs
            .filter { seg in
                guard !seg.isGhost, !seg.isNested else { return false }
                // 다른 일정 위에 겹친 유연한 일정(끼니)은 오른쪽에 얹혀 등뼈를 비켜선다.
                if seg.isFlexible,
                   laned.contains(where: { $0.start < seg.end - 1e-6 && seg.start < $0.end - 1e-6 }) {
                    return false
                }
                return (lanes[seg.id]?.index ?? 0) == 0
            }
            .compactMap { seg -> (top: CGFloat, bottom: CGFloat, seg: TimeSegment)? in
                guard let vis = window.clamp(seg.start, seg.end) else { return nil }
                let top = y(vis.start)
                return (top, top + max(Self.minRowHeight, y(vis.end) - y(vis.start) - 3), seg)
            }
            .sorted { $0.top < $1.top }

        let dayTop = y(window.start)
        let dayBottom = y(window.end)
        guard let first = spine.first else {
            return [Connector(id: "empty", top: dayTop, bottom: dayBottom,
                              from: .secondary, to: .secondary,
                              startHour: window.start, hours: window.span,
                              fadesTop: true, fadesBottom: true)]
        }

        var result: [Connector] = []
        // 하루의 첫머리 — 첫 일정 색이 위에서부터 차오른다.
        if first.top > dayTop + 2 {
            result.append(Connector(id: "head", top: dayTop, bottom: first.top,
                                    from: first.seg.color, to: first.seg.color,
                                    startHour: window.start,
                                    hours: max(0, first.seg.start - window.start), fadesTop: true))
        }
        var reach = first.bottom
        var reachColor = first.seg.color
        var reachHour = first.seg.end
        for item in spine.dropFirst() {
            if item.top > reach + 2 {
                result.append(Connector(id: "gap:\(item.seg.id)", top: reach, bottom: item.top,
                                        from: reachColor, to: item.seg.color,
                                        startHour: reachHour,
                                        hours: max(0, item.seg.start - reachHour)))
            }
            if item.bottom >= reach {
                reach = item.bottom
                reachColor = item.seg.color
            }
            reachHour = max(reachHour, item.seg.end)
        }
        // 하루의 끝머리 — 마지막 일정 색이 아래로 스러진다.
        if dayBottom > reach + 2 {
            result.append(Connector(id: "tail", top: reach, bottom: dayBottom,
                                    from: reachColor, to: reachColor,
                                    startHour: reachHour,
                                    hours: max(0, window.end - reachHour), fadesBottom: true))
        }
        return result
    }

    private func connectorLayer(_ conns: [Connector], trackWidth: CGFloat, now: Double?) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(conns) { c in
                connectorView(c, trackWidth: trackWidth, now: now)
            }
        }
        .animation(Motion.squish, value: conns.map(\.id))
    }

    /// 지금 끄는 손이 이 빈 시간 위에 있는가.
    private func isAimed(_ c: Connector) -> Bool {
        guard dropTargeted, let dropY else { return false }
        return dropY >= c.top && dropY <= c.bottom
    }

    /// 떨어뜨린 높이의 시각. 빈 시간 안에 놓았으면 그 빈 시간 밖으로 삐져나가지 않게 붙인다 —
    /// 앞 일정 끝에 걸쳐 놓아도 앞 일정과 겹치지 않는다.
    private func dropHour(atY y: CGFloat, in conns: [Connector], token: String? = nil) -> Double {
        let raw = hour(atY: y)
        // 무엇을 끌어왔는지 알면 그 길이로 자석을 건다 — 들어가는 빈 시간 **안에** 가둔다.
        if let token, let duration = duration(of: token),
           let snapped = magnetStart(proposed: raw, duration: duration, excluding: nil) {
            return snapped
        }
        guard let gap = conns.first(where: { y >= $0.top && y <= $0.bottom }), gap.hours > 0 else { return raw }
        return min(max(raw, (gap.startHour * 4).rounded(.up) / 4), max(gap.startHour, gap.endHour - 0.25))
    }

    // MARK: 자석

    /// 자석이 끌어당기는 거리. 이만큼 안에 들어오면 빈 시간의 앞머리·끝머리로 붙는다.
    private static let magnetReach = 0.34   // 약 20분

    /// 끌어 온 것의 길이. 할 일은 단계까지 합친 시간, 블록은 제 길이. 모르면 nil(자석 없음).
    private func duration(of token: String) -> Double? {
        if let c = candidates.first(where: { $0.token == token }) { return c.hours }
        if let b = PlanBlock.matching(dragToken: token, in: blocks) { return b.durationHours }
        return nil
    }

    /// 하루에서 비어 있는 시간들 (시각 단위). 끄는 중인 알약은 뺀다 — 제자리가 빈 시간이 된다.
    private func freeIntervals(excluding dragged: TimeSegment?) -> [(start: Double, end: Double)] {
        let busy = segments
            .filter { !$0.isNested && !$0.isGhost && $0.id != dragged?.id }
            // 자정을 넘겨 둘로 나뉜 잠은 같은 출처라 둘 다 뺀다 (→ SegmentSource.key).
            .filter { dragged == nil || $0.source.key != dragged!.source.key }
            .map { ($0.start, $0.end) }
            .sorted { $0.0 < $1.0 }
        var free: [(start: Double, end: Double)] = []
        var cursor = window.start
        for (a, b) in busy {
            if a > cursor + 1e-6 { free.append((cursor, min(a, window.end))) }
            cursor = max(cursor, b)
        }
        if window.end > cursor + 1e-6 { free.append((cursor, window.end)) }
        return free
    }

    /// **자석 자리.**
    ///
    /// ① 놓으려는 자리를 품은 빈 시간에 이 길이가 들어가면 **그 안에 가둔다** — 한 시간 빈자리에
    ///    30분짜리를 놓으면 어디를 짚든 그 사이에 톡 들어가고, 뒤 일정 위로 넘치지 않는다.
    /// ② 그렇지 않으면 가까운(20분 안) 빈 시간의 앞머리나 끝머리로 붙는다.
    /// ③ 둘 다 아니면 자석은 없다 — 사람이 짚은 자리를 그대로 둔다.
    private func magnetStart(proposed: Double, duration: Double, excluding dragged: TimeSegment?) -> Double? {
        let gaps = freeIntervals(excluding: dragged)
        if let holding = gaps.first(where: { proposed >= $0.start - 1e-6 && proposed < $0.end }),
           holding.end - holding.start >= duration - 1e-6 {
            return fit(proposed, in: holding, duration: duration)
        }
        var best: (distance: Double, gap: (start: Double, end: Double), at: Double)?
        for gap in gaps where gap.end - gap.start >= duration - 1e-6 {
            for candidate in [gap.start, gap.end - duration] {
                let d = abs(candidate - proposed)
                guard d <= Self.magnetReach else { continue }
                if best == nil || d < best!.distance { best = (d, gap, candidate) }
            }
        }
        return best.map { fit($0.at, in: $0.gap, duration: duration) }
    }

    /// 15분 격자에 붙이되, 빈 시간 밖으로는 나가지 않게 가둔다.
    /// (앞 일정이 9:50에 끝나도 블록은 10:00에 서고, 뒤 일정 시작을 넘지 않는다.)
    private func fit(_ hour: Double, in gap: (start: Double, end: Double), duration: Double) -> Double {
        let low = (gap.start * 4).rounded(.up) / 4
        let high = ((gap.end - duration) * 4).rounded(.down) / 4
        let snapped = (hour * 4).rounded() / 4
        return min(max(snapped, low), max(low, high))
    }

    /// 빈 시간 한 토막.
    ///
    /// - 길이: 30분 미만은 가는 선만, 2시간 미만은 선과 옅은 글씨, 2시간 이상은 점선과 또렷한 글씨.
    /// - 지난 시간: 오늘이면 지금 선 위쪽은 흐리게 — 이미 흘러가 쓸 수 없는 빈 시간이다.
    /// - 누르면: 그 길이에 들어가는 할 일을 고르거나 새 블록을 그 시각에 세운다 (→ GapFillPopover).
    /// - 끄는 중: 할 일을 끌고 오면 빈 시간들이 밝아지고, 손 아래 빈 시간은 "여기 놓으면 14:00".
    @ViewBuilder
    private func connectorView(_ c: Connector, trackWidth: CGFloat, now: Double?) -> some View {
        let height = max(0, c.bottom - c.top)
        let tuck: CGFloat = 12
        let aimed = isAimed(c)
        let glowing = dropTargeted && c.hours >= 0.25
        let hovered = hoverGap == c.id
        let lineWidth: CGFloat = glowing || hovered ? 6 : (c.size == .sliver ? 3 : 4)
        let strength: Double = aimed ? 1 : (glowing || hovered ? 0.8 : (c.size == .sliver ? 0.4 : 0.55))
        // 지금 선이 이 토막의 어디쯤을 지나는가 (0 = 위끝, 1 = 아래끝). 오늘이 아니면 없다.
        let visualTopHour = window.start + Double(c.top / Self.hourHeight)
        let visualSpan = max(0.01, Double(height / Self.hourHeight))
        let pastFraction = now.map { min(1, max(0, ($0 - visualTopHour) / visualSpan)) }
        let isPast = (pastFraction ?? 0) >= 1
        let gradient = LinearGradient(
            stops: [
                .init(color: c.from.opacity(c.fadesTop ? 0 : strength), location: 0),
                .init(color: c.from.opacity(c.fadesTop ? strength * 0.45 : strength * 0.75), location: 0.25),
                .init(color: c.to.opacity(c.fadesBottom ? strength * 0.45 : strength * 0.75), location: 0.75),
                .init(color: c.to.opacity(c.fadesBottom ? 0 : strength), location: 1),
            ],
            startPoint: .top, endPoint: .bottom)
        let x = Self.gutter + Self.pillWidth / 2

        ZStack(alignment: .topLeading) {
            // 손이 겨냥한 빈 시간은 칸 전체가 옅게 물든다.
            if aimed {
                RoundedRectangle.soft(Corner.card)
                    .fill(Color.accentColor.opacity(0.08))
                    .overlay(RoundedRectangle.soft(Corner.card)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
                    .frame(width: trackWidth, height: max(20, height - 6))
                    .offset(x: Self.gutter - 4, y: c.top + 3)
                    .transition(.opacity)
            }

            // 훑어 그은 만큼이 밝아진다 — 몇 시부터 몇 시까지를 손이 그리는 동안 읽는다.
            if let sc = scrub, sc.gapId == c.id, sc.isDrawn {
                let top = y(sc.start)
                RoundedRectangle.soft(Corner.card)
                    .fill(Color.accentColor.opacity(0.16))
                    .overlay(RoundedRectangle.soft(Corner.card)
                        .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5))
                    .frame(width: trackWidth, height: max(8, y(sc.end) - top))
                    .offset(x: Self.gutter - 4, y: top)

                Text("\(formatHour(sc.start)) – \(formatHour(sc.end)) · \(formatDuration(sc.hours))")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .offset(x: Self.gutter + Self.pillWidth + 10,
                            y: top + max(0, y(sc.end) - top) / 2 - 9)
                    .contentTransition(.numericText())
            }

            Group {
                if c.size == .open && !glowing {
                    // 큰 빈자리는 점선 — 꽉 찬 선보다 '비어 있음'이 먼저 읽힌다.
                    Path { p in
                        p.move(to: CGPoint(x: lineWidth / 2, y: 0))
                        p.addLine(to: CGPoint(x: lineWidth / 2, y: height + tuck * 2))
                    }
                    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [0.1, 8]))
                } else {
                    Capsule().fill(gradient)
                }
            }
            .frame(width: lineWidth, height: height + tuck * 2)
            // 지난 부분은 흐리게.
            .mask {
                if let f = pastFraction {
                    let at = (CGFloat(f) * height + tuck) / (height + tuck * 2)
                    LinearGradient(stops: [.init(color: .black.opacity(0.3), location: 0),
                                           .init(color: .black.opacity(0.3), location: at),
                                           .init(color: .black, location: at),
                                           .init(color: .black, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                } else {
                    Rectangle()
                }
            }
            .shadow(color: aimed ? Color.accentColor.opacity(0.5) : .clear, radius: 6)
            .offset(x: x - lineWidth / 2, y: c.top - tuck)

            gapLabel(c, height: height, aimed: aimed, hovered: hovered, isPast: isPast)
        }
        .animation(Motion.squish, value: aimed)
        .animation(Motion.squish, value: glowing)
        .animation(Motion.squish, value: hovered)
        .allowsHitTesting(false)

        // 누르는 자리 — 빈 시간 전체. 선 아래 깔려 알약보다 뒤에 있다.
        //
        // 여기서 할 수 있는 일은 둘이다.
        //  - **누르면** 채우기 판이 열린다 (→ GapFillPopover).
        //  - **위아래로 훑으면** 그은 만큼이 밝아지고, 손을 떼면 그 시각·그 길이로 새 블록을 세운다.
        //    다섯 시간 빈자리에서 "두 시간만 떼어 쓰겠다"를 말하는 가장 짧은 길이다.
        //
        // ⚠️ **이미 흘러간 빈 시간도 막지 않는다.** 한때 `!isPast`로 걸어 두었는데,
        //    정작 할 일 카드를 끌어다 놓는 길(→ DayDropDelegate)은 지난 시각을 받고 있었다.
        //    같은 자리가 끌면 되고 누르면 안 되는 셈이었다. 무엇보다 지난 시간에 적는 일이
        //    실제로 있다 — 오전에 한 것을 점심에 적어 두고 그날의 계획에서 체크한다.
        //    지나간 자리는 흐리게 그려서 '계획'이 아니라는 것만 눈으로 말한다.
        if canPlan, c.hours >= 0.25, height >= 16 {
            Color.clear
                .frame(width: trackWidth, height: height)
                .contentShape(Rectangle())
                .offset(x: Self.gutter, y: c.top)
                .onHover { hoverGap = $0 ? c.id : (hoverGap == c.id ? nil : hoverGap) }
                .pointingCursor()
                .onTapGesture {
                    // 잡아 둔 시간이 있으면 먼저 놓는다 — 빈 자리를 누르는 건 '그만두기'다.
                    if selection != nil { selection = nil; moveOrigin = nil; return }
                    gapSearch = ""
                    openGap = c.id
                }
                .gesture(
                    DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.trackSpace))
                        .onChanged { v in
                            let at = gapHour(v.location.y, in: c)
                            if scrub?.gapId == c.id {
                                if scrub?.current != at { Haptic.tick() }
                                scrub?.current = at
                            } else {
                                openGap = nil
                                selection = nil
                                scrub = GapScrub(gapId: c.id,
                                                 anchor: gapHour(v.startLocation.y, in: c),
                                                 current: at)
                            }
                        }
                        .onEnded { _ in
                            guard let s = scrub, s.gapId == c.id else { return }
                            scrub = nil
                            // 한 칸도 못 그었으면 훑은 게 아니라 누른 것이다 — 판을 연다.
                            guard s.isDrawn else { gapSearch = ""; openGap = c.id; return }
                            Haptic.snap()
                            // 편집창을 바로 열지 않는다. 그은 자리를 남겨 두고 양끝을 다듬게 한다.
                            gapSearch = ""
                            moveOrigin = nil
                            selection = GapSelection(gapId: c.id,
                                                     low: gapLow(c), high: gapHigh(c),
                                                     start: s.start, end: s.end)
                        }
                )
                .popover(isPresented: Binding(get: { openGap == c.id },
                                              set: { if !$0 { openGap = nil; reopenGapAt = nil } }),
                         arrowEdge: .trailing) {
                    GapFillPopover(startHour: max(c.startHour, window.start), hours: c.hours,
                                   candidates: candidates, search: $gapSearch,
                                   nowHour: now) { token, hour, length in
                        // 판은 닫지 않는다. 알약이 하나 서면 빈 시간이 갈라지므로, 그 **뒤쪽**을
                        // 품은 새 빈 시간에서 판을 도로 연다 (→ reopenGapAt).
                        openGap = nil
                        reopenGapAt = hour + (length ?? duration(of: token) ?? 0) + 1e-3
                        onFillGap(token, hour, length)
                    } onAddBlock: { hour, hours in
                        openGap = nil
                        reopenGapAt = nil
                        onAddBlock(hour, hours)
                    }
                }
        }
    }

    // MARK: 잡아 둔 시간

    private enum SelectionEdge { case top, bottom }

    /// 잡아 둔 시간 — 몸통, 양끝 손잡이, 그리고 무엇을 넣을지 고르는 판.
    @ViewBuilder
    private func selectionLayer(trackWidth: CGFloat, trackHeight: CGFloat) -> some View {
        if let sel = selection {
            let top = y(sel.start)
            let height = max(16, y(sel.end) - top)

            // 몸통 — 끌면 통째로 옮긴다.
            RoundedRectangle.soft(Corner.card)
                .fill(Color.accentColor.opacity(0.18))
                .overlay(RoundedRectangle.soft(Corner.card)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5))
                .frame(width: trackWidth, height: height)
                .offset(x: Self.gutter - 4, y: top)
                .hoverCursor(.openHand)
                .gesture(moveGesture(sel))
                .zIndex(18)

            Text("\(formatHour(sel.start)) – \(formatHour(sel.end)) · \(formatDuration(sel.hours))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText())
                .offset(x: Self.gutter + 6, y: top + max(0, height / 2 - 8))
                .allowsHitTesting(false)
                .zIndex(19)

            selectionHandle(sel, edge: .top, trackWidth: trackWidth, atY: top, span: height)
            selectionHandle(sel, edge: .bottom, trackWidth: trackWidth, atY: top + height, span: height)

            selectionPanel(top: top, trackHeight: trackHeight, trackWidth: trackWidth, sel: sel)
        }
    }

    /// 위·아래 끝의 손잡이. 잡는 자리는 보이는 것보다 넉넉하게 둔다 —
    /// 5pt 막대를 정확히 짚게 하면 늘리려다 몸통을 끌어 옮기게 된다.
    private func selectionHandle(_ sel: GapSelection, edge: SelectionEdge,
                                 trackWidth: CGFloat, atY: CGFloat, span: CGFloat) -> some View {
        // 15분짜리를 잡으면 칸이 12pt다. 손잡이 두 개가 넉넉하게 겹쳐 아래쪽 하나만 잡히던 것을,
        // 잡는 자리를 칸 절반으로 줄여 위·아래를 갈라 준다.
        let grab: CGFloat = min(11, max(4, span / 2))
        return Capsule()
            .fill(Color.accentColor)
            .frame(width: 42, height: 5)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .frame(width: trackWidth, height: grab * 2)
            .contentShape(Rectangle())
            .offset(x: Self.gutter - 4, y: atY - grab)
            .hoverCursor(.resizeUpDown)
            .gesture(edgeGesture(sel, edge: edge))
            .zIndex(19)
    }

    /// 무엇을 넣을지 고르는 판. **팝오버가 아니라 시간표 위에 얹은 카드다** —
    /// 팝오버였다면 손잡이를 짚는 첫 클릭이 판을 닫는 데 쓰여 양끝을 못 끈다.
    private func selectionPanel(top: CGFloat, trackHeight: CGFloat,
                                trackWidth: CGFloat, sel: GapSelection) -> some View {
        // 알약 오른쪽에 세우되, 오른쪽 판을 덮을 만큼 넘치면 왼쪽으로 당긴다.
        let width: CGFloat = 300
        let x = min(Self.gutter + Self.pillWidth + 14, max(0, trackWidth + Self.gutter - width))
        return GapFillPopover(
            startHour: sel.start, hours: sel.hours,
            candidates: candidates, search: $gapSearch,
            adjustable: false,
            onPick: { token, hour, length in
                selection = nil
                onFillGap(token, hour, length)
            },
            onAddBlock: { hour, hours in
                selection = nil
                onDrawBlock(hour, hours)
            },
            onCancel: { selection = nil })
        .background(.regularMaterial, in: .soft(Corner.panel))
        .overlay(RoundedRectangle.soft(Corner.panel)
            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        // 판이 하루 밖으로 흘러내리지 않게 위아래로 가둔다.
        .offset(x: x, y: min(max(0, top - 8), max(0, trackHeight - 340)))
        .zIndex(30)
    }

    /// 한쪽 끝을 끈다. 반대쪽 끝은 그 자리에 있고, 둘은 15분보다 가까워지지 않는다.
    private func edgeGesture(_ sel: GapSelection, edge: SelectionEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.trackSpace))
            .onChanged { v in
                guard var s = selection, s.gapId == sel.gapId else { return }
                let at = min(max(trackHour(v.location.y), s.low), s.high)
                switch edge {
                case .top:    s.start = min(at, s.end - GapSelection.minHours)
                case .bottom: s.end = max(at, s.start + GapSelection.minHours)
                }
                guard s.start != selection?.start || s.end != selection?.end else { return }
                Haptic.tick()
                selection = s
            }
            .onEnded { _ in Haptic.snap() }
    }

    /// 몸통을 끌어 통째로 옮긴다. 길이는 그대로, 빈자리 밖으로는 안 나간다.
    private func moveGesture(_ sel: GapSelection) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.trackSpace))
            .onChanged { v in
                guard var s = selection, s.gapId == sel.gapId else { return }
                let origin = moveOrigin ?? s.start
                if moveOrigin == nil { moveOrigin = s.start }
                let delta = (Double(v.translation.height / Self.hourHeight) * 4).rounded() / 4
                let span = s.hours
                let start = min(max(origin + delta, s.low), max(s.low, s.high - span))
                guard start != s.start else { return }
                Haptic.tick()
                s.start = start
                s.end = start + span
                selection = s
            }
            .onEnded { _ in moveOrigin = nil; Haptic.snap() }
    }

    /// 빈자리의 앞머리·끝 (15분 격자). 잡은 시간은 이 사이를 못 벗어난다.
    private func gapLow(_ c: Connector) -> Double { (max(c.startHour, window.start) * 4).rounded(.up) / 4 }
    private func gapHigh(_ c: Connector) -> Double { (min(c.endHour, window.end) * 4).rounded(.down) / 4 }

    /// 하루 시간표의 자 위 높이 → 시각. 15분 격자에 붙이고, 그 빈 시간 밖으로는 못 나간다.
    private func gapHour(_ y: CGFloat, in c: Connector) -> Double {
        let low = gapLow(c), high = gapHigh(c)
        return min(max(trackHour(y), low), max(low, high))
    }

    /// 하루 시간표의 자 위 높이 → 15분 격자에 붙인 시각.
    private func trackHour(_ y: CGFloat) -> Double {
        let raw = window.start + Double(y / Self.hourHeight)
        return (raw * 4).rounded() / 4
    }

    @ViewBuilder
    private func gapLabel(_ c: Connector, height: CGFloat, aimed: Bool, hovered: Bool, isPast: Bool) -> some View {
        let scrubbing = scrub?.gapId == c.id && scrub?.isDrawn == true
        let showsLabel = !scrubbing && (aimed || (c.size != .sliver && height >= 30) || (hovered && height >= 20))
        if showsLabel {
            let text: String = {
                if aimed, let dropY {
                    return String(localized: "여기 놓으면 \(formatHour(dropHourPreview(atY: dropY, gap: c)))")
                }
                if hovered { return String(localized: "빈 시간 \(formatDuration(c.hours)) · 눌러서 채우기") }
                return String(localized: "빈 시간 \(formatDuration(c.hours))")
            }()
            Text(text)
                .font(.system(size: 10.5, weight: aimed || c.size == .open ? .semibold : .medium))
                .foregroundStyle(aimed || hovered ? Color.accentColor : (c.size == .open ? Color.secondary : Color(nsColor: .tertiaryLabelColor)))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, aimed || hovered ? 7 : 0)
                .padding(.vertical, aimed || hovered ? 2 : 0)
                .background(Color.accentColor.opacity(aimed || hovered ? 0.12 : 0), in: Capsule())
                // 지나간 자리는 흐리다. 다만 손이 그 위에 올라와 있으면 또렷하게 —
                // 채울 수 있는 자리라고 말해 놓고 글씨가 흐리면 누를 수 있는 줄 모른다.
                .opacity(isPast && !aimed && !hovered ? 0.45 : 1)
                .offset(x: Self.gutter + Self.pillWidth + 10,
                        y: aimed ? max(c.top, min(c.bottom - 18, (dropY ?? 0) - 9)) : c.top + height / 2 - 8)
                .contentTransition(.numericText())
                .transition(.opacity)
        }
    }

    private func dropHourPreview(atY y: CGFloat, gap: Connector) -> Double {
        let raw = hour(atY: y)
        // 끄는 동안에는 무엇을 끄는지 모른다 — 앞머리 자석만 미리 보여 준다.
        let head = (gap.startHour * 4).rounded(.up) / 4
        if abs(raw - head) <= Self.magnetReach { return head }
        return min(max(raw, head), max(gap.startHour, gap.endHour - 0.25))
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
                    let title = Text(seg.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .strikethrough(done || seg.isGhost, color: .secondary)
                        .foregroundStyle(done || seg.isGhost ? .secondary : .primary)
                    let when = Text(timeRange(seg))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Group {
                        // 낮은 줄(30분 안팎)에서는 시각과 제목을 한 줄에 나란히 — 두 줄을 욱여넣으면 잘린다.
                        if size.height >= 38 {
                            VStack(alignment: .leading, spacing: 1) {
                                if size.width >= Self.pillWidth + 110 { when.lineLimit(1) }
                                title.lineLimit(size.height >= 62 ? 2 : 1)
                            }
                            .padding(.top, 3)
                        } else {
                            HStack(spacing: 6) {
                                title.lineLimit(1)
                                if size.width >= Self.pillWidth + 150 { when.lineLimit(1) }
                            }
                            .frame(height: max(Self.minRowHeight, size.height), alignment: .center)
                        }
                    }
                    .padding(.trailing, showsCheck ? 30 : 4)
                }
                Spacer(minLength: 0)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(alignment: .topLeading) {
                // 가리키면 줄 전체가 그 색으로 옅게 물든다 — 무엇을 잡으려는지가 손끝에서 읽힌다.
                // 알약과 **같은 키**로 물든다. 키를 줄여 두었더니 긴 잠(8시간)에서는 머리만 물들어
                // 알약이 칠 밖으로 삐져나와 보였다.
                RoundedRectangle.soft(Corner.card)
                    .fill(seg.color.opacity(hovering || dragging ? 0.09 : 0))
                    .frame(height: max(Self.minRowHeight, size.height) + 8)
                    .padding(.leading, -5)
                    .offset(y: -4)
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
                        // 끄는 동안에는 시간표 판이 이웃 판들 위로 올라간다 — 손을 따라 나간 알약이
                        // 옆·아래 판에 **반쯤 가려 끼는** 것을 막는다. 계획 블록만이 아니라
                        // 루틴·끼니를 끌 때도 마찬가지다.
                        zones?.isDragging = true
                        NSCursor.closedHand.set()
                        // 계획 블록은 시간표 밖으로도 끌려 나간다. 받는 판 위면 자석은 끄고 손을 그대로 따른다.
                        if block != nil, let zones {
                            dragPx = v.translation.width
                            let zone = zones.zone(at: v.location)
                            if zones.hovering != zone {
                                withAnimation(Motion.squish) { zones.hovering = zone }
                                if zone != nil { Haptic.tick() }
                            }
                            if zone != nil {
                                magnetHour = nil
                                dragPy = v.translation.height
                                return
                            }
                        }
                        // **자석.** 빈 시간의 앞머리·끝머리 가까이 오면 알약이 그 자리로 톡 빨려 들어간다.
                        let proposed = seg.logicalStart + Double(v.translation.height / Self.hourHeight)
                        if let snapped = magnetStart(proposed: proposed, duration: seg.logicalDuration,
                                                     excluding: seg) {
                            if magnetHour != snapped {
                                magnetHour = snapped
                                Haptic.snap()
                            }
                            withAnimation(Motion.squish) {
                                dragPy = CGFloat(snapped - seg.logicalStart) * Self.hourHeight
                            }
                        } else {
                            magnetHour = nil
                            dragPy = v.translation.height
                        }
                    }
                    .onEnded { v in
                        let snapped = magnetHour
                        let zone = block != nil ? zones?.zone(at: v.location) : nil
                        defer {
                            withAnimation(Motion.squish) {
                                dragId = nil
                                dragPy = 0
                                dragPx = 0
                            }
                            magnetHour = nil
                            zones?.isDragging = false
                            zones?.hovering = nil
                        }
                        guard !seg.isGhost else { return }
                        guard moved(v.translation) else {
                            edit(seg)
                            return
                        }
                        if let zone, let block {
                            switch zone {
                            case .backlog: onReturnToBacklog(block)
                            case .plan: onClearTime(block)
                            }
                            return
                        }
                        let delta = snapped.map { $0 - seg.logicalStart }
                            ?? Double(v.translation.height / Self.hourHeight)
                        actions.move(seg, deltaHours: delta)
                    }
            )

            if showsCheck, let block {
                checkButton(block, color: seg.color)
                    .padding(.top, size.height >= 38 ? 7 : max(0, (size.height - 22) / 2))
                    .padding(.trailing, 2)
            }
        }
        // 받는 판 위에 올라가면 알약이 작게 오므라든다 — 여기 놓으면 시간표에서 빠진다는 뜻.
        .scaleEffect(dragging ? (zones?.hovering != nil ? 0.85 : 1.03) : 1, anchor: .leading)
        .opacity(dragging && zones?.hovering != nil ? 0.9 : 1)
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
        // 낮은 알약에서는 그림도 따라 작아진다.
        let glyphSize: CGFloat = height < 30 ? 11 : 14
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
                        .font(.system(size: glyphSize, weight: .semibold))
                        .symbolEffect(.bounce, value: done)
                } else {
                    Text(g.letter)
                        .font(.system(size: glyphSize, weight: .heavy, design: .rounded))
                        .scaleEffect(done ? 0.9 : 1)
                }
            }
            .foregroundStyle(seg.isGhost || seg.isFlexible ? seg.color : .white)
            .frame(width: Self.pillWidth, height: min(Self.pillWidth, max(Self.minRowHeight, height)))
            .scaleEffect(hovering && !dragging ? 1.05 : 1)
        }
        // 알약도 줄 키를 따른다. 30분짜리가 한 시간처럼 보이면 눈금이 거짓말을 한다.
        .frame(width: Self.pillWidth, height: max(Self.minRowHeight, height))
        .shadow(color: seg.isGhost ? .clear : seg.color.opacity(dragging ? 0.45 : (hovering ? 0.35 : 0.22)),
                radius: dragging ? 9 : (hovering ? 6 : 3), y: dragging ? 5 : 2)
    }

    /// 오른쪽 동그라미 — 누르면 끝낸 것이 되고, 다시 누르면 풀린다 (→ SoftCheck, ReflectionRow의 같은 손짓).
    /// 옆 회고 판과 같은 표시라 어느 쪽에서 눌러도 양쪽이 함께 바뀐다.
    private func checkButton(_ block: PlanBlock, color: Color) -> some View {
        SoftCheck(status: block.reviewStatus, color: color) {
            block.reviewStatus = block.reviewStatus == nil ? .done : nil
            try? context.save()
        }
        .help(block.reviewStatus == nil ? "끝냈다고 표시한다" : "표시를 지운다 (적어 둔 회고는 그대로 남습니다)")
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


// MARK: - 빈 시간 채우기

/// 빈 시간에 넣을 수 있는 할 일 한 줄.
struct GapCandidate: Identifiable {
    let token: String
    let title: String
    let hours: Double
    var id: String { token }
}

/// **빈 시간을 누르면 뜨는 채우기 판.**
///
/// 예전에는 "그 길이에 들어가는 할 일 여섯 개" 목록뿐이었다. 고르면 무조건 빈자리 맨 앞에
/// 꽂히고 판이 닫혔다. 다섯 시간을 세 가지로 채우려면 열고 닫기를 세 번 했고, "세 시부터",
/// "오늘은 한 시간만"을 말할 자리가 아예 없었다. 그래서 판이 세 가지를 더 맡는다.
///
/// - **시작 시각**: 빈자리 안에서 15분씩 앞뒤로. 남은 시간이 그때그때 다시 세어진다.
/// - **길이**: 할 일 제 길이를 그대로 쓰거나, 30분·1시간·…·남은 전부 중에서 고른다.
/// - **찾기**: 목록을 여섯 개로 자르지 않는다. 말로 좁힌다.
///
/// 고르고 나면 판은 **넣은 것 바로 뒤의 빈 시간에서 다시 열린다**
/// (→ DayScheduleView.reopenGapAt). 남은 시간이 줄어드는 걸 보며 이어서 채운다.
struct GapFillPopover: View {
    let startHour: Double
    let hours: Double
    let candidates: [GapCandidate]
    /// 찾는 말. 판이 다시 열려도 남아 있어야 같은 말로 이어 고를 수 있다 — 바깥이 들고 있다.
    @Binding var search: String
    /// 지금 몇 시인가. 오늘이 아니면 nil — 이 빈자리 안에 들면 '지금' 단추가 선다.
    var nowHour: Double? = nil
    /// 시작·길이를 **이 판에서** 정할 수 있는가.
    ///
    /// 훑어 잡아 둔 시간에서 열린 판은 false다. 그 자리는 화면의 손잡이로 정하는데,
    /// 판에도 같은 눈금을 두면 어느 쪽이 참인지 둘이 다툰다.
    var adjustable: Bool = true
    /// (드래그 토큰, 시작 시각, 정한 길이 — nil이면 할 일 제 길이)
    let onPick: (String, Double, Double?) -> Void
    let onAddBlock: (Double, Double) -> Void
    /// 잡아 둔 시간을 놓는다. 손잡이로 잡은 판에만 있다.
    var onCancel: (() -> Void)? = nil

    /// 15분 격자에 맞춘 빈자리의 앞머리·끝.
    private var gapStart: Double { (startHour * 4).rounded(.up) / 4 }
    private var gapEnd: Double { startHour + hours }
    /// 시작 시각을 여기보다 뒤로는 못 민다 — 15분은 남아야 무엇이든 들어간다.
    private var lastStart: Double { max(gapStart, ((gapEnd - 0.25) * 4).rounded(.down) / 4) }

    /// 사람이 민 시작 시각. nil이면 빈자리 앞머리 그대로다.
    ///
    /// `@State private var start = 0`으로 두고 `onAppear`에서 제자리를 찾게 했더니 판이 뜨는
    /// 첫 그림에서 시각과 '남은 시간'이 한 번 튀었다. 기본값은 들고 있지 않고 그때그때 센다.
    @State private var startOverride: Double?
    /// 사람이 정한 길이. nil이면 "할 일 그대로".
    @State private var length: Double?

    private var start: Double { min(max(startOverride ?? gapStart, gapStart), lastStart) }

    /// 15분 격자에 올린 '지금'. 이 빈자리 안에 들 때만 값이 있다.
    ///
    /// 앞머리와 같은 칸이면 내놓지 않는다 — 이미 거기 서 있는데 단추를 두면 눌러도 아무 일이 없다.
    private var snappedNow: Double? {
        guard let n = nowHour else { return nil }
        let at = (n * 4).rounded(.up) / 4
        guard at > gapStart + 1e-6, at <= lastStart + 1e-6 else { return nil }
        return at
    }

    /// 고른 시작 시각부터 빈자리 끝까지 — 여기 들어가는 만큼만 넣을 수 있다.
    private var available: Double { max(0, (gapEnd - start) * 4).rounded(.down) / 4 }

    /// 길이 단추들. 빈자리에 들어가는 것만 세우고, 마지막은 늘 '남은 전부'.
    private var lengthChoices: [Double] {
        var v = [0.5, 1, 1.5, 2, 3].filter { $0 <= available - 0.25 + 1e-6 }
        if available >= 0.25 { v.append(available) }
        return v
    }

    private var shown: [GapCandidate] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return candidates
            .filter { q.isEmpty || $0.title.lowercased().contains(q) }
            // 들어가는 것이 먼저, 그 안에서는 빈자리를 알차게 메우는 긴 것부터.
            .sorted {
                let lhsFits = $0.hours <= available + 1e-6
                let rhsFits = $1.hours <= available + 1e-6
                if lhsFits != rhsFits { return lhsFits }
                if $0.hours != $1.hours { return $0.hours > $1.hours }
                return $0.title < $1.title
            }
    }

    /// 실제로 넣을 길이. nil이면 할 일 제 길이를 그대로 쓴다.
    ///
    /// 길이를 안 정했어도 **통째로는 안 들어가는 할 일**은 남은 만큼만 떼어 넣는다 —
    /// 다섯 시간짜리를 두 시간 빈자리에서 아예 못 고르게 두는 것보다, 두 시간을 떼는 게 낫다.
    private func pickLength(_ item: GapCandidate) -> Double? {
        // 훑어 잡은 시간은 **그 길이가 곧 뜻**이다 — 30분짜리를 두 시간 자리에 잡았으면
        // 두 시간을 쓰겠다는 말이다. 할 일 제 길이로 되돌리지 않는다.
        if !adjustable { return available }
        if let length { return min(length, available) }
        return item.hours > available + 1e-6 ? available : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading

            if adjustable, available >= 0.25 {
                startRow
                lengthRow
            }

            Divider()

            // 몇 개 안 되면 찾을 것도 없다. 다만 찾던 말이 남아 있으면 칸도 남겨야 한다 —
            // 하나씩 넣다 보면 후보가 줄어드는데, 그때 칸만 사라지면 목록이 말없이 걸러진 채 남는다.
            if candidates.count > 6 || !search.isEmpty {
                TextField("할 일 찾기", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
            }

            list

            Divider()

            HStack(spacing: 10) {
                Button {
                    onAddBlock(start, available)
                } label: {
                    Label("이 시간에 새 블록…", systemImage: "plus.circle.fill")
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.borderless)
                .disabled(available < 0.25)

                if let onCancel {
                    Spacer(minLength: 4)
                    Button("취소", action: onCancel)
                        .buttonStyle(.borderless)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        // 판이 다른 빈 시간에서 다시 열렸다 — 앞서 민 시각과 정한 길이는 그 빈자리의 것이었다.
        .onChange(of: startHour) { _, _ in startOverride = nil; length = nil }
    }

    // MARK: 머리

    private var heading: some View {
        VStack(alignment: .leading, spacing: 2) {
            // 빈자리를 누른 판과 훑어 잡은 판은 말이 다르다. 앞엣것은 '비어 있는 만큼'이고
            // 뒤엣것은 '내가 떼어 낸 만큼'이라, 같은 이름으로 부르면 어느 쪽인지 흐려진다.
            Text(adjustable
                 ? String(localized: "빈 시간 \(formatDuration(hours))")
                 : String(localized: "잡은 시간 \(formatDuration(hours))"))
                .font(.headline)
                .contentTransition(.numericText())
            Text("\(formatHour(gapStart)) – \(formatHour(gapEnd))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            if !adjustable {
                Text("양끝을 끌어 시각을 맞춥니다")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 시작 시각 — 15분씩 앞뒤로. 오른쪽에 그 시각부터 남는 시간을 같이 적는다.
    private var startRow: some View {
        HStack(spacing: 6) {
            Text("시작")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            stepButton("chevron.left", enabled: start > gapStart + 1e-6) {
                let at = max(gapStart, ((start - 0.25) * 4).rounded() / 4)
                startOverride = at
                clampLength(after: at)
            }
            Text(formatHour(start))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 52)
            stepButton("chevron.right", enabled: start < lastStart - 1e-6) {
                let at = min(lastStart, ((start + 0.25) * 4).rounded() / 4)
                startOverride = at
                clampLength(after: at)
            }

            if let n = snappedNow {
                Button {
                    Haptic.tick()
                    startOverride = n
                    clampLength(after: n)
                } label: {
                    Text("지금")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.squish)
                .disabled(abs(start - n) < 1e-6)
                .opacity(abs(start - n) < 1e-6 ? 0.4 : 1)
            }

            Spacer(minLength: 4)

            Text("남은 \(formatDuration(available))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .animation(Motion.number, value: start)
    }

    /// 길이 — '할 일 그대로'가 기본이고, 필요할 때만 사람이 정한다.
    private var lengthRow: some View {
        HStack(spacing: 6) {
            Text("길이")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, alignment: .leading)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    lengthChip(nil, label: String(localized: "할 일 그대로"))
                    ForEach(lengthChoices, id: \.self) { v in
                        lengthChip(v, label: v == available && v > 0.5
                                   ? String(localized: "남은 전부")
                                   : formatDuration(v))
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func lengthChip(_ value: Double?, label: String) -> some View {
        let on = length == value
        return Button {
            Haptic.tick()
            withAnimation(Motion.squish) { length = value }
        } label: {
            Text(label)
                .font(.caption.weight(on ? .semibold : .regular))
                .foregroundStyle(on ? Color.white : Color.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(on ? Color.accentColor : Color.primary.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.squish)
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tick()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.06), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.squish)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }

    // MARK: 목록

    @ViewBuilder
    private var list: some View {
        if shown.isEmpty {
            Text(search.isEmpty
                 ? String(localized: "아직 요일을 안 정한 할 일이 없습니다.")
                 : String(localized: "찾는 할 일이 없습니다."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        } else {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(shown) { item in
                        row(item)
                    }
                }
            }
            // 여섯 줄쯤에서 자른다 — 판이 화면을 넘지 않으면서 훑기에는 넉넉하다.
            .frame(maxHeight: 196)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func row(_ item: GapCandidate) -> some View {
        let placed = pickLength(item) ?? item.hours
        // 제 길이대로 다 못 들어간 것 — 몇 시간'만' 떼어 넣는다고 말해 준다.
        let clipped = placed < item.hours - 1e-6

        return Button {
            onPick(item.token, start, pickLength(item))
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                Text(item.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(clipped
                     ? String(localized: "\(formatDuration(placed))만")
                     : formatDuration(placed))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(clipped ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: .soft(Corner.chip))
            .contentShape(Rectangle())
        }
        .buttonStyle(.squish)
        .disabled(available < 0.25)
    }

    /// 시작 시각을 뒤로 밀어 정해 둔 길이가 안 들어가게 되면, 남은 만큼으로 줄인다.
    /// (`available`은 방금 적은 `startOverride`를 되읽으므로, 새 시각을 그대로 받아서 센다.)
    private func clampLength(after newStart: Double) {
        guard let l = length else { return }
        let room = max(0, (gapEnd - newStart) * 4).rounded(.down) / 4
        guard l > room + 1e-6 else { return }
        length = room >= 0.25 ? room : nil
    }
}

/// 하루 시간표의 받는 자리. 끄는 동안 손의 높이를 계속 알려 준다 — `dropDestination`은
/// 놓는 순간에만 위치를 주어서, 끄는 중에 그 아래 빈 시간을 밝힐 수가 없었다.
struct DayDropDelegate: DropDelegate {
    let canPlan: Bool
    @Binding var targeted: Bool
    @Binding var location: CGFloat?
    let onDrop: (String, CGFloat) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        canPlan && info.hasItemsConforming(to: [.plainText])
    }

    func dropEntered(info: DropInfo) {
        withAnimation(Motion.target) { targeted = true }
        location = info.location.y
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        location = info.location.y
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        withAnimation(Motion.target) { targeted = false }
        location = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        let y = info.location.y
        withAnimation(Motion.target) { targeted = false }
        location = nil
        guard canPlan, let provider = info.itemProviders(for: [.plainText]).first else { return false }
        _ = provider.loadTransferable(type: String.self) { result in
            guard case .success(let token) = result else { return }
            DispatchQueue.main.async { onDrop(token, y) }
        }
        return true
    }
}


// MARK: - 시간표 밖으로 끌어내기

/// **일간 시간표 밖의 받는 자리들.** 시간표 안의 알약은 시스템 끌어다 놓기가 아니라 손 제스처로
/// 움직여서(15분 자석·요일 넘기기 없이 제자리 옮기기에 맞춰져 있다) 다른 판의 `dropDestination`이
/// 받지 못한다. 그래서 판들이 제 자리(창 좌표)를 여기 적어 두고, 알약이 손을 뗀 자리를 직접 대 본다.
@MainActor
@Observable
final class DayDragZones {
    enum Zone { case plan, backlog }

    var planFrame: CGRect = .zero
    var backlogFrame: CGRect = .zero
    /// 알약을 끄는 중 — 시간표 판을 오른쪽 판들 위로 올려 알약이 가려지지 않게 한다.
    var isDragging = false
    /// 지금 손 아래에 있는 받는 판.
    var hovering: Zone?

    func zone(at point: CGPoint) -> Zone? {
        if planFrame.insetBy(dx: -6, dy: -6).contains(point) { return .plan }
        if backlogFrame.insetBy(dx: -6, dy: -6).contains(point) { return .backlog }
        return nil
    }
}

extension View {
    /// 이 뷰의 창 좌표 자리를 알린다. 스크롤·크기 바뀜을 따라간다.
    func reportGlobalFrame(_ update: @escaping (CGRect) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { update(proxy.frame(in: .global)) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in update(frame) }
            }
        }
    }
}
