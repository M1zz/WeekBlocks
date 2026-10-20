//
//  WhatsNewView.swift
//  WeekBlocks (무지개 공방)
//
//  **업데이트 뒤 처음 열 때 한 번 뜨는 "새로 생긴 것".**
//
//  업데이트 노트는 App Store 에만 있고, 맥 앱은 저절로 업데이트되니 그걸 읽는 사람이 거의 없다.
//  새로 생긴 것을 모르면 없는 것과 같다 — 그래서 켜자마자 한 번, 짧게 말한다.
//
//  ⚠️ **처음 받은 사람에게는 뜨지 않는다** (`WhatsNewAudience`). 처음 온 사람에게 "새로워졌어요"는
//     무슨 말인지 알 수 없는 말이고, 그 사람은 온보딩이 맞이한다. 첫 실행이면 본 것으로만 적어 둔다.
//  ⚠️ **내용을 바꿀 때 `WhatsNewContent.version` 도 같이 올린다.** 안 올리면 업데이트한 사람은
//     이미 본 것으로 적혀 있어 새 안내를 한 번도 못 본다. 버전과 상관없는 업데이트(고친 것만 있는
//     빌드)에서는 올리지 않는다 — 그때마다 같은 안내가 다시 뜨면 닫는 일만 는다.
//  ⚠️ 설정 ▸ 조언 ▸ '새로 생긴 것 다시 보기' 에서 언제든 다시 볼 수 있다.
//

import SwiftUI
import LeeoKit

/// 이 안내가 소개하는 기능의 버전. 앱 버전이 아니라 **안내 내용의 버전**이다.
enum WhatsNewContent {
    static let version = "1.1.13"
    static let lastSeenKey = "whatsNew.lastSeenVersion"
}

/// 앱을 연 사람이 **어느 쪽인지** — 순수 함수라 시험이 같은 입력을 직접 만든다.
enum WhatsNewAudience: Equatable {
    /// 처음 받은 사람. 온보딩이 맞이하고, 이번 안내는 본 것으로 적어만 둔다.
    case newcomer
    /// 쓰던 사람이고 이번 안내를 아직 못 봤다.
    case needsWhatsNew
    /// 쓰던 사람이고 이미 봤다.
    case upToDate

    /// - Parameters:
    ///   - launchCount: 이번 실행까지 센 누적 실행 횟수 (`LeeoEngagement.launchCount`).
    ///   - lastSeenVersion: 마지막으로 본 안내의 버전.
    static func resolve(launchCount: Int, lastSeenVersion: String?,
                        current: String = WhatsNewContent.version) -> WhatsNewAudience {
        if launchCount <= 1 { return .newcomer }
        return lastSeenVersion == current ? .upToDate : .needsWhatsNew
    }
}

struct WhatsNewView: View {
    var onClose: () -> Void
    /// 시트로 띄울 때만 닫는 단추를 둔다. 설정 안에서 다시 볼 때는 뒤로 가기가 있다.
    var showsCloseButton = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("새로 생긴 것")
                            .font(.title.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                        Text("이번 업데이트에서 달라진 점입니다.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        row("figure.roll",
                            "보기 편한 화면",
                            "손쉬운 사용에서 대비 증가·색상 없이 구별·투명도 줄이기를 켜면 계획표가 그에 맞춰 바뀝니다. 음성 제어로 단추를 이름으로 부를 수도 있습니다.")
                        row("stopwatch",
                            "계획 대비 실제를 무료로도",
                            "회고 추세에서 계획한 시간과 해낸 시간을 무료로 봅니다. 일마다 어긋난 결은 Pro에서 봅니다.")
                        row("ticket",
                            "코드 사용",
                            "프로모션 코드가 있으면 설정이나 Pro 화면의 '코드 사용'에서 넣습니다.")
                        row("map",
                            "앞으로 만들 기능",
                            "설정의 피드백 & 리뷰에서 다음에 만들 것을 보고, 바라는 기능을 보낼 수 있습니다.")
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsCloseButton {
                Divider()
                HStack {
                    Spacer()
                    Button("시작하기") { onClose() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 460, idealWidth: 500, minHeight: 440)
    }

    private func row(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 제목과 설명을 한 덩어리로 읽는다 — 따로 읽으면 무엇의 설명인지 놓친다.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 띄우기

extension View {
    /// 업데이트 뒤 처음 열 때 한 번 "새로 생긴 것"을 띄운다 (→ WhatsNewAudience).
    func whatsNewOnUpdate() -> some View { modifier(WhatsNewPresenter()) }
}

private struct WhatsNewPresenter: ViewModifier {
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task {
                let defaults = UserDefaults.standard
                switch WhatsNewAudience.resolve(launchCount: LeeoEngagement.shared.launchCount,
                                                lastSeenVersion: defaults.string(forKey: WhatsNewContent.lastSeenKey)) {
                case .newcomer:
                    defaults.set(WhatsNewContent.version, forKey: WhatsNewContent.lastSeenKey)
                case .needsWhatsNew:
                    // 창이 자리 잡은 뒤에 — 켜자마자 시트가 덮치면 무엇이 열렸는지 못 본다.
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    defaults.set(WhatsNewContent.version, forKey: WhatsNewContent.lastSeenKey)
                    isPresented = true
                case .upToDate:
                    break
                }
            }
            .sheet(isPresented: $isPresented) {
                WhatsNewView(onClose: { isPresented = false })
            }
    }
}
