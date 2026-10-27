//
//  WeekBlocksTests.swift
//  WeekBlocksTests
//
//  핵심 로직의 단위 시험. 앱을 숙주로 띄우지만, 숙주는 창도 디스크 스토어도 세우지 않는다
//  (→ LaunchEnvironment.isUnitTestHost). 여기서는 순수 함수와 계약만 본다.
//

import XCTest
import LeeoKit
@testable import WeekBlocks

final class WeekBlocksSpecTests: XCTestCase {

    /// 출시하면 안 되는 상태(파는데 페이월로 갈 길이 없음, https 아닌 정책 주소, 분석 싱크 없음 …)를 막는다.
    func testSpecIsReleasable() {
        let issues = LeeoPreflight.audit(WeekBlocksSpec.self)
        XCTAssertTrue(issues.isReleasable, issues.errors.map { "[\($0.code)] \($0.message)" }.joined(separator: "\n"))
    }

    /// 불러올 상품의 차례: Plus 연 → Plus 평생 → Pro 연 → Pro 평생, 그 뒤에 올리기 · 졸업.
    /// 판매를 멈춘 월 구독은 목록에 없다.
    func testPaywallOrder() {
        XCTAssertEqual(WeekBlocksSpec.saleProductIDs,
                       [WeekBlocksSpec.plusYearlyID, WeekBlocksSpec.plusLifetimeID,
                        WeekBlocksSpec.proYearlyID, WeekBlocksSpec.proLifetimeID,
                        WeekBlocksSpec.proUpgradeID, WeekBlocksSpec.proGraduateID])
        XCTAssertEqual(Set(WeekBlocksSpec.saleProductIDs).count, 6)
        XCTAssertFalse(WeekBlocksSpec.saleProductIDs.contains(WeekBlocksSpec.proMonthlyID))
    }

