//
//  OfferCode.swift
//  WeekBlocks (무지개 공방)
//
//  **프로모션 코드 넣기** — App Store Connect 에서 만든 오퍼 코드(구독 할인·무료 기간)를
//  앱 안에서 바로 쓴다. 코드를 받은 사람이 App Store 앱을 찾아 들어가지 않아도 된다.
//
//  새 상품이 필요 없다 — 이미 파는 Pro 구독(연간·월간)과 평생 이용권에 코드를 붙여 나눠 준다.
//  코드를 쓰면 영수증이 바뀌고, `PurchaseManager.refresh()` 가 그것을 읽어 Pro 를 연다.
//
//  ⚠️ macOS 15 부터 있는 시트다. 그 아래 맥에서는 단추를 세우지 않는다 — 눌러도 아무 일이
//     없는 단추는 고장으로 읽힌다.
//

import SwiftUI
import StoreKit

enum OfferCode {
    /// 이 맥에서 코드 넣는 시트를 띄울 수 있는가.
    static var isAvailable: Bool {
        if #available(macOS 15.0, *) { return true }
        return false
    }
}

extension View {
    /// `isPresented` 가 켜지면 App Store 의 코드 넣기 시트를 띄우고, 닫히면 영수증을 다시 읽는다.
    func offerCodeSheet(isPresented: Binding<Bool>) -> some View {
        modifier(OfferCodeSheet(isPresented: isPresented))
    }
}

private struct OfferCodeSheet: ViewModifier {
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.offerCodeRedemption(isPresented: $isPresented) { result in
                if case .failure(let error) = result {
                    AppLog.launch.error("코드 넣기 실패: \(String(describing: error), privacy: .public)")
                }
                // 성공이든 취소든 영수증을 다시 읽는다 — 코드를 쓴 뒤 창을 닫아도 Pro 가 바로 열리게.
                Task { await PurchaseManager.shared.refresh() }
            }
        } else {
            content
        }
    }
}
