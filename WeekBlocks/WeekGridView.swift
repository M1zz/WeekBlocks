import SwiftUI

/// '이번 주 계획' 컬럼에 시각 순으로 섞어 표시하는 한 항목.
/// '요일별 하루' 타임라인의 보이는 조각을 그대로 따른다:
/// - 고정 루틴이 자정을 넘겨 두 조각이면 각 조각이 따로(occurrenceID로 구분) → 위·아래 두 번 표시.
/// - 유연 쿼터(끼니)는 다른 일정과 겹치지 않는 세션만 자기 시각 위치에 표시.
enum DayPlanItem: Identifiable {
    case fixedRoutine(Routine, occurrenceID: String, atHour: Double, hours: Double)
    case quotaSession(Routine, sessionIndex: Int, atHour: Double)
    case block(PlanBlock, atHour: Double)

    var id: String {
        switch self {
        case .fixedRoutine(_, let oid, _, _): "fixed:\(oid)"
        case .quotaSession(let r, let idx, _): "quota:\(r.name):\(idx)"
        case .block(let b, _): b.dragToken
        }
    }

    /// 이 항목이 하루의 몇 시에 서 있는가. '지금' 선을 어디에 끼울지 여기서 나온다.
    /// 타임라인이 실제로 그린 시작 시각과 같은 값이라, 두 화면의 순서가 어긋나지 않는다.
    var atHour: Double {
        switch self {
        case .fixedRoutine(_, _, let h, _): h
        case .quotaSession(_, _, let h): h
        case .block(_, let h): h
        }
    }

    /// 이 항목이 차지하는 시간. 칩 사이의 **틈을 재는** 데 쓴다 (→ DayColumn.gapZone).
    var hours: Double {
        switch self {
        case .fixedRoutine(_, _, _, let h): h
        case .quotaSession(let r, _, _): r.dailyQuotaHours / Double(max(1, r.sessionsPerDay))
        case .block(let b, _): b.durationHours
        }
    }

    /// 이 항목이 끝나는 시각.
    var endHour: Double { atHour + hours }

    /// 요일 칸에서 이 항목을 끌 때 실어 보내는 표.
    /// 계획 블록은 제 토큰(`block:`), 루틴·끼니는 **어느 요일의 어느 조각인지**까지 싣는다.
    func dragToken(on day: DayOfWeek) -> String {
        switch self {
        case .fixedRoutine(let r, _, let h, _):
            RoutineDragToken(kind: .fixed(pieceStart: h), day: day, name: r.name).encoded
        case .quotaSession(let r, let index, _):
            RoutineDragToken(kind: .quota(sessionIndex: index), day: day, name: r.name).encoded
        case .block(let b, _):
            b.dragToken
        }
    }
}

/// **요일 칸의 루틴·끼니 칩을 끌 때 실어 보내는 표.**
///
/// 받는 쪽은 이 표로 이번 주 그 요일의 시각만 옮긴다 (→ ContentView.moveRoutine).
///
/// ⚠️ `routine:`(아래 루틴 카드를 끌어 **새 계획 블록을 만드는** 표)과 머리를 따로 쓴다.
///    같은 머리를 쓰면 칩을 옮기려다 블록이 하나 더 생긴다.
struct RoutineDragToken {
    enum Kind {
        /// 고정 루틴. 자정을 넘겨 둘로 그려진 잠은 **잡은 조각**이 어디서 시작했는지를 싣는다.
        case fixed(pieceStart: Double)
        case quota(sessionIndex: Int)
    }

    let kind: Kind
    let day: DayOfWeek
    let name: String

    private static let prefix = "move-routine:"

    init(kind: Kind, day: DayOfWeek, name: String) {
        self.kind = kind
        self.day = day
        self.name = name
    }

    var encoded: String {
        switch kind {
        case .fixed(let start): "\(Self.prefix)f|\(day.rawValue)|\(start)|\(name)"
        case .quota(let index): "\(Self.prefix)q|\(day.rawValue)|\(index)|\(name)"
        }
    }

    /// 이름에 `|`가 들어 있어도 되게, 앞의 세 칸만 자르고 나머지는 통째로 이름으로 본다.
    init?(_ token: String) {
        guard token.hasPrefix(Self.prefix) else { return nil }
        let parts = token.dropFirst(Self.prefix.count)
            .split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count == 4, let rawDay = Int(parts[1]), let day = DayOfWeek(rawValue: rawDay) else { return nil }
        switch parts[0] {
        case "f":
            guard let start = Double(parts[2]) else { return nil }
            kind = .fixed(pieceStart: start)
        case "q":
            guard let index = Int(parts[2]) else { return nil }
            kind = .quota(sessionIndex: index)
        default:
            return nil
        }
        self.day = day
        self.name = String(parts[3])
    }
}