    /// 예전 '함께 쓰기' 상품과 판매를 멈춘 월 구독을 가진 사람도 Pro 다. 권한 목록에서 빠지면 산 사람이 잠긴다.
    func testLegacyPurchaseStillUnlocksPro() {
        XCTAssertTrue(WeekBlocksSpec.proEntitlementIDs.contains(WeekBlocksSpec.legacySyncProductID))
        XCTAssertEqual(WeekBlocksSpec.proLifetimeID, WeekBlocksSpec.legacySyncProductID)
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.legacySyncProductID]), .pro)
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.proMonthlyID]), .pro)
    }

    /// 상품마다 여는 칸. 연 구독은 같은 칸의 평생과 같다.
    func testEachProductOpensItsTier() {
        XCTAssertEqual(WeekBlocksSpec.tier(owned: []), .free)
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.plusYearlyID]), .plus)
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.plusLifetimeID]), .plus)
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.proYearlyID]), .pro)
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.proLifetimeID]), .pro)
        // 졸업 상품은 Pro 평생이다.
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.proGraduateID]), .pro)
        // 상관없는 상품(패스 · 모르는 것)은 아무것도 열지 않는다.
        XCTAssertEqual(WeekBlocksSpec.tier(owned: ["com.devkoan.ScheduleDensityApp.forever"]), .free)
    }

    /// Plus 평생에서 올리기를 사면 Pro, Plus 와 Pro 를 함께 가지면 높은 쪽.
    func testUpgradeAndMixedOwnership() {
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.plusLifetimeID, WeekBlocksSpec.proUpgradeID]), .pro)
        XCTAssertEqual(WeekBlocksSpec.tier(owned: [WeekBlocksSpec.plusLifetimeID, WeekBlocksSpec.proYearlyID]), .pro)
        XCTAssertTrue(WeekBlocksSpec.proLifetimeIDs.contains(WeekBlocksSpec.proUpgradeID))
        XCTAssertTrue(WeekBlocksSpec.proLifetimeIDs.contains(WeekBlocksSpec.proGraduateID))
    }

    /// 졸업 제안은 자동 갱신 구독에게만. 평생 상품은 구독 목록에 없다.
    func testSubscriptionIDs() {
        XCTAssertEqual(WeekBlocksSpec.subscriptionIDs,
                       [WeekBlocksSpec.plusYearlyID, WeekBlocksSpec.proYearlyID, WeekBlocksSpec.proMonthlyID])
    }

    /// 언제나 평생 패스는 가장 높은 칸(Pro)을 열고, 아이폰 표는 그 등급만큼 연다.
    func testPassAndCrossPlatformResolve() {
        XCTAssertEqual(MacTier.resolve(owned: [], crossPlatform: nil, foreverPass: true), .pro)
        XCTAssertEqual(MacTier.resolve(owned: [WeekBlocksSpec.plusYearlyID], crossPlatform: nil, foreverPass: true), .pro)
        XCTAssertEqual(MacTier.resolve(owned: [], crossPlatform: .plus, foreverPass: false), .plus)
        XCTAssertEqual(MacTier.resolve(owned: [], crossPlatform: .pro, foreverPass: false), .pro)
        XCTAssertEqual(MacTier.resolve(owned: [WeekBlocksSpec.plusLifetimeID], crossPlatform: .pro, foreverPass: false), .pro)
        XCTAssertEqual(MacTier.resolve(owned: [WeekBlocksSpec.proYearlyID], crossPlatform: .plus, foreverPass: false), .pro)
        XCTAssertEqual(MacTier.resolve(owned: [], crossPlatform: nil, foreverPass: false), .free)
    }

    /// 패스 상품은 앱의 권한 목록에 넣지 않는다. `LeeoForeverPass` 가 따로 판정한다.
    func testPassProductsAreNotAppEntitlements() {
        let pass = Set(LeeoForeverPassRule.productIDs(bundleID: "com.devkoan.ScheduleDensityApp"))
        XCTAssertTrue(pass.isDisjoint(with: WeekBlocksSpec.proEntitlementIDs))
        XCTAssertTrue(pass.isDisjoint(with: WeekBlocksSpec.plusEntitlementIDs))
        XCTAssertTrue(pass.isDisjoint(with: Set(WeekBlocksSpec.saleProductIDs)))
        XCTAssertTrue(LeeoForeverPassRule.family.contains("com.devkoan.ScheduleDensityApp"))
    }

    /// 원격 스위치 이름은 CloudKit 대시보드의 필드 이름이다. 바꾸면 이미 꺼 둔 스위치가 조용히 켜진다.
    func testRemoteFlagNamesAreStable() {
        XCTAssertEqual(WeekBlocksFlag.allCases.map(\.rawValue),
                       ["calendarExport", "calendarAutoImport", "scheduleSharing"])
    }

    /// 짝인 아이폰 앱이 함께 쓰는 앱 목록에서 맨 앞에 서야 한다.
    func testFamilyIdentity() {
        XCTAssertEqual(WeekBlocksSpec.familyID, "rainbow-mac")
        XCTAssertEqual(WeekBlocksSpec.familyFeatured.first, "rainbow-ios")
    }
}

final class WhatsNewAudienceTests: XCTestCase {

    func testFirstLaunchIsNewcomer() {
        XCTAssertEqual(WhatsNewAudience.resolve(launchCount: 1, lastSeenVersion: nil), .newcomer)
        XCTAssertEqual(WhatsNewAudience.resolve(launchCount: 0, lastSeenVersion: nil), .newcomer)
    }

    func testReturningUserSeesCurrentVersionOnce() {
        XCTAssertEqual(WhatsNewAudience.resolve(launchCount: 12, lastSeenVersion: nil, current: "1.1.13"),
                       .needsWhatsNew)
        XCTAssertEqual(WhatsNewAudience.resolve(launchCount: 12, lastSeenVersion: "1.1.12", current: "1.1.13"),
                       .needsWhatsNew)
        XCTAssertEqual(WhatsNewAudience.resolve(launchCount: 13, lastSeenVersion: "1.1.13", current: "1.1.13"),
                       .upToDate)
    }
}

final class ConcretenessCheckerTests: XCTestCase {

    func testConcreteBlockPasses() {
        let issues = ConcretenessChecker.validate(title: "Combine 학습",
                                                  successCriteria: "예제 3개를 직접 짜서 돌려 본다",
                                                  deliverable: "예제 저장소")
        XCTAssertTrue(issues.isEmpty, issues.map(\.message).joined(separator: "\n"))
    }

    func testEmptyFieldsAreReported() {
        XCTAssertEqual(ConcretenessChecker.validate(title: "", successCriteria: "", deliverable: "").count, 3)
    }

