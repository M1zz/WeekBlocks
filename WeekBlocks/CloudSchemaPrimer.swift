//
//  CloudSchemaPrimer.swift
//  WeekBlocks
//
//  **모델에 있는 모든 필드를 CloudKit 스키마에 만들어 둔다.** (디버그 전용)
//
//  아이폰 '욕망의 무지개'의 같은 이름 파일을 맥으로 옮긴 것이다. 두 앱이 같은 컨테이너를
//  쓰므로 같은 도구가 양쪽에 있어야 한다.
//
//  CloudKit은 **값이 실제로 쓰인 필드만** 만든다. 옵셔널 필드에 한 번도 값을 안 넣으면
//  스키마에 그 칸이 안 생기고, Development → Production 배포에도 안 실려 간다.
//  그러면 출시 뒤 사용자가 그 값을 **처음 넣는 순간** 서버가 모르는 필드라며 거절하고,
//  거절 하나가 미러링 초기화를 통째로 실패시켜 동기화가 멈춘다. 조용히, 그 사람에게만.
//
//    var isShared: Bool = true          → 값이 있으니 칸이 생긴다
//    var calendarEventID: String? = nil → nil 이면 안 보내서 칸이 안 생긴다  ⚠️
//
//  손으로 기능을 하나씩 다 써 보는 것으로는 이걸 못 막는다. 빠뜨리기 쉽고, 빠뜨린 것은
//  눈에 안 보인다. 그래서 **모든 옵셔널에 값을 채운 표본을 한 벌 만들어 올리고, 올라간 뒤
//  지운다.** 레코드는 지워도 스키마는 남는다.
//
//  ⚠️ 디버그 빌드에서만, Development 환경에서만 쓸 것. 표본이 잠깐 목록에 보였다 사라진다.
//     Production에서는 애초에 필드가 자동 생성되지 않으므로 소용도 없다.
//
//  ⚠️ **모델에 옵셔널 필드를 더할 때마다 여기도 함께 고칠 것.** 안 고치면 이 파일이
//     있으나 마나다 — 지금 채우는 것은 PlanBlock 넷과 BacklogItem 넷이다.
//     (Routine·RoutineOccurrence·QuotaPlacement·BacklogCategory에는 옵셔널이 없다.)
//

#if DEBUG

import Foundation
import SwiftData

enum CloudSchemaPrimer {

    /// 표본임을 한눈에 알아보게 하는 이름. 지우다 실패해도 사용자가 알아본다.
    static let marker = "⟨스키마 표본 · 지워도 됩니다⟩"

    struct Report {
        var created: Int
        var deleted: Int
        var note: String
    }

    /// 모든 모델의 모든 필드에 값을 채운 표본을 만들었다가 지운다.
    ///
    /// - Parameter settleSeconds: 만들고 지우기까지 기다리는 시간. 그 사이에 내보내기가
    ///   돌아야 스키마가 생긴다. 너무 짧으면 지워진 뒤에 올라가 아무 칸도 안 생긴다.
    @MainActor
    static func prime(_ context: ModelContext, settleSeconds: UInt64 = 25) async -> Report {
        let now = Date()
        let week = Date.currentWeekStart

        // ── 모든 옵셔널에 값을 넣는다. 이게 이 파일의 존재 이유다. ──────────
        let category = BacklogCategory(name: marker, colorName: "blue",
                                       iconName: "tag", sortIndex: 9_999)

        let item = BacklogItem(title: marker, durationHours: 1, sortIndex: 9_999,
                               categoryID: category.uuid, weekStartDate: week)
        item.completedAt = now
        item.parentToken = "schema-sample-parent"
        item.labelRaw = "schema-sample-label"
        item.isShared = true
        item.originInstallID = "schema-sample-install"

        let block = PlanBlock(day: .mon, timeBand: .morning, durationHours: 1,
                              title: marker, successCriteria: "sample",
                              deliverable: "sample", weekStartDate: week)
        block.reviewStatusRaw = "sample"
        block.reviewNote = "sample"
        block.reviewedAt = now
        // 캘린더 가져오기가 더한 칸 (→ CalendarImport.swift). 이 줄이 없으면 이 필드는
        // 실제로 캘린더를 가져와 본 사람의 기기에서만 생긴다.
        block.calendarEventID = "schema-sample-event"

        for model in [category as any PersistentModel, item, block] {
            context.insert(model)
        }
        do {
            try context.save()
        } catch {
            return Report(created: 0, deleted: 0, note: "표본을 못 만들었습니다: \(error)")
        }

        // 내보내기가 돌 시간을 준다. 이 사이에 서버에 칸이 생긴다.
        try? await Task.sleep(nanoseconds: settleSeconds * 1_000_000_000)

        // ── 치운다. 스키마는 남는다. ────────────────────────────────────────
        var deleted = 0
        for model in [category as any PersistentModel, item, block] {
            context.delete(model)
            deleted += 1
        }
        try? context.save()

        return Report(created: 3, deleted: deleted,
                      note: "표본을 올렸다 지웠습니다. 콘솔의 Development 스키마에 칸이 생겼는지 확인한 뒤 Production으로 배포하세요.")
    }
}

#endif
