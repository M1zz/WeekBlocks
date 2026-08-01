import Foundation

// MARK: - 전파 계약 (Broadcast Contract)
//
// '전파 필요'로 체크한 할 일은 일반 항목과 다른 전처리를 밟는다.
// 일반 항목의 전처리가 ConcretenessChecker(나에게 구체적인가)라면,
// 전파 항목의 전처리는 이 파일(상대가 받아서 쓸 수 있는가)이다.
//
// 전제: 전파가 필요한 이유는 사회성이나 실력이 아니라 정보 비대칭이다.
// 나는 진행 상황을 알고 상대는 0인데 실패의 피해는 함께 진다.
// 그래서 전파할 것은 진척도가 아니라 판단이고, 상대가 밖에 그대로
// 옮길 수 있는 문장이어야 한다. 이 파일은 그 문장과 그걸 보낼 날짜를 만든다.
//
// SwiftUI에 의존하지 않는다 (모델과 함께 iOS 타깃에 전파 가능).

// MARK: 전파 대상

/// 누구에게 알리는가. 같은 계약이라도 대상에 따라 강조점과 리드타임이 다르다.
enum BroadcastAudience: String, Codable, CaseIterable, Identifiable {
    /// 내 일을 근거로 밖에다 자기 이름 걸고 말해야 하는 사람.
    case decisionMaker = "decisionMaker"
    /// 내 산출물을 받아서 자기 일을 시작하는 사람.
    case downstream = "downstream"
    /// 나와 나란히 일하는 동급 동료.
    case peer = "peer"
    /// 외부 클라이언트.
    case client = "client"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .decisionMaker: "의사결정자 (책임 라인)"
        case .downstream: "내 뒤에 붙는 동료 (하류)"
        case .peer: "동급 동료"
        case .client: "외부 클라이언트"
        }
    }

    var shortLabel: String {
        switch self {
        case .decisionMaker: "의사결정자"
        case .downstream: "하류 동료"
        case .peer: "동료"
        case .client: "클라이언트"
        }
    }

    /// 이 대상이 실제로 필요한 것 — 편집기에서 무엇을 채워야 하는지 안내한다.
    var needsMost: String {
        switch self {
        case .decisionMaker:
            "밖에 그대로 옮길 수 있는 문장. 날짜 + 확신도 + 변수 하나."
        case .downstream:
            "진행률이 아니라 계약. 어떤 모양으로, 언제 오는지."
        case .peer:
            "내 일을 언제 시작할 수 있는지. 조율 정보."
        case .client:
            "약속한 날짜와 그 날짜의 근거. 변경은 선택지와 함께."
        }
    }

    /// 이 대상에게 나쁜 소식을 전할 때 확보해 줘야 하는 추가 여유(일).
    /// 의사결정자·클라이언트는 받은 소식을 다시 밖으로 옮겨야 하므로 더 이르게 알린다.
    var extraLeadDays: Int {
        switch self {
        case .decisionMaker: 2
        case .client: 3
        case .downstream: 1
        case .peer: 0
        }
    }

    /// 강조점이 형태(하류·동료)인가 확신도(의사결정자·클라이언트)인가.
    var emphasizesHandoffForm: Bool {
        self == .downstream || self == .peer
    }
}

// MARK: 확신도

enum BroadcastConfidence: String, Codable, CaseIterable, Identifiable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .high: "높음"
        case .medium: "보통"
        case .low: "낮음"
        }
    }

    /// 확신도가 낮으면 리스크 게이트를 더 앞으로 당긴다.
    var extraLeadDays: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 3
        }
    }
}

// MARK: 전파 시점

enum BroadcastCheckpointKind: String, Codable {
    /// 착수 선언 — 형식·주기와 "연락 없음 = 정상 진행" 규칙을 먼저 못 박는다.
    case kickoff
    /// 미확정 변수가 판명되는 날.
    case variableResolve
    /// 중간 판단 전파 — 진행률이 아니라 정한 것 / 버린 것 / 걸리는 것.
    case mid
    /// 리스크 게이트 — 어긋날 낌새를 상대가 조치할 수 있는 시점에 통보.
    case riskGate
    /// 최종 확정 — 예정대로 가는지 한 번 더.
    case finalConfirm

