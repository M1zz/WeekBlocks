//
//  WeekBlocksUITests.swift
//  WeekBlocksUITests
//
//  앱을 실제로 띄워 한 바퀴 돈다 — 켜기 → (첫 안내/새 소식 닫기) → 주 넘기기 → 회고 열고 닫기 →
//  설정 열고 닫기. 그리고 손쉬운 사용 자동 점검.
//
//  ⚠️ `-uiTesting` 으로 띄운다. 그러면 앱은 **메모리 안 스토어로만** 돌고, 사람의 iCloud·캘린더·
//     위젯·공유 상자에 쓰지 않는다 (→ LaunchEnvironment.swift). 통계도 끈다(`-usage.optOut YES`).
//  ⚠️ 화면 말은 한국어로 고정한다 — 단추를 이름으로 찾는다.
//

import XCTest

final class WeekBlocksUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uiTesting", "-usage.optOut", "YES",
                                "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR"]
        app.launch()
        dismissLaunchSheets()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// 켜자마자 뜰 수 있는 시트 둘 — 처음 온 사람의 안내, 업데이트한 사람의 새 소식.
    private func dismissLaunchSheets() {
        let skip = app.buttons["건너뛰기"]
        let start = app.buttons["시작하기"]
        // 둘 다 몇 초 뒤에 뜬다(창이 자리 잡은 다음). 넉넉히 기다린다.
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            if skip.exists { skip.click(); break }
            if start.exists { start.click(); break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        }
    }

    func testCoreLoop() throws {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 10))

        // 주 넘기기 — 화살표 단추에 단 이름(지난주·다음 주)으로 찾는다.
        let next = app.buttons["다음 주"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.click()
        app.buttons["지난주"].click()

        // 회고 — 툴바에서 열고 닫는다.
        let reflection = app.toolbars.buttons["회고"]
        XCTAssertTrue(reflection.waitForExistence(timeout: 5))
        reflection.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])

        // 설정 — 열고, 주간 계획 묶음이 서 있는지 보고, 완료로 닫는다.
        let settings = app.toolbars.buttons["설정"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.click()
        let done = app.buttons["완료"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["주간 계획"].exists)
        done.click()
        XCTAssertFalse(done.waitForExistence(timeout: 2))
    }

    func testAccessibilityAudit() throws {
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }
}
