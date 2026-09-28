import SwiftUI

/// 그날 **해야 할 일**이 몇 개이고 그중 몇 개를 찍었는가.
///
/// 루틴은 뺀다 — '오늘의 계획'에서 체크 동그라미가 서는 줄과 같은 기준이다
/// (→ PlanBlock.isRoutineKind). 수면·끼니까지 세면 매일 같은 칸이 차서 날마다 똑같아 보인다.
struct TodoLoad: Equatable {
    var total: Int
    /// 끝냄·부분·건너뜀 중 하나라도 찍은 것. 더는 붙잡고 있지 않다.
    var marked: Int

    var remaining: Int { total - marked }

    init(_ blocks: [PlanBlock], routineNames: Set<String>) {
        let todos = blocks.filter { !$0.isRoutineKind(routineNames) }
        total = todos.count
        marked = todos.filter { $0.reviewStatus != nil }.count
    }
}

/// **그날의 무지개.** 아이폰 '욕망의 무지개'의 한 줄과 같은 뜻이다 —
/// 가로로 늘어선 칸 수가 그날 한꺼번에 굴리는 일의 수다.
///
/// 할 일 하나가 한 칸이고, 빨강부터 차례로 찬다. 보라까지 차면 일곱 개 —
/// 하나만 어긋나도 그날 전체가 밀리는 날이다. 색은 **몇 번째 칸인지**를 말할 뿐
/// 할 일의 분류와는 상관없다 (→ Rainbow.lanes, 아이폰 laneColors와 같은 차례).
///
/// 남은 일은 진하게, 찍은 일은 옅게 뒤로 선다. 아이폰에서 '진한 칸은 시간을 쓰는 날,
/// 옅은 칸은 매여만 있는 날'인 것과 같은 결이다 — 하나 끝낼 때마다 진한 칸이 오른쪽부터 줄어든다.
struct TodoRainbow: View {
    let load: TodoLoad
    /// 칸 하나의 폭. nil이면 받은 폭을 일곱 칸이 나눠 가진다.
    var cellWidth: CGFloat? = nil
    var cellHeight: CGFloat = 6

    private static let lanes = Rainbow.spectrum.count

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<Self.lanes, id: \.self) { i in
                    Capsule(style: .continuous)
                        .fill(fill(i))
                        .frame(width: cellWidth, height: cellHeight)
                        .frame(maxWidth: cellWidth == nil ? .infinity : nil)
                }
            }
            // 일곱을 넘친 것은 칸을 더 늘리지 않고 수로 말한다. 칸이 늘면 한 주의 줄이 어긋난다.
            if load.total > Self.lanes {
                Text(verbatim: "+\(load.total - Self.lanes)")
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Rainbow.laneColor(Self.lanes - 1))
                    .fixedSize()
                    .transition(.pop)
            }
        }
        .animation(Motion.squish, value: load)
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(help)
    }

    private func fill(_ i: Int) -> Color {
        if i < load.remaining { return Rainbow.laneColor(i) }
        if i < load.total { return Rainbow.laneColor(i).opacity(0.25) }
        return Color.primary.opacity(0.06)
    }

    private var help: String {
        load.total == 0
            ? String(localized: "해야 할 일 없음")
            : String(localized: "해야 할 일 \(load.total)개 · 남은 것 \(load.remaining)개")
    }
}

extension Rainbow {
    /// 몇 번째 칸의 색. 빨강(0) → 보라(6), 넘치면 보라에 머문다.
    static func laneColor(_ index: Int) -> Color {
        let hex = spectrum[min(max(0, index), spectrum.count - 1)].hex
        return Color(hex: hex) ?? .accentColor
    }
}
