import SwiftUI
import SwiftData

// MARK: - 전파 필요 섹션
//
// 할 일은 전부 백로그에 있다. 이 섹션은 그것을 옮겨오는 게 아니라
// **백로그 항목 중 전파해야 하는 것만 골라 비추는 창**이다. (같은 항목이 양쪽에 보인다)
//
// 여기 모아 두는 이유는 전파가 내가 손을 움직여야 하는 일이기 때문이다.
// 계약을 써 두는 것만으로는 아무 일도 일어나지 않는다.
//
// 순서는 급한 것부터 — 지남 → 오늘 → 예정 → 계약 미확정.
// 전파 필요 항목이 하나도 없으면 섹션 자체가 나타나지 않는다.

struct BroadcastPlanSection: View {
    @Environment(\.modelContext) private var context

    /// 주 구분 없이 모든 할 일 (전파 시점은 주 경계와 무관하다).
    let allItems: [BacklogItem]
    /// 계획 블록도 전파 계약을 가질 수 있다 (백로그 항목을 요일에 드롭하면 블록이 된다).
    /// 계약을 승계해 놓고 여기 안 보이면 넘긴 의미가 없다.
    var allBlocks: [PlanBlock] = []

    /// 계약 시트를 열 대상. 소유자 타입이 둘이므로 케이스로 구분한다.
    private enum ContractTarget: Identifiable {
        case item(BacklogItem)
        case block(PlanBlock)

        var id: PersistentIdentifier {
            switch self {
            case .item(let i): i.persistentModelID
            case .block(let b): b.persistentModelID
            }
        }

        /// 이미 요일에 배치된 계획 블록인가 (백로그에 남아 있는 항목과 구분해 표시한다).
        var isBlock: Bool {
            if case .block = self { return true }
            return false
        }
    }

    @State private var contractTarget: ContractTarget?

    /// 줄 하나의 급한 정도. 정렬과 색을 함께 결정한다.
    private enum Urgency: Int {
        case overdue = 0    // 이미 보내야 했다
        case today = 1      // 오늘 보낸다
        case upcoming = 2   // 예정
        case noContract = 3 // 계약이 없어 날짜조차 없다
    }

    private struct Entry: Identifiable {
        let holder: any BroadcastContractHolder
        let target: ContractTarget
        /// nil이면 계약 미확정 — 아직 전파 시점을 계산할 수 없다.
        let checkpoint: BroadcastCheckpoint?
        let urgency: Urgency

        var id: String {
            "\(holder.persistentModelID.hashValue)-\(checkpoint?.token ?? "nocontract")"
        }
    }

    /// 전파 필요한 것 전부 (백로그 항목 + 계획 블록). 급한 순으로 정렬한다.
    private var entries: [Entry] {
        let itemTargets: [(any BroadcastContractHolder, ContractTarget)] =
            allItems
                .filter { $0.needsBroadcast && !$0.isCompleted }
                .map { ($0, .item($0)) }
        let blockTargets: [(any BroadcastContractHolder, ContractTarget)] =
            allBlocks
                .filter { $0.needsBroadcast }
                .map { ($0, .block($0)) }

        return (itemTargets + blockTargets)
            .map { holder, target -> Entry in
                guard let next = holder.nextBroadcastCheckpoint else {
                    // 계약 미확정이거나, 모든 시점을 이미 보낸 상태.
                    return Entry(holder: holder, target: target, checkpoint: nil, urgency: .noContract)
                }
                let d = BroadcastPlanner.dayCount(from: Date(), to: next.date)
                let urgency: Urgency = d < 0 ? .overdue : (d == 0 ? .today : .upcoming)
                return Entry(holder: holder, target: target, checkpoint: next, urgency: urgency)
            }
            .sorted { a, b in
                if a.urgency != b.urgency { return a.urgency.rawValue < b.urgency.rawValue }
                // 같은 급함 안에서는 날짜순, 날짜가 없으면 제목순.
                switch (a.checkpoint?.date, b.checkpoint?.date) {
                case let (x?, y?): return x < y
                case (nil, nil): return a.holder.title < b.holder.title
                case (_?, nil): return true
                case (nil, _?): return false
                }
            }
    }

