//
//  Corner.swift
//  WeekBlocks
//
//  **모서리는 여기서 고른다.**
//
//  둥글기가 파일마다 2·3·4·5·6·7·8·10으로 흩어져 있어서 같은 급의 카드끼리도 모서리가
//  달랐고, 전체가 각져 보였다. 크기 급을 다섯으로 묶고 모두 한 단계씩 둥글게 올렸다.
//  그리고 전부 **연속 곡률**(`.continuous`)로 그린다 — 원호를 이어 붙인 모서리는 직선과
//  만나는 자리가 꺾여 보이는데, 연속 곡률은 애플 기본 앱의 카드처럼 부드럽게 흘러 들어간다.
//
//  ⚠️ 새 모서리에 숫자를 직접 쓰지 않는다. 가장 가까운 급을 쓴다 — 급을 하나씩 늘리면
//     다시 흩어진다.
//  ⚠️ 높이가 곧 둥글기인 것(진행 막대·배지·왼쪽 색 막대)은 급이 아니라 `Capsule()`이다.
//     작은 색 견본은 `Circle()`이다.
//

import SwiftUI

enum Corner {
    /// 시간축 위의 조각 막대 (높이 20pt 안팎).
    static let segment: CGFloat = 6
    /// 시간축 한 줄의 바탕.
    static let track: CGFloat = 8
    /// 요일 칸 안의 칩, 작은 행·단추.
    static let chip: CGFloat = 10
    /// 할 일 카드·루틴 카드·입력 칸·안내 상자.
    static let card: CGFloat = 14
    /// 요일 칸·요약 카드처럼 다른 것을 담는 판.
    static let panel: CGFloat = 18
}

extension Shape where Self == RoundedRectangle {
    /// 연속 곡률 모서리. `RoundedRectangle(cornerRadius:)` 대신 이것을 쓴다.
    ///
    ///     .background(tint, in: .soft(Corner.card))
    ///     RoundedRectangle.soft(Corner.chip).strokeBorder(…)
    static func soft(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}