struct DayColumn: View {
    let day: DayOfWeek
    let date: Date
    var canPlan: Bool = true
    /// 일정 기준으로 지금 하고 있는 조각. 그 칩에 남은 시간이 붙는다 (→ ScheduleClock.swift).
    var currentSlot: ScheduleSlot? = nil
    /// 시각 순으로 정렬된 통합 항목(고정 루틴·쿼터·블록).
    let items: [DayPlanItem]
    let onAdd: () -> Void
    let onEdit: (PlanBlock) -> Void
    /// 루틴을 눌렀을 때 — 상세(정보·실행 전략·프리모템)
    let onEditRoutine: (Routine) -> Void
    /// 루틴 '수정' — 이름·요일·시각을 바꾸는 편집기
    var onEditRoutineSchedule: ((Routine) -> Void)? = nil
    let onDropBacklog: (String) -> Void
    /// 칩과 칩 **사이**에 떨어뜨렸을 때. (토큰, 놓을 시각, 그 틈의 크기)
    /// 틈보다 큰 것이 들어오면 받는 쪽이 겹침을 알린다 (→ ContentView.dropIntoGap).
    var onDropIntoGap: (String, Double, Double) -> Void = { _, _, _ in }
    /// 요일 머리를 눌렀을 때 — 그날의 일간으로 (→ ContentView.openDay).
    var onOpenDay: (() -> Void)? = nil

