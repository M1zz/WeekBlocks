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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.day.shortLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.title)
                        .font(.body.weight(.medium))
                    Text("\(block.timeBand.shortLabel) · \(String(format: "%.1fh", block.durationHours))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPicker
            }

            if !block.successCriteria.isEmpty {
                Text("기준: \(block.successCriteria)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 26)
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
                .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var statusPicker: some View {
        HStack(spacing: 4) {
            ForEach(ReviewStatus.allCases) { status in
                Button {
                    block.reviewStatus = block.reviewStatus == status ? nil : status
                    onChange()
                } label: {
                    Image(systemName: status.systemImage)
                        .font(.system(size: 18))
                        .foregroundStyle(tint(for: status, selected: block.reviewStatus == status))
                }
                .buttonStyle(.borderless)
                .help(status.label)
            }
        }
    }

    private func tint(for status: ReviewStatus, selected: Bool) -> Color {
        if !selected { return .secondary.opacity(0.4) }
        switch status {
        case .done: return .green
        case .partial: return .yellow
        case .skipped: return .red
        }
    }
}
