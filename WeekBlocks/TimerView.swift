//
//  TimerView.swift
//  무지개 공방
//
//  "운동 1시간"이라고 적어 둔 계획에, 지금 얼마 남았는가.
//
//  기본은 **일정 기준**이다. 아무것도 누르지 않아도, 수면이 23:00–07:00이고 지금이 23:29면
//  타이머는 이미 7:31:00을 세고 있다 (→ ScheduleClock.swift).
//  계획보다 늦게 시작했거나 계획에 없는 일을 할 때만 '지금부터' 따로 센다 (→ TaskTimer.swift).
//

import SwiftUI
import SwiftData

// MARK: - 타이머 창

struct TimerWindowView: View {
    @Query private var allBlocksRaw: [PlanBlock]
    /// 잠긴 기기에서 만든 남의 것은 안 그린다 (→ TodoSharing.swift).
    /// **거르는 자리는 여기 하나뿐이다** — 화면마다 조건을 따로 쓰면 어딘가는 새어 보인다.
    private var allBlocks: [PlanBlock] { allBlocksRaw.filter(TodoSharing.isVisible) }
    @Query(sort: [SortDescriptor(\Routine.sortIndex)]) private var routinesRaw: [Routine]
    /// 잠긴 기기에서 만든 남의 것은 안 그린다 (→ TodoSharing.swift).
    /// **거르는 자리는 여기 하나뿐이다** — 화면마다 조건을 따로 쓰면 어딘가는 새어 보인다.
    private var routines: [Routine] { routinesRaw.filter(TodoSharing.isVisible) }
    @Query private var allOccurrences: [RoutineOccurrence]
    @Query private var allQuotaPlacements: [QuotaPlacement]

    @State private var timer = TaskTimer.shared

    var body: some View {
        Group {
            if timer.isActive {
                // 직접 센 것이 우선이다 — 사람이 손으로 누른 것이 일정보다 지금을 잘 안다.
                RunningTimerFace()
            } else {
                // 1초마다 다시 그린다. 세는 주체가 따로 없고, 계산은 '지금'에서 바로 나온다.
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    ScheduleTimerFace(slots: slots, now: ctx.date)
                }
            }
        }
        .frame(minWidth: 380, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var slots: [ScheduleSlot] {
        ScheduleClock.slots(routines: routines, blocks: allBlocks,
                            occurrences: allOccurrences, placements: allQuotaPlacements)
    }
}

// MARK: - 일정 기준 얼굴

/// 지금 하고 있는 일정과 거기 남은 시간. 시작 버튼이 없다 — 시작은 이미 일정에 적혀 있다.
struct ScheduleTimerFace: View {
    let slots: [ScheduleSlot]
    let now: Date

    @State private var timer = TaskTimer.shared

    private var current: ScheduleSlot? { ScheduleClock.current(slots, at: now) }
    private var upcoming: ScheduleSlot? { ScheduleClock.next(slots, at: now) }

