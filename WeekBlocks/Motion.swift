import SwiftUI

// MARK: - 움직임의 어휘
//
// 화면이 바뀌는 자리마다 제각각 시간을 적어 두면, 같은 손짓인데 어떤 곳은 빠르고
// 어떤 곳은 느려서 앱이 한 물건으로 안 읽힌다. **무엇이 일어나는가**로 이름을 붙이고
// 그 이름만 쓴다 — 나중에 결을 고칠 때도 한 자리만 고치면 된다.
//
// 시간은 짧게 잡는다. 계획을 짜는 화면은 손이 여러 번 오가는 곳이라,
// 한 번에 0.3초를 넘기면 다음 손짓이 앞의 움직임을 기다리게 된다.
enum Motion {
    /// 카드·칩이 생기고 사라지고 자리를 옮긴다. 목록의 기본 결.
    static let card = Animation.spring(response: 0.34, dampingFraction: 0.82)

    /// 줄 하나가 서고 내려간다. 카드보다 가볍게.
    static let row = Animation.spring(response: 0.28, dampingFraction: 0.86)

    /// 접었다 펴는 것 — 요약, '요일에 올린 일', 폼의 한 묶음.
    static let disclose = Animation.snappy(duration: 0.26)

    /// 한 자리에서 다른 자리로 넘어간다 (보는 자리 바꾸기·주 넘기기·안내 걸음).
    static let screen = Animation.snappy(duration: 0.3)

    /// 알리는 줄이 위에서 내려오고 올라간다.
    static let banner = Animation.snappy(duration: 0.22)

    /// 손이 올라가고 내려간다. 눈이 좇을 것이 아니라 **곧바로** 답해야 한다.
    static let hover = Animation.easeOut(duration: 0.13)

    /// 받을 자리라는 표시가 켜지고 꺼진다.
    static let target = Animation.easeOut(duration: 0.12)

    /// 시간 자 위에서 띠가 제자리를 찾아간다 (15분 격자에 붙는 순간).
    static let timeline = Animation.spring(response: 0.3, dampingFraction: 0.9)

    /// 숫자가 바뀐다 (남은 시간·퍼센트). 자릿수가 굴러가는 결.
    static let number = Animation.snappy(duration: 0.25)
}

extension AnyTransition {
    /// 카드가 목록에 끼어들고 빠진다. 오고 가는 결이 같아야 한 장이 들고 난 것으로 읽힌다.
    static let card = AnyTransition.scale(scale: 0.94).combined(with: .opacity)

    /// 줄이 위에서 밀려 들어오고 그 자리에서 스러진다.
    static let row = AnyTransition.asymmetric(
        insertion: .move(edge: .top).combined(with: .opacity),
        removal: .opacity
    )

    /// 접힌 것이 펴진다. 양쪽 결이 같아야 한 덩어리가 여닫히는 것으로 읽힌다.
    static let disclose = AnyTransition.move(edge: .top).combined(with: .opacity)

    /// 위에서 내려오는 알림 줄.
    static let banner = AnyTransition.move(edge: .top).combined(with: .opacity)

    /// 손이 올라갔을 때만 나타나는 작은 단추.
    static let control = AnyTransition.scale(scale: 0.8).combined(with: .opacity)

    /// 옆으로 한 장 넘긴다. **나가는 쪽과 들어오는 쪽이 같은 방향**으로 흘러야
    /// 한 장이 넘어간 것으로 읽힌다. 밀리는 거리는 짧게 — 화면이 통째로 날아다니면 산만하다.
    static func pageSlide(forward: Bool, distance: CGFloat = 28) -> AnyTransition {
        .asymmetric(
            insertion: .offset(x: forward ? distance : -distance).combined(with: .opacity),
            removal: .offset(x: forward ? -distance : distance).combined(with: .opacity)
        )
    }
}