    private func count(_ urgency: Urgency) -> Int {
        entries.filter { $0.urgency == urgency }.count
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    headerRow
                    VStack(spacing: 6) {
                        ForEach(entries) { e in
                            PendingBroadcastRow(
                                holder: e.holder,
                                checkpoint: e.checkpoint,
                                isPlanned: e.target.isBlock,
                                onOpen: { contractTarget = e.target },
                                onMarkSent: {
                                    guard let cp = e.checkpoint else { return }
                                    e.holder.markCheckpoint(cp.token, done: true)
                                    // 이 줄의 주인은 할 일일 수도, 계획 블록일 수도 있다.
                                    // 둘은 서로 다른 스토어에 살아서 한쪽만 저장하면 조용히 되돌아간다.
                                    try? context.save()
                                    PlanStore.shared.save()
                                }
                            )
                        }
                    }
                }
                .sheet(item: $contractTarget) { target in
                    Group {
                        switch target {
                        case .item(let item): BroadcastContractView(item: item)
                        case .block(let block): BroadcastContractView(item: block)
                        }
                    }
                    .frame(minWidth: 560, minHeight: 640)
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("전파 필요")
                .font(.headline)
            if !statusSummary.isEmpty {
                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// 상태 요약 한 줄. 0인 항목은 넣지 않고, 전체 개수는 합으로 알 수 있으니 따로 쓰지 않는다.
    private var statusSummary: String {
        var parts: [String] = []
        if count(.overdue) > 0 { parts.append("지남 \(count(.overdue))") }
        if count(.today) > 0 { parts.append("오늘 \(count(.today))") }
        if count(.upcoming) > 0 { parts.append("예정 \(count(.upcoming))") }
        if count(.noContract) > 0 { parts.append("계약 미확정 \(count(.noContract))") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 보낼 것 한 줄

struct PendingBroadcastRow: View {
    /// 백로그 항목이거나 계획 블록. 계약 접근자는 프로토콜이 공용으로 제공한다.
    let holder: any BroadcastContractHolder
    /// nil이면 아직 전파 시점이 없다 — 계약 미확정이거나 모든 시점을 이미 보냈다.
    let checkpoint: BroadcastCheckpoint?
    /// 이미 요일에 배치된 계획 블록인가.
    var isPlanned: Bool = false
    let onOpen: () -> Void
    let onMarkSent: () -> Void

    @State private var copied = false

    /// 계약이 아직 안 끝났는가 (시점이 없는 이유가 미확정인가, 다 보냈는가).
    /// 급한 정도는 색이 아니라 dDayLabel("3일 지남" / "오늘" / "D-7")과 정렬 순서가 전달한다.
    private var contractPending: Bool {
        checkpoint == nil && !holder.broadcastContractVerified
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(holder.title.isEmpty ? "제목 없음" : holder.title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            if let cp = checkpoint {
                // "3일 지남" / "오늘" / "D-7" — 급한 정도가 색이 아니라 말에 담겨 있다.
                Text(BroadcastPlanner.dDayLabel(cp.date))
                    .font(.system(size: 13))
                    .monospacedDigit()

                Button(copied ? "복사됨" : "복사") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cp.script, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        copied = false
                    }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 13))

                Button("보냄", action: onMarkSent)
                    .buttonStyle(.borderless)
                    .font(.system(size: 13))
            }

            Button(contractPending ? "계약 마치기" : "계약", action: onOpen)
                .buttonStyle(.borderless)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .help(helpText)
    }

    /// 시점 · 대상 · 날짜를 한 줄로. D-day는 오른쪽에 있으므로 여기서 반복하지 않고,
    /// 약속일은 계약 안에 있으므로 줄에 다시 쓰지 않는다.
    private var subtitle: String {
        var parts: [String] = [statusLabel]
        let who = holder.broadcastRecipient.trimmingCharacters(in: .whitespaces)
        if !who.isEmpty { parts.append(who) }
        if let cp = checkpoint { parts.append(BroadcastPlanner.dateLabel(cp.date)) }
        if isPlanned { parts.append("계획에 배치됨") }
        return parts.joined(separator: " · ")
    }

    private var statusLabel: String {
        if let cp = checkpoint { return cp.kind.label }
        return contractPending ? "계약 미확정" : "전파 완료"
    }

    private var helpText: String {
        if let cp = checkpoint { return cp.kind.purpose }
        return contractPending
            ? "전파 필요로 체크했지만 계약이 아직 확정되지 않았습니다. 계약을 마치면 알려야 하는 날짜가 만들어집니다."
            : "예정된 전파를 모두 보냈습니다."
    }
}
