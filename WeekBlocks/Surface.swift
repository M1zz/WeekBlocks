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
import AppKit

extension Color {
    /// 대시보드의 바닥. 카드보다 한 톤 가라앉는다.
    static let canvas = Color(nsColor: NSColor(name: "WeekBlocksCanvas") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.105, green: 0.105, blue: 0.115, alpha: 1)
            : NSColor(srgbRed: 0.945, green: 0.945, blue: 0.957, alpha: 1)
    })

    /// 바닥 위에 올라간 카드.
    static let surface = Color(nsColor: NSColor(name: "WeekBlocksSurface") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.165, green: 0.165, blue: 0.178, alpha: 1)
            : .white
    })

    /// 카드 가장자리. 밝을 때는 그림자가 경계를 맡으므로 거의 안 보인다.
    static let surfaceEdge = Color(nsColor: NSColor(name: "WeekBlocksSurfaceEdge") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.04)
    })
}

/// 바닥 위에 올라간 카드의 **바탕**. `.background { DashboardSurface() }`로 깐다.
struct DashboardSurface: View {
    var radius: CGFloat = Corner.panel

    var body: some View {
        RoundedRectangle.soft(radius)
            .fill(Color.surface)
            // 두 겹: 바짝 붙은 얇은 그림자가 윤곽을, 넓게 퍼진 그림자가 떠 있는 높이를 만든다.
            .shadow(color: .black.opacity(0.05), radius: 1, y: 0.5)
            .shadow(color: .black.opacity(0.07), radius: 14, y: 4)
            .overlay(RoundedRectangle.soft(radius).strokeBorder(Color.surfaceEdge, lineWidth: 0.5))
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
