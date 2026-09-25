//
//  OverlapRule.swift
//  WeekBlocks
//
//  **겹친 시간은 누구의 몫인가.**
//
//  09–18시 회사 안에 12–13시 점심이 서 있으면, 그 한 시간은 회사인가 점심인가.
//  하루가 차지한 시간(남은 시간)은 어느 쪽이든 같다 — 겹친 곳은 한 번만 센다 (→ TimelineLayout.unionLength).
//  갈리는 것은 **회사를 몇 시간으로 부를지**다. "점심 먹는 동안은 일하는 게 아니다"라는 사람도,
//  "점심까지 회사 시간이다"라는 사람도 있어서 앱이 정하지 않고 사람이 기준을 고른다.
//

import SwiftUI

enum OverlapRule: String, CaseIterable, Identifiable {
    /// 바깥 루틴 시간은 그대로. 안에 든 끼니·계획은 그 시간 안에서 함께 지나간다. (지금까지의 셈)
    case keepOuter
    /// 안에 든 끼니·계획만큼 바깥 고정 루틴 시간에서 뺀다.
    case subtractInner

    var id: String { rawValue }

    /// 저장 자리. 화면마다 `@AppStorage(OverlapRule.storageKey)`로 읽어 바로 따라 바뀐다.
    static let storageKey = "overlapRule"
    /// 배너에서든 설정에서든 **한 번 골랐는가**. 고른 사람에게는 다시 묻지 않는다.
    static let decidedKey = "overlapRuleDecided"

    var title: LocalizedStringKey {
        switch self {
        case .keepOuter:     "바깥 일정 기준"
        case .subtractInner: "안쪽 일정 기준"
        }
    }

    var summary: LocalizedStringKey {
        switch self {
        case .keepOuter:     "회사 안에서 먹은 점심도 회사 시간으로 셉니다."
        case .subtractInner: "점심 먹는 동안은 회사 시간이 아닙니다. 겹친 만큼 회사에서 뺍니다."
        }
    }
}

extension TimelineLayout {
    /// 고정 루틴 구간 하나에 **다른 것이 얹혀 겹친 시간**. 끼니와 따로 올린 계획만 센다.
    ///
    /// 루틴 안 일정(`isNested`)은 루틴 **안에서 하는 일**이라 빼지 않는다 — 회사 안의 회의는 회사 일이다.
    /// 고정 루틴끼리 겹친 것도 빼지 않는다. 어느 쪽이 안인지 말할 수 없다.
    static func innerOverlap(of seg: TimeSegment, among segs: [TimeSegment]) -> Double {
        guard case .fixedRoutine = seg.source, !seg.isGhost else { return 0 }
        let clipped: [(Double, Double)] = segs.compactMap { other in
            guard other.id != seg.id, !other.isGhost, !other.isNested else { return nil }
            switch other.source {
            case .quotaSession, .planBlock: break
            default: return nil
            }
            let s = max(seg.start, other.start), e = min(seg.end, other.end)
            return e > s ? (s, e) : nil
        }
        return unionLength(clipped)
    }

    /// 이 규칙으로 센 이 **조각**의 길이. 규칙이 '바깥 기준'이면 그린 길이 그대로다.
    static func countedHours(of seg: TimeSegment, among segs: [TimeSegment], rule: OverlapRule) -> Double {
        let drawn = seg.end - seg.start
        guard rule == .subtractInner else { return drawn }
        return max(0, drawn - innerOverlap(of: seg, among: segs))
    }

    /// 배너가 예로 들 겹침 하나 — 가장 오래 겹친 것. (바깥 이름, 안쪽 이름, 바깥 길이, 겹친 시간)
    static func biggestOverlap(in segs: [TimeSegment]) -> OverlapExample? {
        var best: OverlapExample?
        for outer in segs {
            let overlap = innerOverlap(of: outer, among: segs)
            guard overlap >= 0.25, overlap > (best?.overlap ?? 0) else { continue }
            // 어떤 것이 얹혀 있는지 — 가장 많이 겹친 하나의 이름을 든다.
            let inner = segs
                .filter { o in
                    guard o.id != outer.id, !o.isGhost, !o.isNested else { return false }
                    if case .fixedRoutine = o.source { return false }
                    if case .none = o.source { return false }
                    return true
                }
                .max { a, b in
                    min(outer.end, a.end) - max(outer.start, a.start) < min(outer.end, b.end) - max(outer.start, b.start)
                }
            guard let inner else { continue }
            best = OverlapExample(outer: outer.title, inner: inner.title,
                                  outerHours: outer.end - outer.start, overlap: overlap)
        }
        return best
    }
}

