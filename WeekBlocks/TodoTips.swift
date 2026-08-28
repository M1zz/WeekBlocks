//
//  TodoTips.swift
//
//  할 일 화면의 조언을 담는 곳 — 전부 TipKit으로 낸다.
//
//  왜 TipKit인가:
//  화면에 조언을 상시로 깔아두면 정보가 너무 많아 정작 일을 시작하기 어렵다.
//  TipKit은 (1) 필요한 때에만 뜨고 (2) 닫으면 다시 안 뜨고 (3) 시스템이 빈도를 조절한다.
//  그래서 "알려줘야 하는 것"은 전부 여기로 모으고, 화면에는 지금 할 일만 남긴다.
//
//  ⚠️ 이 파일은 iOS('욕망의 무지개')와 macOS('무지개 공방') 두 레포에 **같은 내용으로**
//     복제돼 있다. 한쪽을 고치면 다른 쪽도 반드시 같이 고칠 것.
//

import SwiftUI
import TipKit

// MARK: - 앱 시작할 때 한 번

enum TodoTips {
    /// 앱 진입점에서 한 번 부른다. 실패해도 앱은 그대로 돌아간다(팁만 안 뜬다).
    static func configure() {
        try? Tips.configure([
            // 규칙을 만족하면 바로 보여준다. 어차피 각 팁은 한 번 닫으면 끝이다.
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault)
        ])
    }

    /// 조언을 처음부터 다시 보고 싶을 때 (설정에서 부른다).
    static func resetAll() {
        try? Tips.resetDatastore()
    }
}

// MARK: - 단계 나누기

/// 한 할 일 안에 단계가 둘 이상 생긴 순간, 단계에 무엇을 정해 주면 되는지 한 번만 설명한다.
struct ShareSplitTip: Tip {
    /// 단계를 둘 이상 만들어 본 적이 있는가.
    @Parameter static var hasSplit: Bool = false

    var title: Text { Text("한 자리에서 닫히는 크기로") }
    var message: Text? {
        Text("단계는 한 번 앉아서 끝낼 수 있는 크기여야 합니다. 하다 만 단계는 다음 시간까지 주의를 끌고 갑니다.\n이 일 전체 시간은 단계들의 합이 됩니다.")
    }
    var image: Image? { Image(systemName: "bolt.fill") }
    var rules: [Rule] {
        #Rule(Self.$hasSplit) { $0 == true }
    }
}

// MARK: - 쪼개기 조언 (내용이 그때그때 다른 팁)

/// `TodoSplitAdvisor`가 만든 구성 조언 하나를 팁으로 낸다.
///
/// 조언 종류마다 다른 `id`를 쓴다 — 한 종류를 닫으면 그 종류만 다시 안 뜨고,
/// 다른 종류의 조언은 계속 뜬다.
struct SplitHintTip: Tip {
    let hint: SplitHint

    var id: String { "split-hint-\(hint.code)" }
    var title: Text { Text(hint.title) }
    var message: Text? {
        if let source = hint.source {
            return Text("\(hint.detail)\n\n— \(source)")
        }
        return Text(hint.detail)
    }
    var image: Image? {
        switch hint.tone {
        case .good:    return Image(systemName: "checkmark.seal.fill")
        case .caution: return Image(systemName: "exclamationmark.triangle.fill")
        case .info:    return Image(systemName: "lightbulb")
        }
    }
}

/// 단계 하나에 붙는 경고(시동 비용·너무 큰 단계 등)를 팁으로 낸다.
/// 지금 할 단계에만 띄운다 — 모든 줄에 경고를 깔면 다시 정보가 너무 많아진다.
struct StepWarningTip: Tip {
    let warning: StepAdvice.Warning

    var id: String { "step-warning-\(warning.source)" }
    var title: Text { Text("이 단계, 이대로 괜찮을까요") }
    var message: Text? { Text("\(warning.message)\n\n— \(warning.source)") }
    var image: Image? { Image(systemName: "exclamationmark.triangle.fill") }
}
