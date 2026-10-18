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

    /// 페이월에 서는 차례 — 연간이 먼저, 평생, 월간은 비교 기준이라 마지막.
    /// 차례가 바뀌면 처음 고른 상품(연간)과 맨 앞 카드가 어긋난다.
    func testPaywallOrder() {
        XCTAssertEqual(WeekBlocksSpec.proProductIDs,
                       [WeekBlocksSpec.proYearlyID, WeekBlocksSpec.proLifetimeID, WeekBlocksSpec.proMonthlyID])
        XCTAssertEqual(Set(WeekBlocksSpec.proProductIDs).count, 3)
    }

    /// 예전 '함께 쓰기' 상품을 산 사람도 Pro 다 — 권한 목록에서 빠지면 산 사람이 잠긴다.
    func testLegacyPurchaseStillUnlocksPro() {
        XCTAssertTrue(WeekBlocksSpec.proEntitlementIDs.contains(WeekBlocksSpec.legacySyncProductID))
        XCTAssertEqual(WeekBlocksSpec.proLifetimeID, WeekBlocksSpec.legacySyncProductID)
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
