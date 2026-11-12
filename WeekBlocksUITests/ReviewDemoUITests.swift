//
//  ReviewDemoUITests.swift
//  WeekBlocksUITests
//
//  **App Review 에 낼 화면 녹화의 손.** 심사가 "실기기에서 앱을 켜는 것부터 보통 흐름까지 찍어 보내라"
//  (Guideline 2.1 Information Needed) 고 할 때 쓴다. 녹화와 앱 실행은 `scripts/record-review-video.sh` 가
//  하고, 이 시험은 이미 떠 있는 앱에 붙어서 사람이 쓰듯 천천히 누른다. 답변문은 docs/APP_REVIEW_NOTES.md.
//
//  ⚠️ 혼자 돌지 않는다 — `TEST_RUNNER_REVIEW_DEMO=1` 일 때만 돈다 (스크립트가 붙인다).
//     시험이 직접 `launch()` 하면 이 맥OS 에서 창이 안 열려서, 앱은 스크립트가 `open` 으로 띄운다.
//  ⚠️ 앱은 `-uiTesting` 으로 뜬다 — 메모리 안 스토어라 사람의 iCloud·캘린더에 쓰지 않는다 (→ LaunchEnvironment).
//  ⚠️ 할 일 이름에 f·y 를 넣지 않는다. 이 맥의 입력기로 치면 그 글자가 빠진다.
//  ⚠️ 결제 단추는 누르지 않는다 — 샌드박스 로그인 창이 뜨면 화면에 남아 다음 클릭마다 60초씩 막고,
//     심사에는 '로그인이 있는 앱'으로 읽힌다. 요금제 화면까지만 보인다.
//

import XCTest

final class ReviewDemoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["REVIEW_DEMO"] == "1",
                          "scripts/record-review-video.sh 가 돌릴 때만")
        continueAfterFailure = true
        app = XCUIApplication(bundleIdentifier: "com.example.ScheduleDensityApp")
    }

    func testReviewWalkthrough() throws {
        print("DEMO-READY")   // 스크립트가 이 줄을 보고 앱을 띄운다
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline && !app.windows.firstMatch.exists { sleep(1) }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "앱 창이 안 떴다")
        pause(2)

        // 창을 화면 가득 — 영상에 다른 창이 섞이지 않게.
        if window.frame.width < 1500 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 12)).doubleClick()
            pause(3)
        }

        // 1. 처음 쓰는 사람의 안내 — 빼놓을 수 없는 시간부터 세운다.
        click(app.buttons["Let me help you set them up"])
        pause(2)
        click(prefixed("Sleep,"))
        click(prefixed("Meals,"))
        click(prefixed("Work · school,"))
        pause(1)
        app.typeKey(.return, modifierFlags: [])      // 3개 만들고 다음
        pause(3)
        app.typeKey(.return, modifierFlags: [])      // 다 봤습니다
        pause(3)

        // 2. 할 일을 적는다.
        click(app.buttons["New to-do"])
        type("Prepare the client presentation")
        type("Book the dentist")
        app.typeKey(.escape, modifierFlags: [])
        pause(2)

        // 3. 할 일을 요일 칸으로 끌어다 놓는다 → 계획 블록.
        let card = prefixed("Prepare the client presentation")
        let friday = app.buttons["Add a block on Friday"].firstMatch
        if card.waitForExistence(timeout: 5), friday.exists {
            card.click(forDuration: 0.8, thenDragTo: friday)
        }
        pause(3)

        // 4. 하루를 24시간 자로 본다.
        click(app.radioButtons["Timeline view"])
        pause(4)
        click(app.radioButtons["Block view"])
        pause(2)

        // 5. 지금 하는 일에 남은 시간.
        click(app.toolbars.buttons["Timer"])
        pause(4)
        app.typeKey("w", modifierFlags: .command)
        pause(2)

        // 6. 회고 — 이번 주, 그리고 추세(유료 칸의 문).
        click(app.toolbars.buttons["Review"])
        pause(3)
        click(app.radioButtons["Trends"])
        pause(3)

        // 7. 요금제 — 무료 · Plus · Pro 와 값, 구매 복원.
        //    결제 단추는 누르지 않는다: 샌드박스 로그인 창이 떠서 '로그인이 있는 앱'으로 읽히고, 메일 주소가 찍힌다.
        click(app.buttons["See Plus"])
        pause(7)
        click(app.buttons["Later"])
        pause(1)
        click(app.buttons["Done"])
        pause(2)

        // 8. 설정 — 아이폰과 오가기 등.
        click(app.toolbars.buttons["Settings"])
        pause(4)
        click(app.buttons["Done"])
        pause(3)
        print("DEMO-DONE")
    }

    // MARK: - 손

    private func pause(_ seconds: UInt32) { sleep(seconds) }

    private func prefixed(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func click(_ element: XCUIElement) {
        let element = element.firstMatch
        if element.waitForExistence(timeout: 5) { element.click() } else { print("DEMO-MISSING \(element)") }
        sleep(1)
    }

    /// 첫 글자 뒤에 잠깐 쉰다 — 입력을 시작한 직후 화면이 다시 그려진다.
    private func type(_ text: String) {
        app.typeText(String(text.prefix(1)))
        sleep(1)
        for c in text.dropFirst() { app.typeText(String(c)); usleep(45_000) }
        sleep(1)
        app.typeKey(.return, modifierFlags: [])
        sleep(1)
    }
}
