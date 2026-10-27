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
    /// 사람에게 보여 주는 이름 — 영어 환경에서는 "Rainbow Craft"이 된다.
    static var appName: String { String(localized: "무지개 공방", comment: "앱 이름") }
    static let developerEmail = "leeo@kakao.com"

    /// 함께 쓰는 앱 목록(`LeeoFamilyCatalog`)에서 이 앱의 자리. 설정 ▸ 함께 쓰면 좋은 앱에서
    /// 자기 자신을 빼고, 짝인 아이폰 앱 '욕망의 무지개'를 맨 앞에 세운다.
    static let familyID: String? = "rainbow-mac"
    static let familyFeatured = ["rainbow-ios"]

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

    /// **파는 것은 Plus · Pro 두 칸이다** (2026-10 개편). 칸마다 연 구독과 평생을 나란히 둔다.
    ///
    /// 선은 이렇게 긋는다: **이번 주를 사는 데 필요한 것은 무료, 지난 주들이 쌓여야 보이는 것은 Plus,
    /// 남에게 내보내는 것과 아이폰까지 함께 여는 것은 Pro.**
    ///  · 무료: 주간·일간 계획, 루틴, 할 일, 이번 주 회고(글로 복사 포함), 타이머, 캘린더 가져오기, 아이폰과 오가기
    ///  · Plus: 회고 추세 8주, 요일별·시간대별·계획 대비 실제 카드, 다른 주 계획 가져오기
    ///  · Pro: Plus 전부 + 내 일정 공유 링크 + 아이폰 '욕망의 무지개' Pro
    ///
    /// ⚠️ 예전에 팔려던 것은 '아이폰으로 건너가기'(`legacySyncProductID`)였다. 그 ID 는 지금 Pro 평생이다.
    /// ⚠️ 판매를 멈춘 월 구독(`proMonthlyID`)도 권한 목록에는 남긴다. 구독자는 끝날 때까지 Pro 다.
    /// ⚠️ **여기 선언했다고 팔기 시작하는 게 아니다.** 실제로 파는지는 `MacEntitlement.sellsPro`가 정한다.
    static let monetization = LeeoMonetization.freemiumSubscription(
        LeeoSubscriptionConfig(
            productIDs: saleProductIDs,
            // 자체 약관이 없으므로 애플 표준 사용권 계약(EULA)을 건다.
            // App Store Connect의 '사용권 계약'을 표준으로 두는 것과 짝이다.
            termsURL: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!,
            // LeeoStore 의 hasPro 는 '무엇이든 유료 칸을 가졌는가'다. 어느 칸인지는 `tier(owned:)` 가 가른다.
            entitlementIDs: plusEntitlementIDs.union(proEntitlementIDs),
            gate: LeeoGatePolicy(
                // 무료로도 **써 보고 알 만큼**은 연다: 지난 2주 추세는 그냥 보인다.
                freeLimits: [Gate.trendWeeks: ReflectionTrends.freeWeekCount],
                proOnly: [Gate.trends, Gate.weekCopy, Gate.share])
        )
    )

    // MARK: - 상품 ID

    /// App Store Connect의 상품 ID.
    /// ⚠️ 콘솔에 만든 것·`WeekBlocks.storekit`에 적은 것과 **글자 하나까지 같아야 한다.**
    /// Plus 연 · Pro 연(· 판매를 멈춘 Pro 월)은 같은 구독 그룹에 있어야 서로 갈아탈 수 있다.
    static let plusYearlyID = "com.devkoan.ScheduleDensityApp.plus.yearly"
    static let plusLifetimeID = "com.devkoan.ScheduleDensityApp.plus"
    static let proYearlyID = "com.devkoan.ScheduleDensityApp.pro.yearly"
    /// **Pro 평생은 예전 '함께 쓰기' 상품을 이어 쓴다** (2026-10-13). ID에 'sync'가 남지만 사용자에게는 안 보인다.
    static let proLifetimeID = legacySyncProductID
    /// Plus 평생을 산 사람이 Pro 평생으로 올리는 값.
    static let proUpgradeID = "com.devkoan.ScheduleDensityApp.pro.upgrade"
    /// 구독 졸업: 구독 중인 사람에게만 보이는 Pro 평생.
    static let proGraduateID = "com.devkoan.ScheduleDensityApp.pro.graduate"
    /// 판매 중지(2026-10). 구독자는 끝날 때까지 Pro 다.
    static let proMonthlyID = "com.devkoan.ScheduleDensityApp.pro.monthly"

    /// 예전 '함께 쓰기'(비소모성). 지금은 Pro 평생 이용권이다 (→ proLifetimeID).
    static let legacySyncProductID = "com.devkoan.ScheduleDensityApp.sync"

    /// 불러올 상품. 페이월의 칸 차례(Plus 연 → Plus 평생 → Pro 연 → Pro 평생)에 올리기 · 졸업이 붙는다.
    static let saleProductIDs = [plusYearlyID, plusLifetimeID, proYearlyID, proLifetimeID,
                                 proUpgradeID, proGraduateID]

    /// Plus 를 여는 상품.
    static let plusEntitlementIDs: Set<String> = [plusYearlyID, plusLifetimeID]
    /// 이 중 하나라도 있으면 Pro 다. 판매를 멈춘 것도 빼지 않는다.
    static let proEntitlementIDs: Set<String> = [proYearlyID, proLifetimeID, proMonthlyID,
                                                 proUpgradeID, proGraduateID]
    /// 자동 갱신 구독(졸업 제안의 대상).
    static let subscriptionIDs: Set<String> = [plusYearlyID, proYearlyID, proMonthlyID]
    /// 끝이 없는 Pro. 이걸 가진 사람에게는 졸업을 권하지 않고, 패스는 올리기 값으로 판다.
    static let proLifetimeIDs: Set<String> = [proLifetimeID, proUpgradeID, proGraduateID]

    /// **가진 상품이 어느 칸을 여는가.** 연 구독은 같은 칸의 평생과 같다.
    static func tier(owned: Set<String>) -> MacTier {
        if !owned.isDisjoint(with: proEntitlementIDs) { return .pro }
        if !owned.isDisjoint(with: plusEntitlementIDs) { return .plus }
        return .free
    }

    /// 게이트 열쇠말. 문자열을 여기저기 흩어 적으면 오타 하나로 조용히 안 잠긴다.
    enum Gate {
        /// 지난 주들의 회고 추세.
        static let trends = "reflectionTrends"
        /// 다른 주의 계획을 이번 주에 깔기.
        static let weekCopy = "weekCopy"
        /// 추세를 몇 주까지 거슬러 보는가 (무료는 2주).
        static let trendWeeks = "trendWeeks"
        /// 내 일정을 남에게 보기 전용 링크로 공유하기 (Pro). 회고 복사는 2026-10 부터 무료라 열쇠가 없다.
        static let share = "share"
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
                      .emptyStates, .conversionFunnel,
                      .accessibility, .killSwitch,
                      .performanceMonitoring, .structuredLogging,
                      .automatedTests, .staticAnalysis, .continuousIntegration],
        notApplicable: [
            .accountDeletion: "계정이 없다 — 로그인도 회원가입도 하지 않는다",
            .biometricLock: "잠글 비밀이 없다. 할 일과 주간 계획뿐이다",
            .widgets: "맥 위젯은 아직. 아이폰 쪽(욕망의 무지개)이 먼저다",
            .abTesting: "한 사람이 만드는 앱에 두 갈래를 굴릴 손이 없다",
        ]
    )
}
