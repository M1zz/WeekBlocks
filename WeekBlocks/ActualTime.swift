//
//  ActualTime.swift
//  무지개 공방
//
//  **계획한 만큼 걸렸나.** 재고 싶은 사람만 잰다.
//
//  타이머는 본래 일정을 따른다 — 일정이 시작되면 물러나고, 끝나면 사라진다 (→ TaskTimer.reconcile).
//  그래서 실제로 얼마나 걸렸는지는 아무 데도 남지 않았다. 그렇다고 모두에게 재라고 하면
//  계획을 짜는 앱이 감시하는 앱이 된다. 그래서 **설정 ▸ 타이머 ▸ '걸린 시간 재기'** 를 켠 사람만:
//   · 타이머가 일정을 따르지 않고 켠 순간부터 끝까지 그대로 센다.
//   · 멈추는 순간 그만큼을 그 블록의 `actualMinutes`에 더한다 (나눠서 해도 쌓인다).
//
//  끈 사람에게도 '계획 대비 실제'는 선다 — 회고에서 찍은 결과로 해낸 시간을 셈한다
//  (→ ReflectionTrends.hours). 잰 값이 있으면 거기에 '일마다 몇 % 더 걸리는가'가 더해질 뿐이다.
//

import Foundation
import SwiftData

enum ActualTime {
    static let enabledKey = "timer.measuresActual"

    /// '걸린 시간 재기'를 켰는가. 기본은 꺼짐.
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    /// 1분이 안 되는 것은 잘못 누른 것으로 본다.
    static let minimumSeconds: TimeInterval = 60

    /// 잰 시간을 그 블록에 더한다.
    ///
    /// 열쇠(`dragToken`)로 먼저 찾고, 못 찾으면 **오늘 같은 제목**으로 찾는다 —
    /// persistentModelID 글자는 앱을 다시 켜면 달라질 수 있다 (→ TaskTimer.reconcile과 같은 까닭).
    @MainActor
    static func record(token: String, title: String, seconds: TimeInterval) {
        guard seconds >= minimumSeconds, token.hasPrefix("block:") else { return }
        let context = PlanStore.shared.context
        guard let blocks = try? context.fetch(FetchDescriptor<PlanBlock>()) else { return }
        let block = PlanBlock.matching(dragToken: token, in: blocks) ?? blocks.first { b in
            b.title == title && Calendar.current.isDateInToday(b.date)
        }
        guard let block else { return }
        block.actualMinutes = (block.actualMinutes ?? 0) + seconds / 60
        try? context.save()
    }
}

private extension PlanBlock {
    /// 이 블록이 서 있는 날.
    var date: Date {
        Calendar(identifier: .iso8601).date(byAdding: .day, value: day.rawValue, to: weekStartDate) ?? weekStartDate
    }
}
