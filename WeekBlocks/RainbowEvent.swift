//
//  RainbowEvent.swift
//  욕망의 무지개 · 무지개 공방 (두 앱이 같은 파일을 쓴다)
//
//  **무지개 일정을 맥과 아이폰이 함께 쓰는 자리.**
//
//  아이폰의 무지개 일정(`Event`)은 이 기기에만 있는 스토어에 산다. 맥에는 그걸 읽을 길이 없어서,
//  아이폰에서 적은 일정과 할 일 기한이 맥에는 하나도 안 보였다.
//
//  그렇다고 `Event`를 통째로 CloudKit으로 옮기지 않는다. 그 스토어는 iCloud 사본이 없는 유일본이고,
//  옮기다 하나라도 어긋나면 되돌릴 곳이 없다. 대신 **함께 쓰는 사본**을 공용 스토어에 하나 더 둔다.
//   · 아이폰: `Event`가 원본 그대로 남고, 다리(→ RainbowBridge.swift)가 두 쪽을 맞춘다.
//   · 맥: 이 모델만 읽고 쓴다.
//
//  ⚠️ **지우지 않는다 — `deletedAt`을 찍는다.** 공용 스토어가 비어서 내려오는 일(미러 다시 받기,
//     다른 iCloud 계정)이 생겨도 그걸 '지웠다'로 읽어 아이폰 원본을 지우면 안 된다. 사람이 지운 것은
//     표가 남고, 표 없이 사라진 것은 아이폰 원본에서 다시 세운다.
//  ⚠️ 칸 이름 · 타입 · 기본값은 두 앱에서 **글자 하나까지 같아야 한다.** CloudKit 레코드 타입
//     `CD_RainbowEvent` 하나를 두 앱이 함께 쓴다. 출시 전에 Production 스키마 배포가 필요하다.
//

import Foundation
import SwiftData

@Model
final class RainbowEvent {
    /// 두 기기가 같은 일정을 부르는 이름. 만들 때 한 번 정하고 안 바꾼다.
    var uuid: String = UUID().uuidString
    var title: String = ""
    /// 시작일 (그날 0시).
    var startDate: Date = Date()
    /// 종료일 (그날 0시). `isInfinite`면 보지 않는다.
    var endDate: Date = Date()
    /// "#RRGGBB".
    var colorHex: String = "#FF3B30"
    var hoursPerDay: Double = 2.0
    /// 하는 요일 `[Int]` JSON (1=일 … 7=토). nil이면 매일.
    var selectedWeekdaysData: Data? = nil
    /// 5주 × 7일 = 35칸 `[Bool]` JSON. 있으면 요일보다 먼저 본다.
    var weeklyPatternData: Data? = nil
    /// "high" · "medium" · "low".
    var importanceRaw: String = "medium"
    var isInfinite: Bool = false
    /// 빼 둔 날 `[Date]` JSON.
    var excludedDatesData: Data? = nil
    /// 이어진 할 일(BacklogItem)의 dragToken — 할 일의 기한이 이 일정이다.
    var todoToken: String? = nil
    var createdAt: Date = Date()
    /// 마지막으로 고친 때. 두 기기가 같은 일정을 따로 고쳤을 때 나중 것을 고른다.
    var updatedAt: Date = Date()
    /// 사람이 지웠다. 행은 남겨 둔다 (→ 파일 머리 주석).
    var deletedAt: Date? = nil
    /// 처음 만든 기기의 설치 id (→ TodoSharing.installID).
    var originInstallID: String = ""

    init(uuid: String = UUID().uuidString, title: String = "") {
        self.uuid = uuid
        self.title = title
    }

    /// 사람이 지운 표가 있다. (`isDeleted`는 SwiftData가 쓰는 이름이라 피한다.)
    var isRemoved: Bool { deletedAt != nil }

    var selectedWeekdays: [Int]? {
        get { selectedWeekdaysData.flatMap { try? JSONDecoder().decode([Int].self, from: $0) } }
        set { selectedWeekdaysData = newValue.flatMap { try? JSONEncoder().encode($0) } }
    }

    var weeklyPattern: [Bool]? {
        get {
            guard let data = weeklyPatternData,
                  let p = try? JSONDecoder().decode([Bool].self, from: data), p.count == 35 else { return nil }
            return p
        }
        set {
            weeklyPatternData = (newValue?.count == 35) ? newValue.flatMap { try? JSONEncoder().encode($0) } : nil
        }
    }

    var excludedDates: Set<Date> {
        get {
            guard let data = excludedDatesData,
                  let dates = try? JSONDecoder().decode([Date].self, from: data) else { return [] }
            return Set(dates.map { Calendar.current.startOfDay(for: $0) })
        }
        set {
            let days = newValue.map { Calendar.current.startOfDay(for: $0) }.sorted()
            excludedDatesData = try? JSONEncoder().encode(days)
        }
    }

    /// 무한 반복이면 시작일부터 365일 (아이폰 `Event.effectiveEndDate`와 같다).
    var effectiveEndDate: Date {
        isInfinite ? (Calendar.current.date(byAdding: .day, value: 365, to: startDate) ?? endDate) : endDate
    }

    /// 기간 안인가 — 시작일부터 종료일까지, 손으로 뺀 날만 빼고.
    func spans(_ date: Date) -> Bool {
        let d = Calendar.current.startOfDay(for: date)
        guard d >= startDate, d <= effectiveEndDate else { return false }
        return !excludedDates.contains(d)
    }

    /// 이날 실제로 하는가 — 35일 패턴 → 요일 → 뺀 날 차례 (아이폰 `Event.occursOn`과 같다).
    func occurs(on date: Date) -> Bool {
        let cal = Calendar.current
        let d = cal.startOfDay(for: date)
        guard d >= startDate, d <= effectiveEndDate else { return false }
        if let pattern = weeklyPattern {
            let since = cal.dateComponents([.day], from: startDate, to: d).day ?? 0
            let i = since % 35
            if i >= 0, i < 35, !pattern[i] { return false }
        } else if let days = selectedWeekdays, !days.isEmpty {
            if !days.contains(cal.component(.weekday, from: d)) { return false }
        }
        return !excludedDates.contains(d)
    }
}
