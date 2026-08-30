//
//  BacklogItem+Fragment.swift
//
//  단계 하나가 조각인지 덩어리인지를 가르는 두 질문에 **사용자가 직접 답한 것**을
//  저장한다. 앱의 판정(→ TodoSplitAdvisor)은 낱말과 시간으로 짐작한 것이라
//  남의 일에 대해서는 자주 틀린다. 틀린 판정을 못 고치면 판정 전체를 안 믿게 되므로,
//  뒤집을 자리를 열어 둔다. 대신 **묻지는 않는다** — 앱이 먼저 답해 두고,
//  사용자는 단계를 들여다볼 때 틀린 것만 고친다.
//
//  저장 자리는 옛 '착수 조건' 필드(labelRaw)를 다시 쓴다. 새 필드를 더하면 맥앱과
//  공유하는 CloudKit 스키마를 양쪽에서 같이 바꿔야 하는데, 이 값은 그만한 무게가 없다.
//  옛 값("immediate", "focus" …)은 접두어가 없으니 저절로 '답 없음'으로 읽힌다.
//
//  ⚠️ 이 파일은 iOS('욕망의 무지개')와 macOS('무지개 공방') 두 레포에 **같은 내용으로**
//     복제돼 있다. 한쪽을 고치면 다른 쪽도 반드시 같이 고칠 것.
//

import Foundation

extension BacklogItem {

    /// 저장 형식: `pick:` + 질문 하나의 답 + 질문 둘의 답. 각 자리는 y / n / ?.
    /// 예) `pick:y?` = "시동 없이 시작된다"는 직접 답했고, 나머지는 앱 판정.
    private static let pickPrefix = "pick:"

    /// 사용자가 두 질문에 직접 답한 것. 비어 있으면 앱 판정을 그대로 쓴다.
    var fragmentPick: FragmentPick {
        get {
            guard let raw = labelRaw, raw.hasPrefix(Self.pickPrefix) else { return .none }
            let chars = Array(raw.dropFirst(Self.pickPrefix.count))
            guard chars.count == 2 else { return .none }
            return FragmentPick(start: Self.decode(chars[0]), closing: Self.decode(chars[1]))
        }
        set {
            guard newValue.isSet else {
                // 답을 다 거둬들이면 옛 값까지 같이 지운다. 안 그러면 다음에 읽을 때
                // 접두어 없는 찌꺼기가 남아 '답 없음'인지 '옛 착수 조건'인지 알 수 없다.
                labelRaw = nil
                return
            }
            labelRaw = Self.pickPrefix + Self.encode(newValue.start) + Self.encode(newValue.closing)
        }
    }

    /// 한 질문의 답만 바꾼다. nil을 넣으면 그 자리를 앱 판정으로 되돌린다.
    func setFragmentAnswer(_ value: Bool?, for question: FragmentQuestion) {
        var pick = fragmentPick
        pick.set(value, for: question)
        fragmentPick = pick
    }

    private static func decode(_ char: Character) -> Bool? {
        switch char {
        case "y": return true
        case "n": return false
        default:  return nil
        }
    }

    private static func encode(_ value: Bool?) -> String {
        guard let value else { return "?" }
        return value ? "y" : "n"
    }
}

// MARK: - 목록에서 줄을 가르는 규칙
//
// 두 앱이 같은 순서와 같은 색을 쓰기 위한 공통 판정. iOS는 목록의 띠로,
// macOS는 카드 그리드의 순서와 배경색으로 옮긴다.

extension BacklogItem {
    /// 두 질문에 모두 '예'라고 **사용자가 직접** 답해 둔 줄인가 = '바로 하면 되는 일'.
    ///
    /// 앱 판정(→ `TodoSplitAdvisor`)과 일부러 구분한다. 짐작으로 올린 줄이 섞이면
    /// 그 자리를 한 번 믿었다가 데인 뒤로 다시는 안 보게 된다.
    var isMarkedNow: Bool {
        let pick = fragmentPick
        return pick.start == true && pick.closing == true
    }
}

extension TodoTree {
    /// 목록에서 이 줄이 서는 자리. 값이 곧 순서다 (작을수록 위).
    enum Lane: Int, Comparable {
        /// 바로 하면 되는 일 — 표시해 둔 줄, 또는 표시해 둔 단계를 품은 일.
        case now = 0
        /// 그냥 하면 되는 것 — 시간도 마감도 안 잡은 줄.
        case errand = 1
        /// 시간을 잡은 일.
        case planned = 2

        static func < (a: Lane, b: Lane) -> Bool { a.rawValue < b.rawValue }
    }

    /// 이 할 일 안에서 사용자가 표시해 둔, 아직 안 끝난 단계.
    /// 차례와 상관없이 이게 있으면 줄에 세운다 — 표시해 둔 뜻이 그것이다.
    func markedStep(of item: BacklogItem) -> BacklogItem? {
        let candidates = hasChildren(item) ? leaves(of: item) : [item]
        return candidates.first { !$0.isCompleted && $0.isMarkedNow }
    }

    /// 이 줄이 어느 자리에 서는가.
    ///
    /// `hasDeadline`은 무지개에 그어 둔 줄이 있는지 — 마감이 붙은 일은 시간이 0이어도
    /// '그냥 하면 되는 것'이 아니다. 일정은 다른 스토어에 있어 여기서 못 보므로
    /// 부르는 쪽이 알려준다.
    func lane(of item: BacklogItem, hasDeadline: Bool = false) -> Lane {
        if markedStep(of: item) != nil { return .now }
        if isErrand(item), !hasDeadline { return .errand }
        return .planned
    }
}
