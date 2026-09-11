//
//  Affordance.swift
//  WeekBlocks
//
//  **잡을 수 있는 것은 눌러 보기 전에 알린다.**
//
//  계획 블록은 끌어 옮길 수 있고 루틴 칩은 못 옮기는데, 둘이 같은 높이·같은 커서였다.
//  무엇이 잡히는지는 한 번씩 끌어 봐야 알았다. 잡히는 것 위에서는 손 모양이 되고
//  (끄는 동안에는 쥔 손), 못 잡는 것 위에서는 평소 화살표 그대로다.
//  떠 있는 모양(그림자)은 각 칩이 직접 그린다 (→ BlockChip · DayTimelineRow.segmentView).
//

import SwiftUI
import AppKit

extension View {
    /// 끌 수 있는 것 위에서 손 모양 커서.
    ///
    /// ⚠️ `NSCursor.push()/pop()`으로 쌓지 않고 `set()`으로 덮는다. 쌓아 두면 가리킨 채로
    ///    뷰가 사라질 때(끌어서 다른 요일로 옮기면 그 칩은 이 칸에서 사라진다) `pop`이
    ///    불리지 않아 화살표로 영영 못 돌아온다.
    func grabCursor(enabled: Bool = true) -> some View {
        onContinuousHover { phase in
            guard enabled else { return }
            switch phase {
            case .active: NSCursor.openHand.set()
            case .ended:  NSCursor.arrow.set()
            }
        }
    }
}
