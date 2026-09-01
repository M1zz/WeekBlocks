import SwiftUI
import SwiftData

// MARK: - 전파 계약 편집기 (전파 필요 항목의 전처리)
//
// 일반 할 일은 제목과 시간만 있으면 된다. '전파 필요'로 체크한 항목은 이 시트를 통과해야 한다.
// 통과 기준은 내가 이해했는지가 아니라, 상대가 받아서 자기 일에 쓸 수 있는지다.
// 통과하면 데드라인에서 역산한 '알려야 하는 날짜들'과 그날 보낼 문장이 만들어진다.

/// 백로그 항목과 계획 블록 둘 다 계약을 가지므로 소유자 타입에 대해 제네릭이다.
struct BroadcastContractView<Holder: BroadcastContractHolder>: View {
    @Environment(\.modelContext) private var context

    /// 계약의 주인은 할 일(BacklogItem)일 수도, 계획 블록(PlanBlock)일 수도 있다.
    /// 둘은 서로 다른 스토어에 살아서(→ Stores.swift), 이 화면을 어느 쪽에서 열었든
    /// 양쪽을 다 저장해야 적어 둔 계약이 조용히 되돌아가지 않는다.
    private func saveContract() {
        try? context.save()
        PlanStore.shared.save()
        TodoStore.shared.save()
    }
    @Environment(\.dismiss) private var dismiss

    @Bindable var item: Holder

    @State private var issues: [BroadcastContractIssue] = []
    @State private var advisories: [BroadcastContractIssue] = []
    @State private var copied: String? = nil

    private var contract: BroadcastPlanner.Contract { item.broadcastContract }
    private var checkpoints: [BroadcastCheckpoint] { item.broadcastCheckpoints }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            Form {
                audienceSection
                deadlineSection
                handoffSection
                twoDatesSection
                variableSection
                ruleSection
                verdictSection
                if !checkpoints.isEmpty {
                    checkpointSection
                    cardSection
                }
            }
            .formStyle(.grouped)

