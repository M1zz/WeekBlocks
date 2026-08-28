//
//  TodoTree.swift
//
//  할 일의 뎁스(단계) 계산 — 순수 로직.
//
//  시간은 **위에서 아래로** 내려간다.
//  단계는 같은 BacklogItem이고, `parentToken`(부모의 dragToken)으로 매달린다.
//
//  시간은 **아래에서 위로** 쌓인다: 단계마다 소요시간을 적으면 그 값이
//  시간을 데려오고, 상위 할 일의 시간은 단계들의 합이다.
//
//  예전에는 반대였다 — 상위 할 일의 시간이 100%이고 단계들이 그걸 나눠 갖는 구조로,
//  비중 슬라이더·자물쇠·N분의 1이 딸려 있었다. 그 구조는 "이 단계가 전체의 몇 %냐"에
//  답했는데, 쪼개는 사람은 그 물음에 답할 수가 없다. 단계를 실제로 하느냐 마느냐를
//  가르는 건 비율이 아니라 '지금 시작할 수 있느냐'였다.
//
import Foundation

/// 부모-자식 관계를 한 번만 색인해두고 쓰는 조회기.
/// `BacklogItem.parentToken`(부모의 `dragToken`)으로 연결된다.
struct TodoTree {
    /// 부모 토큰 → 자식들 (진행 순서대로 정렬).
    private let childrenByParent: [String: [BacklogItem]]
    /// 자식 토큰 → 부모.
    private let parentByToken: [String: BacklogItem]
    /// 최상위 할 일들 (= 단계를 매다는 단위).
    let roots: [BacklogItem]

    /// 잘못된 데이터(부모-자식 순환)로 무한 재귀에 빠지지 않도록 두는 한계.
    /// 사람이 손으로 만드는 단계 구조가 이보다 깊을 일은 없다.
    static let maxDepth = 12

    init(_ items: [BacklogItem]) {
        let tokens = Set(items.map(\.dragToken))
        var byParent: [String: [BacklogItem]] = [:]
        var byToken: [String: BacklogItem] = [:]
        var tops: [BacklogItem] = []

        for item in items {
            // 부모가 목록에 없으면(삭제됐거나 아직 동기화 전이면) 최상위로 취급한다.
            // 그래야 고아가 된 단계가 화면에서 사라지지 않는다.
            if let parent = item.parentToken, !parent.isEmpty, tokens.contains(parent), parent != item.dragToken {
                byParent[parent, default: []].append(item)
            } else {
                tops.append(item)
            }
        }

        let inOrder: (BacklogItem, BacklogItem) -> Bool = { a, b in
            if a.sortIndex != b.sortIndex { return a.sortIndex < b.sortIndex }
            return a.createdAt < b.createdAt
        }

        self.childrenByParent = byParent.mapValues { $0.sorted(by: inOrder) }
        self.roots = tops.sorted(by: inOrder)

        for (parentToken, kids) in byParent {
            guard let parent = items.first(where: { $0.dragToken == parentToken }) else { continue }
            for kid in kids { byToken[kid.dragToken] = parent }
        }
        self.parentByToken = byToken
    }

    // MARK: - 구조 조회

    func children(of item: BacklogItem) -> [BacklogItem] {
        childrenByParent[item.dragToken] ?? []
    }

    func hasChildren(_ item: BacklogItem) -> Bool {
        !(childrenByParent[item.dragToken] ?? []).isEmpty
    }

    func parent(of item: BacklogItem) -> BacklogItem? {
        parentByToken[item.dragToken]
    }

    /// 최상위 조상 (그 할 일 전체 = 100%인 항목).
    func root(of item: BacklogItem) -> BacklogItem {
        var current = item
        var depth = 0
        while let up = parentByToken[current.dragToken], depth < Self.maxDepth {
            current = up
            depth += 1
        }
        return current
    }

    /// 자기를 포함한 하위 전체를 진행 순서(깊이 우선)로.
    func subtree(of item: BacklogItem) -> [BacklogItem] {
        var result: [BacklogItem] = []
        visit(item, depth: 0) { node, _ in result.append(node) }
        return result
    }

    /// 잎(더 쪼개지 않은 단계)들을 진행 순서대로. 자식이 없으면 자기 자신 하나.
    func leaves(of item: BacklogItem) -> [BacklogItem] {
        var result: [BacklogItem] = []
        visit(item, depth: 0) { node, _ in
            if (childrenByParent[node.dragToken] ?? []).isEmpty { result.append(node) }
        }
        return result
    }

    /// 화면에 들여쓰기와 함께 그리기 위한 (항목, 깊이) 목록. 자기 자신은 깊이 0.
    func flattened(from item: BacklogItem) -> [(item: BacklogItem, depth: Int)] {
        var result: [(BacklogItem, Int)] = []
        visit(item, depth: 0) { node, depth in result.append((node, depth)) }
        return result
    }

    private func visit(_ item: BacklogItem, depth: Int, _ body: (BacklogItem, Int) -> Void) {
        guard depth < Self.maxDepth else { return }
        body(item, depth)
        for child in childrenByParent[item.dragToken] ?? [] {
            visit(child, depth: depth + 1, body)
        }
    }

    // MARK: - 시간·비중·진행률

    /// 이 일에 걸리는 예상 시간. **아래에서 위로 합산한다** —
    /// 단계가 있으면 단계들의 합이고, 없으면 자기 속성이 정한 시간이다.
    ///
    /// 예전에는 반대였다(상위가 100%이고 단계들이 그걸 나눠 가짐). 그 구조는
    /// "이 단계가 전체의 몇 %냐"에 답했는데, 단계를 실제로 하느냐 마느냐를 가르는 건
    /// 비율이 아니라 '한 자리에서 닫히는 크기'였다. 그래서 비중을 걷어내고,
    /// 시간은 단계를 하나씩 더할 때마다 위로 쌓이게 했다.
    func totalHours(of item: BacklogItem) -> Double {
        let kids = children(of: item)
        guard !kids.isEmpty else { return max(0, item.durationHours) }
        return kids.reduce(0) { $0 + totalHours(of: $1) }
    }