    var label: String {
        switch self {
        case .kickoff: "착수 선언"
        case .variableResolve: "변수 판명"
        case .mid: "중간 판단"
        case .riskGate: "리스크 게이트"
        case .finalConfirm: "최종 확정"
        }
    }

    /// 이 시점에 무엇을 하는가 (왜 이 날짜인지).
    var purpose: String {
        switch self {
        case .kickoff:
            "언제 어떤 형태로 연락할지, 그리고 연락이 없으면 정상 진행이라는 규칙을 먼저 정한다. 이 한 번이 그 뒤 며칠의 불안을 대신 처리한다."
        case .variableResolve:
            "미확정이라고 예고한 변수가 판명되는 날. 결과와 일정 영향만 한 줄."
        case .mid:
            "진행률이 아니라 판단을 전파한다. 설익은 산출물을 노출하지 않고도 예측가능성이 확보된다."
        case .riskGate:
            "여기까지가 상대가 조치할 수 있는 마지막 시점이다. 늦은 나쁜 소식이 신뢰를 깎는 거의 유일한 요인이므로, 낌새가 보이면 이 날짜를 기다리지 말고 즉시 보낸다."
        case .finalConfirm:
            "예정대로 가는지 확정한다. 변경이면 새 날짜와 선택지를 함께."
        }
    }
}

struct BroadcastCheckpoint: Identifiable {
    /// 날짜가 바뀌어도 유지되는 안정 식별자 (완료 체크 저장 키).
    let token: String
    let kind: BroadcastCheckpointKind
    let date: Date
    /// 그대로 복사해서 보낼 수 있는 초안.
    let script: String
    let isDone: Bool

    var id: String { token }
}

// MARK: - 역산 플래너

enum BroadcastPlanner {

    private static var cal: Calendar {
        var c = Calendar(identifier: .iso8601)
        c.firstWeekday = 2
        return c
    }

    // MARK: 입력

    /// 계약 내용 묶음 — BacklogItem에서 그대로 채워 넣는다.
    struct Contract {
        var title: String = ""
        var audience: BroadcastAudience = .decisionMaker
        var recipient: String = ""
        var handoffForm: String = ""
        var deadline: Date? = nil
        var earliest: Date? = nil
        var latest: Date? = nil
        var confidence: BroadcastConfidence = .medium
        var openVariable: String = ""
        var variableResolveDate: Date? = nil
        var noSignalRuleAgreed: Bool = false
        /// 착수 시점 (보통 항목 생성일).
        var startedAt: Date = Date()
    }

    /// 상대에게 약속한 날. 없으면 데드라인.
    /// 역산의 기준은 데드라인이 아니라 '내가 약속한 날'이어야 한다.
    static func promiseDate(_ c: Contract) -> Date? {
        c.latest ?? c.deadline
    }

    // MARK: 전파 시점 추천 — 데드라인 역산

    /// 날짜 계획의 한 칸 — 문장 생성 전 단계.
    /// 문장(script)이 계획 정보를 참조하므로, 날짜 계산과 문장 생성은 반드시 분리한다.
    private struct PlannedDate {
        let token: String
        let kind: BroadcastCheckpointKind
        let date: Date
    }

    /// 데드라인(정확히는 약속일)로부터 역산해 알려야 하는 날짜들을 만든다.
    /// 결과는 절대 날짜이므로 '오늘'과 무관하다 (D-day 표기만 오늘을 쓴다).
    /// - Parameter doneTokens: 이미 보낸 시점의 token 집합.
    static func checkpoints(for c: Contract,
                            doneTokens: Set<String> = []) -> [BroadcastCheckpoint]
    {
        plannedDates(for: c).map { entry in
            BroadcastCheckpoint(
                token: entry.token,
                kind: entry.kind,
                date: entry.date,
                script: script(for: entry.kind, contract: c, checkpointDate: entry.date),
                isDone: doneTokens.contains(entry.token)
            )
        }
    }