    @State private var isDropTargeted = false
    /// 지금 겨냥한 틈. 그 자리에 파란 선이 선다.
    @State private var targetedGap: Int?

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    /// 그 시각을 0–24 소수 시간으로. (14:30 → 14.5)
    static func hourOfDay(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    /// 이 항목이 '지금 하고 있는 그것'인가.
    ///
    /// 이름만으로는 모자란다 — 같은 루틴이 이레 내내 서 있고, 자정을 넘긴 잠은
    /// 두 칸에 나뉘어 그려진다. 요일과 시작 시각까지 맞아야 한 칩에만 남은 시간이 붙는다.
    private func liveSlot(for item: DayPlanItem) -> ScheduleSlot? {
        guard let slot = currentSlot, slot.day == day,
              abs(slot.startHourInDay - item.atHour) < 0.01 else { return nil }
        switch item {
        case .fixedRoutine(let r, _, _, _):
            return slot.id == TaskTimer.token(for: r) ? slot : nil
        case .quotaSession(let r, let index, _):
            return slot.id == "\(TaskTimer.token(for: r)):\(index)" ? slot : nil
        case .block(let b, _):
            return slot.id == b.dragToken ? slot : nil
        }
    }

    /// 하루의 항목들. 오늘 칸에는 붉은 '지금' 선이, 항목 사이사이에는 **끼워 넣는 자리**가 선다.
    ///
    /// 예전에는 오늘/오늘 아닌 칸이 각자 목록을 그렸다가 한쪽만 고치는 일이 생겼다. 하나로 합쳤다.
    @ViewBuilder
    private func itemList(now: Double?) -> some View {
        // 지금보다 늦은 첫 항목 **앞**에 선을 끼운다. 그런 항목이 없으면 맨 아래 = 오늘 계획을 다 지났다.
        let cut = now.map { n in items.firstIndex { $0.atHour > n } ?? items.count }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if let now, index == cut { nowMarker(now) }
                gapZone(at: index)
                chip(for: item)
                    .transition(.card)
            }
            if let now, cut == items.count { nowMarker(now) }
            gapZone(at: items.count)
        }
        // 요일 칸은 @Query가 스스로 갈아 끼우는 자리다 — 무엇이 서 있는지가 바뀌었을 때만
        // 결이 붙게 값으로 건다. (분이 흘러 '지금' 선만 내려가는 것에는 반응하지 않는다)
        .animation(Motion.card, value: items.map(\.id))
    }

    /// **칩과 칩 사이에 끼워 넣는 자리.**
    ///
    /// 요일 칸에는 '수동 순서'라는 것이 없다 — 자리는 곧 시각이다(`PlanBlock.sortHour`).
    /// 그래서 순서를 바꾼다는 것은 **시각을 정한다**는 뜻이고, 그 시각을 여기서 이웃한
    /// 두 항목으로부터 잡는다: 앞 항목이 끝나는 시각에 놓는다.
    private func gapZone(at index: Int) -> some View {
        let targeted = targetedGap == index
        return Color.clear
            .frame(height: targeted ? 14 : 8)
            .frame(maxWidth: .infinity)
            .overlay {
                if targeted {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(height: 3)
                        .padding(.horizontal, 2)
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { dropped, _ in
                targetedGap = nil
                guard canPlan, let token = dropped.first else { return false }
                let bounds = gapBounds(at: index, excluding: token)
                onDropIntoGap(token, bounds.start, bounds.gap)
                return true
            } isTargeted: { targetedGap = ($0 && canPlan) ? index : nil }
            .animation(Motion.target, value: targeted)
    }

    /// 이 틈이 **언제 시작해서 얼마나 넓은가.**
    /// 맨 위는 0시부터, 맨 아래는 24시까지로 본다.
    ///
    /// ⚠️ **끌고 있는 그 항목은 빼고 잰다.** 제 바로 아래 틈에 놓았는데 자기 끝 시각부터 재면,
    ///    제자리에 둔 것이 제 길이만큼 뒤로 밀린다.
    private func gapBounds(at index: Int, excluding token: String? = nil) -> (start: Double, gap: Double) {
        let isDragged: (DayPlanItem) -> Bool = { token != nil && $0.dragToken(on: day) == token }
        let prev = items[..<index].last { !isDragged($0) }
        let next = items[index...].first { !isDragged($0) }
        let start = prev?.endHour ?? 0
        let end = next?.atHour ?? 24
        return (max(0, min(start, 24)), max(0, end - start))
    }

    /// 한 항목의 칩. '지금' 선을 끼우느라 두 곳에서 쓰므로 따로 뺐다.
    @ViewBuilder
    private func chip(for item: DayPlanItem) -> some View {
        switch item {
        // 시각은 뺀다 — 칸이 이미 시각 순으로 서 있어서, 줄마다 시각을 또 적으면
        // 자기 위아래를 되풀이할 뿐이다. 길이는 이 자리 말고는 어디에도 안 적혀 있다.
        // (자정을 넘겨 쪼개진 조각은 각자 자기 길이를 보여, 합이 루틴 전체 길이가 된다.)
        case .fixedRoutine(let routine, _, _, let hours):
            RoutineChip(routine: routine,
                        subtitleOverride: shortHours(hours),
                        currentSlot: liveSlot(for: item),
                        onEdit: onEditRoutineSchedule.map { f in { f(routine) } },
                        dragToken: item.dragToken(on: day)) {
                onEditRoutine(routine)
            }
        case .quotaSession(let routine, let index, _):
            // 쿼터는 주간 합계가 아니라 **회당** 길이를 보여야 한 줄이 한 번을 가리킨다.
            RoutineChip(routine: routine,
                        subtitleOverride: shortHours(routine.dailyQuotaHours
                                                     / Double(max(1, routine.sessionsPerDay))),
                        currentSlot: liveSlot(for: item),
                        timerToken: "\(TaskTimer.token(for: routine)):\(index)",
                        onEdit: onEditRoutineSchedule.map { f in { f(routine) } },
                        dragToken: item.dragToken(on: day)) { onEditRoutine(routine) }
        case .block(let block, _):
            BlockChip(block: block, currentSlot: liveSlot(for: item)) { onEdit(block) }
        }
    }

    /// 지금 이 순간의 자리. 시각을 함께 적어 '요일별 하루'의 붉은 선과 같은 값임을 알린다.
    private func nowMarker(_ hour: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Color.red).frame(width: 5, height: 5)
            Rectangle().fill(Color.red.opacity(0.7)).frame(height: 1)
            Text(formatHour(hour))
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.red)
        }
        .padding(.vertical, 1)
        .transition(.opacity)
        .accessibilityLabel("지금 \(formatHour(hour))")
    }

    private var dayNumber: String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(spacing: 1) {
                Text(day.shortLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isToday ? Color.red : .secondary)
                Text(dayNumber)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? .white : .primary)
                    .frame(width: 30, height: 30)
                    .background {
                        if isToday {
                            Circle().fill(Color.red)
                        }
                    }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.bottom, 2)
            // 요일 머리를 누르면 그날 하루를 크게 편다 (→ DayScheduleView).
            .contentShape(Rectangle())
            .onTapGesture { onOpenDay?() }
            .pointingCursor(enabled: onOpenDay != nil)
            .help(String(localized: "\(day.longLabel) 하루 보기"))

            // 고정 루틴·유연 쿼터·계획 블록을 시각 순으로 섞어, '요일별 하루' 타임라인과 같은 흐름으로 표시.
            //
            // 오늘 칸에는 지나간 것과 남은 것 사이에 붉은 '지금' 선이 끼어든다.
            // 컬럼이 시각 순으로 서 있으므로, 선 위는 이미 지난 계획이고 아래가 남은 계획이다.
            if isToday {
                // 분이 바뀌면 선도 한 칸씩 내려간다. 다시 그리는 건 오늘 칸 하나뿐이다.
                TimelineView(.everyMinute) { ctx in
                    itemList(now: Self.hourOfDay(ctx.date))
                }
            } else {
                itemList(now: nil)
            }

            Button(action: onAdd) {
                Image(systemName: canPlan ? "plus" : "lock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle.soft(Corner.chip)
                            .strokeBorder(
                                Color.secondary.opacity(0.25),
                                style: StrokeStyle(lineWidth: 0.5, dash: [3, 3])
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canPlan)
            .help(canPlan ? "\(day.longLabel)에 블록 추가" : "고정 루틴을 먼저 추가하세요")
        }
        .padding(8)
        // 이웃 칸과 키를 맞춘다 — 들쭉날쭉한 카드는 대시보드가 아니라 쌓아 둔 종이로 읽힌다.
        // (가장 긴 칸에 맞추는 것은 부르는 쪽 HStack의 `.fixedSize(vertical:)`다.)
        .frame(minHeight: 150, maxHeight: .infinity, alignment: .top)
        .background {
            // 요일 칸 하나하나가 대시보드 위에 올라간 카드다 (→ Surface.swift).
            DashboardSurface()
            if isDropTargeted {
                RoundedRectangle.soft(Corner.panel)
                    .fill(Color.accentColor.opacity(0.08))
                RoundedRectangle.soft(Corner.panel)
                    .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard canPlan, let token = items.first else { return false }
            onDropBacklog(token)
            return true
        } isTargeted: { targeted in
            withAnimation(Motion.target) { isDropTargeted = canPlan && targeted }
        }
    }
}

