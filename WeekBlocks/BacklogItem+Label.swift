//
//  BacklogItem+Label.swift
//
//  라벨(TodoLabel)을 BacklogItem에서 읽는 자리.
//
//  ⚠️ TodoSplitAdvisor.swift에 붙어 있던 것을 떼어냈다. 그 파일은 순수 로직이라
//     공유 익스텐션도 함께 컴파일하는데, 모델(BacklogItem)에 얹힌 확장이 같이 있으면
//     익스텐션까지 모델과 그 딸린 것들을 전부 끌고 와야 했다.
//  ⚠️ 이 파일도 iOS('욕망의 무지개')와 macOS('무지개 공방') 두 레포에 같은 내용으로
//     복제돼 있다. 한쪽을 고치면 다른 쪽도 반드시 같이 고칠 것.
//

import Foundation

extension BacklogItem {
    /// 이 항목의 착수 조건. 아직 고르지 않았으면 예상 시간에서 짐작한다.
    /// 속성이 '얼마나 걸리나'였던 시절의 값도 `resolve`가 받아 준다.
    var label: TodoLabel {
        if let raw = labelRaw, let value = TodoLabel.resolve(raw) { return value }
        return .nearest(toHours: durationHours)
    }

    /// 사용자가 직접 고른 속성인가 (짐작이 아니라).
    var hasLabel: Bool {
        guard let raw = labelRaw else { return false }
        return TodoLabel.resolve(raw) != nil
    }
}
