//
//  WeekBlocksFlag.swift
//  WeekBlocks (무지개 공방)
//
//  **심사 없이 끌 수 있는 기능들** (LeeoKit `LeeoRemoteFlags`).
//
//  남의 데이터를 건드리는 일만 여기 둔다 — 고장 나면 앱 밖까지 번지는 것들이다.
//  캘린더에 쓰는 일이 잘못되면 사람의 캘린더가 어지러워지고, 일정 공유가 잘못되면
//  남에게 엉뚱한 일정이 간다. 그런 일이 생기면 고친 빌드가 심사를 지나는 며칠 동안
//  번지지 않게 여기서 먼저 끈다.
//
//  끄는 법: CloudKit 대시보드(iCloud.com.Ysoup.FeedbackHub, Production · Public)의
//  레코드 타입 `RemoteFlags` / recordName `flags_com.devkoan.ScheduleDensityApp` 에
//  아래 rawValue 를 이름으로 한 **Int64** 필드를 두고 0 을 넣는다. 필드가 없거나 1 이면 켬.
//
//  ⚠️ **조회 실패 = 켬.** 네트워크가 없다고 기능이 꺼지면 스위치가 장애 원인이 된다.
//  ⚠️ 갱신은 켤 때 백그라운드로, 6시간 간격이다. 끈 값은 다음 실행부터 닿는다.
//

import LeeoKit

enum WeekBlocksFlag: String, LeeoRemoteFlag, CaseIterable {
    /// 계획을 '무지개 공방' 캘린더에 쓰기 (→ CalendarBridge.exportPlan).
    case calendarExport
    /// 고른 캘린더의 일정을 저절로 가져오기 (→ CalendarBridge.isAutoReady).
    case calendarAutoImport
    /// 내 주간 일정을 보기 전용 링크로 공유하기 (→ ScheduleShareStore).
    case scheduleSharing

    /// 지금 이 기능을 써도 되는가. 네트워크를 타지 않고 마지막으로 받아 둔 값을 본다.
    var isOn: Bool { LeeoRemoteFlags.isEnabled(self) }
}
