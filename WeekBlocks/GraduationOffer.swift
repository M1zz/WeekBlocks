//
//  GraduationOffer.swift
//  WeekBlocks
//
//  **구독 졸업.** 구독 중인 사람에게 6개월째와 갱신 7일 전에 한 번씩 평생가를 보인다
//  (→ LeeoGraduation, PurchaseManager.takeGraduationOffer). 설정의 '평생으로 바꾸기'는 늘 같은 시트를 연다.
//

import SwiftUI
import LeeoKit

extension View {
    /// 앱이 열릴 때 영수증을 읽은 뒤, 졸업할 때면 시트를 한 번 띄운다.
    func graduationOfferOnLaunch() -> some View { modifier(GraduationOfferOnLaunch()) }
}

private struct GraduationOfferOnLaunch: ViewModifier {
    @State private var purchases = PurchaseManager.shared
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            // 켤 때 읽는 영수증(→ WeekBlocksApp)이 subscription 을 채운 뒤에 판정한다.
            .onChange(of: purchases.subscription) { _, _ in
                if !showing, purchases.takeGraduationOffer() { showing = true }
            }
            .sheet(isPresented: $showing) {
                LeeoGraduationOfferView(graduate: purchases.graduateProduct) {
                    await purchases.refresh()
                }
                .frame(minWidth: 420, minHeight: 420)
            }
    }
}