    /// 역산 날짜만 계산한다 (문장 생성 없음).
    private static func plannedDates(for c: Contract) -> [PlannedDate] {
        guard let promise = promiseDate(c) else { return [] }

        let cal = self.cal
        let start = cal.startOfDay(for: min(c.startedAt, promise))
        let promiseDay = cal.startOfDay(for: promise)
        let span = dayCount(from: start, to: promiseDay)
        guard span >= 0 else { return [] }

        var raw: [(token: String, kind: BroadcastCheckpointKind, date: Date)] = []

        // 1. 착수 선언 — 항상. 기간이 하루라도 이건 있어야 한다.
        raw.append((token: "kickoff", kind: .kickoff, date: start))

        // 2. 리스크 게이트 — 약속일에서 역산. 이 기능의 핵심.
        let lead = riskGateLeadDays(span: span, audience: c.audience, confidence: c.confidence)
        let gate = cal.date(byAdding: .day, value: -lead, to: promiseDay) ?? promiseDay
        if gate > start {
            raw.append((token: "riskGate", kind: .riskGate, date: gate))
        }

        // 3. 중간 판단 — 착수와 리스크 게이트 사이. 기간이 길면 2주 간격으로 여러 번.
        let midAnchorEnd = gate > start ? gate : promiseDay
        for (i, d) in midDates(start: start, end: midAnchorEnd, span: span).enumerated() {
            raw.append((token: "mid\(i + 1)", kind: .mid, date: d))
        }

        // 4. 변수 판명일 — 예고한 변수가 결론 나는 날.
        if hasOpenVariable(c), let rd = c.variableResolveDate {
            let day = cal.startOfDay(for: rd)
            if day >= start && day <= promiseDay {
                raw.append((token: "variableResolve", kind: .variableResolve, date: day))
            }
        }

        // 5. 최종 확정 — 약속일 하루 전.
        if span >= 2 {
            let confirm = cal.date(byAdding: .day, value: -1, to: promiseDay) ?? promiseDay
            if confirm > start {
                raw.append((token: "finalConfirm", kind: .finalConfirm, date: confirm))
            }
        }

        // 주말에 걸린 날짜를 평일로 옮긴다 (주말 통보는 상대가 조치할 수 없다).
        // 마감에 묶인 게이트·확정은 앞의 평일로 당기고, 중간 판단은 뒤의 평일로 미룬다.
        // 착수 선언과 변수 판명일은 실제 사건에 묶여 있으므로 그대로 둔다.
        let snapped = raw.map { entry -> PlannedDate in
            switch entry.kind {
            case .kickoff, .variableResolve:
                return PlannedDate(token: entry.token, kind: entry.kind, date: entry.date)
            case .mid:
                return PlannedDate(token: entry.token,
                                   kind: entry.kind,
                                   date: snapToWeekday(entry.date, forward: true, bound: promiseDay))
            case .riskGate, .finalConfirm:
                return PlannedDate(token: entry.token,
                                   kind: entry.kind,
                                   date: snapToWeekday(entry.date, forward: false, bound: start))
            }
        }

        // 평일로 옮기다 보면 중간 판단이 착수 바로 다음날이나 게이트 직전에 붙을 수 있다.
        // 그런 신호는 정보를 주지 않고 통수만 늘리므로 버린다.
        let gateOrPromise = snapped.first { $0.kind == .riskGate }?.date ?? promiseDay
        let spaced = snapped.filter { entry in
            guard entry.kind == .mid else { return true }
            return dayCount(from: start, to: entry.date) >= 2
                && dayCount(from: entry.date, to: gateOrPromise) >= 2
        }

        // 같은 날에 두 개 이상 몰리면 하나만 남긴다 (짧은 일감에서 흔하다).
        // 남기는 기준은 그날 보낼 문장이 상대에게 가장 쓸모 있는 것.
        var byDay: [Date: PlannedDate] = [:]
        for entry in spaced {
            let key = cal.startOfDay(for: entry.date)
            if let existing = byDay[key], priority(existing.kind) >= priority(entry.kind) { continue }
            byDay[key] = entry
        }

        return byDay.values.sorted { $0.date < $1.date }
    }