struct RoutineChip: View {
    let routine: Routine
    /// 컬럼에서 끼니 세션처럼 '이 occurrence의 시각'을 보여주고 싶을 때 부제를 대체.
    var subtitleOverride: String? = nil
    /// 일정 기준으로 지금 하고 있는 조각 (→ ScheduleClock.swift).
    var currentSlot: ScheduleSlot? = nil
    /// 타이머가 이 칩을 부르는 이름. 끼니는 회차까지 달라야 세션 하나를 가리킬 수 있다.
    var timerToken: String? = nil
    /// '수정' — 이름·요일·시각을 바꾸는 편집기로. 없으면 버튼을 띄우지 않는다.
    var onEdit: (() -> Void)? = nil
    /// 끌 때 실어 보낼 표. 있으면 같은 요일 안에서 끌어 시각을 옮길 수 있다 (→ RoutineDragToken).
    var dragToken: String? = nil
    let onTap: () -> Void

    @State private var hovering = false

    private var isQuota: Bool { routine.kind == .quota }

    private var token: String { timerToken ?? TaskTimer.token(for: routine) }

    /// 이 루틴 한 번의 길이. 쿼터는 주간 합계만 적혀 있으므로 회당 시간을 계산해 쓴다.
    private var timerHours: Double {
        guard isQuota else { return routine.durationHours }
        let sessions = max(1, routine.sessionsPerDay)
        return routine.dailyQuotaHours / Double(sessions)
    }

    // 쿼터(유연)는 점선 테두리 + 더 옅은 배경으로 '시간 유연'임을 드러낸다(타임라인 점선과 일관).
    private var subtitle: String {
        if let subtitleOverride { return subtitleOverride }
        if isQuota {
            var s = String(localized: "주 \(String(format: "%.1f", routine.weeklyHours))h")
            if routine.sessionsPerDay > 0 { s += String(localized: " · \(routine.sessionsPerDay)회") }
            return s
        }
        return "\(formatHour(routine.startHour))  \(String(format: "%.1fh", routine.durationHours))"
    }

