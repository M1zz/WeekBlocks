import SwiftUI
import SwiftData

struct BlockEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// 이 날에 이미 잡혀 있는 것들 — 만들기 전에 자리가 있는지 말해 주려고 본다.
    @Query(sort: [SortDescriptor(\Routine.sortIndex)]) private var allRoutinesRaw: [Routine]
    /// 잠긴 기기에서 만든 남의 것은 안 그린다 (→ TodoSharing.swift).
    /// **거르는 자리는 여기 하나뿐이다** — 화면마다 조건을 따로 쓰면 어딘가는 새어 보인다.
    private var allRoutines: [Routine] { allRoutinesRaw.filter(TodoSharing.isVisible) }
    @Query private var allBlocksRaw: [PlanBlock]
    /// 잠긴 기기에서 만든 남의 것은 안 그린다 (→ TodoSharing.swift).
    /// **거르는 자리는 여기 하나뿐이다** — 화면마다 조건을 따로 쓰면 어딘가는 새어 보인다.
    private var allBlocks: [PlanBlock] { allBlocksRaw.filter(TodoSharing.isVisible) }
    let existing: PlanBlock?
    let day: DayOfWeek
    let weekStart: Date
    /// 새 블록일 때 고정 루틴을 피해 자동 배정할 시간대.
    var suggestedBand: TimeBand = .evening
    /// 새 블록을 **이 시각에** 세운다 — 일간의 빈 시간을 눌러 열었을 때. nil이면 시간대로만 둔다.
    var initialStartHour: Double? = nil
    /// 새 블록의 처음 길이 — 빈 시간의 길이. 두 시간을 넘으면 기본값(2시간)을 둔다.
    var initialDuration: Double? = nil
    /// 그 길이를 **사람이 직접 그었는가** — 빈 시간을 위아래로 훑어 범위를 그린 경우.
    /// 그때는 깎지 않는다. 다섯 시간 빈자리를 누른 것과 세 시간을 그은 것은 다른 말이다.
    var initialDurationIsExplicit: Bool = false
    /// **이미 확보된 루틴 시간 안의 일정으로 연다** — 일간에서 루틴 띠의 `+`로 왔을 때.
    /// 회사 시간 안의 회의는 자유 시간을 더 쓰지 않는다. 창을 열자마자 그 뜻이 켜져 있어야
    /// 사람이 토글을 다시 찾아 켤 일이 없다.
    var initialWithinRoutine: Bool = false

    @State private var title: String = ""
    @State private var timeBand: TimeBand = .evening
    @State private var durationHours: Double = 2
    @State private var successCriteria: String = ""
    @State private var deliverable: String = ""

    /// 돌아왔을 때 무엇부터 할지 (→ PlanBlock.nextAction).
    @State private var nextAction: String = ""
    @State private var withinRoutine: Bool = false
    @State private var startHour: Double = 9
    /// **몇 시에 하는지 정해 둔 블록인가.**
    ///
    /// 예전에는 '루틴 안 일정'만 정확한 시각을 가졌고, 나머지는 시간대(아침·오후·…)만 물었다.
    /// 그러나 하루 시간표가 생긴 뒤로 보통 블록도 시각을 갖는다 — 빈 시간을 훑어 그리거나,
    /// 할 일 카드를 자 위에 떨어뜨리면 그 높이가 곧 시작 시각이다. 그런데도 이 창은 시간대만
    /// 보여 주었고, **저장할 때 그 시각을 -1로 지웠다.** 14시에 세워 둔 블록을 열어 제목만
    /// 고쳐도 시각이 날아갔다. 이제 시각이 있는 블록은 시각을 보여 주고 그대로 지킨다.
    ///
    /// 끄면 "그날 하긴 하는데 몇 시인지는 안 정함"이 된다 (`startHour = -1`).
    /// 하루 시간표에서 알약을 계획 판으로 끌어내는 것(→ ContentView.onClearTime)과 같은 상태다.
    @State private var hasExactTime: Bool = false

    /// '자세히 정하기'를 펼쳐 두었는가. **기본은 접힘.**
    /// 이미 적어 둔 것이 있는 블록을 열 때만 펴서, 적힌 글이 접힌 채 숨지 않게 한다.
    @State private var showsDetail: Bool = false
    /// 새 블록에서 **제목 말고 다른 것도 정하러** 펼쳤는가. 기본은 접힘 — 제목 한 줄만 묻는다.
    @State private var showsMore: Bool = false
    @FocusState private var titleFocused: Bool
    @State private var issues: [ConcretenessIssue] = []

    /// startHour(Double) ↔ Date 브리지 — 시:분 DatePicker용.
    private var startTimeBinding: Binding<Date> {
        Binding(
            get: {
                let total = Int((startHour * 60).rounded())
                var c = DateComponents(); c.hour = (total / 60) % 24; c.minute = total % 60
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                startHour = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
            }
        )
    }

    /// **새 블록은 제목 한 줄이면 된다.**
    ///
    /// 빈 시간을 훑어서 왔으면 요일·시각·길이는 이미 정해져 있다. 그런데 창은 "활동 / 무엇을
    /// 할 것인가?"부터 루틴 안 토글, 시각 토글, 길이, 자세히 정하기까지 한 벌을 다 펼쳐 놓아서,
    /// 제목 하나 적으려고 연 창이 설문지처럼 보였다. 이미 정해진 것은 한 줄로 **말해 주고**,
    /// 고치고 싶을 때만 그 줄을 눌러 펼친다. 적고 ⏎ 치면 끝.
    private var isCompact: Bool { existing == nil && !showsMore }

    var body: some View {
        Group {
            if isCompact { compactBody } else { fullBody }
        }
        .animation(Motion.disclose, value: showsMore)
        // 시각을 정하기로 켰는데 아직 아무 시각도 없으면, 고른 시간대가 시작하는 때로 세운다.
        // 00:00이 뜨면 사람이 거기서부터 스무 번을 눌러야 한다.
        .onChange(of: hasExactTime) { _, on in
            guard on, existing?.startHour ?? -1 < 0, initialStartHour == nil else { return }
            startHour = timeBand.defaultStartHour
        }
        // ⚠️ 바깥(body)에 둔다. 펼친 창에만 붙여 두면 접힌 창에서는 안 불려서,
        //    훑어 그은 시각·길이 대신 09:00 · 2시간이 떴다.
        .onAppear {
            if existing == nil {
                timeBand = initialStartHour.map(TimeBand.containing) ?? suggestedBand
                // 루틴 띠 오른쪽 절반을 훑어서 왔다 — 루틴 시간 안의 일정이다.
                withinRoutine = initialWithinRoutine
                // 빈 시간을 훑거나 눌러서 왔으면 그 시각이 이미 정해진 것이다.
                if let h = initialStartHour { startHour = h; hasExactTime = true }
                if let d = initialDuration {
                    let snapped = max(0.25, (d * 4).rounded(.down) / 4)
                    durationHours = initialDurationIsExplicit ? snapped : min(2, snapped)
                }
            }
            loadExisting()
            revalidate()
        }
        // 창이 뜨자마자 제목 칸에 손이 가 있다. 시트가 서는 한 박자 뒤에 잡아야 먹힌다.
        .task {
            try? await Task.sleep(for: .milliseconds(80))
            titleFocused = true
        }
    }

    private var compactBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("제목", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .focused($titleFocused)
                    .onSubmit { save() }
                    .onChange(of: title) { revalidate() }

                // 이미 정해진 것 — 요일·시각·길이. 누르면 전부 펼쳐 고친다.
                Button {
                    showsMore = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: withinRoutine ? "rectangle.inset.filled" : "clock")
                        Text(whenSummary)
                            .monospacedDigit()
                        Image(systemName: "chevron.down")
                            .imageScale(.small)
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingCursor()
                .help(String(localized: "시각·길이·자세한 내용 정하기"))
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            footerBar
        }
        .frame(width: 460)
    }

    /// 접힌 창에서 이미 정해진 것을 한 줄로. "월요일 · 11:00–12:00 · 1시간"
    private var whenSummary: String {
        let span = formatDuration(durationHours)
        if withinRoutine || hasExactTime {
            let range = "\(formatHour(startHour))–\(formatHour(startHour + durationHours))"
            return withinRoutine
                ? String(localized: "\(day.longLabel) · \(range) · 루틴 시간 안")
                : String(localized: "\(day.longLabel) · \(range) · \(span)")
        }
        return String(localized: "\(day.longLabel) · \(timeBand.label) · \(span)")
    }

    private var fullBody: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Form {
                Section {
                    TextField("제목", text: $title, prompt: Text("제목"))
                        .focused($titleFocused)
                        .onChange(of: title) { revalidate() }
                }

                Section {
                    Toggle("기존 루틴 시간 안에서 진행 (회의 등)", isOn: $withinRoutine)
                } footer: {
                    if withinRoutine {
                        Text("회사일 같은 이미 확보된 시간 안의 일정입니다. 자유 시간을 추가로 쓰지 않고, 타임라인에서 루틴 위에 겹쳐 표시됩니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("시간") {
                    // 루틴 안 일정은 늘 시각을 갖는다 — 회의는 '오후 어딘가'에 있지 않다.
                    if !withinRoutine {
                        Toggle("몇 시에 할지 정하기", isOn: $hasExactTime)
                    }
                    if withinRoutine || hasExactTime {
                        HStack {
                            Text("시작")
                            Spacer()
                            DatePicker("", selection: startTimeBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                            Text("→ " + formatHour(startHour + durationHours))
                                .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                        }
                    } else {
                        Picker("시간대", selection: $timeBand) {
                            ForEach(TimeBand.allCases) { band in
                                Text(band.label).tag(band)
                            }
                        }
                    }
                    HStack {
                        Text("길이 (h)")
                        Spacer()
                        TextField("", value: $durationHours, format: .number.precision(.fractionLength(0...2)))
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $durationHours, in: 0.25...12, step: 0.25)
                            .labelsHidden()
                    }
                }

                // **고급 질문은 접어 둔다.**
                //
                // 계획을 세우는 손이 가장 자주 하는 일은 '무엇을 몇 시에'까지다. 성공 기준·
                // 산출물·다음 첫 동작은 그 일을 벼릴 때 쓰는 것이지, 블록 하나 세울 때마다
                // 통과해야 하는 관문이 아니다 — 애초에 할 일 카드를 끌어다 놓아 만든 블록은
                // 이 셋을 묻지도 않는다(→ ContentView.convertBacklogItem). 편집창만 강요하는
                // 바람에 같은 블록이 만드는 길에 따라 다른 잣대를 받고 있었다.
                //
                // 비워 둔 채 저장하면 그 블록은 '구체성 미검증'으로 서고(주황색, → DayTimelineView),
                // 나중에 눌러서 다듬으면 된다. 막는 대신 표시한다.
                if !withinRoutine {
                    Section {
                        DisclosureGroup(isExpanded: $showsDetail) {
                            detailFields
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("자세히 정하기")
                                Text(detailSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            // '루틴 안'을 켜면 묻는 칸이 통째로 달라진다. 구체성 판정도 적는 대로 바뀐다.
            .animation(Motion.disclose, value: withinRoutine)
            .animation(Motion.disclose, value: hasExactTime)
            .animation(Motion.disclose, value: showsDetail)
            .animation(Motion.row, value: issues.map(\.message))

            Divider()

            footerBar
        }
        .frame(minWidth: 520, minHeight: 540)
    }

    // MARK: subviews

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(existing == nil ? "\(day.longLabel) — 블록 추가" : "\(day.longLabel) — 블록 다듬기")
                    .font(.title3.weight(.medium))
                if let existing, let reviewedAt = existing.reviewedAt {
                    Text("회고 완료 · \(reviewedAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(20)
    }

    /// 접어 둔 고급 질문들. 세울 때 통과해야 하는 관문이 아니라, 벼릴 때 쓰는 자리다.
    private var detailFields: some View {
        VStack(alignment: .leading, spacing: 14) {
            detailField("성공 기준",
                        footer: "측정 가능한 문장으로 적어 주세요. \"열심히 한다\", \"잘 한다\"는 통과되지 않습니다.") {
                TextField("", text: $successCriteria,
                          prompt: Text("예: sink/assign 차이를 노트에 정리하고 예제 실행 성공"), axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: successCriteria) { revalidate() }
            }
            detailField("산출물", footer: "끝났을 때 손에 남는 것.") {
                TextField("", text: $deliverable,
                          prompt: Text("예: 정리 노트 1장 + 동작하는 예제 1개"), axis: .vertical)
                    .lineLimit(1...3)
                    .onChange(of: deliverable) { revalidate() }
            }
            // 돌아왔을 때 다시 올라오는 값을 줄이는 한 줄 (→ PlanBlock.nextAction).
            // 보통은 타이머를 멈출 때 적지만, 미리 적어 둘 수도 있어야 한다.
            detailField("다음 첫 동작", footer: "끊겼다가 돌아왔을 때 무엇부터 하면 되는지. 비워 두어도 됩니다.") {
                TextField("", text: $nextAction, prompt: Text("예: 3번 예제부터 다시 돌려보기"), axis: .vertical)
                    .lineLimit(1...3)
            }
            // 아무것도 안 적었는데 "아직 추상적입니다"를 들이미는 것은 나무라는 것이다.
            // 적기 시작한 뒤부터 본다.
            if hasDetail { resultView }
        }
        .padding(.top, 6)
    }

    private func detailField<Content: View>(_ title: LocalizedStringKey, footer: LocalizedStringKey,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.callout.weight(.medium))
            content()
            Text(footer).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// 고급 칸에 무언가 적었는가.
    private var hasDetail: Bool {
        !successCriteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !deliverable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !nextAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 접어 둔 채로도 안에 무엇이 있는지 한 줄로 말한다.
    private var detailSummary: String {
        guard hasDetail else {
            return String(localized: "성공 기준 · 산출물 · 다음 첫 동작 — 비워 두어도 저장됩니다")
        }
        return issues.isEmpty
            ? String(localized: "구체성 통과")
            : String(localized: "아직 덜 적었습니다")
    }

    private var resultView: some View {
        Group {
            if issues.isEmpty {
                Label {
                    Text("충분히 구체적입니다. 끝난 뒤 잘 보냈는지 판단할 수 있습니다.")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .font(.callout)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("아직 추상적입니다", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout.weight(.medium))
                    ForEach(issues) { issue in
                        HStack(alignment: .top, spacing: 6) {
                            Text("·")
                            Text(issue.message)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var footerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 이 날에 자리가 남는지 먼저 말한다. 넘겨도 막지는 않는다 —
            // 하루를 넘겨 잡아 두고 나중에 줄이는 것도 계획하는 방법이다.
            if let crowding {
                Label(crowding, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.disclose)
            }

            HStack {
            if existing != nil {
                Button(role: .destructive) {
                    if let existing {
                        withAnimation(Motion.card) {
                            context.delete(existing); try? context.save()
                        }
                    }
                    dismiss()
                } label: {
                    Text("삭제")
                }
            }
            Spacer()
            Button("취소") { dismiss() }
                .keyboardShortcut(.cancelAction)

            // 버튼이 흐린 이유를 버튼 옆에서 말한다.
            if !missing.isEmpty && !isCompact {
                Label("\(missing.joined(separator: " · "))", systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.trailing, 4)
                    .transition(.control)
            }

            Button("저장") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .animation(Motion.hover, value: missing)
        .animation(Motion.disclose, value: crowding)
    }

    /// 저장하려면 아직 해야 하는 것. 비어 있으면 저장할 수 있다.
    ///
    /// 예전에는 성공 기준·산출물까지 통과해야 저장이 열렸다. 그런데 정작 할 일 카드를
    /// 끌어다 놓아 만든 블록은 그 셋 없이도 서 있었다 — 같은 블록에 두 잣대였다.
    /// 이제 막지 않고 **'구체성 미검증'으로 표시**한다 (→ save()의 concreteVerified).
    private var missing: [String] {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return [String(localized: "제목을 적어 주세요")] }
        return []
    }

    /// 이 날이 이미 얼마나 찼는지. 새로 넣을 길이가 남은 자리보다 크면 말해 준다.
    private var crowding: String? {
        guard !withinRoutine, durationHours > 0 else { return nil }
        let cal = Calendar(identifier: .iso8601)
        let dayBlocks = allBlocks.filter {
            $0.day == day && !$0.withinRoutine
                && cal.isDate($0.weekStartDate, inSameDayAs: weekStart)
                && $0.persistentModelID != existing?.persistentModelID
        }
        let routineHours = allRoutines
            .filter { $0.kind == .fixed && $0.selectedDays.contains(day) }
            .reduce(0) { $0 + $1.durationHours }
            + allRoutines.filter { $0.kind == .quota }.reduce(0) { $0 + $1.dailyQuotaHours }
        let planned = dayBlocks.reduce(0) { $0 + $1.durationHours }
        let free = 24 - routineHours - planned
        guard durationHours > free else { return nil }
        let f = { (h: Double) in h == h.rounded() ? String(format: "%.0f", h) : String(format: "%.1f", h) }
        if free <= 0 {
            return String(localized: "\(day.longLabel)은 이미 꽉 찼습니다 — 루틴과 계획으로 24시간을 다 썼어요")
        }
        return String(localized: "\(day.longLabel)에 남은 자리는 \(f(free))시간입니다 — \(f(durationHours))시간을 넣으면 넘칩니다")
    }

    // MARK: logic

    /// 시각을 정해 둔 블록인가. 루틴 안 일정은 늘 그렇다.
    private var keepsExactTime: Bool { withinRoutine || hasExactTime }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func revalidate() {
        issues = ConcretenessChecker.validate(
            title: title,
            successCriteria: successCriteria,
            deliverable: deliverable
        )
    }

    private func loadExisting() {
        guard let existing else { return }
        title = existing.title
        timeBand = existing.timeBand
        durationHours = existing.durationHours
        successCriteria = existing.successCriteria
        deliverable = existing.deliverable
        nextAction = existing.nextAction ?? ""
        withinRoutine = existing.withinRoutine
        hasExactTime = existing.withinRoutine || existing.startHour >= 0
        if existing.startHour >= 0 { startHour = existing.startHour }
        // 이미 적어 둔 것이 있으면 펴 둔다 — 접힌 칸 안에 글이 숨어 있으면 지운 줄 안다.
        showsDetail = hasDetail
        revalidate()
    }

    private func save() {
        guard canSave else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sc = successCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
        let dv = deliverable.trimmingCharacters(in: .whitespacesAndNewlines)
        let na = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        // 막지 않는 대신 표시로 남긴다. 세 가지를 다 통과한 블록만 또렷한 색으로 서고,
        // 비워 둔 것은 주황색 '구체성 미검증'이 되어 나중에 다듬으라고 말한다.
        let verified = !withinRoutine
            && ConcretenessChecker.validate(title: t, successCriteria: sc, deliverable: dv).isEmpty

        if let existing {
            existing.title = t
            existing.durationHours = durationHours
            existing.successCriteria = withinRoutine ? "" : sc
            existing.deliverable = withinRoutine ? "" : dv
            existing.nextAction = na.isEmpty ? nil : na
            existing.day = day
            existing.weekStartDate = weekStart
            existing.withinRoutine = withinRoutine
            // ⚠️ 한때 `withinRoutine ? startHour : -1` 이었다. 자 위에 세워 둔 보통 블록을
            //    열어 제목만 고쳐도 시각이 -1로 지워졌다. 시각을 가진 블록은 시각을 지킨다.
            existing.startHour = keepsExactTime ? startHour : -1
            // 시각이 있으면 시간대는 거기서 따라 나온다 — 둘이 어긋나면 칩의 부제가 거짓말을 한다.
            existing.timeBand = keepsExactTime ? TimeBand.containing(startHour) : timeBand
            existing.concreteVerified = verified
        } else {
            let block = PlanBlock(
                day: day,
                timeBand: keepsExactTime ? TimeBand.containing(startHour) : timeBand,
                durationHours: durationHours,
                title: t,
                successCriteria: withinRoutine ? "" : sc,
                deliverable: withinRoutine ? "" : dv,
                weekStartDate: weekStart,
                concreteVerified: verified,
                withinRoutine: withinRoutine,
                startHour: keepsExactTime ? startHour : -1
            )
            block.nextAction = na.isEmpty ? nil : na
            context.insert(block)
            Telemetry.record(.planBlockAdded)
        }
        // 시트가 닫히면서 뒤 화면에 새 칩이 돋는다. 결 없이 담으면 툭 나타난다.
        withAnimation(Motion.card) { try? context.save() }
        dismiss()
    }
}