    /// 완료한 잎들의 시간 합.
    func doneHours(of item: BacklogItem) -> Double {
        leaves(of: item).filter(\.isCompleted).reduce(0) { $0 + max(0, $1.durationHours) }
    }

    /// 0...1 진행률 = 끝낸 단계 수 ÷ 전체 단계 수.
    ///
    /// 시간으로 재지 않는다. '기다림'은 내 시간을 0으로 쓰는데, 시간으로 재면 그 단계를
    /// 끝내도 진행률이 꿈쩍하지 않는다. 사람이 세는 방식(4개 중 2개)과도 맞다.
    func progress(of item: BacklogItem) -> Double {
        let all = leaves(of: item)
        guard !all.isEmpty else { return item.isCompleted ? 1 : 0 }
        return Double(all.filter(\.isCompleted).count) / Double(all.count)
    }

    // MARK: - 갈라 세기 (합치지 않는 집계)

    func currentStep(of item: BacklogItem) -> BacklogItem? {
        leaves(of: item).first { !$0.isCompleted }
    }

    /// 방금 끝낸 단계 = 마지막으로 완료된 잎 (되돌리기 대상).
    func lastDoneStep(of item: BacklogItem) -> BacklogItem? {
        leaves(of: item).last { $0.isCompleted }
    }

    func leafCount(of item: BacklogItem) -> Int { leaves(of: item).count }

    func doneLeafCount(of item: BacklogItem) -> Int { leaves(of: item).filter(\.isCompleted).count }

    /// "3단계 중 2번째" 처럼 쓸 현재 단계 번호(1부터). 다 끝났으면 nil.
    func currentStepNumber(of item: BacklogItem) -> Int? {
        let all = leaves(of: item)
        guard let index = all.firstIndex(where: { !$0.isCompleted }) else { return nil }
        return index + 1
    }

    // MARK: - 변경 (호출한 쪽에서 context.save())

    /// 지금 할 일을 끝냈다고 표시하고 다음 단계로 넘긴다.
    /// 마지막 단계였다면 할 일 전체가 완료된다. 완료 처리한 단계를 돌려준다.
    @discardableResult
    func advance(_ item: BacklogItem, now: Date = Date()) -> BacklogItem? {
        guard let step = currentStep(of: item) else { return nil }
        setCompleted(step, true, now: now)
        return step
    }

    /// 마지막으로 완료한 단계를 되돌린다. 되돌린 단계를 돌려준다.
    @discardableResult
    func rewind(_ item: BacklogItem) -> BacklogItem? {
        guard let step = lastDoneStep(of: item) else { return nil }
        setCompleted(step, false)
        return step
    }

    /// 한 단계의 완료 상태를 바꾸고, 하위와 조상의 상태를 다시 맞춘다.
    func setCompleted(_ item: BacklogItem, _ value: Bool, now: Date = Date()) {
        // 중간 단계를 직접 체크하면 그 아래 단계도 전부 따라간다.
        for node in subtree(of: item) {
            node.isCompleted = value
            node.completedAt = value ? (node.completedAt ?? now) : nil
        }
        rollUp(from: item, now: now)
    }

    /// 조상들의 완료 상태를 자식 기준으로 다시 계산한다.
    /// (자식이 전부 끝났으면 부모도 완료, 하나라도 남았으면 부모는 미완료)
    ///
    /// 시간은 건드리지 않는다 — 부모의 시간은 저장된 값이 아니라 자식들의 합으로
    /// 그때그때 계산되기 때문이다 (→ totalHours).
    func rollUp(from item: BacklogItem, now: Date = Date()) {
        var current = item
        var depth = 0
        while let parent = parentByToken[current.dragToken], depth < Self.maxDepth {
            let kids = children(of: parent)
            let allDone = !kids.isEmpty && kids.allSatisfy(\.isCompleted)
            parent.isCompleted = allDone
            parent.completedAt = allDone ? (parent.completedAt ?? now) : nil
            current = parent
            depth += 1
        }
    }

    // MARK: - 속성 정하기

    /// 단계를 새로 붙일 때 쓸 sortIndex (형제들 맨 뒤).
    func nextSortIndex(under parent: BacklogItem) -> Int {
        (children(of: parent).map(\.sortIndex).max() ?? -1) + 1
    }
}

// MARK: - 단계 만들기

extension TodoTree {
    /// 부모 아래에 새 단계를 만든다. 저장(insert/save)은 호출한 쪽에서 한다.
    ///
    /// 상위 할 일의 시간은 단계들의 합이므로 여기서 따로 손대지 않는다(아래에서 위로).
    /// 주(weekStartDate)와 카테고리는 부모를 따라간다 — 단계는 부모와 한 덩어리로 움직인다.
    static func makeStep(under parent: BacklogItem,
                         title: String,
                         sortIndex: Int,
                         durationHours: Double = TodoTree.defaultStepHours) -> BacklogItem
    {
        let step = BacklogItem(title: title,
                               durationHours: durationHours,
                               sortIndex: sortIndex,
                               categoryID: parent.categoryID,
                               weekStartDate: parent.weekStartDate)
        step.parentToken = parent.dragToken
        return step
    }
}

extension TodoTree {
    /// 새 단계·새 할 일의 기본 소요시간. 적을 때는 안 묻고, 상세에서 고친다.
    static let defaultStepHours: Double = 0.5
}