    var body: some View {
        // 누르면 상세. 요일·시각 수정은 우클릭 메뉴로 간다.
        // (손을 올리면 뜨던 '수정' 단추는 뗐다 — 좁은 칸에서 제목을 가리고, 끌려고 잡는 자리와 겹쳤다.)
        chipBody
            .contentShape(.soft(Corner.chip))
            // 끌기를 탭보다 안쪽에 둔다 — 순서가 뒤집히면 누르는 동안 끌기가 시작되지 못한다 (→ BlockChip).
            .modifier(OptionalDraggable(token: dragToken))
            .onTapGesture(perform: onTap)
            .onHover { hovering = $0 }
            .grabCursor(enabled: dragToken != nil)
            .animation(Motion.hover, value: hovering)
            .contextMenu {
                if let onEdit {
                    Button(action: onEdit) {
                        Label("요일·시각 수정…", systemImage: "calendar.badge.clock")
                    }
                    Divider()
                }
                // 쿼터(끼니 등)는 회당 시간이 따로다 — 그 값으로 센다.
                TimerMenuItems(token: token,
                               title: routine.name,
                               hours: timerHours,
                               iconName: routine.iconName,
                               colorName: routine.colorName)
            }
            .help("\(routine.scheduleDescription)\n눌러서 상세 · 같은 요일 안에서 끌어 시각 옮기기 · 우클릭으로 타이머 시작")
    }

    private var chipBody: some View {
        let color = routine.displayColor
        return HStack(spacing: 6) {
                Image(systemName: routine.iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(routine.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .opacity(0.7)
                    // 지금 하고 있는 것이면 남은 시간이 한 줄 더 선다. 좁은 칸에서 눌리지 않게 제 줄로.
                    TimerBadge(token: token, tint: color, slot: currentSlot)
                }

                Spacer()

                // 끝에 자물쇠·↔ 표시를 두지 않는다. 루틴 칩도 같은 요일 안에서는 끌어 옮길 수 있어
                // 자물쇠는 '못 옮긴다'로, ↔는 '다른 요일로도 간다'로 잘못 읽혔다.
                // 잡힌다는 건 손 모양 커서가, 쿼터의 유연함은 점선 테두리가 말한다.
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(isQuota ? (hovering ? 0.12 : 0.07) : (hovering ? 0.20 : 0.14)),
                        in: .soft(Corner.chip))
            // 테두리는 **유연한 시간(쿼터)에만** 긋는다 — 점선이 '자리를 옮길 수 있다'는 뜻이다.
            // 고정 루틴은 채움만으로 가려지고, 선까지 두르면 요일 칸 안이 선으로 빽빽해진다.
            .overlay(
                RoundedRectangle.soft(Corner.chip)
                    .strokeBorder(color.opacity(isQuota ? (hovering ? 0.55 : 0.4) : (hovering ? 0.35 : 0)),
                                  style: isQuota ? StrokeStyle(lineWidth: 1, dash: [3, 2]) : StrokeStyle(lineWidth: 1))
            )
            .foregroundStyle(color)
    }
}

/// 표가 있을 때만 끌 수 있게 한다.
private struct OptionalDraggable: ViewModifier {
    let token: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let token {
            content.draggable(token)
        } else {
            content
        }
    }
}

/// 칩 귀퉁이에 들어갈 **짧은** 길이.
/// `formatDuration`의 "1시간 30분"은 좁은 요일 칸에서 제목을 밀어내므로 여기서는 안 쓴다.
/// 딱 떨어지면 소수점을 떼서 "2h", 아니면 "1.5h".
func shortHours(_ hours: Double) -> String {
    let rounded = (hours * 10).rounded() / 10
    if rounded == rounded.rounded() { return "\(Int(rounded))h" }
    return String(format: "%.1fh", rounded)
}

struct BlockChip: View {
    let block: PlanBlock
    /// 일정 기준으로 지금 하고 있는 조각 (→ ScheduleClock.swift).
    var currentSlot: ScheduleSlot? = nil
    let onTap: () -> Void

    @State private var hovering = false

    private var palette: (bg: Color, fg: Color, stroke: Color) {
        if block.concreteVerified {
            return (Color.accentColor.opacity(0.22), Color.accentColor, Color.accentColor.opacity(0.55))
        } else {
            return (Color.orange.opacity(0.22), Color.orange, Color.orange.opacity(0.6))
        }
    }

