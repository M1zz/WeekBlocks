import SwiftUI
import SwiftData

struct BlockEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let existing: PlanBlock?
    let day: DayOfWeek
    let weekStart: Date
    /// 새 블록일 때 고정 루틴을 피해 자동 배정할 시간대.
    var suggestedBand: TimeBand = .evening

    @State private var title: String = ""
    @State private var timeBand: TimeBand = .evening
    @State private var durationHours: Double = 2
    @State private var successCriteria: String = ""
    @State private var deliverable: String = ""

    @State private var withinRoutine: Bool = false
    @State private var startHour: Double = 9

    @State private var hasCheckedOnce: Bool = false
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

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Form {
                Section("활동") {
                    TextField("무엇을 할 것인가?", text: $title, prompt: Text("예: Swift Combine 학습"))
                        .onChange(of: title) { if hasCheckedOnce { revalidate() } }
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
                    if withinRoutine {
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

                if !withinRoutine {
                    Section {
                        TextField("", text: $successCriteria, prompt: Text("예: sink/assign 차이를 노트에 정리하고 예제 실행 성공"), axis: .vertical)
                            .lineLimit(2...4)
                            .onChange(of: successCriteria) { if hasCheckedOnce { revalidate() } }
                    } header: {
                        Text("성공 기준")
                    } footer: {
                        Text("측정 가능한 문장으로 적어 주세요. \"열심히 한다\", \"잘 한다\"는 통과되지 않습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section {
                        TextField("", text: $deliverable, prompt: Text("예: 정리 노트 1장 + 동작하는 예제 1개"), axis: .vertical)
                            .lineLimit(1...3)
                            .onChange(of: deliverable) { if hasCheckedOnce { revalidate() } }
                    } header: {
                        Text("산출물")
                    } footer: {
                        Text("끝났을 때 손에 남는 것.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if hasCheckedOnce {
                        Section {
                            resultView
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            footerBar
        }
        .onAppear {
            if existing == nil { timeBand = suggestedBand }
            loadExisting()
            // 일반 블록은 처음부터 구체성 피드백을 실시간 표시 (별도 '구체성 체크' 버튼 없이).
            if !withinRoutine {
                hasCheckedOnce = true
                revalidate()
            }
        }
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
        HStack {
            if existing != nil {
                Button(role: .destructive) {
                    if let existing { context.delete(existing); try? context.save() }
                    dismiss()
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
                .disabled(!canSave)
        }
        .padding(20)
    }

    // MARK: logic

    private var canSave: Bool {
        if withinRoutine {
            // 루틴 안 일정은 구체성 검사 없이 제목만 있으면 저장.
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return hasCheckedOnce && issues.isEmpty
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
        withinRoutine = existing.withinRoutine
        if existing.startHour >= 0 { startHour = existing.startHour }
        // 일반 블록만 즉시 구체성 표시
        if !withinRoutine {
            hasCheckedOnce = true
            revalidate()
        }
    }

    private func save() {
        guard canSave else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let sc = successCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
        let dv = deliverable.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing {
            existing.title = t
            existing.timeBand = timeBand
            existing.durationHours = durationHours
            existing.successCriteria = withinRoutine ? "" : sc
            existing.deliverable = withinRoutine ? "" : dv
            existing.day = day
            existing.weekStartDate = weekStart
            existing.withinRoutine = withinRoutine
            existing.startHour = withinRoutine ? startHour : -1
            existing.concreteVerified = !withinRoutine
        } else {
            let block = PlanBlock(
                day: day,
                timeBand: timeBand,
                durationHours: durationHours,
                title: t,
                successCriteria: withinRoutine ? "" : sc,
                deliverable: withinRoutine ? "" : dv,
                weekStartDate: weekStart,
                concreteVerified: !withinRoutine,
                withinRoutine: withinRoutine,
                startHour: withinRoutine ? startHour : -1
            )
            context.insert(block)
        }
        try? context.save()
        dismiss()
    }
}
