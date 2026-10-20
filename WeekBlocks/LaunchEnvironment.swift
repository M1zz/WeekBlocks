//
//  LaunchEnvironment.swift
//  WeekBlocks (무지개 공방)
//
//  **시험이 띄운 실행인가.** 시험은 개발자의 맥에서 돈다 — 같은 번들 ID 라서 그 맥에 깔린
//  진짜 무지개 공방과 **같은 샌드박스·같은 iCloud** 를 본다. 아무 표시 없이 시험이 앱을 띄우면
//  시험이 만든 빈 스토어가 사람의 캘린더('무지개 공방' 캘린더를 비운다), 공유 중인 일정,
//  공유 메뉴로 받아 둔 할 일 상자, 위젯을 덮어쓴다.
//
//  그래서 시험이 띄운 실행은 **메모리 안 스토어로만** 돌고, 앱 밖으로 쓰는 길을 모두 닫는다.
//
//  - 단위 시험의 숙주(`XCTestConfigurationFilePath`): 창도 그리지 않는다. 시험은 순수 로직만 본다.
//  - UI 시험(`-uiTesting` 인자): 화면은 평소대로, 데이터는 메모리 안에서만.
//    통계는 UI 시험이 `-usage.optOut YES` 로 함께 끈다 (→ Telemetry.optOutKey).
//

import Foundation

enum LaunchEnvironment {
    /// 단위 시험 번들이 이 앱을 숙주로 띄웠다.
    static let isUnitTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// UI 시험이 띄웠다 (`XCUIApplication.launchArguments` 에 `-uiTesting`).
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// 시험이 띄운 실행 — 디스크의 스토어·iCloud·캘린더·위젯·공유 상자에 쓰지 않는다.
    static var isUnderTest: Bool { isUnitTestHost || isUITesting }
}
