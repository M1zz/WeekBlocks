//
//  SunsetNotice.swift
//  WeekBlocks (무지개 공방)
//
//  **이 맥 앱(com.devkoan.ScheduleDensityApp)은 곧 App Store 에서 내려간다.**
//
//  켤 때마다 맨 먼저 알린다 — 한 번만 띄우면 못 본 사람이 생긴다.
//  돈을 낸 사람이 연락할 곳을 함께 적는다. 닫으면 평소대로 쓸 수 있다.
//

import SwiftUI

enum SunsetNotice {
    static let contactEmail = "leeo@kakao.com"
}

private struct SunsetNoticeModifier: ViewModifier {
    @State private var isPresented = true

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            SunsetNoticeView { isPresented = false }
        }
    }
}

extension View {
    /// 켤 때마다 "곧 내려가요" 안내를 맨 먼저 띄운다.
    func sunsetNoticeOnLaunch() -> some View {
        modifier(SunsetNoticeModifier())
    }
}

struct SunsetNoticeView: View {
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)

            Text("이 앱은 곧 App Store 에서 삭제됩니다")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("그동안 이 앱을 써 주셔서 감사합니다.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("유료로 결제하신 분은 아래 메일로 연락해 주세요.")
                .multilineTextAlignment(.center)

            Text(verbatim: SunsetNotice.contactEmail)
                .font(.title3.monospaced())
                .textSelection(.enabled)

            HStack(spacing: 12) {
                Button("확인", action: onClose)
                    .keyboardShortcut(.cancelAction)
                Button("메일 보내기") {
                    if let url = URL(string: "mailto:\(SunsetNotice.contactEmail)") { openURL(url) }
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.top, 4)
        }
        .padding(32)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
