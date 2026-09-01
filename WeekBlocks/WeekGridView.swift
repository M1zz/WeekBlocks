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
        case .block(let b, _): "block:\(String(describing: b.persistentModelID))"
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

    /// 한 항목의 칩. '지금' 선을 끼우느라 두 곳에서 쓰므로 따로 뺐다.
    @ViewBuilder
    private func chip(for item: DayPlanItem) -> some View {
        switch item {
        case .fixedRoutine(let routine, _, let atHour, let hours):
            // 자정을 넘겨 쪼개진 조각은 각자 자기 길이를 보여, 합이 루틴 전체 길이가 되도록.
            RoutineChip(routine: routine,
                        subtitleOverride: "\(formatHour(atHour))  \(String(format: "%.1fh", hours))",
                        onEdit: onEditRoutineSchedule.map { f in { f(routine) } }) {
                onEditRoutine(routine)
            }
        case .quotaSession(let routine, _, let atHour):
            RoutineChip(routine: routine, subtitleOverride: formatHour(atHour),
                        onEdit: onEditRoutineSchedule.map { f in { f(routine) } }) { onEditRoutine(routine) }
        case .block(let block, _):
            BlockChip(block: block) { onEdit(block) }
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
        VStack(alignment: .leading, spacing: 6) {
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
                    VStack(alignment: .leading, spacing: 6) {
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
        .frame(minHeight: 180, alignment: .top)
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
    /// '수정' — 이름·요일·시각을 바꾸는 편집기로. 없으면 버튼을 띄우지 않는다.
    var onEdit: (() -> Void)? = nil
    let onTap: () -> Void

    @State private var hovering = false

    private var isQuota: Bool { routine.kind == .quota }

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
            .help("\(routine.scheduleDescription)\n눌러서 상세 · '수정'으로 요일·시각 변경")
    }

    private var chipBody: some View {
        let color = routine.displayColor
        return HStack(spacing: 6) {
                Image(systemName: routine.iconName)
                    .font(.system(size: 13))
                    .foregroundStyle(color)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .opacity(0.7)
                }

                Spacer()

                Image(systemName: isQuota ? "arrow.left.and.right" : "lock.fill")
                    .font(.system(size: 11))
                    .opacity(isQuota ? 0.5 : 0.35)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
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

struct BlockChip: View {
    let block: PlanBlock
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
            .onTapGesture(perform: onTap)
            .overlay(alignment: .topTrailing) { editButton }
            .onHover { hovering = $0 }
            // 다른 요일로 끌어 옮기기 — 드롭 대상(DayColumn)에서 요일을 바꾼다.
            .draggable("block:" + String(describing: block.persistentModelID))
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let status = block.reviewStatus {
                        Image(systemName: status.systemImage)
                            .font(.system(size: 13))
                            .foregroundStyle(reviewTint(status))
                    }
                    Text(block.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 4) {
                    Text(block.timeBand.shortLabel)
                    Text("·")
                    Text(String(format: "%.1fh", block.durationHours))
                }
                .font(.system(size: 13))
                .opacity(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
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
