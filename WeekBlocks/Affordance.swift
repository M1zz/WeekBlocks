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

    /// 누르면 다른 자리로 건너가는 것(요일 머리 → 그날 하루) 위에서 손가락 커서.
    func pointingCursor(enabled: Bool = true) -> some View {
        hoverCursor(.pointingHand, enabled: enabled)
    }

    /// 손이 올라오면 이 커서로 — 끌어 옮기는 몸통, 늘였다 줄이는 양끝처럼
    /// **무엇을 할 수 있는 자리인지 손 모양이 먼저 말하는** 곳에 쓴다.
    func hoverCursor(_ cursor: NSCursor, enabled: Bool = true) -> some View {
        onContinuousHover { phase in
            guard enabled else { return }
            switch phase {
            case .active: cursor.set()
            case .ended:  NSCursor.arrow.set()
            }
        }
    }
}

// MARK: - 쫀쫀하게

/// **누르면 눌린다.** 평범한 단추(`.plain`)와 같은 모양에, 누르는 동안 살짝 오므라들었다가
/// 놓으면 통 튀어 돌아온다. 손가락이 무엇을 눌렀는지를 화면이 받아 준다.
///
/// 오므라드는 정도는 크기에 맞춘다 — 같은 비율이면 작은 동그라미는 티가 안 나고
/// 줄 전체를 감싼 단추는 화면이 출렁인다. 늘 몇 pt만큼만 들어간다.
struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .visualEffect { content, proxy in
                content.scaleEffect(pressed ? Self.pressedScale(for: proxy.size) : 1)
            }
            .animation(pressed ? Motion.press : Motion.squish, value: pressed)
    }

    nonisolated static func pressedScale(for size: CGSize) -> CGFloat {
        let longest = max(size.width, size.height, 1)
        return 1 - min(0.12, 5 / longest)
    }
}

extension ButtonStyle where Self == SquishButtonStyle {
    static var squish: SquishButtonStyle { SquishButtonStyle() }
}

extension View {
    /// 가리키면 한 뼘 떠오른다. 잡을 수 있는 카드·칩에.
    func hoverLift(_ hovering: Bool, scale: CGFloat = 1.01) -> some View {
        scaleEffect(hovering ? scale : 1)
            .animation(Motion.squish, value: hovering)
    }
}

/// **손끝에 오는 딸깍.** 포스 터치 트랙패드에서만 느껴지고, 나머지에서는 아무 일도 없다.
///
/// 소리 대신 손이다 — 눈을 떼고 끌어도 15분 격자에 붙었는지, 표시가 찍혔는지가 손에 온다.
/// 자주 울리면 잡음이 되므로 **무언가가 자리를 잡은 순간**에만 부른다.
enum Haptic {
    /// 제자리에 놓였다 — 끌어 옮기기·떨어뜨리기가 끝났을 때.
    static func snap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// 상태가 한 칸 바뀌었다 — 체크·표시·고르기.
    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
