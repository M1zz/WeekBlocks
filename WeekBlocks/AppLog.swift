//
//  AppLog.swift
//  WeekBlocks (무지개 공방)
//
//  **무슨 일이 있었는지 남기는 한 곳.** 예전에는 `print` 였다. print 는 Xcode 에 붙어 있을 때만
//  보이고, 사용자의 맥에서 "할 일이 사라졌어요" 가 오면 아무 흔적도 없었다.
//  `Logger` 로 남기면 콘솔 앱(또는 `log show`)에서 이 앱만 골라 볼 수 있고, sysdiagnose 에도 실린다.
//
//      log show --last 1h --predicate 'subsystem == "com.devkoan.ScheduleDensityApp"'
//
//  ⚠️ **적은 내용(할 일 제목·이름)은 남기지 않는다.** 개수·파일 이름·오류만 남긴다.
//     문자열은 기본이 private 이라 남겨도 가려지지만, 애초에 안 넘기는 편이 확실하다.
//  ⚠️ 공유 확장(TodoShareExtension)도 이 파일을 함께 쓴다 — 확장의 번들 ID 가 subsystem 이 된다.
//

import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.devkoan.ScheduleDensityApp"

    /// 스토어 열기·겹친 것 정리·다시 받기.
    static let store = Logger(subsystem: subsystem, category: "store")
    /// 데이터 금고 — 사본·스냅숏·되살리기 (→ DataVault.swift, VaultMonitor.swift).
    static let vault = Logger(subsystem: subsystem, category: "vault")
    /// 아이폰과 함께 쓰기·공유 메뉴로 받은 할 일.
    static let sharing = Logger(subsystem: subsystem, category: "sharing")
    /// 조용한 푸시 등록.
    static let push = Logger(subsystem: subsystem, category: "push")
    /// 켤 때 — 세이프 모드·원격 스위치.
    static let launch = Logger(subsystem: subsystem, category: "launch")

    /// **오래 걸리는 일의 구간** (→ Instruments ▸ Points of Interest).
    ///
    /// 켤 때 스토어를 세우는 일, 금고 스냅숏, 캘린더와 맞추기처럼 사람이 기다리게 되는 일만 잰다.
    /// 느려졌다는 말이 오면 Instruments 로 어느 구간이 늘었는지 바로 본다.
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)

    /// `name` 구간을 재며 `work` 를 돌린다.
    @discardableResult
    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name, id: signposter.makeSignpostID())
        defer { signposter.endInterval(name, state) }
        return try work()
    }
}