    /// 같은 날에 겹쳤을 때 남길 우선순위 (클수록 우선).
    private static func priority(_ kind: BroadcastCheckpointKind) -> Int {
        switch kind {
        case .kickoff: 4          // 계약 선언이 먼저다.
        case .riskGate: 3         // 선택지가 붙는 문장. 가장 값이 크다.
        case .finalConfirm: 2
        case .variableResolve: 1
        case .mid: 0
        }
    }

    /// 리스크 게이트를 약속일보다 며칠 앞에 둘지.
    /// 기간의 1/4을 기본으로, 대상이 소식을 다시 옮겨야 하거나 확신도가 낮으면 더 앞으로.
    static func riskGateLeadDays(span: Int,
                                 audience: BroadcastAudience,
                                 confidence: BroadcastConfidence) -> Int
    {
        guard span > 0 else { return 0 }
        let base = Int((Double(span) * 0.25).rounded())
        let total = base + audience.extraLeadDays + confidence.extraLeadDays
        // 최소 1일. 상한은 기간의 70%(착수 직후로 붙는 걸 막는다)와 10일 중 작은 쪽.
        let ceiling = max(1, min(10, Int((Double(span) * 0.7).rounded())))
        return max(1, min(total, ceiling))
    }

    /// 중간 판단 시점들. 5일 미만이면 중간이 없고, 3주를 넘으면 2주 간격으로 반복한다.
    private static func midDates(start: Date, end: Date, span: Int) -> [Date] {
        guard span >= 5 else { return [] }
        let cal = self.cal
        let window = dayCount(from: start, to: end)
        guard window >= 3 else { return [] }

        if span <= 21 {
            let offset = max(1, window / 2)
            guard let d = cal.date(byAdding: .day, value: offset, to: start), d < end else { return [] }
            return [d]
        }

        var result: [Date] = []
        var offset = 14
        while offset < window - 1 {
            if let d = cal.date(byAdding: .day, value: offset, to: start), d < end {
                result.append(d)
            }
            offset += 14
        }
        // 아주 긴 일은 중간 신호가 촘촘해도 4번을 넘기면 그 자체가 부담이 된다.
        return Array(result.prefix(4))
    }

    // MARK: 보낼 문장

    /// 그대로 복사해 보낼 수 있는 초안. 괄호는 사용자가 채우는 자리다.
    static func script(for kind: BroadcastCheckpointKind,
                       contract c: Contract,
                       checkpointDate: Date) -> String
    {
        let title = c.title.isEmpty ? "(할 일)" : c.title
        let promise = promiseDate(c).map(dateLabel) ?? "(늦어도 날짜)"
        let form = c.handoffForm.isEmpty ? "(넘길 형태)" : c.handoffForm
        let variable = hasOpenVariable(c) ? c.openVariable : "없음"
        let resolve = c.variableResolveDate.map(dateLabel)

        switch kind {
        case .kickoff:
            var lines: [String] = []
            if c.audience.emphasizesHandoffForm {
                lines.append("\(title) → \(form) 형태로 넘깁니다.")
                if let e = c.earliest.map(dateLabel) {
                    lines.append("빠르면 \(e), 늦어도 \(promise) 보장.")
                } else {
                    lines.append("늦어도 \(promise) 보장.")
                }
                lines.append("지금 미확정: \(variable)\(resolve.map { " (\($0)에 판명)" } ?? "").")
                lines.append("넘길 형태가 바뀌면 즉시 알립니다. 그 외 내부 변경은 따로 알리지 않습니다.")
            } else {
                lines.append("\(title) 착수했습니다.")
                lines.append("\(promise)까지 가능합니다. 확신도 \(c.confidence.label).")
                if variable == "없음" {
                    lines.append("현재 미확정 변수 없습니다.")
                } else {
                    lines.append("변수는 \(variable) 하나고\(resolve.map { " \($0)에 판명됩니다" } ?? " 판명 시 알립니다").")
                }
                if c.noSignalRuleAgreed {
                    lines.append("중간에 연락이 없으면 정상 진행입니다. 어긋날 낌새가 보이면 그때 바로 알립니다.")
                } else {
                    lines.append("중간 알림은 \(midCountLabel(c))이고, 어긋날 낌새가 보이면 그때 바로 알립니다.")
                }
            }
            return lines.joined(separator: "\n")

        case .mid:
            return [
                "\(title) 중간 상황 알려드립니다.",
                "정한 것: (이렇게 가기로 정했습니다)",
                "버린 것: (검토했지만 버린 안)",
                "걸리는 것: \(variable == "없음" ? "(없음)" : variable)",
                "일정은 \(promise) 그대로입니다."
            ].joined(separator: "\n")

        case .variableResolve:
            return [
                "\(title) — \(variable) 판명됐습니다.",
                "결과: (판명된 내용)",
                "일정 영향: 없음 / (N)일 (있으면 아래 선택지)"
            ].joined(separator: "\n")

        case .riskGate:
            return [
                "\(title) — \(promise) 일정 점검입니다.",
                "유지 가능하면: 예정대로 \(promise)에 \(form) 넘깁니다. 확신도 \(c.confidence.label).",
                "어긋나면: 이대로면 (N)일 밀립니다. 범위를 (이만큼) 줄이면 \(promise) 유지 가능하고, 저는 후자를 권합니다.",
                "— 결정만 하시면 됩니다."
            ].joined(separator: "\n")

        case .finalConfirm:
            return [
                "\(title) — 예정대로 \(promise)에 \(form) 넘깁니다.",
                "(변경이면: 새 날짜 + 이유 + 선택지 두 개)"
            ].joined(separator: "\n")
        }
    }

