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
    static let appName = "무지개 공방"
    static let developerEmail = "leeo@kakao.com"

    /// WeekBlocks.entitlements에 iCloud.com.Ysoup.FeedbackHub 컨테이너가 있어야 한다.
    /// 공용 피드백 허브(FeedbackHub)로 수집 — appIdentifier로 앱을 구분한다.
    /// (앱 데이터는 iCloud.com.devkoan.ScheduleDensity 컨테이너에서 계속 동기화된다.)
    static let feedback = LeeoFeedbackConfig(
        containerIdentifier: "iCloud.com.Ysoup.FeedbackHub",
        appIdentifier: "com.devkoan.ScheduleDensityApp"
    )
}