    var body: some View {
        VStack(spacing: 14) {
            if let slot = current {
                runningSlot(slot)
            } else {
                idle
            }

            Divider().padding(.horizontal, -4)
            todayList
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 지금 하고 있는 것

    private func runningSlot(_ slot: ScheduleSlot) -> some View {
        let tint = slot.colorName.map(paletteColor) ?? .accentColor
        return VStack(spacing: 12) {
            VStack(spacing: 4) {
                Label(slot.title, systemImage: slot.iconName)
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                Text("\(clock(slot.start))–\(clock(slot.end)) · \(formatDuration(slot.hours))")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            ZStack {
                Circle().stroke(tint.opacity(0.14), lineWidth: 13)
                Circle()
                    .trim(from: 0, to: slot.progress(at: now))
                    .stroke(tint, style: StrokeStyle(lineWidth: 13, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(formatCountdown(slot.remaining(at: now)))
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text("남음")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 190, height: 190)

            Text("\(clock(slot.end))에 끝납니다")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            // 계획보다 늦게 앉았을 때. 일정 기준을 버리고 '지금부터' 온전한 길이를 센다.
            Button {
                timer.start(token: slot.id, title: slot.title,
                            plannedSeconds: slot.duration,
                            iconName: slot.iconName, colorName: slot.colorName)
            } label: {
                Label("지금부터 \(formatDuration(slot.hours)) 세기", systemImage: "timer")
            }
            .controlSize(.small)
            .help("늦게 시작했을 때 — 일정에 적힌 끝 시각 대신 지금부터의 길이를 셉니다")
        }
    }

    // MARK: 지금은 비어 있을 때

    private var idle: some View {
        VStack(spacing: 10) {
            Image(systemName: "cup.and.saucer")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("지금은 올려 둔 일정이 없습니다")
                .font(.system(size: 16, weight: .semibold))

            if let next = upcoming {
                VStack(spacing: 3) {
                    Text("다음 · \(next.title)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(next.colorName.map(paletteColor) ?? .accentColor)
                    Text("\(clock(next.start)) 시작 · \(formatCountdown(next.start.timeIntervalSince(now))) 뒤")
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: 오늘 남은 것들

    private var todayList: some View {
        let cal = Calendar.current
        let rest = slots
            .filter { cal.isDate($0.start, inSameDayAs: now) || $0.end > now }
            .filter { $0.end > now && $0.start < now.addingTimeInterval(24 * 3600) }
            .sorted { $0.start < $1.start }

        return VStack(alignment: .leading, spacing: 6) {
            Text("여기서부터 남은 하루")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            if rest.isEmpty {
                Text("남은 일정이 없습니다.")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(spacing: 5) {
                        ForEach(rest) { slot in
                            SlotRow(slot: slot, now: now)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func clock(_ date: Date) -> String { formatHour(hourOfDay(date)) }
}

/// 남은 하루의 한 줄. 지금 하고 있는 것은 테두리로 도드라진다.
private struct SlotRow: View {
    let slot: ScheduleSlot
    let now: Date

    @State private var timer = TaskTimer.shared

    private var isNow: Bool { slot.contains(now) }
    private var tint: Color { slot.colorName.map(paletteColor) ?? .accentColor }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: slot.iconName)
                .font(.system(size: 13))
                .foregroundStyle(tint)
                .frame(width: 16)

            Text(slot.title)
                .font(.system(size: 13, weight: isNow ? .semibold : .regular))
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(isNow
                 ? formatCountdown(slot.remaining(at: now)) + " 남음"
                 : formatHour(hourOfDay(slot.start)))
                .font(.system(size: 12, weight: isNow ? .semibold : .regular))
                .monospacedDigit()
                .foregroundStyle(isNow ? tint : .secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(tint.opacity(isNow ? 0.12 : 0.05)))
        .overlay(RoundedRectangle(cornerRadius: 7)
            .stroke(tint.opacity(isNow ? 0.5 : 0.15), lineWidth: isNow ? 1.1 : 0.6))
        .contextMenu {
            TimerMenuItems(token: slot.id, title: slot.title, hours: slot.hours,
                           iconName: slot.iconName, colorName: slot.colorName)
        }
    }
}

// MARK: - 직접 센 타이머의 얼굴

/// 일정 기준을 벗어나 '지금부터' 세는 중. 늦게 시작했거나 계획에 없는 일을 할 때.
struct RunningTimerFace: View {
    @State private var timer = TaskTimer.shared

    private var tint: Color {
        if timer.isOvertime { return .red }
        return timer.target?.colorName.map(paletteColor) ?? .accentColor
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            ZStack {
                // 다 쓴 만큼 고리가 채워진다. 초과해도 두 바퀴 돌지 않는다.
                Circle().stroke(tint.opacity(0.14), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: timer.progress)

                VStack(spacing: 2) {
                    Text(formatCountdown(timer.remaining))
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .contentTransition(.numericText())
                    Text(timer.isOvertime ? "초과" : "남음")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 210, height: 210)
            .padding(.vertical, 4)

            footnote
            controls
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(spacing: 6) {
            Label(timer.target?.title ?? "", systemImage: timer.target?.iconName ?? "timer")
                .font(.system(size: 19, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let planned = timer.target?.plannedSeconds {
                Text("지금부터 " + formatDuration(planned / 3600))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 멈춰 있으면 그렇다고 말한다. 흐르고 있으면 이대로 끝나는 시각을 말한다.
    /// 초과 중일 때 "몇 시에 끝난다"는 거짓말이므로 대신 얼마나 넘겼는지를 적는다.
    @ViewBuilder
    private var footnote: some View {
        if !timer.isRunning {
            Label("멈춰 있습니다", systemImage: "pause.circle")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else if timer.isOvertime {
            Text("계획보다 " + formatDuration(-timer.remaining / 3600) + " 넘겼습니다")
                .font(.system(size: 13))
                .foregroundStyle(.red)
        } else {
            Text("이대로면 " + formatHour(hourOfDay(timer.projectedEnd)) + "에 끝납니다")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    timer.toggle()
                } label: {
                    Label(timer.isRunning ? "일시정지" : "이어서",
                          systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                Button {
                    timer.stop()
                } label: {
                    Label("일정 기준으로", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .help("직접 세는 것을 그만두고, 일정에 적힌 시각을 다시 따릅니다")
            }

            HStack(spacing: 10) {
                Button("+5분") { timer.extend(minutes: 5) }
                Button("+10분") { timer.extend(minutes: 10) }
                Button("처음부터") { timer.restart() }
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 어디서든 보이는 남은 시간

/// 한 주를 보는 자리 맨 위에 서서, 지금 하는 일과 남은 시간을 한 줄로 말한다.
/// 타이머 창을 열어 두지 않아도 "무엇을 하는 중이고 얼마 남았는지"가 늘 보이도록.
struct TimerPill: View {
    /// 일정 기준으로 지금 하고 있는 것. 직접 센 타이머가 있으면 그쪽이 이긴다.
    let slot: ScheduleSlot?
    let onOpen: () -> Void

    @State private var timer = TaskTimer.shared

    var body: some View {
        if let target = timer.target {
            pill(icon: timer.isRunning ? target.iconName : "pause.fill",
                 title: target.title,
                 tint: timer.isOvertime ? .red : (target.colorName.map(paletteColor) ?? .accentColor)) {
                Text(formatCountdown(timer.remaining))
            }
        } else if let slot {
            // 1초마다 숫자만 다시 그린다. 주간 화면 전체를 다시 그리지 않게 여기서 가둔다.
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                pill(icon: slot.iconName,
                     title: slot.title,
                     tint: slot.colorName.map(paletteColor) ?? .accentColor) {
                    Text(formatCountdown(slot.remaining(at: ctx.date)))
                }
            }
        }
    }

    private func pill<Value: View>(icon: String, title: String, tint: Color,
                                   @ViewBuilder value: () -> Value) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                value()
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .help("타이머 창 열기 (⇧⌘R)")
    }
}

// MARK: - 계획 위에서 바로 세기

/// 칩·구간을 오른쪽 눌렀을 때 나오는 한 줄. 어디서 시작하든 같은 말이 되도록 여기 하나만 둔다.
/// 일정에 적힌 시각은 이미 저절로 세고 있으므로, 이건 "지금부터" 따로 세고 싶을 때의 길이다.
struct TimerMenuItems: View {
    let token: String
    let title: String
    let hours: Double
    var iconName: String = "timer"
    var colorName: String? = nil

    @State private var timer = TaskTimer.shared

    var body: some View {
        if timer.isTiming(token) {
            Button { timer.toggle() } label: {
                Label(timer.isRunning ? "타이머 일시정지" : "타이머 이어서",
                      systemImage: timer.isRunning ? "pause.fill" : "play.fill")
            }
            Button { timer.stop() } label: {
                Label("일정 기준으로 되돌리기", systemImage: "arrow.uturn.backward")
            }
        } else {
            Button {
                timer.start(token: token, title: title, plannedSeconds: hours * 3600,
                            iconName: iconName, colorName: colorName)
            } label: {
                Label("지금부터 \(formatDuration(hours)) 세기", systemImage: "timer")
            }
        }
    }
}

/// 칩 안에서 "이건 지금 세고 있다"를 남은 시간으로 말한다.
/// 계획을 보는 자리에서 눈을 떼지 않아도 얼마 남았는지 읽히도록.
struct TimerBadge: View {
    let token: String
    var tint: Color = .accentColor
    /// 일정 기준으로 지금 하고 있는 조각. 직접 센 타이머가 없을 때 이 값이 선다.
    var slot: ScheduleSlot? = nil

    @State private var timer = TaskTimer.shared

    var body: some View {
        if timer.isTiming(token) {
            badge(icon: timer.isRunning ? "timer" : "pause.fill",
                  tint: timer.isOvertime ? .red : tint) {
                Text(formatCountdown(timer.remaining))
            }
        } else if !timer.isActive, let slot, slot.id == token {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                // 끝난 조각은 스스로 사라진다 — 바깥이 다시 그려주기를 기다리지 않는다.
                if slot.contains(ctx.date) {
                    badge(icon: "timer", tint: tint) {
                        Text(formatCountdown(slot.remaining(at: ctx.date)))
                    }
                }
            }
        }
    }

    private func badge<Value: View>(icon: String, tint: Color,
                                    @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            value()
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(tint)
        // 요일 칸은 좁다. 줄바꿈을 허락하면 숫자가 세로로 무너진다.
        .lineLimit(1)
        .fixedSize()
    }
}

/// 그 시각을 0–24 소수 시간으로. (14:30 → 14.5)
func hourOfDay(_ date: Date) -> Double {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
}
