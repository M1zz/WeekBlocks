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

    @State private var isDropTargeted = false

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

    /// 한 항목의 칩. '지금' 선을 끼우느라 두 곳에서 쓰므로 따로 뺐다.
    @ViewBuilder
    private func chip(for item: DayPlanItem) -> some View {
        switch item {
        case .fixedRoutine(let routine, _, let atHour, _):
            // 길이는 뺀다 — BlockChip과 같은 이유다. 시각만 남긴다.
            // (자정을 넘겨 쪼개진 조각도 시작 시각이 다르므로 여전히 구별된다.)
            RoutineChip(routine: routine,
                        subtitleOverride: formatHour(atHour),
                        currentSlot: liveSlot(for: item),
                        onEdit: onEditRoutineSchedule.map { f in { f(routine) } }) {
                onEditRoutine(routine)
            }
        case .quotaSession(let routine, let index, let atHour):
            RoutineChip(routine: routine, subtitleOverride: formatHour(atHour),
                        currentSlot: liveSlot(for: item),
                        timerToken: "\(TaskTimer.token(for: routine)):\(index)",
                        onEdit: onEditRoutineSchedule.map { f in { f(routine) } }) { onEditRoutine(routine) }
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

            // 고정 루틴·유연 쿼터·계획 블록을 시각 순으로 섞어, '요일별 하루' 타임라인과 같은 흐름으로 표시.
            //
            // 오늘 칸에는 지나간 것과 남은 것 사이에 붉은 '지금' 선이 끼어든다.
            // 컬럼이 시각 순으로 서 있으므로, 선 위는 이미 지난 계획이고 아래가 남은 계획이다.
            if isToday {
                // 분이 바뀌면 선도 한 칸씩 내려간다. 다시 그리는 건 오늘 칸 하나뿐이다.
                TimelineView(.everyMinute) { ctx in
                    let now = Self.hourOfDay(ctx.date)
                    // 지금보다 늦은 첫 항목 **앞**에 선을 끼운다. 그런 항목이 없으면 맨 아래 = 오늘 계획을 다 지났다.
                    let cut = items.firstIndex { $0.atHour > now } ?? items.count
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if index == cut { nowMarker(now) }
                            chip(for: item)
                        }
                        if cut == items.count { nowMarker(now) }
                    }
                }
            } else {
                ForEach(items) { item in
                    chip(for: item)
                }
            }

            Button(action: onAdd) {
                Image(systemName: canPlan ? "plus" : "lock")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
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
        .frame(minHeight: 150, alignment: .top)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTargeted
                      ? Color.accentColor.opacity(0.08)
                      : Color(nsColor: .controlBackgroundColor))
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard canPlan, let token = items.first else { return false }
            onDropBacklog(token)
            return true
        } isTargeted: { isDropTargeted = canPlan && $0 }
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
            var s = String(format: "주 %.1fh", routine.weeklyHours)
            if routine.sessionsPerDay > 0 { s += " · \(routine.sessionsPerDay)회" }
            return s
        }
        return "\(formatHour(routine.startHour))  \(String(format: "%.1fh", routine.durationHours))"
    }

    var body: some View {
        // 겉을 Button으로 두면 안에 놓은 '수정' 버튼이 클릭을 못 받는다.
        chipBody
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .onTapGesture(perform: onTap)
            .overlay(alignment: .topTrailing) {
                if hovering, let onEdit {
                    Button("수정", action: onEdit)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                        .overlay(Capsule().stroke(routine.displayColor.opacity(0.5), lineWidth: 0.5))
                        .padding(4)
                }
            }
            .onHover { hovering = $0 }
            .contextMenu {
                // 쿼터(끼니 등)는 회당 시간이 따로다 — 그 값으로 센다.
                TimerMenuItems(token: token,
                               title: routine.name,
                               hours: timerHours,
                               iconName: routine.iconName,
                               colorName: routine.colorName)
            }
            .help("\(routine.scheduleDescription)\n눌러서 상세 · 우클릭으로 타이머 시작")
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

                Image(systemName: isQuota ? "arrow.left.and.right" : "lock.fill")
                    .font(.system(size: 11))
                    .opacity(isQuota ? 0.5 : 0.35)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(isQuota ? (hovering ? 0.12 : 0.07) : (hovering ? 0.18 : 0.12)),
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(color.opacity(hovering ? 0.55 : 0.4),
                            style: isQuota ? StrokeStyle(lineWidth: 1, dash: [3, 2]) : StrokeStyle(lineWidth: 1))
            )
            .foregroundStyle(color)
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
        // 겉을 Button으로 두면 안에 놓은 '수정' 버튼이 클릭을 못 받는다.
        // 칩 전체는 탭 제스처로, 수정은 별도 버튼으로 분리한다.
        chipBody
            .contentShape(RoundedRectangle(cornerRadius: 7))
            // 다른 요일로 끌어 옮기기 — 드롭 대상(DayColumn)에서 요일을 바꾼다.
            //
            // ⚠️ 순서가 중요하다. `.onTapGesture`를 먼저 붙이면 탭이 안쪽(우선순위 높은)
            //    제스처가 되어 마우스를 눌러 끄는 동안 드래그가 시작되지 못한다.
            //    드래그를 안쪽에 두면, 움직이지 않은 클릭만 바깥의 탭으로 떨어진다.
            .draggable(block.dragToken)
            .onTapGesture(perform: onTap)
            .overlay(alignment: .topTrailing) { editButton }
            .onHover { hovering = $0 }
            // 계획을 보는 자리에서 바로 세기 시작한다 — 창을 열러 갈 필요 없이 (→ TimerView.swift).
            .contextMenu {
                TimerMenuItems(token: block.dragToken, title: block.title, hours: block.durationHours)
            }
            .help(block.successCriteria.isEmpty
                  ? "구체성 미검증 — 눌러서 다듬기 · 드래그해서 다른 요일로 옮기기"
                  : block.successCriteria + "\n드래그해서 다른 요일로 옮길 수 있습니다.")
    }

    @ViewBuilder
    private var editButton: some View {
        if hovering {
            Button("수정", action: onTap)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                .overlay(Capsule().stroke(palette.stroke, lineWidth: 0.5))
                .padding(4)
        }
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
            .background(palette.bg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(palette.stroke, lineWidth: hovering ? 1.5 : 1)
            )
            .foregroundStyle(palette.fg)
    }

    private func reviewTint(_ status: ReviewStatus) -> Color {
        switch status {
        case .done: .green
        case .partial: .yellow
        case .skipped: .red
        }
    }
}
