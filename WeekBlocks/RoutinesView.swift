import SwiftUI
import SwiftData

struct RoutineRow: View {
    let routine: Routine
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(routine.displayColor.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: routine.iconName)
                    .foregroundStyle(routine.displayColor)
                    .font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.body.weight(.medium))
                Text(routine.scheduleDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                if routine.kind == .fixed {
                    Text(String(format: "%.1fh/일", routine.durationHours))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                }
                Text(String(format: "%.1fh/주", routine.totalWeeklyHours))
                    .font(routine.kind == .fixed ? .caption : .callout)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            if hovering {
                Button { onEdit() } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                if routine.kind == .fixed {
                    // 협상 불가 고정 루틴은 실수 삭제 방지를 위해 목록에선 잠금.
                    // 삭제는 편집(연필) → 삭제 버튼에서 확인 후 가능.
                    Button { onEdit() } label: {
                        Image(systemName: "lock.fill").font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("협상 불가 고정 루틴 — 편집에서 삭제할 수 있습니다")
                } else {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            } else if routine.kind == .fixed {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.45))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        .draggable("routine:\(routine.name)")
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
    }
}

/// "고정 루틴 · 협상 불가" 섹션용 블록 카드. 고정·쿼터 두 종류 모두 표시.
struct RoutineBlock: View {
    let routine: Routine
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        let color = routine.displayColor
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: routine.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(routine.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hovering {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    if routine.kind == .fixed {
                        // 협상 불가 고정 루틴 — 실수 삭제 방지로 잠금(편집에서만 삭제).
                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        Button(role: .destructive) { onDelete() } label: {
                            Image(systemName: "trash").font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                } else if routine.kind == .fixed {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(.secondary.opacity(0.45))
                }
            }

            Text(routine.scheduleDescription)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)   // 1줄짜리도 2줄 공간 확보 → 모든 블록 높이 통일
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if routine.kind == .fixed {
                    Text(String(format: "%.1fh/일", routine.durationHours))
                        .font(.system(size: 11, weight: .medium))
                }
                Text(String(format: "%.1fh/주", routine.totalWeeklyHours))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(hovering ? 0.16 : 0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(hovering ? 0.45 : 0.28), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .draggable("routine:\(routine.name)")
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { onEdit() }
        .help(routine.scheduleDescription)
    }
}

struct RoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let existing: Routine?

    @State private var name: String = ""
    @State private var iconName: String = "calendar"
    @State private var kind: RoutineKind = .fixed
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var startHour: Double = 7
    @State private var durationHours: Double = 1
    @State private var weeklyHours: Double = 4
    @State private var sessionsPerDay: Int = 0
    @State private var showingDeleteConfirm = false

    private let iconOptions: [String] = [
        "moon.fill", "fork.knife", "figure.run", "figure.walk", "figure.strengthtraining.traditional",
        "bed.double.fill", "cup.and.saucer.fill", "book.fill", "person.2.fill",
        "heart.fill", "calendar", "briefcase.fill", "house.fill"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(existing == nil ? "루틴 추가" : "루틴 편집")
                    .font(.title3.weight(.medium))
                Spacer()
            }
            .padding(20)

            Divider()

