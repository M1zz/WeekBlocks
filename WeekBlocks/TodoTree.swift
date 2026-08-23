//
//  TodoTree.swift
//
//  할 일의 뎁스(단계) 계산 — 순수 로직.
//
//  시간은 **위에서 아래로** 내려간다.
//  할 일을 적을 때 "몇 시간 걸릴까"를 먼저 받는다 — 그게 그 일의 100%다.
//  그 안의 단계들은 이 시간을 **나눠 갖는다**. 기본은 N분의 1이고, 한 단계를
//  사용자가 직접 조정하면 나머지 단계들이 남은 몫을 다시 나눠, 합계는 언제나
//  부모의 예상 시간(=100%)이 된다.
//
//  - 부모의 예상 시간 = 사용자가 정한 값 (자식이 늘어도 총량은 그대로)
//  - 자식들의 시간 합 = 부모의 예상 시간 (언제나 100%)
//  - 사용자가 직접 정한 단계(isManualWeight)는 자동 재분배에서 빠진다
//  - 진행률 = 완료한 잎(더 못 쪼갠 단계)들의 시간 합 / 전체 시간
//  - '지금 할 일' = 순서상 첫 번째 미완료 잎
//
//  ⚠️ 이 파일은 iOS('욕망의 무지개')와 macOS('무지개 공방') 두 레포에 **같은 내용으로**
//     복제돼 있다. 한쪽을 고치면 다른 쪽도 반드시 같이 고칠 것 — 두 앱이 같은 CloudKit
//     데이터를 읽고 쓰기 때문에 계산이 갈라지면 같은 할 일의 진행률이 기기마다 달라진다.
//

import Foundation

/// 부모-자식 관계를 한 번만 색인해두고 쓰는 조회기.
/// `BacklogItem.parentToken`(부모의 `dragToken`)으로 연결된다.
struct TodoTree {
    /// 부모 토큰 → 자식들 (진행 순서대로 정렬).
    private let childrenByParent: [String: [BacklogItem]]
    /// 자식 토큰 → 부모.
    private let parentByToken: [String: BacklogItem]
    /// 최상위 할 일들 (= 각자가 100%인 단위).
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

    /// 이 항목에 배정된 예상 시간 = 사용자가 정한 값(부모가 있으면 부모에게서 나눠 받은 몫).
    ///
    /// 예산이 비어 있는 이상한 데이터(다른 기기에서 반쯤 동기화된 중간 상태 등)에서만
    /// 아래 단계들의 합으로 대신 답한다.
    func totalHours(of item: BacklogItem) -> Double {
        let own = max(0, item.durationHours)
        if own > 0 { return own }
        return leaves(of: item).reduce(0) { $0 + max(0, $1.durationHours) }
    }

    /// 완료한 잎들의 시간 합.
    func doneHours(of item: BacklogItem) -> Double {
        leaves(of: item).filter(\.isCompleted).reduce(0) { $0 + max(0, $1.durationHours) }
    }

    /// 0...1 진행률. 시간이 모두 0이면 개수 비율로 떨어뜨린다.
    func progress(of item: BacklogItem) -> Double {
        let total = totalHours(of: item)
        if total > 0 { return min(1, doneHours(of: item) / total) }
        let all = leaves(of: item)
        guard !all.isEmpty else { return item.isCompleted ? 1 : 0 }
        return Double(all.filter(\.isCompleted).count) / Double(all.count)
    }

    /// 부모 안에서 이 단계가 차지하는 비중 (0...1). 부모가 없으면 1(= 그 자체가 100%).
    func weight(of item: BacklogItem) -> Double {
        guard let parent = parentByToken[item.dragToken] else { return 1 }
        let parentTotal = totalHours(of: parent)
        guard parentTotal > 0 else {
            let count = children(of: parent).count
            return count > 0 ? 1 / Double(count) : 1
        }
        return min(1, totalHours(of: item) / parentTotal)
    }

    /// 최상위 할 일 전체에서 이 단계가 차지하는 비중 (0...1).
    /// 중첩된 단계는 조상들의 비중이 곱해진다 (50% 안의 60% → 30%).
    func weightInRoot(of item: BacklogItem) -> Double {
        var result = 1.0
        var current = item
        var depth = 0
        while parentByToken[current.dragToken] != nil, depth < Self.maxDepth {
            result *= weight(of: current)
            current = parentByToken[current.dragToken]!
            depth += 1
        }
        return result
    }