    func testVagueKoreanCriteriaFail() {
        let issues = ConcretenessChecker.validate(title: "영어 공부",
                                                  successCriteria: "열심히 단어를 외워 본다",
                                                  deliverable: "단어장 정리")
        XCTAssertEqual(issues.count, 1)
    }

    /// "잘"은 홀로 설 때만 모호하다 — "잘라"·"잘못" 같은 말까지 막으면 멀쩡한 기준이 떨어진다.
    func testStandaloneJalOnly() {
        XCTAssertEqual(ConcretenessChecker.validate(title: "원고 다듬기",
                                                    successCriteria: "원고를 잘 써서 넘긴다 오늘",
                                                    deliverable: "원고 파일").count, 1)
        XCTAssertTrue(ConcretenessChecker.validate(title: "원고 다듬기",
                                                   successCriteria: "잘못 쓴 문장 10개를 고친다",
                                                   deliverable: "원고 파일").isEmpty)
    }

    /// 영어 문장은 낱말 경계로 본다 — "some"이 "something"에 걸리면 안 된다.
    func testEnglishWordBoundaries() {
        XCTAssertTrue(ConcretenessChecker.validate(title: "Write report",
                                                   successCriteria: "Draft something with 3 sections",
                                                   deliverable: "report.pages").isEmpty)
        XCTAssertEqual(ConcretenessChecker.validate(title: "Write report",
                                                    successCriteria: "Work hard on the draft today",
                                                    deliverable: "report.pages").count, 1)
    }
}

final class FormattingTests: XCTestCase {

    /// 요일 칸의 짧은 길이 — 딱 떨어지면 소수점을 뗀다.
    func testShortHours() {
        XCTAssertEqual(shortHours(2), "2h")
        XCTAssertEqual(shortHours(1.5), "1.5h")
        XCTAssertEqual(shortHours(0.25), "0.3h")
    }
}

/// 두 무지개 앱이 함께 쓰는 표(→ ProMark.swift). 필드 이름 · 값은 아이폰 앱과 글자 하나까지 같아야 한다.
final class ProMarkTierTests: XCTestCase {

    func testTierRawValuesAreTheContract() {
        XCTAssertEqual(ProMarkTier.plus.rawValue, "plus")
        XCTAssertEqual(ProMarkTier.pro.rawValue, "pro")
        XCTAssertLessThan(ProMarkTier.plus, ProMarkTier.pro)
    }

    /// 등급이 없는 예전 기록은 Pro 로 읽는다.
    func testMissingTierReadsAsPro() {
        let old = ProMark(platform: .ios, productID: "x", validUntil: nil)
        old.tier = nil
        XCTAssertEqual(old.markTier, .pro)
        let plus = ProMark(platform: .ios, productID: "x", validUntil: nil, tier: .plus)
        XCTAssertEqual(plus.tier, "plus")
        XCTAssertEqual(plus.markTier, .plus)
    }

    /// 상대 표 중 살아 있는 가장 높은 등급. 내 표와 끝난 표는 치지 않는다.
    func testBestOtherTier() {
        let now = Date()
        let plus = ProMark(platform: .ios, productID: "a", validUntil: nil, tier: .plus)
        let expiredPro = ProMark(platform: .ios, productID: "b", validUntil: now.addingTimeInterval(-60), tier: .pro)
        let mine = ProMark(platform: .mac, productID: "c", validUntil: nil, tier: .pro)
        XCTAssertEqual(ProMarkStore.bestOtherTier([plus, expiredPro, mine], now: now), .plus)

        let livePro = ProMark(platform: .ios, productID: "d", validUntil: now.addingTimeInterval(3600), tier: .pro)
        XCTAssertEqual(ProMarkStore.bestOtherTier([plus, livePro], now: now), .pro)
        XCTAssertNil(ProMarkStore.bestOtherTier([mine, expiredPro], now: now))
    }

    func testMacTierMapsToMark() {
        XCTAssertNil(MacTier.free.markTier)
        XCTAssertEqual(MacTier.plus.markTier, .plus)
        XCTAssertEqual(MacTier.pro.markTier, .pro)
        XCTAssertEqual(MacTier(ProMarkTier.plus), .plus)
        XCTAssertEqual(MacTier(nil), .free)
    }
}
