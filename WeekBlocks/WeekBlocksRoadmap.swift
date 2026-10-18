//
//  WeekBlocksRoadmap.swift
//  WeekBlocks (무지개 공방)
//
//  **앞으로 만들 것**의 원본. 설정 ▸ 앞으로 만들 기능(`LeeoRoadmapView`)이 이 목록을 그대로 보여 준다.
//
//  ⚠️ 개발하다 "이건 다음에" 가 생기면 **여기에 한 줄을 더한다.** 코드의 TODO 주석으로만 남기지 않는다.
//     - 새 항목: `.planned`. 손대기 시작하면 `.building`. 내보내면 `.shipped("1.2.0")`.
//     - id 는 한 번 정하면 바꾸지 않는다(문구는 바꿔도 된다).
//     - 문구는 사용자 말로 쓴다(내부 이름 · 기술 용어 금지). 번역은 WeekBlocks/Localizable.xcstrings 에
//       다른 문구처럼 모든 언어로 넣는다(빈칸이 있으면 그 언어에서 한국어가 보인다).
//     - 사용자에게 보일 만한 것만 적는다. 리팩터링 · 시험 · 빌드 설정은 `.sprintcommander/tasks.json` 의 몫이다.
//

import SwiftUI
import LeeoKit

extension WeekBlocksSpec {
    static var roadmap: [LeeoRoadmapItem] {[
        // MARK: 다음에 만들어요
        .init(id: "a11y.voiceover", status: .building,
              title: String(localized: "VoiceOver로 더 편하게", comment: "Roadmap item: better VoiceOver support"),
              detail: String(localized: "VoiceOver가 계획표의 블록과 단추를 빠짐없이, 알맞은 순서로 읽어 줘요.", comment: "Roadmap item detail: better VoiceOver support")),
        .init(id: "a11y.largetext", status: .planned,
              title: String(localized: "큰 글씨에 맞춘 화면", comment: "Roadmap item: layouts for larger text"),
              detail: String(localized: "글자를 키워도 계획표가 잘리지 않고 보기 좋게 다시 놓여요.", comment: "Roadmap item detail: layouts for larger text")),
        .init(id: "a11y.contrast", status: .shipped("1.1.13"),
              title: String(localized: "보기 편한 색과 대비", comment: "Roadmap item: better colors and contrast"),
              detail: String(localized: "대비를 높이거나 색을 구별하기 어려워도 무지개 블록을 알아볼 수 있어요.", comment: "Roadmap item detail: better colors and contrast")),
        .init(id: "whatsnew", status: .shipped("1.1.13"),
              title: String(localized: "업데이트 소식", comment: "Roadmap item: what's new after an update"),
              detail: String(localized: "업데이트 뒤 처음 열 때 무엇이 새로 생겼는지 알려 줘요.", comment: "Roadmap item detail: what's new after an update")),
        .init(id: "gift", status: .planned,
              title: String(localized: "Pro 선물하기", comment: "Roadmap item: gift Pro"),
              detail: String(localized: "무지개 공방 Pro를 다른 사람에게 선물할 수 있어요.", comment: "Roadmap item detail: gift Pro")),
        .init(id: "shortcuts", status: .planned,
              title: String(localized: "Siri와 단축어", comment: "Roadmap item: Siri and Shortcuts"),
              detail: String(localized: "Siri에게 말하거나 단축어로 할 일을 바로 더해요.", comment: "Roadmap item detail: Siri and Shortcuts")),
        .init(id: "lock.faceid", status: .planned,
              title: String(localized: "Touch ID 잠금", comment: "Roadmap item: Touch ID lock"),
              detail: String(localized: "Touch ID로 앱을 잠가 내 계획과 회고를 지켜요.", comment: "Roadmap item detail: Touch ID lock")),
        .init(id: "autosave", status: .planned,
              title: String(localized: "적던 내용 이어 쓰기", comment: "Roadmap item: keep unsaved drafts"),
              detail: String(localized: "쓰다가 앱이 꺼져도 적던 내용이 그대로 남아 있어요.", comment: "Roadmap item detail: keep unsaved drafts")),
    ]}
}

// MARK: - 화면

/// 설정 ▸ 앞으로 만들 기능. "이런 기능이 있으면 좋겠어요" 는 기능 제안으로 시작하는 피드백 창을 연다.
struct RoadmapScreen: View {
    @State private var showFeedback = false

    var body: some View {
        LeeoRoadmapView<WeekBlocksSpec>(onSuggest: { showFeedback = true })
            .sheet(isPresented: $showFeedback) {
                NavigationStack {
                    LeeoFeedbackView<WeekBlocksSpec>(initialType: .feature)
                }
                .frame(minWidth: 480, minHeight: 560)
            }
    }
}
