//
//  Surface.swift
//  WeekBlocks
//
//  **대시보드 위에 카드가 올라가 있는 것처럼.**
//
//  바닥(창 바탕)과 카드(요일 칸·요약·할 일·루틴)가 거의 같은 흰색이라 경계가 없었고,
//  칩들이 허공에 떠 있었다. 바닥을 한 톤 가라앉히고 카드는 한 톤 올린 뒤 옅은 그림자를
//  깐다. 그러면 무엇이 한 덩어리인지가 선을 긋지 않고도 보인다.
//
//  ⚠️ 그림자는 **바탕 모양에만** 건다. 뷰 전체에 걸면 안에 든 글자·칩마다 그림자가 생겨
//     흐려지고, 요일 칸이 분마다 다시 그려질 때 그만큼 무거워진다.
//  ⚠️ 어두운 모드에서는 그림자가 바닥에 묻힌다. 그래서 가장자리에 아주 옅은 선을 함께 둔다.
//

import SwiftUI

extension Color {
    // 색은 에셋 카탈로그(Assets.xcassets ▸ Dashboard*)에 있다. 밝은·어두운 모양에
    // **고대비** 모양을 한 벌씩 더 두었다 — 손쉬운 사용 ▸ 대비 증가를 켜면 바닥이 한 톤 더
    // 가라앉고(어두울 때는 검정) 카드 가장자리 선이 또렷해진다. 옅은 회색 위의 흰 카드는
    // 대비를 높인 화면에서 경계가 아예 사라졌다.

    /// 대시보드의 바닥. 카드보다 한 톤 가라앉는다.
    static let canvas = Color("DashboardCanvas")

    /// 바닥 위에 올라간 카드.
    static let surface = Color("DashboardSurface")

    /// 카드 가장자리. 밝을 때는 그림자가 경계를 맡으므로 거의 안 보인다(고대비에서는 또렷하다).
    static let surfaceEdge = Color("DashboardSurfaceEdge")
}

/// 바닥 위에 올라간 카드의 **바탕**. `.background { DashboardSurface() }`로 깐다.
struct DashboardSurface: View {
    var radius: CGFloat = Corner.panel
    /// 어두운 모드에서는 그림자가 바닥에 묻혀 경계를 못 맡는다 — 가장자리 선을 두 배로 세운다.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle.soft(radius)
            .fill(Color.surface)
            // 두 겹: 바짝 붙은 얇은 그림자가 윤곽을, 넓게 퍼진 그림자가 떠 있는 높이를 만든다.
            .shadow(color: .black.opacity(0.05), radius: 1, y: 0.5)
            .shadow(color: .black.opacity(0.07), radius: 14, y: 4)
            .overlay(RoundedRectangle.soft(radius)
                .strokeBorder(Color.surfaceEdge,
                              lineWidth: contrast == .increased ? 1.5 : (colorScheme == .dark ? 1 : 0.5)))
    }
}

extension View {
    /// 한 묶음(할 일·루틴·시간축)을 대시보드 카드 하나로 올린다.
    func dashboardPanel(padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { DashboardSurface() }
    }
}

// MARK: - 떠 있는 것의 바탕

/// 시간표 **위에 떠 있는** 조각(블록 그리는 창·겹침 알약·접기 단추)의 바탕.
///
/// 평소에는 반투명 재질이라 아래 시간표가 비친다 — 무엇 위에 떠 있는지가 보인다.
/// 손쉬운 사용 ▸ 투명도 줄이기를 켠 사람에게는 비치는 무늬가 글씨를 흐리는 소음이라
/// **카드와 같은 불투명 색**으로 깐다. 시스템이 재질을 회색으로 바꿔 주기는 하지만,
/// 그러면 이 앱의 카드와 결이 달라져 떠 있는 것만 다른 앱처럼 보인다.
struct FloatingBackdrop<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color.surface, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

extension View {
    /// 시간표 위에 떠 있는 조각의 바탕 (→ FloatingBackdrop).
    func floatingBackdrop<S: InsettableShape>(in shape: S) -> some View {
        modifier(FloatingBackdrop(shape: shape))
    }
}