            Form {
                Section("기본") {
                    TextField("이름", text: $name, prompt: Text("예: 수면, 식사, 운동"))
                    iconPicker
                }

                Section("스케줄 방식") {
                    Picker("방식", selection: $kind) {
                        ForEach(RoutineKind.allCases) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if kind == .fixed {
                    Section("요일") {
                        HStack(spacing: 6) {
                            ForEach(DayOfWeek.allCases) { day in
                                DayToggle(
                                    label: day.shortLabel,
                                    isOn: selectedDays.contains(day)
                                ) {
                                    if selectedDays.contains(day) { selectedDays.remove(day) }
                                    else { selectedDays.insert(day) }
                                }
                            }
                        }
                    }
                    Section("시간") {
                        HStack {
                            Text("시작")
                            Spacer()
                            DatePicker("", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text(endTimeLabel)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack {
                            Text("길이")
                            Spacer()
                            TextField("", value: $durationHours, format: .number.precision(.fractionLength(0...2)))
                                .frame(width: 56)
                                .multilineTextAlignment(.trailing)
                            Text("h").foregroundStyle(.secondary)
                            Stepper("", value: $durationHours, in: 0.25...24, step: 0.5)
                                .labelsHidden()
                        }
                        HStack {
                            Text("주간 합계")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f h", Double(selectedDays.count) * durationHours))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } else {
                    Section("주간 쿼터") {
                        HStack {
                            Text("주 (h)")
                            Spacer()
                            TextField("", value: $weeklyHours, format: .number.precision(.fractionLength(0...2)))
                                .frame(width: 100)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            Text("하루 횟수")
                            Spacer()
                            Stepper(sessionsPerDay > 0 ? "\(sessionsPerDay)회 (끼니·세션)" : "미설정",
                                    value: $sessionsPerDay, in: 0...12)
                        }
                        if weeklyHours > 0 {
                            HStack(alignment: .firstTextBaseline) {
                                Text("계산")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(quotaPreview)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                            }
                            .font(.callout)
                        }
                        Text("정확한 요일·시간 없이 주 단위로만 추적합니다. 자유 시간 계산에는 그대로 반영됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if let existing {
                    Button(role: .destructive) {
                        if existing.kind == .fixed {
                            showingDeleteConfirm = true   // 고정 루틴은 확인 후 삭제
                        } else {
                            context.delete(existing); try? context.save()
                            dismiss()
                        }
                    } label: {
                        Text("삭제")
                    }
                }
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("저장") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(20)
        }
        .onAppear { loadExisting() }
        .alert("고정 루틴 삭제", isPresented: $showingDeleteConfirm) {
            Button("삭제", role: .destructive) {
                if let existing { context.delete(existing); try? context.save() }
                dismiss()
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("협상 불가 고정 루틴입니다. 이 루틴과 주간 배치가 모두 삭제됩니다. 계속할까요?")
        }
    }

    private var iconPicker: some View {
        HStack(spacing: 6) {
            Text("아이콘")
            Spacer()
            Picker("", selection: $iconName) {
                ForEach(iconOptions, id: \.self) { name in
                    HStack {
                        Image(systemName: name)
                        Text(name)
                    }
                    .tag(name)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
        }
    }

    /// startHour(Double) ↔ Date 브리지 — 시:분 DatePicker용.
    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                let total = Int((startHour * 60).rounded())
                var comps = DateComponents()
                comps.hour = (total / 60) % 24
                comps.minute = total % 60
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                startHour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            }
        )
    }

    private var endTimeLabel: String {
        "→ " + formatHour(startHour + durationHours)
    }

    private var quotaPreview: String {
        let daily = weeklyHours / 7
        var s = "일 평균 " + formatDuration(daily)
        if sessionsPerDay > 0 {
            s += " · 회당 약 " + formatDuration(daily / Double(sessionsPerDay))
        }
        return s
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if kind == .fixed { return !selectedDays.isEmpty && durationHours > 0 }
        return weeklyHours > 0
    }

    private func loadExisting() {
        guard let existing else { return }
        name = existing.name
        iconName = existing.iconName
        kind = existing.kind
        selectedDays = existing.selectedDays
        startHour = existing.startHour
        durationHours = existing.durationHours
        weeklyHours = existing.weeklyHours
        sessionsPerDay = existing.sessionsPerDay
    }

    private func save() {
        let mask = selectedDays.reduce(0) { $0 | (1 << $1.rawValue) }
        if let existing {
            existing.name = name
            existing.iconName = iconName
            existing.kind = kind
            existing.dayMask = mask
            existing.startHour = startHour
            existing.durationHours = durationHours
            existing.weeklyHours = weeklyHours
            existing.sessionsPerDay = sessionsPerDay
        } else {
            let r = Routine(
                name: name,
                iconName: iconName,
                kind: kind,
                dayMask: mask,
                startHour: startHour,
                durationHours: durationHours,
                weeklyHours: weeklyHours,
                sessionsPerDay: sessionsPerDay,
                sortIndex: Int(Date().timeIntervalSince1970)
            )
            context.insert(r)
        }
        try? context.save()
        dismiss()
    }
}

private struct DayToggle: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout.weight(.medium))
                .frame(width: 36, height: 32)
                .background(
                    isOn ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .foregroundStyle(isOn ? Color.accentColor : .primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isOn ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

