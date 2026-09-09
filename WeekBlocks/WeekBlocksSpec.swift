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

    /// **파는 것은 '함께 쓰기' 하나다.** 한 번 사면 끝인 비소모성 상품 하나뿐이고,
    /// 구독이 아니다. 이 한 줄이 "페이월이 필요한가"의 답이고, 여기서
    /// `paywall`(상품·약관·개인정보 링크)과 `gate`(무엇이 잠기는가)가 따라 나온다.
    ///
    /// ⚠️ 잠기는 것은 **적기가 아니라 건너가기**다. 적는 것은 이 앱의 본체라 잠그지
    ///    않는다 — 그래서 `freeLimits`(몇 개까지 무료)가 비어 있고 `proOnly` 하나만 있다.
    ///    (→ TodoAccess.swift · MacEntitlement.swift)
    ///
    /// ⚠️ **여기 선언했다고 팔기 시작하는 게 아니다.** 실제로 잠글지는
    ///    `MacEntitlement.sellsAccess`가 정한다. 상품이 App Store Connect에 서기 전에
    ///    잠그면 아무도 못 사는 채로 쓰던 사람의 것만 닫힌다.
    static let monetization = LeeoMonetization.freemium(
        LeeoPurchaseConfig(
            productIDs: [syncProductID],
            gate: LeeoGatePolicy(proOnly: [Gate.sync])
        )
    )

    /// App Store Connect의 비소모성 상품 ID.
    /// ⚠️ 콘솔에 만든 것·`WeekBlocks.storekit`에 적은 것과 **글자 하나까지 같아야 한다.**
    static let syncProductID = "com.devkoan.ScheduleDensityApp.sync"

    /// 게이트 열쇠말. 문자열을 여기저기 흩어 적으면 오타 하나로 조용히 안 잠긴다.
    enum Gate {
        /// 여기서 적은 것이 아이폰으로 건너가는가.
        static let sync = "sync"
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
