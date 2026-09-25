import SwiftUI
import SwiftData

struct RoutineRow: View {
    let routine: Routine
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            GlyphBadge(symbol: routine.iconName, title: routine.name, color: routine.displayColor,
                       size: 32, style: routine.kind == .quota ? .dashed : .filled)
                .scaleEffect(hovering ? 1.04 : 1)
                .animation(Motion.squish, value: hovering)
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
                    Text(String(localized: "\(String(format: "%.1f", routine.durationHours))h/일"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                }
                Text(String(localized: "\(String(format: "%.1f", routine.totalWeeklyHours))h/주"))
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
                    // 중요한 고정 루틴은 실수 삭제 방지를 위해 목록에선 잠금.
                    // 삭제는 편집(연필) → 삭제 버튼에서 확인 후 가능.
                    Button { onEdit() } label: {
                        Image(systemName: "lock.fill").font(.system(size: 14))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("중요한 고정 루틴 — 편집에서 삭제할 수 있습니다")
                } else {
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                }
            } else if routine.kind == .fixed {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .transition(.control)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle.soft(Corner.panel))
        .overlay(RoundedRectangle.soft(Corner.panel).stroke(Color.secondary.opacity(0.12), lineWidth: 0.5))
        .draggable("routine:\(routine.name)")
        .onHover { hovering = $0 }
        .hoverLift(hovering, scale: 1.01)
        .animation(Motion.hover, value: hovering)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit() }
    }
}

/// "고정 루틴 · 중요한 일" 섹션용 블록 카드. 고정·쿼터 두 종류 모두 표시.
struct RoutineBlock: View {
    let routine: Routine
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    var body: some View {
        let color = routine.displayColor
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                GlyphBadge(symbol: routine.iconName, title: routine.name, color: color,
                           size: 26, style: routine.kind == .quota ? .dashed : .filled)
                    .scaleEffect(hovering ? 1.04 : 1)
                    .animation(Motion.squish, value: hovering)
                Text(routine.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if hovering {
                    Button { onEdit() } label: {
                        Image(systemName: "pencil").font(.system(size: 13))
                    }
                    .buttonStyle(.squish)
                    if routine.kind == .fixed {
                        // 중요한 고정 루틴 — 실수 삭제 방지로 잠금(편집에서만 삭제).
                        Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Button(role: .destructive) { onDelete() } label: {
                            Image(systemName: "trash").font(.system(size: 13))
                        }
                        .buttonStyle(.squish)
                        .foregroundStyle(.red)
                    }
                } else if routine.kind == .fixed {
                    Image(systemName: "lock.fill").font(.system(size: 12)).foregroundStyle(.secondary.opacity(0.45))
                        .transition(.control)
                }
            }

            Text(routine.scheduleDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)   // 1줄짜리도 2줄 공간 확보 → 모든 블록 높이 통일
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                if routine.kind == .fixed {
                    Text(String(localized: "\(String(format: "%.1f", routine.durationHours))h/일"))
                        .font(.system(size: 13, weight: .medium))
                }
                Text(String(localized: "\(String(format: "%.1f", routine.totalWeeklyHours))h/주"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(hovering ? 0.14 : 0.08), in: .soft(Corner.panel))
        // 색 채움이 곧 경계다. 테두리는 가리킬 때만 선다.
        .overlay(RoundedRectangle.soft(Corner.panel).strokeBorder(color.opacity(hovering ? 0.35 : 0), lineWidth: 1))
        .contentShape(.soft(Corner.panel))
        .draggable("routine:\(routine.name)")
        .onHover { hovering = $0 }
        .hoverLift(hovering)
        .animation(Motion.hover, value: hovering)
        .onTapGesture(count: 2) { onEdit() }
        .help(routine.scheduleDescription)
    }
}

struct RoutineEditorView: View {
    /// 요일 단추도 시간표와 같은 차례로 선다 (→ WeekStartSetting).
    @AppStorage(WeekStartSetting.key) private var weekStartsOnSunday = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// 겹침을 미리 말해 주려면 이미 세워 둔 것들을 알아야 한다.
    @Query(sort: [SortDescriptor(\Routine.sortIndex)]) private var allRoutinesRaw: [Routine]
    /// 잠긴 기기에서 만든 남의 것은 안 그린다 (→ TodoSharing.swift).
    /// **거르는 자리는 여기 하나뿐이다** — 화면마다 조건을 따로 쓰면 어딘가는 새어 보인다.
    private var allRoutines: [Routine] { allRoutinesRaw.filter(TodoSharing.isVisible) }

