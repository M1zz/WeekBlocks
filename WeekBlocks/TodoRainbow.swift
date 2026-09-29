import SwiftUI

/// 그날 **해야 할 일**이 몇 개이고 그중 몇 개를 찍었는가.
///
/// 루틴은 뺀다 — '오늘의 계획'에서 체크 동그라미가 서는 줄과 같은 기준이다
/// (→ PlanBlock.isRoutineKind). 수면·끼니까지 세면 매일 같은 칸이 차서 날마다 똑같아 보인다.
struct TodoLoad: Equatable {
    var total: Int
    /// 끝냄·부분·건너뜀 중 하나라도 찍은 것. 더는 붙잡고 있지 않다.
    var marked: Int
    /// 칸 차례대로, 그 칸의 일을 찍었는가.
    var marks: [Bool]
    /// 블록(`dragToken`) → 그 블록이 차지한 칸의 색.
    ///
    /// **무지개의 빨간 칸을 만든 그 일이 주간 칩·일간 자·블록에서도 빨갛게 선다.**
    /// 전에는 계획 블록이 전부 액센트(파랑)여서, 무지개에서 본 칸이 어느 일인지 이어지지 않았다.
    /// 루틴 이름의 블록은 칸을 안 차지하므로 여기 없다 — 제 색(액센트)을 그대로 쓴다.
    var colors: [String: Color] { colorNames.mapValues(paletteColor) }
    /// 같은 것을 팔레트 이름으로 ("red"…). 타이머처럼 색을 이름으로 들고 다니는 곳이 쓴다 (→ TimerTarget.colorName).
    var colorNames: [String: String]

    var remaining: Int { total - marked }

    init(_ blocks: [PlanBlock], routineNames: Set<String>) {
        // 칸 차례 = 하루에 놓인 차례. 찍어도 칸이 옮겨 가지 않아야 블록 색이 그대로 머문다.
        let todos = blocks.filter { !$0.isRoutineKind(routineNames) }
            .sorted { ($0.sortHour, $0.createdAt) < ($1.sortHour, $1.createdAt) }
        total = todos.count
        marks = todos.map { $0.reviewStatus != nil }
        marked = marks.filter { $0 }.count
        let lanes = Rainbow.spectrum.count
        colorNames = Dictionary(todos.enumerated().map { ($1.dragToken, Rainbow.spectrum[min($0, lanes - 1)].name) },
                                uniquingKeysWith: { a, _ in a })
    }

    /// 이 블록의 무지개 색. 칸을 안 차지하는 블록(루틴 이름)이면 nil.
    func color(for block: PlanBlock) -> Color? { colorName(for: block).map(paletteColor) }
    func colorName(for block: PlanBlock) -> String? { colorNames[block.dragToken] }
}

/// **그날의 무지개.** 아이폰 '욕망의 무지개'의 한 줄과 같은 뜻이다 —
/// 가로로 늘어선 칸 수가 그날 한꺼번에 굴리는 일의 수다.
///
/// 할 일 하나가 한 칸이고, 빨강부터 차례로 찬다. 보라까지 차면 일곱 개 —
/// 하나만 어긋나도 그날 전체가 밀리는 날이다. 색은 **몇 번째 칸인지**를 말할 뿐
/// 할 일의 분류와는 상관없다 (→ Rainbow.lanes, 아이폰 laneColors와 같은 차례).
///
/// 칸의 차례는 하루에 놓인 차례이고, 같은 색이 그 블록에도 칠해진다 (→ TodoLoad.colors).
/// 남은 일은 진하게, 찍은 일은 옅게 선다 — 하나 끝내면 그 일의 칸이 제자리에서 옅어진다.
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
        if i < load.total {
            return load.marks[i] ? Rainbow.laneColor(i).opacity(0.25) : Rainbow.laneColor(i)
        }
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