/// 실제 시간표에서 찾은 겹침 하나. 배너와 설정의 예시가 **사람의 일정 이름으로** 말하게 한다.
struct OverlapExample: Equatable {
    let outer: String
    let inner: String
    let outerHours: Double
    let overlap: Double

    /// 설정을 처음 열었을 때처럼 실제 겹침이 없을 때 드는 예.
    static let sample = OverlapExample(outer: String(localized: "회사"), inner: String(localized: "점심"),
                                       outerHours: 9, overlap: 1)
}

// MARK: - 그림으로 보는 예

/// 두 기준을 나란히 그린다. 바깥 막대 위에 안쪽이 얹히고, 오른쪽에 **몇 시간으로 세는지**가 선다.
/// 설정과 배너가 같은 그림을 쓴다 — 고르기 전에 무엇이 바뀌는지 눈으로 먼저 본다.
struct OverlapRuleExampleView: View {
    let example: OverlapExample
    let rule: OverlapRule

    var body: some View {
        let counted = rule == .subtractInner ? example.outerHours - example.overlap : example.outerHours
        HStack(spacing: 12) {
            GeometryReader { geo in
                let w = geo.size.width
                // 겹친 칸은 바깥 막대 가운데쯤에 얹는다 — 점심은 대개 한가운데다.
                let innerW = max(10, w * example.overlap / max(example.outerHours, 0.25))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.35))
                    Capsule()
                        .fill(Color.orange.opacity(0.9))
                        .frame(width: innerW)
                        .offset(x: (w - innerW) / 2)
                    // 빼는 기준이면 겹친 칸이 바깥 막대에서 **도려낸 것**처럼 보이게 빗금을 뗀다.
                    if rule == .subtractInner {
                        Capsule()
                            .strokeBorder(Color.orange, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                            .frame(width: innerW)
                            .offset(x: (w - innerW) / 2)
                    }
                }
            }
            .frame(height: 14)

            Text("\(example.outer) \(shortHours(counted)) · \(example.inner) \(shortHours(example.overlap))")
                .font(.body)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 넛지

/// 이번 주 시간표에 **실제로 겹침이 생겼을 때** 한 번 묻는다.
///
/// 설정 깊숙이 기준을 두기만 하면 거기 있는 줄 모른다. 반대로 처음부터 물으면 아직 겹친 적이 없어
/// 무슨 말인지 모른다. 그래서 겹침이 생긴 그 순간, 그 사람의 일정 이름으로 두 답을 그려 보인다.
struct OverlapNudgeBanner: View {
    let example: OverlapExample
    let onChoose: (OverlapRule) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "square.2.layers.3d")
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text("「\(example.outer)」 안에 「\(example.inner)」 \(shortHours(example.overlap)) 겹쳐 있어요")
                        .font(.headline)
                    Text("겹친 시간을 어느 쪽 몫으로 셀까요? 남은 시간은 어느 쪽이든 같고, 바깥 일정의 길이만 달라집니다. 설정에서 언제든 바꿀 수 있습니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("지금 기준대로 두고 더 묻지 않기")
            }

            HStack(spacing: 10) {
                ForEach(OverlapRule.allCases) { rule in
                    choice(rule)
                }
            }
            .padding(.leading, 34)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: .soft(Corner.card))
    }

    private func choice(_ rule: OverlapRule) -> some View {
        Button { onChoose(rule) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.title)
                    .font(.body.weight(.semibold))
                OverlapRuleExampleView(example: example, rule: rule)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: .soft(Corner.card))
            .contentShape(.soft(Corner.card))
        }
        .buttonStyle(.plain)
    }
}