            Divider()
            footerBar
        }
        .onAppear {
            if item.deadline == nil { seedDeadline() }
            revalidate()
        }
    }

    // MARK: 헤더 / 푸터

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title.isEmpty ? "전파 계약" : item.title)
                    .font(.title3.weight(.medium))
                Text("전파할 것은 진척도가 아니라 판단입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(24)
    }

    private var footerBar: some View {
        HStack(spacing: 10) {
            if !issues.isEmpty {
                // 확정 버튼 옆. 왜 눌리지 않는지가 여기서 끝난다.
                Text(missingFieldLabels.isEmpty
                     ? "\(issues.count)개를 더 채워야 확정할 수 있습니다"
                     : "확정하려면 더 필요합니다 — " + missingFieldLabels.joined(separator: " · "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()

            Button("전파 필요 해제") {
                item.needsBroadcast = false
                item.broadcastContractVerified = false
                saveContract()
                dismiss()
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)

            Button("나중에") { save(verified: false) }
                .keyboardShortcut(.cancelAction)

            Button("계약 확정") { save(verified: true) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!issues.isEmpty)
        }
        .padding(20)
    }

    // MARK: 미작성 표시 (빨간색)

    /// 이 칸을 막고 있는 문제들.
    private func issues(for fields: [BroadcastContractField]) -> [BroadcastContractIssue] {
        issues.filter { issue in
            guard let f = issue.field else { return false }
            return fields.contains(f)
        }
    }

    private func isBlocking(_ fields: BroadcastContractField...) -> Bool {
        !issues(for: fields).isEmpty
    }

    /// 섹션 제목 — 막혀 있으면 색이 아니라 제목에 '미작성'을 붙여 알린다.
    private func sectionHeader(_ title: String, _ fields: BroadcastContractField...) -> some View {
        Text(issues(for: fields).isEmpty ? title : "\(title) — 미작성")
    }

    /// 섹션 안에 붙는 빨간 사유. 왜 확정할 수 없는지 그 자리에서 말해 준다.
    @ViewBuilder
    private func fieldIssues(_ fields: BroadcastContractField...) -> some View {
        let list = issues(for: fields)
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(list) { issue in
                    Text(issue.message)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 2)
        }
    }

    /// 아직 못 채운 칸 이름들 — 푸터에 한 줄로.
    private var missingFieldLabels: [String] {
        var seen: [BroadcastContractField] = []
        for issue in issues {
            if let f = issue.field, !seen.contains(f) { seen.append(f) }
        }
        return seen.map(\.label)
    }

    // MARK: 섹션 — 대상

    private var audienceSection: some View {
        Section {
            Picker("대상", selection: audienceBinding) {
                ForEach(BroadcastAudience.allCases) { a in
                    Text(a.label).tag(a)
                }
            }
            TextField("누구에게", text: $item.broadcastRecipient,
                      prompt: Text("예: 박팀장 / 디자인팀 김OO"))
                .onChange(of: item.broadcastRecipient) { revalidate() }
        } header: {
            sectionHeader("누구에게", .recipient)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                fieldIssues(.recipient)
                Text(item.broadcastAudience.needsMost)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 섹션 — 데드라인

    private var deadlineSection: some View {
        Section {
            optionalDateRow("데드라인", date: dateBinding(\.deadline),
                            defaultOffset: 14, blocking: isBlocking(.deadline))
        } header: {
            sectionHeader("데드라인", .deadline)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                fieldIssues(.deadline)
                Text("내가 끝내려는 날이 아니라 넘어가야 하는 날. 전파 시점은 여기서 역산됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 섹션 — 넘길 형태

    private var handoffSection: some View {
        Section {
            TextField("", text: $item.handoffForm,
                      prompt: Text("예: 필드 정의 문서 1장 + 동작하는 API 엔드포인트 2개"),
                      axis: .vertical)
                .lineLimit(1...3)
                .onChange(of: item.handoffForm) { revalidate() }
        } header: {
            sectionHeader("넘길 형태", .handoffForm)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                fieldIssues(.handoffForm)
                Text("형태를 먼저 선언해두면 상대가 병렬로 일할 수 있고, 내부는 몇 번을 갈아엎어도 알릴 필요가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 섹션 — 두 날짜

    private var twoDatesSection: some View {
        Section {
            // 비어 있는 쪽을 짚어 준다. 두 날짜가 다 있는데 순서·범위가 어긋난 경우는
            // 섹션 제목과 아래 빨간 사유가 알려 준다.
            optionalDateRow("빠르면", date: dateBinding(\.earliestDate), defaultOffset: 7,
                            blocking: isBlocking(.dates) && item.earliestDate == nil)
            optionalDateRow("늦어도 (보장)", date: dateBinding(\.latestDate), defaultOffset: 12,
                            blocking: isBlocking(.dates) && item.latestDate == nil)

            if item.deadline != nil && (item.earliestDate == nil || item.latestDate == nil) {
                Button("데드라인에서 두 날짜 추천") { suggestTwoDates() }
                    .buttonStyle(.borderless)
            }
        } header: {
            sectionHeader("두 날짜", .dates)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                fieldIssues(.dates)
                Text("단일 날짜는 그 날짜가 곧 리스크가 됩니다. 두 개로 주면 어긋날 여지가 계약에 포함됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 섹션 — 확신도 / 변수

    private var variableSection: some View {
        Section {
            Picker("확신도", selection: confidenceBinding) {
                ForEach(BroadcastConfidence.allCases) { c in
                    Text(c.label).tag(c)
                }
            }
            .pickerStyle(.segmented)

            TextField("지금 미확정인 것", text: $item.openVariable,
                      prompt: Text("예: 외부 API 응답 속도 (없으면 \"없음\")"))
                .onChange(of: item.openVariable) { revalidate() }

            if BroadcastPlanner.hasOpenVariable(contract) {
                optionalDateRow("판명되는 날", date: dateBinding(\.variableResolveDate),
                                defaultOffset: 4, blocking: isBlocking(.variableResolve))
            }
        } header: {
            sectionHeader("확신도와 변수", .openVariable, .variableResolve)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                fieldIssues(.openVariable, .variableResolve)
                Text("예고된 변수는 리스크가 아니지만, 예고 없이 나타난 변수는 리스크입니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 섹션 — 규칙

    private var ruleSection: some View {
        Section {
            Toggle("\"연락 없음 = 정상 진행\" 규칙 합의됨", isOn: $item.noSignalRuleAgreed)
                .onChange(of: item.noSignalRuleAgreed) { revalidate() }
        } footer: {
            Text("착수 시점에 못 박으면 그 뒤의 중간 문의가 거의 사라집니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 섹션 — 검사 결과

    private var verdictSection: some View {
        Section {
            // 막는 사유는 각 칸 아래에 이미 빨갛게 있고 푸터에도 요약된다.
            // 여기서 또 나열하면 같은 말이 세 번 나온다. 통과 상태만 알린다.
            if issues.isEmpty {
                Text("확정할 수 있습니다. 상대가 받아서 쓸 수 있는 계약입니다.")
                    .font(.callout)
            }
            ForEach(advisories) { a in
                Text(a.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 섹션 — 추천 전파 시점 (역산 결과)

    private var checkpointSection: some View {
        Section {
            ForEach(checkpoints) { cp in
                CheckpointRow(
                    checkpoint: cp,
                    onToggleDone: {
                        item.markCheckpoint(cp.token, done: !cp.isDone)
                        saveContract()
                    },
                    onCopy: { copy(cp.script, key: cp.token) },
                    copied: copied == cp.token
                )
            }
        } header: {
            HStack {
                Text("알려야 하는 날짜 — 데드라인 역산")
                Spacer()
                if let promise = BroadcastPlanner.promiseDate(contract) {
                    Text("기준 \(BroadcastPlanner.dateLabel(promise))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("역산 기준은 데드라인이 아니라 '늦어도' 보장일입니다. 낌새가 보이면 날짜를 기다리지 말고 즉시 보내세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 섹션 — 어디 한 곳에 둘 네 줄

    private var cardSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(BroadcastPlanner.contractCard(contract))
                    .font(.system(size: 14, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                Button(copied == "card" ? "복사됨" : "복사") {
                    copy(BroadcastPlanner.contractCard(contract), key: "card")
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("어디 한 곳에 써둘 네 줄")
        } footer: {
            Text("한 곳에 써두고 변경 시 갱신하면 같은 질문을 여러 번 받지 않습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 바인딩 헬퍼

    private var audienceBinding: Binding<BroadcastAudience> {
        Binding(
            get: { item.broadcastAudience },
            set: { item.broadcastAudience = $0; revalidate() }
        )
    }

    private var confidenceBinding: Binding<BroadcastConfidence> {
        Binding(
            get: { item.broadcastConfidence },
            set: { item.broadcastConfidence = $0; revalidate() }
        )
    }

    private func dateBinding(_ key: ReferenceWritableKeyPath<Holder, Date?>) -> Binding<Date?> {
        Binding(
            get: { item[keyPath: key] },
            set: { item[keyPath: key] = $0; revalidate() }
        )
    }

    /// 날짜가 없으면 '추가' 버튼, 있으면 DatePicker + 지우기.
    /// `blocking`이면 이 칸이 계약 확정을 막고 있다는 뜻이라 빨갛게 표시한다.
    private func optionalDateRow(_ label: String,
                                 date: Binding<Date?>,
                                 defaultOffset: Int,
                                 blocking: Bool = false) -> some View
    {
        HStack {
            Text(blocking ? "\(label) — 미작성" : label)
            Spacer()
            if let value = date.wrappedValue {
                DatePicker("", selection: Binding(get: { value }, set: { date.wrappedValue = $0 }),
                           displayedComponents: .date)
                    .labelsHidden()
                Text(BroadcastPlanner.dDayLabel(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("지우기") { date.wrappedValue = nil }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("날짜 지정") {
                    date.wrappedValue = Calendar.current.date(byAdding: .day, value: defaultOffset, to: Date())
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: 로직

    private func revalidate() {
        let c = item.broadcastContract
        issues = BroadcastContractChecker.validate(c)
        advisories = issues.isEmpty ? BroadcastContractChecker.advisories(c) : []
    }

    /// 데드라인이 비어 있으면 항목이 속한 주의 금요일을 초기값으로 제안한다.
    private func seedDeadline() {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let friday = cal.date(byAdding: .day, value: 4, to: item.weekStartDate) ?? Date()
        item.deadline = friday > Date() ? friday : cal.date(byAdding: .day, value: 11, to: friday)
    }

    /// 데드라인에서 두 날짜를 제안한다. '늦어도'는 데드라인 하루 전(넘기지 않도록),
    /// '빠르면'은 남은 기간의 30%를 앞당긴 날.
    private func suggestTwoDates() {
        guard let deadline = item.deadline else { return }
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2

        let span = max(1, BroadcastPlanner.dayCount(from: item.createdAt, to: deadline))
        let latest = cal.date(byAdding: .day, value: span >= 3 ? -1 : 0, to: deadline) ?? deadline
        let backoff = max(1, Int((Double(span) * 0.3).rounded()))
        let earliest = cal.date(byAdding: .day, value: -backoff, to: latest) ?? latest

        if item.latestDate == nil { item.latestDate = latest }
        if item.earliestDate == nil {
            item.earliestDate = max(earliest, cal.startOfDay(for: Date()))
        }
        revalidate()
    }

    private func save(verified: Bool) {
        item.needsBroadcast = true
        item.broadcastContractVerified = verified && issues.isEmpty
        saveContract()
        dismiss()
    }

    private func copy(_ text: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = key
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if copied == key { copied = nil }
        }
    }
}

// MARK: - 전파 시점 한 줄

struct CheckpointRow: View {
    let checkpoint: BroadcastCheckpoint
    let onToggleDone: () -> Void
    let onCopy: () -> Void
    let copied: Bool

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                // 날짜 · D-day · "오늘 보내세요"는 같은 사실의 세 표현이라 D-day 하나로 합쳤다.
                VStack(alignment: .leading, spacing: 2) {
                    Text(checkpoint.kind.label)
                        .font(.system(size: 15))
                        .strikethrough(checkpoint.isDone, color: .secondary)
                        .foregroundStyle(checkpoint.isDone ? .secondary : .primary)
                    // 보냄 여부는 취소선이, 급한 정도는 "3일 지남"/"오늘" 같은 말이 전달한다.
                    Text(checkpoint.isDone
                         ? "\(BroadcastPlanner.dateLabel(checkpoint.date)) · 보냄"
                         : "\(BroadcastPlanner.dateLabel(checkpoint.date)) · \(BroadcastPlanner.dDayLabel(checkpoint.date))")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer(minLength: 12)

                Button(expanded ? "접기" : "문장") { expanded.toggle() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 13))

                Button(checkpoint.isDone ? "보냄 취소" : "보냈음", action: onToggleDone)
                    .buttonStyle(.borderless)
                    .font(.system(size: 13))
            }

            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(checkpoint.kind.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(checkpoint.script)
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))

                    Button(copied ? "복사됨" : "복사", action: onCopy)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