    /// 자동으로 몫을 받는(= 사용자가 직접 정하지 않은) 형제가 몇 개인지.
    func autoShareCount(under parent: BacklogItem) -> Int {
        children(of: parent).filter { !$0.isManualWeight }.count
    }

    // MARK: - 지금 할 일

    /// 지금 해야 할 단계 = 순서상 첫 번째 미완료 잎. 전부 끝났으면 nil.
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
    /// 시간은 건드리지 않는다 — 부모의 예상 시간은 사용자가 정한 값이고,
    /// 자식들이 그걸 나눠 갖는 구조이기 때문이다.
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

    // MARK: - 예산 나눠 갖기 (위 → 아래)
    //
    // 나누다 보면 1분이 남는다(60분을 7단계로). 그 1분을 버리면 합이 99%가 되므로
    // 분 단위 정수로 계산하고 남는 분은 앞 단계부터 하나씩 얹는다 — 합은 언제나 정확히 100%.

    private static func minutes(_ hours: Double) -> Int { max(0, Int((hours * 60).rounded())) }
    private static func hours(_ minutes: Int) -> Double { Double(max(0, minutes)) / 60 }

    /// `total`분을 `weights` 비율대로 나눈다. 비율이 모두 0이면 N분의 1.
    private static func split(_ total: Int, by weights: [Int]) -> [Int] {
        guard !weights.isEmpty else { return [] }
        let total = max(0, total)
        let sum = weights.reduce(0, +)
        var result = sum > 0
            ? weights.map { total * max(0, $0) / sum }
            : Array(repeating: total / weights.count, count: weights.count)
        // 정수 나눗셈에서 잘려나간 분을 앞에서부터 되돌려준다 (남는 분 < 단계 수).
        var left = total - result.reduce(0, +)
        var index = 0
        while left > 0 && index < result.count {
            result[index] += 1
            left -= 1
            index += 1
        }
        return result
    }

    /// 이 항목에 `minutes`분을 배정하고, 아래 단계들은 지금 비율을 지킨 채 같이 늘고 준다.
    private func assign(_ item: BacklogItem, minutes total: Int, depth: Int = 0) {
        item.durationHours = Self.hours(total)
        guard depth < Self.maxDepth else { return }
        let kids = children(of: item)
        guard !kids.isEmpty else { return }
        let shares = Self.split(total, by: kids.map { Self.minutes($0.durationHours) })
        for (kid, share) in zip(kids, shares) { assign(kid, minutes: share, depth: depth + 1) }
    }

    /// 이 일 전체가 몇 시간인지를 바꾼다 (최상위 할 일이면 그게 곧 100%).
    /// 아래 단계들은 비율을 지킨 채 함께 조정된다.
    func setTotalHours(_ item: BacklogItem, to hours: Double) {
        assign(item, minutes: Self.minutes(hours))
    }

    /// 한 단계의 예상 시간을 사용자가 직접 정한다.
    /// 나머지 형제들이 남은 몫을 나눠 가져, 부모 안의 합계는 언제나 100%로 유지된다.
    ///
    /// - Parameter manual: 사용자가 손으로 정한 것인지. true면 이 단계는 다음 자동 분배에서 빠진다.
    func setHours(_ item: BacklogItem, to hours: Double, manual: Bool = true) {
        guard let parent = parentByToken[item.dragToken] else {
            setTotalHours(item, to: hours)
            return
        }
        let budget = Self.minutes(totalHours(of: parent))
        let siblings = children(of: parent).filter { $0.dragToken != item.dragToken }

        // 단계가 하나뿐이면 그 단계가 곧 부모 전부다 — 조정할 여지가 없다.
        guard !siblings.isEmpty else {
            item.isManualWeight = false
            assign(item, minutes: budget)
            return
        }

        let want = min(max(0, Self.minutes(hours)), budget)
        if manual { item.isManualWeight = true }
        assign(item, minutes: want)

        // 남은 몫은 '자동'인 형제들끼리 나눈다. 사용자가 직접 정해 둔 형제는 그대로 둔다.
        var pool = siblings.filter { !$0.isManualWeight }
        var rest = budget - want
        let fixed = siblings.filter(\.isManualWeight).reduce(0) { $0 + Self.minutes($1.durationHours) }
        if pool.isEmpty || fixed > rest {
            // 자동인 형제가 없거나, 고정해 둔 형제들만으로도 남은 몫을 넘는다
            // → 어쩔 수 없이 형제 전부가 비율대로 물러난다 (합계 100%가 먼저다).
            pool = siblings
        } else {
            rest -= fixed
        }
        let shares = Self.split(rest, by: pool.map { Self.minutes($0.durationHours) })
        for (sibling, share) in zip(pool, shares) { assign(sibling, minutes: share) }
    }

