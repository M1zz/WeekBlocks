//
//  TodoStepsView.swift
//  무지개 공방
//
//  할 일 하나를 '들여다보는' 시트 — 그 안의 단계(뎁스)를 순서대로 보여주고 편집한다.
//
//  할 일 전체가 몇 시간인지를 먼저 정하고(그게 100%), 단계들이 그 시간을 나눠 갖는다.
//  기본은 N분의 1이고, 한 단계를 직접 조정하면 나머지가 남은 몫을 다시 나눠
//  합계는 언제나 100%가 된다. 계산은 TodoTree.swift(iOS와 공유하는 순수 로직)에 있다.
//
//  화면은 '라벨 먼저'다 — 적을 때 고른 라벨을 크게 보여준다. 조언은 화면에 깔지 않고
//  전부 TipKit으로 낸다 (→ TodoTips.swift). 필요한 때 한 번 뜨고, 닫으면 다시 안 뜬다.
//

import SwiftUI
import SwiftData
import TipKit

struct TodoStepsView: View {
    /// 100%에 해당하는 최상위 할 일.
    let root: BacklogItem

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\BacklogItem.sortIndex), SortDescriptor(\BacklogItem.createdAt)])
    private var allItems: [BacklogItem]

    /// 새 단계를 붙일 자리. nil이면 최상위 할 일 바로 아래.
    @State private var addTarget: BacklogItem?
    @State private var newTitle = ""
    /// 새 단계의 라벨. nil이면 '자동' — 형제들과 N분의 1로 나눠 갖는다.
    /// 새 단계의 속성. 백로그의 빈 줄과 같은 키를 써서, 어디서 적든 지난번 값이 따라온다.
    @FocusState private var focused: Bool

    private var tree: TodoTree { TodoTree(allItems) }

    private var rows: [(item: BacklogItem, depth: Int)] {
        Array(tree.flattened(from: root).dropFirst())
    }

    /// 구성 전체에 대한 조언 (조각 시간 연구 기반).
    private var hints: [SplitHint] {
        let tree = self.tree
        let leaves = tree.hasChildren(root) ? tree.leaves(of: root) : []
        return TodoSplitAdvisor.hints(rootTitle: root.title,
                                      steps: leaves.map { ($0.title, $0.durationHours) })
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if rows.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("아직 단계가 없습니다.")
                                .font(.callout.weight(.medium))
                            Text("이 할 일을 이루는 단계를 '되어야 하는 순서대로' 적어보세요.\n단계들은 전체 \(formatDuration(tree.totalHours(of: root)))를 N분의 1로 나눠 갖습니다.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Divider()

                        HStack {
                            Label("쪼개기 도우미", systemImage: "wand.and.stars")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Button("이 뼈대로 4단계 만들기", action: applyTemplate)
                                .buttonStyle(.borderedProminent)
                        }

                        ForEach(Array(TodoSplitAdvisor.template(for: root.title).enumerated()), id: \.offset) { _, step in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 10) {
                                    Text(step.title)
                                        .font(.system(size: 14))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Text(step.note)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }

                        if let hint = topHint, SplitHintTip(hint: hint).shouldDisplay {
                            Divider()
                            TipView(SplitHintTip(hint: hint))
                        }
                    }
                    .padding(20)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("단계")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 4)

                        // 단계에 무엇을 정해 주면 되는지 여기서 한 번만 설명한다.
                        if ShareSplitTip().shouldDisplay {
                            TipView(ShareSplitTip()).padding(.bottom, 6)
                        }

                        ForEach(rows, id: \.item.id) { row in
                            StepRow(
                                item: row.item,
                                depth: row.depth,
                                isCurrent: row.item.dragToken == tree.currentStep(of: root)?.dragToken,
                                hasChildren: tree.hasChildren(row.item),
                                progress: tree.progress(of: row.item),
                                share: share(of: row.item),
                                onHours: { setHours(row.item, $0) },
                                onToggle: { toggle(row.item) },
                                onAddChild: { addTarget = row.item; focused = true },
                                onMoveUp: { move(row.item, by: -1) },
                                onMoveDown: { move(row.item, by: 1) },
                                onDelete: { remove(row.item) }
                            )
                        }

                        if let hint = topHint, SplitHintTip(hint: hint).shouldDisplay {
                            Divider().padding(.vertical, 8)
                            TipView(SplitHintTip(hint: hint))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }

            Divider()

            inputBar
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - 헤더

    private var header: some View {
        let progress = tree.progress(of: root)
        let stepCount = tree.hasChildren(root) ? tree.leafCount(of: root) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(root.title)
                        .font(.title3.weight(.semibold))
                    if let step = tree.currentStep(of: root) {
                        HStack(spacing: 6) {
                            // 기호 하나로는 이게 '지금 할 것'이라는 뜻이 안 읽힌다. 말로 적는다.
                            Text("지금 단계")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                            Text(step.title)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                        }
                    } else if stepCount > 0 {
                        Label("모든 단계를 마쳤습니다", systemImage: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(progress >= 1 ? Color.green : Color.accentColor)
                Button("완료") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }

            ProgressView(value: progress)
                .tint(progress >= 1 ? .green : .accentColor)

            // 지금 할 단계에 경고가 있으면 그것만 팁으로. (다른 줄에는 안 깐다)
            if let step = tree.currentStep(of: root),
               !tree.hasChildren(step),
               let warning = TodoSplitAdvisor.advice(title: step.title,
                                                     durationHours: step.durationHours).warning {
                TipView(StepWarningTip(warning: warning))
            }

            // 이 일 전체가 몇 시간인가 = 100%. 단계들은 이 시간을 나눠 갖는다.
            HStack(spacing: 8) {
                totalHoursMenu
                Text(stepCount > 0 ? "= 100%, 단계 \(stepCount)개가 나눠 가짐" : "= 100%")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()

            }
        }
        .padding(20)
    }

    /// 이 일 전체에 걸리는 시간. 고르는 게 아니라 **단계들의 합**이다 —
    /// 단계를 더하거나 속성을 바꾸면 여기 숫자가 따라 움직인다.
    private var totalHoursMenu: some View {
        HStack(spacing: 5) {
            Image(systemName: "sum").font(.system(size: 13))
            Text("다 하면 \(formatDuration(tree.totalHours(of: root)))")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .fixedSize()
    }


    // MARK: - 조언 (전부 TipKit)

    /// 구성 전체에 대한 조언 중 지금 가장 중요한 하나만 팁으로 낸다.
    /// 경고가 있으면 경고를, 없으면 잘 쪼갰다는 확인을. 닫으면 그 종류는 다시 안 뜬다.
    private var topHint: SplitHint? {
        let all = hints
        return all.first { $0.tone == .caution } ?? all.first
    }

    // MARK: - 추가 입력 줄

    private var inputBar: some View {
        return VStack(alignment: .leading, spacing: 6) {
            if let target = addTarget {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.turn.down.right").font(.caption2)
                    Text("‘\(target.title)’ 아래에 추가")
                        .font(.caption)
                        .lineLimit(1)
                    Button {
                        addTarget = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.secondary)
            }

            if !newTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            }

            HStack(spacing: 10) {
                TextField("다음에 할 단계", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit(addStep)

                Button("추가", action: addStep)
                    .buttonStyle(.borderless)
                    .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    /// 지금 빈 줄에 적히면 붙을 속성.

    // MARK: - 동작

    /// 이 단계가 전체에서 차지하는 몫. 분모는 잎(실제로 하는 단계)들의 합이다 —
    /// 중간 묶음까지 더하면 두 번 센다.
    private func share(of item: BacklogItem) -> Double? {
        let total = tree.leaves(of: root).reduce(0) { $0 + $1.durationHours }
        guard total > 0 else { return nil }
        let hours = tree.hasChildren(item) ? tree.totalHours(of: item) : item.durationHours
        return hours / total
    }

    /// 단계 시간을 직접 적는다. 상위 할 일의 시간은 아래에서 위로 저절로 따라온다.
    private func setHours(_ item: BacklogItem, _ hours: Double) {
        item.durationHours = hours
        try? context.save()
    }

    private func addStep() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let parent = addTarget ?? root

        let step = TodoTree.makeStep(under: parent,
                                     title: title,
                                     sortIndex: tree.nextSortIndex(under: parent))
        context.insert(step)

        // 새로 만든 단계까지 넣어 트리를 다시 세운다 (@Query 갱신 전에도 계산이 맞도록).
        // 시간은 손댈 게 없다 — 위쪽 숫자는 이 단계가 더해지면서 저절로 커진다.
        let updated = TodoTree(allItems + [step])
        if updated.children(of: parent).count >= 2 { ShareSplitTip.hasSplit = true }
        updated.rollUp(from: step)
        try? context.save()

        newTitle = ""
        focused = true
    }

    /// 쪼개기 도우미의 기본 뼈대를 그대로 단계로 만든다.
    /// 뼈대의 시간은 '비율의 씨앗'이다 — 전체 예상 시간을 그 비율대로 나눠 갖는다.
    private func applyTemplate() {
        let tree = self.tree
        var index = tree.nextSortIndex(under: root)
        var made: [BacklogItem] = []
        for step in TodoSplitAdvisor.template(for: root.title) {
            let node = TodoTree.makeStep(under: root,
                                         title: step.title,
                                         sortIndex: index)
            context.insert(node)
            made.append(node)
            index += 1
        }
        let updated = TodoTree(allItems + made)
        updated.rollUp(from: root)
        try? context.save()
    }

    private func toggle(_ item: BacklogItem) {
        withAnimation {
            tree.setCompleted(item, !item.isCompleted)
            try? context.save()
        }
    }

    /// 속성을 바꾸면 시간도 그 속성의 것으로 따라간다 — 고르는 건 하나뿐이라는 약속을 지킨다.
    private func remove(_ item: BacklogItem) {
        let tree = self.tree
        let parent = tree.parent(of: item)
        let victims = Set(tree.subtree(of: item).map(\.dragToken))
        withAnimation {
            for node in tree.subtree(of: item) { context.delete(node) }
            if let parent {
                // 시간은 남은 단계들의 합이라 저절로 줄어든다. 완료 상태만 다시 굴려 준다.
                let updated = TodoTree(allItems.filter { !victims.contains($0.dragToken) })
                updated.rollUp(from: parent)
            }
            try? context.save()
        }
    }

    private func move(_ item: BacklogItem, by offset: Int) {
        let tree = self.tree
        guard let parent = tree.parent(of: item) else { return }
        var siblings = tree.children(of: parent)
        guard let index = siblings.firstIndex(where: { $0.dragToken == item.dragToken }) else { return }
        let target = index + offset
        guard siblings.indices.contains(target) else { return }
        siblings.swapAt(index, target)
        for (i, sibling) in siblings.enumerated() { sibling.sortIndex = i }
        withAnimation { try? context.save() }
    }
}

// MARK: - 단계 한 줄

private struct StepRow: View {
    let item: BacklogItem
    let depth: Int
    let isCurrent: Bool
    let hasChildren: Bool
    let progress: Double
    /// 이 단계가 이 할 일 전체에서 차지하는 몫(0...1).
    let share: Double?
    let onHours: (Double) -> Void
    let onToggle: () -> Void
    let onAddChild: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false

    private var hoursBinding: Binding<Double> {
        Binding(get: { item.durationHours },
                set: { onHours(max(0.25, min(12, $0))) })
    }

    var body: some View {
        HStack(spacing: 8) {
            if depth > 1 {
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                    .padding(.leading, CGFloat(depth - 2) * 16)
                    .padding(.vertical, 3)
            }

            Button(action: onToggle) {
                Image(systemName: item.isCompleted
                      ? "checkmark.circle.fill"
                      : (isCurrent ? "arrowtriangle.right.circle.fill" : "circle"))
                    .font(.system(size: 16))
                    .foregroundStyle(item.isCompleted ? .green : (isCurrent ? .orange : Color.secondary))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if hasChildren {
                    ProgressView(value: progress)
                        .tint(progress >= 1 ? .green : .accentColor)
                        .frame(maxWidth: 160)
                }

            }

            Spacer()

            // 시간은 여기서 직접 적는다. 그리고 그게 전체에서 몇 %인지 바로 옆에 —
            // 시간을 손으로 적게 된 뒤로는 이 숫자가 "어디를 더 쪼개야 하나"를 말해준다.
            if !hasChildren {
                HStack(spacing: 2) {
                    TextField("", value: hoursBinding, format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.plain)
                        .frame(width: 34)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                    Text("h").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }

            if let share {
                Text("\(Int((share * 100).rounded()))%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.primary)
                    .frame(width: 40, alignment: .trailing)
            }

            if hovering {
                Button(action: onAddChild) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("하위 단계 추가")
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("삭제")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isCurrent ? Color.orange.opacity(0.08) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("하위 단계 추가", action: onAddChild)
            Button("위로", action: onMoveUp)
            Button("아래로", action: onMoveDown)
            Divider()
            Button("삭제", role: .destructive, action: onDelete)
        }
    }
}