    /// 어디 한 곳에 써두고 변경 시 갱신할 네 줄. 같은 질문을 여러 명이 각각 물어오는 걸 막는다.
    static func contractCard(_ c: Contract) -> String {
        let title = c.title.isEmpty ? "(할 일)" : c.title
        let form = c.handoffForm.isEmpty ? "(넘길 형태)" : c.handoffForm
        let earliest = c.earliest.map(dateLabel) ?? "(빠르면)"
        let latest = c.latest.map(dateLabel) ?? c.deadline.map(dateLabel) ?? "(늦어도)"
        let variable = hasOpenVariable(c) ? c.openVariable : "없음"
        let resolve = c.variableResolveDate.map { " — \(dateLabel($0))에 판명" } ?? ""

        var lines = [
            "산출물: \(title)",
            "넘길 형태: \(form)",
            "빠르면 \(earliest) / 늦어도 \(latest) 보장",
            "지금 미확정: \(variable)\(resolve)"
        ]
        if !c.audience.emphasizesHandoffForm {
            lines.insert("확신도: \(c.confidence.label)", at: 3)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: 날짜 표기

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.dateFormat = "M/d(E)"
        return f
    }()

    /// "8/12(수)"
    static func dateLabel(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    /// "오늘" / "내일" / "D-3" / "3일 지남"
    static func dDayLabel(_ date: Date, today: Date = Date()) -> String {
        let d = dayCount(from: today, to: date)
        switch d {
        case 0: return "오늘"
        case 1: return "내일"
        case let n where n > 1: return "D-\(n)"
        default: return "\(-d)일 지남"
        }
    }

    /// 오늘 기준으로 이미 보내야 했던 시점인지.
    static func isOverdue(_ checkpoint: BroadcastCheckpoint, today: Date = Date()) -> Bool {
        !checkpoint.isDone && dayCount(from: today, to: checkpoint.date) < 0
    }

    static func isDueToday(_ checkpoint: BroadcastCheckpoint, today: Date = Date()) -> Bool {
        !checkpoint.isDone && dayCount(from: today, to: checkpoint.date) == 0
    }

    // MARK: 내부 헬퍼

    static func hasOpenVariable(_ c: Contract) -> Bool {
        let v = c.openVariable.trimmingCharacters(in: .whitespacesAndNewlines)
        return !v.isEmpty && v != "없음" && v != "없다"
    }

    /// 착수 문장에 넣을 중간 전파 횟수. 문장 생성 중이므로 날짜 계획만 조회한다
    /// (checkpoints를 부르면 문장 생성이 재귀한다).
    private static func midCountLabel(_ c: Contract) -> String {
        let count = plannedDates(for: c).filter { $0.kind == .mid }.count
        return count <= 1 ? "1회" : "총 \(count)회"
    }

    /// 두 날짜의 자정 기준 일 수 차이 (to - from).
    static func dayCount(from: Date, to: Date) -> Int {
        let cal = self.cal
        let a = cal.startOfDay(for: from)
        let b = cal.startOfDay(for: to)
        return cal.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// 주말이면 평일로 옮긴다. `forward`면 다음 평일(월요일), 아니면 앞의 평일(금요일).
    /// 옮긴 결과가 `bound`를 넘으면(뒤로 갈 때는 넘어서면, 앞으로 갈 때는 못 미치면) 원래 날짜를 쓴다.
    private static func snapToWeekday(_ date: Date, forward: Bool, bound: Date) -> Date {
        let cal = self.cal
        var d = date
        for _ in 0..<7 {
            let wd = cal.component(.weekday, from: d)   // 1 = 일요일, 7 = 토요일
            if wd != 1 && wd != 7 { break }
            guard let next = cal.date(byAdding: .day, value: forward ? 1 : -1, to: d) else { break }
            d = next
        }
        if forward { return d < bound ? d : date }
        return d > bound ? d : date
    }
}

// MARK: - 전파 계약 전처리 검사
//
// 일반 항목은 제목과 시간만 있으면 저장된다. 전파 항목은 여기를 통과해야 한다.
// 통과 기준은 "내가 이해했는가"가 아니라 "상대가 받아서 자기 일에 쓸 수 있는가"다.

/// 계약의 어느 칸이 막고 있는지. 편집기가 그 칸을 빨갛게 표시하는 데 쓴다.
enum BroadcastContractField: String, Hashable, CaseIterable {
    case recipient
    case deadline
    case handoffForm
    case dates              // 빠르면 / 늦어도
    case openVariable
    case variableResolve

    /// 미작성 목록에 쓰는 짧은 이름.
    var label: String {
        switch self {
        case .recipient: "누구에게"
        case .deadline: "데드라인"
        case .handoffForm: "넘길 형태"
        case .dates: "두 날짜"
        case .openVariable: "미확정 변수"
        case .variableResolve: "판명되는 날"
        }
    }
}

struct BroadcastContractIssue: Identifiable, Hashable {
    let id = UUID()
    /// 어느 칸의 문제인가. nil이면 특정 칸에 붙지 않는 참고 사항(advisory).
    var field: BroadcastContractField? = nil
    let message: String
}

enum BroadcastContractChecker {

    /// 넘길 형태에 들어가면 상대가 자기 일을 짤 수 없는 표현.
    private static let vagueForms: [String] = [
        "정리해서", "잘 만들어", "적당히", "대충", "알아서", "완성해서", "어느 정도"
    ]

    static func validate(_ c: BroadcastPlanner.Contract) -> [BroadcastContractIssue] {
        var issues: [BroadcastContractIssue] = []

        let recipient = c.recipient.trimmingCharacters(in: .whitespacesAndNewlines)
        let form = c.handoffForm.trimmingCharacters(in: .whitespacesAndNewlines)
        let variable = c.openVariable.trimmingCharacters(in: .whitespacesAndNewlines)

        if recipient.isEmpty {
            issues.append(.init(field: .recipient, message: "누구에게 알릴지 적어 주세요. 대상이 정해지지 않으면 강조점도 시점도 정할 수 없습니다."))
        }

        guard let deadline = c.deadline else {
            issues.append(.init(field: .deadline, message: "데드라인이 없으면 역산할 수 없습니다. 알려야 하는 날짜는 데드라인에서 거꾸로 나옵니다."))
            return issues + formIssues(form: form, variable: variable, contract: c)
        }

        // 두 날짜 — 단일 날짜를 주면 그 날짜가 곧 리스크가 된다.
        switch (c.earliest, c.latest) {
        case (nil, nil):
            issues.append(.init(field: .dates, message: "빠르면 · 늦어도 두 날짜를 적어 주세요. 하나만 주면 그 날짜가 곧 리스크가 되고, 어긋나는 순간 신뢰 문제로 넘어갑니다."))
        case (nil, _):
            issues.append(.init(field: .dates, message: "'빠르면' 날짜가 없습니다. 상대가 앞당겨 쓸 수 있는 여지를 남겨 주세요."))
        case (_, nil):
            issues.append(.init(field: .dates, message: "'늦어도' 보장 날짜가 없습니다. 상대가 계획을 세우는 기준은 이쪽입니다."))
        default:
            break
        }

        if let e = c.earliest, let l = c.latest, BroadcastPlanner.dayCount(from: e, to: l) < 0 {
            issues.append(.init(field: .dates, message: "'빠르면'이 '늦어도'보다 늦습니다. 두 날짜의 순서를 확인해 주세요."))
        }

        if let l = c.latest, BroadcastPlanner.dayCount(from: l, to: deadline) < 0 {
            issues.append(.init(field: .dates, message: "'늦어도' 보장일이 데드라인(\(BroadcastPlanner.dateLabel(deadline)))을 넘습니다. 보장할 수 없는 약속입니다."))
        }

        if let e = c.earliest, let l = c.latest, BroadcastPlanner.dayCount(from: e, to: l) == 0,
           BroadcastPlanner.dayCount(from: c.startedAt, to: l) >= 5 {
            issues.append(.init(field: .dates, message: "빠르면과 늦어도가 같은 날입니다. 폭이 없으면 단일 날짜와 같습니다."))
        }

        if let rd = c.variableResolveDate, BroadcastPlanner.dayCount(from: rd, to: deadline) < 0 {
            issues.append(.init(field: .variableResolve, message: "변수 판명일이 데드라인 뒤입니다. 그때 알아도 조치할 시간이 없습니다."))
        }

        if BroadcastPlanner.dayCount(from: c.startedAt, to: deadline) < 0 {
            issues.append(.init(field: .deadline, message: "데드라인이 이미 지났습니다. 날짜를 다시 확인해 주세요."))
        }

        return issues + formIssues(form: form, variable: variable, contract: c)
    }

    private static func formIssues(form: String,
                                   variable: String,
                                   contract c: BroadcastPlanner.Contract) -> [BroadcastContractIssue]
    {
        var issues: [BroadcastContractIssue] = []

        if form.count < 4 {
            issues.append(.init(field: .handoffForm, message: "넘길 형태를 적어 주세요. 상대가 알아야 하는 건 진행률이 아니라 '어떤 모양으로 오는지'입니다. (예: \"CSV 3개 + 필드 정의 문서\")"))
        } else if let vague = vagueForms.first(where: { form.contains($0) }) {
            issues.append(.init(field: .handoffForm, message: "넘길 형태에 \"\(vague)\" 같은 표현이 있습니다. 받는 쪽이 그걸 전제로 자기 일을 짤 수 있는 형태로 적어 주세요."))
        }

        if variable.isEmpty {
            issues.append(.init(field: .openVariable, message: "지금 미확정인 것을 하나 적어 주세요. 정말 없으면 \"없음\"이라고 적으면 됩니다. 예고된 변수는 리스크가 아니지만, 예고 없이 나타난 변수는 리스크입니다."))
        } else if BroadcastPlanner.hasOpenVariable(c) && c.variableResolveDate == nil {
            issues.append(.init(field: .variableResolve, message: "그 변수가 언제 판명되는지 적어 주세요. 변수에 날짜가 붙으면 상대는 기다릴 수 있습니다."))
        }

        return issues
    }

    /// 통과했지만 더 하면 좋은 것 — 저장을 막지는 않는다.
    static func advisories(_ c: BroadcastPlanner.Contract) -> [BroadcastContractIssue] {
        var out: [BroadcastContractIssue] = []
        if !c.noSignalRuleAgreed {
            out.append(.init(message: "\"연락 없음 = 정상 진행\" 규칙을 아직 합의하지 않았습니다. 이 한 줄을 착수 시점에 못 박으면 중간 문의가 거의 사라집니다."))
        }
        if c.confidence == .low, BroadcastPlanner.hasOpenVariable(c) == false {
            out.append(.init(message: "확신도가 낮은데 미확정 변수가 없다고 되어 있습니다. 무엇이 불확실한지 짚어두면 나중에 설명할 일이 줄어듭니다."))
        }
        return out
    }
}