    var body: some View {
        // 칩 전체를 탭 제스처로 연다 — 누르면 곧 편집기다.
        // (손을 올리면 뜨던 '수정' 단추는 뗐다 — 누르는 것과 같은 일을 두 번 말했다.)
        chipBody
            .contentShape(.soft(Corner.chip))
            // 다른 요일로 끌어 옮기기 — 드롭 대상(DayColumn)에서 요일을 바꾼다.
            //
            // ⚠️ 순서가 중요하다. `.onTapGesture`를 먼저 붙이면 탭이 안쪽(우선순위 높은)
            //    제스처가 되어 마우스를 눌러 끄는 동안 드래그가 시작되지 못한다.
            //    드래그를 안쪽에 두면, 움직이지 않은 클릭만 바깥의 탭으로 떨어진다.
            .draggable(block.dragToken)
            .onTapGesture(perform: onTap)
            .onHover { hovering = $0 }
            // 잡을 수 있다는 것을 손 모양으로 (→ Affordance.swift).
            .grabCursor()
            .animation(Motion.hover, value: hovering)
            // 계획을 보는 자리에서 바로 세기 시작한다 — 창을 열러 갈 필요 없이 (→ TimerView.swift).
            .contextMenu {
                TimerMenuItems(token: block.dragToken, title: block.title, hours: block.durationHours)
            }
            // 내리는 길이 생겼으니 말해 준다 — 손짓은 있는데 아무도 모르면 없는 것과 같다.
            .help(block.successCriteria.isEmpty
                  ? String(localized: "구체성 미검증 — 눌러서 다듬기 · 다른 요일로 끌어 옮기기 · 할 일 목록으로 끌어 내리면 날짜가 무름")
                  : block.successCriteria
                    + "\n" + String(localized: "다른 요일로 끌어 옮길 수 있습니다.")
                    + "\n" + String(localized: "할 일 목록으로 끌어 내리면 날짜가 무릅니다."))
    }

    

    private var chipBody: some View {
            // 제목 줄 끝에 **길이**를 붙인다.
            //
            // 한때 이 자리에 시간대(아침·오후·저녁)를 뒀는데, 칸이 이미 시각 순으로 서
            // 있어서 그 줄은 자기 위아래를 되풀이할 뿐이었다. 길이는 어디에도 안 적혀
            // 있으니 이 자리에서만 알 수 있다.
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let status = block.reviewStatus {
                        Image(systemName: status.systemImage)
                            .font(.system(size: 11))
                            .foregroundStyle(reviewTint(status))
                    }
                    Text(block.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    Text(shortHours(block.durationHours))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .opacity(0.7)
                        .layoutPriority(1)
                }

                // 지금 하고 있는 것이면 남은 시간이 한 줄 더 선다.
                TimerBadge(token: block.dragToken, tint: palette.fg, slot: currentSlot)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            // **옮길 수 있는 것은 떠 있다.** 요일 칸에서 끌어 옮길 수 있는 건 계획 블록뿐이라,
            // 이것만 흰 바탕 위에 색을 얹고 그림자를 깔아 칸에서 들어 올린다. 루틴 칩은 칸에
            // 붙은 납작한 색면으로 둔다 — 둘이 같은 높이면 무엇이 잡히는지 끌어 봐야 안다.
            // 손이 올라가면 한 뼘 더 뜬다(집어 들기 직전).
            .background {
                ZStack {
                    RoundedRectangle.soft(Corner.chip).fill(Color.surface)
                    RoundedRectangle.soft(Corner.chip).fill(palette.bg)
                }
                .compositingGroup()
                .shadow(color: palette.fg.opacity(hovering ? 0.32 : 0.22),
                        radius: hovering ? 6 : 2.5, y: hovering ? 3 : 1.5)
            }
            // 검증됐는지는 채움 색(파랑·주황)이 이미 말한다. 테두리는 가리킬 때만 선다.
            .overlay(
                RoundedRectangle.soft(Corner.chip)
                    .strokeBorder(palette.stroke.opacity(hovering ? 1 : 0), lineWidth: 1.2)
            )
            .foregroundStyle(palette.fg)
            .offset(y: hovering ? -1 : 0)
    }

    private func reviewTint(_ status: ReviewStatus) -> Color {
        switch status {
        case .done: .green
        case .partial: .yellow
        case .skipped: .red
        }
    }
}