    /// 한 단계의 비중(0...1)을 직접 정한다. 나머지는 `setHours`와 같다.
    func setWeight(_ item: BacklogItem, to fraction: Double) {
        guard let parent = parentByToken[item.dragToken] else { return }
        setHours(item, to: max(0, min(1, fraction)) * totalHours(of: parent))
    }

    /// 새로 붙인 단계에 첫 몫을 준다 — 형제가 n개가 됐으니 N분의 1.
    /// 직접 정해 둔 형제의 몫은 건드리지 않고, 자동인 형제들끼리 다시 나눈다.
    func giveInitialShare(_ item: BacklogItem, hours: Double? = nil) {
        guard let parent = parentByToken[item.dragToken] else { return }
        let count = max(1, children(of: parent).count)
        item.isManualWeight = false
        setHours(item, to: hours ?? totalHours(of: parent) / Double(count), manual: hours != nil)
    }

    /// 직접 정해 둔 비중을 풀고 자동(N분의 1)으로 되돌린다.
    /// 다른 형제가 정해 둔 몫은 그대로 두고, 자동인 형제들끼리만 남은 몫을 다시 나눈다.
    func releaseManual(_ item: BacklogItem) {
        guard let parent = parentByToken[item.dragToken] else { return }
        item.isManualWeight = false
        let kids = children(of: parent)
        let autos = kids.filter { !$0.isManualWeight }
        guard !autos.isEmpty else { return }
        let fixed = kids.filter(\.isManualWeight).reduce(0) { $0 + Self.minutes($1.durationHours) }
        let rest = max(0, Self.minutes(totalHours(of: parent)) - fixed)
        let shares = Self.split(rest, by: Array(repeating: 1, count: autos.count))
        for (kid, share) in zip(autos, shares) { assign(kid, minutes: share) }
    }

    /// 단계들을 다시 N분의 1로. 직접 정해 둔 비중도 모두 풀린다.
    func splitEvenly(under parent: BacklogItem) {
        let kids = children(of: parent)
        guard !kids.isEmpty else { return }
        for kid in kids { kid.isManualWeight = false }
        let shares = Self.split(Self.minutes(totalHours(of: parent)),
                                by: Array(repeating: 1, count: kids.count))
        for (kid, share) in zip(kids, shares) { assign(kid, minutes: share) }
    }

    /// 자식들의 합을 부모의 예산에 다시 맞춘다 (지금 비율은 유지).
    /// 단계를 지웠을 때, 또는 다른 기기에서 온 데이터가 어긋났을 때 쓴다.
    func fit(under parent: BacklogItem) {
        assign(parent, minutes: Self.minutes(totalHours(of: parent)))
    }

    /// 단계를 새로 붙일 때 쓸 sortIndex (형제들 맨 뒤).
    func nextSortIndex(under parent: BacklogItem) -> Int {
        (children(of: parent).map(\.sortIndex).max() ?? -1) + 1
    }
}

// MARK: - 단계 만들기

extension TodoTree {
    /// 부모 아래에 새 단계를 만든다. 저장(insert/save)은 호출한 쪽에서 한다.
    ///
    /// 시간은 여기서 정하지 않는다 — 만든 뒤 `giveInitialShare(_:)`로 부모의 예산에서
    /// N분의 1을 받아 간다. `seedHours`는 그 전까지 임시로 들고 있을 값(비율의 씨앗)이다.
    /// 주(weekStartDate)와 카테고리는 부모를 따라간다 — 단계는 부모와 한 덩어리로 움직인다.
    static func makeStep(under parent: BacklogItem,
                         title: String,
                         sortIndex: Int,
                         seedHours: Double = 0,
                         label: TodoLabel? = nil) -> BacklogItem
    {
        let step = BacklogItem(title: title,
                               durationHours: max(0, seedHours),
                               sortIndex: sortIndex,
                               categoryID: parent.categoryID,
                               weekStartDate: parent.weekStartDate,
                               label: label)
        step.parentToken = parent.dragToken
        return step
    }
}
