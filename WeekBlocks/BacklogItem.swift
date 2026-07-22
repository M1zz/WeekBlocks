import Foundation
import SwiftData

@Model
final class BacklogItem {
    var title: String = ""
    var durationHours: Double = 1
    var sortIndex: Int = 0
    var createdAt: Date = Date()
    // Stable string token used to identify the item during drag-and-drop.
    var dragToken: String = UUID().uuidString
    /// 연결된 BacklogCategory.uuid (없으면 nil = 미분류).
    var categoryID: String? = nil
    /// 이 할 일이 속한 주 (월요일 00:00). 지난 주에 못 한 항목 구분에 사용.
    var weekStartDate: Date = Date.currentWeekStart
    /// iOS Todo에서 체크한 완료 상태. 완료되면 맥 백로그 그리드에서는 숨긴다.
    var isCompleted: Bool = false
    var completedAt: Date? = nil

    init(title: String,
         durationHours: Double = 1,
         sortIndex: Int = 0,
         categoryID: String? = nil,
         weekStartDate: Date = Date.currentWeekStart)
    {
        self.title = title
        self.durationHours = durationHours
        self.sortIndex = sortIndex
        self.dragToken = UUID().uuidString
        self.categoryID = categoryID
        self.weekStartDate = weekStartDate
    }
}
