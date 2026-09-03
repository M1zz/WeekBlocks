import SwiftUI
import SwiftData

struct ReflectionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let weekStart: Date

    @Query private var allBlocks: [PlanBlock]

    private var weekBlocks: [PlanBlock] {
        allBlocks
            .filter { Calendar.current.isDate($0.weekStartDate, inSameDayAs: weekStart) }
            .sorted { ($0.day.rawValue, $0.timeBand.rawValue) < ($1.day.rawValue, $1.timeBand.rawValue) }
    }

    private var stats: (done: Int, partial: Int, skipped: Int, pending: Int) {
        var d = 0, p = 0, s = 0, pe = 0
        for b in weekBlocks {
            switch b.reviewStatus {
            case .done: d += 1
            case .partial: p += 1
            case .skipped: s += 1
            case nil: pe += 1
            }
        }
        return (d, p, s, pe)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if weekBlocks.isEmpty {
                ContentUnavailableView(
                    "이번 주에는 계획된 블록이 없습니다",
                    systemImage: "tray",
                    description: Text("주간 계획을 먼저 채운 뒤 다시 확인하세요.")
                )
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(weekBlocks) { block in
                            ReflectionRow(block: block) {
                                try? context.save()
                            }
                            Divider()
                        }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("주간 회고")
                .font(.title3.weight(.medium))

            HStack(spacing: 10) {
                statTile(label: "달성", value: stats.done, color: .green)
                statTile(label: "부분", value: stats.partial, color: .yellow)
                statTile(label: "건너뜀", value: stats.skipped, color: .red)
                statTile(label: "미회고", value: stats.pending, color: .secondary)
            }
        }
        .padding(20)
    }

    private func statTile(label: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title3.weight(.medium))
                .foregroundStyle(color)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ReflectionRow: View {
    @Bindable var block: PlanBlock
    let onChange: () -> Void

    @State private var hovering = false

    /// 다 한 것으로 보는가. 줄을 흐리고 제목에 줄을 긋는 기준이다.
    private var isDone: Bool { block.reviewStatus == .done }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // **할 일 목록과 같은 자리, 같은 손짓** — 왼쪽 동그라미를 눌러 끝낸다
                // (→ BacklogView의 '요일에 올린 일'). 세 갈래 상태는 이 동그라미의
                // 모양으로 드러나므로, 눈으로 읽는 것과 손으로 누르는 것이 한 자리에 있다.
                checkButton

                Text(block.day.shortLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isDone)
                        .foregroundStyle(isDone ? .secondary : .primary)
                    Text("\(block.timeBand.shortLabel) · \(String(format: "%.1fh", block.durationHours))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // 부분·건너뜀은 자주 쓰는 손짓이 아니다. 늘 세워 두면 '끝냄' 하나를
                // 누르러 온 사람이 셋 중에 고르는 일이 되므로, 가리키기 전에는 숨긴다.
                // (마우스를 안 쓰는 사람을 위해 줄 전체에 같은 메뉴를 우클릭으로도 단다.)
                stateMenu
                    .opacity(hovering ? 1 : 0)
            }

            if !block.successCriteria.isEmpty {
                Text("기준: \(block.successCriteria)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 52)
            }

            if block.reviewStatus != nil {
                TextField(
                    "한 줄 회고 — 무엇이 잘 됐고 무엇이 안 됐는지",
                    text: Binding(
                        get: { block.reviewNote ?? "" },
                        set: { block.reviewNote = $0.isEmpty ? nil : $0; onChange() }
                    ),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .padding(.leading, 52)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { stateButtons }
    }

    /// 누르면 끝낸 것이 되고, 다시 누르면 도로 안 본 것이 된다.
    /// 부분·건너뜀이 찍혀 있을 때 누르면 그것도 풀린다 — 체크박스는 늘 '지금 상태를 끈다'.
    private var checkButton: some View {
        Button {
            block.reviewStatus = block.reviewStatus == nil ? .done : nil
            onChange()
        } label: {
            Image(systemName: block.reviewStatus?.systemImage ?? "circle")
                .font(.system(size: 16))
                .foregroundStyle(tint(for: block.reviewStatus))
        }
        .buttonStyle(.plain)
        .help(block.reviewStatus == nil ? "끝냈다고 표시한다" : "표시를 지운다 (적어 둔 회고는 그대로 남습니다)")
    }

    private var stateMenu: some View {
        Menu {
            stateButtons
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("부분 달성·건너뜀으로 표시")
    }

    @ViewBuilder
    private var stateButtons: some View {
        ForEach(ReviewStatus.allCases) { status in
            Button {
                block.reviewStatus = block.reviewStatus == status ? nil : status
                onChange()
            } label: {
                Label(status.label, systemImage: block.reviewStatus == status
                      ? "checkmark" : status.systemImage)
            }
        }
        if block.reviewStatus != nil {
            Divider()
            // 지우는 것은 **표시뿐**이다. 적어 둔 한 줄 회고는 그대로 둔다 —
            // 잘못 눌러서 쓴 글이 날아가면 다시는 안 적는다.
            Button("표시 지우기") {
                block.reviewStatus = nil
                onChange()
            }
        }
    }

    private func tint(for status: ReviewStatus?) -> Color {
        switch status {
        case .done: return .green
        case .partial: return .yellow
        case .skipped: return .red
        case nil: return .secondary.opacity(0.5)
        }
    }
}
