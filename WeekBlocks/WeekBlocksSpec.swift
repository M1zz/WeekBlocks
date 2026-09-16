//
//  WeekBlocksSpec.swift
//  WeekBlocks (무지개 공방)
//
//  LeeoKit 계약(LeeoAppSpec) 준수 — 이 앱의 공통 기능 설정값 단일 소스.
//  피드백 시스템 구현은 전부 LeeoKit에 있고, 앱은 이 설정만 제공한다.
//

import Foundation
import LeeoKit

enum WeekBlocksSpec: LeeoAppSpec {
    /// 사람에게 보여 주는 이름 — 영어 환경에서는 "Rainbow Workshop"이 된다.
    static var appName: String { String(localized: "무지개 공방", comment: "앱 이름") }
    static let developerEmail = "leeo@kakao.com"

    /// WeekBlocks.entitlements에 iCloud.com.Ysoup.FeedbackHub 컨테이너가 있어야 한다.
    /// 공용 피드백 허브(FeedbackHub)로 수집 — appIdentifier로 앱을 구분한다.
    /// (앱 데이터는 iCloud.com.devkoan.ScheduleDensity 컨테이너에서 계속 동기화된다.)
    static let feedback = LeeoFeedbackConfig(
        containerIdentifier: "iCloud.com.Ysoup.FeedbackHub",
        appIdentifier: "com.devkoan.ScheduleDensityApp"
    )

    /// LeeoKit 3부터는 기본값이 없다 — 모든 앱이 한 번은 선언해야 하는 의무 링크.
    ///
    /// ⚠️ 주소도 번역한다. 영어로 쓰는 사람에게 한국어 방침을 열어 주면 읽을 수가 없다.
    ///    영어 자리는 docs/privacy-en.html · docs/support-en.html 이다.
    ///    스토어(App Store Connect)에 넣는 주소도 같은 것을 쓴다 (→ docs/STORE_NOTES_*.txt).
    static var legal: LeeoLegalConfig {
        LeeoLegalConfig(
            privacyURL: URL(string: String(localized: "https://m1zz.github.io/WeekBlocks/privacy.html",
                                           comment: "개인정보 처리방침 주소"))!,
            supportURL: URL(string: String(localized: "https://m1zz.github.io/WeekBlocks/",
                                           comment: "지원 페이지 주소"))!,
            marketingURL: URL(string: String(localized: "https://m1zz.github.io/WeekBlocks/",
                                             comment: "지원 페이지 주소"))!
        )
    }

    /// **파는 것은 「무지개 공방 Pro」다.** 연간·월간 구독과 평생 이용권, 셋 중 무엇을 사도 같은 Pro다.
    ///
    /// 선은 이렇게 긋는다: **이번 주를 사는 데 필요한 것은 무료, 지난 주들이 쌓여야 보이는 것은 Pro.**
    /// 주간·일간 계획, 루틴, 할 일, 이번 주 회고, 타이머, 아이폰과 오가기까지 전부 무료다.
    /// Pro는 회고 추세(→ ReflectionTrendsView)와 다른 주 계획 가져오기(→ WeekCopyView)를 연다.
    ///
    /// ⚠️ 예전에 팔려던 것은 '아이폰으로 건너가기'(`legacySyncProductID`)였다. 원래 되던 것을
    ///    막는 셈이라 뺏는 것으로 읽혀서 **동기화는 무료로 되돌렸다** (→ TodoAccess.swift).
    ///    그 상품을 산 사람이 있다면 Pro로 인정한다 — `entitlementIDs`에 함께 넣어 둔다.
    ///
    /// ⚠️ **여기 선언했다고 팔기 시작하는 게 아니다.** 실제로 파는지는
    ///    `MacEntitlement.sellsPro`가 정한다. 상품이 App Store Connect에 서기 전에 켜면
    ///    아무도 못 사는 채로 Pro 기능만 잠긴다.
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: proProductIDs,
            // 자체 약관이 없으므로 애플 표준 사용권 계약(EULA)을 건다.
            // App Store Connect의 '사용권 계약'을 표준으로 두는 것과 짝이다.
            termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
            entitlementIDs: Set(proProductIDs + [legacySyncProductID]),
            gate: LeeoGatePolicy(proOnly: [Gate.trends, Gate.weekCopy])
        )
    )

    /// App Store Connect의 상품 ID.
    /// ⚠️ 콘솔에 만든 것·`WeekBlocks.storekit`에 적은 것과 **글자 하나까지 같아야 한다.**
    /// 연간·월간은 같은 구독 그룹(「무지개 공방 Pro」)에 넣어야 서로 갈아탈 수 있다.
    static let proYearlyID = "com.devkoan.ScheduleDensityApp.pro.yearly"
    static let proLifetimeID = "com.devkoan.ScheduleDensityApp.pro.lifetime"
    static let proMonthlyID = "com.devkoan.ScheduleDensityApp.pro.monthly"

    /// 페이월에 서는 차례 그대로 — 연간이 먼저, 평생, 월간은 비교 기준이라 마지막.
    static let proProductIDs = [proYearlyID, proLifetimeID, proMonthlyID]

    /// 예전 '함께 쓰기'(비소모성). 더는 팔지 않지만 산 사람은 Pro다.
    static let legacySyncProductID = "com.devkoan.ScheduleDensityApp.sync"

    /// 게이트 열쇠말. 문자열을 여기저기 흩어 적으면 오타 하나로 조용히 안 잠긴다.
    enum Gate {
        /// 지난 주들의 회고 추세.
        static let trends = "reflectionTrends"
        /// 다른 주의 계획을 이번 주에 깔기.
        static let weekCopy = "weekCopy"
    }

    /// **익명 사용 통계를 피드백 허브로 보낸다** (→ Telemetry.swift).
    ///
    /// 이 줄이 있어야 LeeoKit 안에서 저절로 나는 이벤트(페이월 노출·구매 시도·성공·실패·
    /// 복원·피드백 제출)가 어딘가에 쌓인다. 선언하지 않으면 기본이 no-op이라
    /// "페이월은 봤는데 아무도 안 샀다"와 "페이월을 아무도 못 봤다"를 구분할 수 없다.
    ///
    /// ⚠️ 사람이 끄면 여기부터 막힌다 — `WeekBlocksAnalytics`가 스위치를 본다.
    static let analytics: any LeeoAnalytics = WeekBlocksAnalytics()

    /// 완성도 체크리스트 신고. 적어 두지 않으면 전부 '아직 안 봤음'으로 집계된다.
    /// (피드백·리뷰 요청·결제 안정성·정책 링크처럼 LeeoKit이 대는 항목은 여기 안 적는다.)
    static let capabilities = LeeoCapabilities(
        implemented: [.cloudSync, .backupExport, .structuredStorage, .schemaMigration,
                      .analytics, .feedbackChannel,
                      .privacyManifest, .minimalPermissions,
                      .localization, .darkMode, .onboarding, .microInteractions,
                      .emptyStates, .conversionFunnel],
        notApplicable: [
            .accountDeletion: "계정이 없다 — 로그인도 회원가입도 하지 않는다",
            .biometricLock: "잠글 비밀이 없다. 할 일과 주간 계획뿐이다",
            .widgets: "맥 위젯은 아직. 아이폰 쪽(욕망의 무지개)이 먼저다",
            .abTesting: "한 사람이 만드는 앱에 두 갈래를 굴릴 손이 없다",
        ]
    )
}