    let existing: Routine?

    @State private var name: String = ""
    @State private var iconName: String = "calendar"
    @State private var kind: RoutineKind = .fixed
    @State private var selectedDays: Set<DayOfWeek> = []
    @State private var startHour: Double = 7
    @State private var durationHours: Double = 1
    @State private var weeklyHours: Double = 4
    @State private var sessionsPerDay: Int = 0
    /// 회차별 기본 시각을 **손으로 고쳤는가**. nil 이면 고르게 나눈 값을 쓴다(저장도 nil).
    @State private var customStarts: [Double]?
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
                            ForEach(DayOfWeek.displayOrder(sundayFirst: weekStartsOnSunday)) { day in
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
                        // 만들고 나서 타임라인에서 발견하는 것보다, 만들기 전에 말해 준다.
                        // 막지는 않는다 — 정말 겹쳐야 하는 일도 있다.
                        if !conflicts.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("이미 세워 둔 것과 겹칩니다", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.orange)
                                ForEach(conflicts, id: \.self) { line in
                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.disclose)
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
                        // **횟수 → 회당 → 주 합계** 순으로 묻는다.
                        // 사람은 "밥은 하루 세 번, 한 번에 한 시간"으로 생각하지
                        // "주 21시간"으로 생각하지 않는다. 예전에는 주 합계만 받아서,
                        // 회당 한 시간을 만들려고 21을 역산해 넣어야 했다.
                        HStack {
                            Text("하루 횟수")
                            Spacer()
                            Stepper(sessionsPerDay > 0 ? "\(sessionsPerDay)회 (끼니·세션)" : "미설정",
                                    value: $sessionsPerDay, in: 0...12)
                        }
                        if sessionsPerDay > 0 {
                            HStack {
                                Text("회당 (h)")
                                Spacer()
                                TextField("", value: perSessionBinding,
                                          format: .number.precision(.fractionLength(0...2)))
                                    .frame(width: 100)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        HStack {
                            Text("주 (h)")
                            Spacer()
                            TextField("", value: $weeklyHours, format: .number.precision(.fractionLength(0...2)))
                                .frame(width: 100)
                                .multilineTextAlignment(.trailing)
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
                        if sessionsPerDay > 0 {
                            Text("회당과 주 합계는 한 값의 두 얼굴입니다 — 한쪽을 고치면 다른 쪽이 따라 바뀝니다(회당 × 횟수 × 7일). 편한 쪽으로 넣으세요.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    // 매일 몇 시에 — 지금 시간표에 서 있는 시각이 그대로 보이고, 여기서 고친다.
                    if weeklyHours > 0 {
                        sessionTimesSection
                    }
                }
            }
            .formStyle(.grouped)
            // 방식(고정 ↔ 쿼터)을 바꾸면 묻는 칸이 통째로 갈린다.
            // 겹침 안내도 값이 바뀌는 대로 스스로 서고 내려간다.
            .animation(Motion.disclose, value: kind)
            .animation(Motion.disclose, value: conflicts)
            .animation(Motion.disclose, value: sessionsPerDay > 0)
            .animation(Motion.disclose, value: weeklyHours > 0)
            .animation(Motion.disclose, value: customStarts)

            Divider()

            HStack {
                if let existing {
                    Button(role: .destructive) {
                        if existing.kind == .fixed {
                            showingDeleteConfirm = true   // 고정 루틴은 확인 후 삭제
                        } else {
                            withAnimation(Motion.card) {
                                context.delete(existing); try? context.save()
                            }
                            dismiss()
                        }
                    } label: {
                        Text("삭제")
                    }
                }
                // 버튼이 흐린 이유를 버튼 옆에서 말한다. 예전에는 왜 못 누르는지
                // 아무 데도 안 적혀 있어서, 무엇이 비었는지 찾아 헤매야 했다.
                if !missing.isEmpty {
                    Label("\(missing.joined(separator: " · "))을(를) 채워 주세요",
                          systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.leading, 4)
                        .transition(.control)
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
            .animation(Motion.hover, value: missing)
        }
        .onAppear { loadExisting() }
        .alert("고정 루틴 삭제", isPresented: $showingDeleteConfirm) {
            Button("삭제", role: .destructive) {
                if let existing {
                    withAnimation(Motion.card) {
                        context.delete(existing); try? context.save()
                    }
                }
                dismiss()
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("중요한 고정 루틴입니다. 이 루틴과 주간 배치가 모두 삭제됩니다. 계속할까요?")
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

    /// **회당 시간으로 주 합계를 거꾸로 정한다.**
    ///
    /// 저장되는 값은 여전히 `weeklyHours` 하나다 — 모델을 늘리지 않고 입력하는 각도만
    /// 하나 더 낸 것이다. 두 칸이 같은 값을 가리키므로 어느 쪽을 고쳐도 다른 쪽이 따라온다.
    ///
    ///     주 합계 = 회당 × 하루 횟수 × 7일
    ///
    /// ⚠️ 횟수가 0이면 회당이라는 말이 성립하지 않는다. 그때는 칸을 아예 안 띄운다.
    private var perSessionBinding: Binding<Double> {
        Binding(
            get: {
                guard sessionsPerDay > 0 else { return 0 }
                return weeklyHours / 7 / Double(sessionsPerDay)
            },
            set: { newValue in
                guard sessionsPerDay > 0 else { return }
                weeklyHours = max(0, newValue) * Double(sessionsPerDay) * 7
            }
        )
    }

    private var quotaPreview: String {
        let daily = weeklyHours / 7
        var s = String(localized: "일 평균 \(formatDuration(daily))")
        if sessionsPerDay > 0 {
            s += String(localized: " · 회당 약 \(formatDuration(daily / Double(sessionsPerDay)))")
        }
        return s
    }

    /// 저장하려면 아직 채워야 하는 것들. 비어 있으면 저장할 수 있다.
    private var missing: [String] {
        var m: [String] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { m.append(String(localized: "이름", comment: "루틴을 저장하려면 채워야 하는 칸")) }
        if kind == .fixed {
            if selectedDays.isEmpty { m.append(String(localized: "요일", comment: "루틴을 저장하려면 채워야 하는 칸")) }
            if durationHours <= 0 { m.append(String(localized: "길이", comment: "루틴을 저장하려면 채워야 하는 칸")) }
        } else if weeklyHours <= 0 {
            m.append(String(localized: "주당 시간", comment: "루틴을 저장하려면 채워야 하는 칸"))
        }
        return m
    }

    /// 지금 값으로 세우면 **이미 있는 고정 루틴과 겹치는 곳**들.
    ///
    /// 겹친다고 못 만들게 막지는 않는다 — 회의 중 이동처럼 정말 겹치는 일도 있다.
    /// 다만 만들고 나서 타임라인에서 발견하는 것보다, 만들기 전에 말해 주는 편이 낫다.
    private var conflicts: [String] {
        guard kind == .fixed, !selectedDays.isEmpty, durationHours > 0 else { return [] }
        let mine = (startHour, startHour + durationHours)
        var found: [String] = []
        for other in allRoutines where other.kind == .fixed {
            if let existing, other.persistentModelID == existing.persistentModelID { continue }
            let theirs = (other.startHour, other.startHour + other.durationHours)
            let days = selectedDays.intersection(other.selectedDays)
            guard !days.isEmpty, let overlap = Self.overlapHours(mine, theirs), overlap > 0.01
            else { continue }
            let dayLabels = days.sorted { $0.rawValue < $1.rawValue }.map(\.shortLabel).joined(separator: "·")
            found.append(String(localized: "\(dayLabels) — \(other.name)와 \(fmtHours(overlap))시간"))
        }
        return found
    }

    /// 자정을 넘는 구간까지 보고 겹치는 시간을 잰다 (잠처럼 23시에 시작하는 것들).
    private static func overlapHours(_ a: (Double, Double), _ b: (Double, Double)) -> Double? {
        func split(_ r: (Double, Double)) -> [(Double, Double)] {
            r.1 <= 24 ? [r] : [(r.0, 24), (0, r.1 - 24)]
        }
        var total: Double = 0
        for x in split(a) {
            for y in split(b) {
                total += max(0, min(x.1, y.1) - max(x.0, y.0))
            }
        }
        return total > 0 ? total : nil
    }

    private func fmtHours(_ h: Double) -> String {
        h == h.rounded() ? String(format: "%.0f", h) : String(format: "%.1f", h)
    }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if kind == .fixed { return !selectedDays.isEmpty && durationHours > 0 }
        return weeklyHours > 0
    }

    // MARK: 회차별 시각

    private var pieces: Int { max(1, sessionsPerDay) }
    private var sessionLength: Double { (weeklyHours / 7) / Double(pieces) }

    /// i번째 회차가 **지금** 서는 시각 — 고친 것이 있으면 그것, 없으면 고르게 나눈 값.
    /// 시간표가 그리는 것과 같은 셈이다 (→ Routine.defaultSessionStart).
    private func displayStart(_ i: Int) -> Double {
        if let customStarts, i < customStarts.count {
            return min(max(customStarts[i], 0), max(0, 24 - sessionLength))
        }
        return Routine.evenSessionStart(index: i, pieces: pieces, length: sessionLength)
    }

    private func startBinding(_ i: Int) -> Binding<Date> {
        Binding(
            get: {
                let total = Int((displayStart(i) * 60).rounded())
                var c = DateComponents(); c.hour = (total / 60) % 24; c.minute = total % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                var starts = (0..<pieces).map(displayStart)
                starts[i] = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
                customStarts = starts
            })
    }

    /// **매일 몇 시에** — 지금 시간표에 서 있는 시각을 그대로 보여 주고, 여기서 고치면 모든 날이 따라온다.
    ///
    /// 한때 이 시각은 어디에도 없었다. 하루 활동 구간(07:30~19:30)에 고르게 나눈 계산값이라, 점심을
    /// 12시로 두려면 요일마다 끌어야 했고 다음 주면 도로 13시였다.
    private var sessionTimesSection: some View {
        Section {
            ForEach(0..<pieces, id: \.self) { i in
                HStack {
                    Text(pieces == 1 ? String(localized: "매일") : String(localized: "\(i + 1)회"))
                    Spacer()
                    DatePicker("", selection: startBinding(i), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("→ " + formatHour(displayStart(i) + sessionLength))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } header: {
            Text("매일 몇 시에")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(customStarts == nil
                     ? "지금은 하루 활동 시간(07:30~19:30)에 고르게 나눈 시각입니다. 고치면 모든 날의 기본이 됩니다."
                     : "모든 날의 기본 시각입니다. 시간표에서 그날만 옮긴 것은 그날만 따로 섭니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                if customStarts != nil {
                    Button("고르게 나누기로 되돌리기") { customStarts = nil }
                        .buttonStyle(.borderless)
                        .font(.body)
                }
            }
        }
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
        let stored = existing.storedSessionStarts
        customStarts = stored.isEmpty ? nil : stored
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
            existing.setSessionStarts(customStarts.map { Array($0.prefix(pieces)) })
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
            r.setSessionStarts(customStarts.map { Array($0.prefix(pieces)) })
            context.insert(r)
            Telemetry.record(.routineAdded)
        }
        withAnimation(Motion.card) { try? context.save() }
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
                    in: RoundedRectangle.soft(Corner.chip)
                )
                .foregroundStyle(isOn ? Color.accentColor : .primary)
                .overlay(
                    RoundedRectangle.soft(Corner.chip)
                        .stroke(isOn ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        }
        .buttonStyle(.squish)
        .animation(Motion.hover, value: isOn)
    }
}

