//
//  TodoSplitAdvisor.swift
//
//  할 일을 단계로 쪼갤 때 옆에서 훈수를 두는 순수 로직.
//
//  근거는 조각 시간(fragmented time) 연구들이다. 사용자가 감으로 쪼개는 대신
//  "이 단계는 5분에 집을 수 있는가 / 덩어리를 지켜야 하는가"를 앱이 말해준다.
//
//  판정은 **두 질문**으로만 이루어진다 (→ FragmentQuestion).
//    하나. 시동 없이 바로 시작할 수 있는가.   ← 아니면 조각에서 시동만 걸다 끝난다.
//    둘.   조각 안에서 완전히 끝나는가.       ← 아니면 잔여물이 다음 시간까지 따라온다.
//  둘 다 '예'인 단계만 조각이다. 답은 앱이 낱말과 시간으로 먼저 적어두고,
//  사용자는 틀렸을 때만 뒤집는다 (→ FragmentPick, BacklogItem+Fragment.swift).
//  이름표 하나로 답을 주던 옛 '착수 조건'과 다른 점이 여기다 — 답이 아니라
//  **묻는 문장**을 보여주기 때문에, 틀렸다는 것도 사용자가 알아볼 수 있다.
//
//  - 타임 컨페티 (Schulte 2014, Whillans 2020)
//    5분 × 12 ≠ 60분. 조각은 총량으로 환산되지 않는다 → 조각용 단계가 따로 있어야 한다.
//  - 주의 잔여물 (Leroy 2009, Leroy & Schmidt 2016)
//    끝내지 못하고 넘어간 일은 다음 시간까지 오염시킨다 → 단계는 '닫히는' 크기여야 한다.
//  - 중단·재개 비용 (Mark et al. 2008)
//    중단된 작업 복귀에 평균 23분. 시동 비용 > 조각 크기면 수확은 0이다.
//  - 몸은 조각으로 된다 (Stamatakis 2022 VILPA) / 머리는 안 된다 (Albulescu 2022)
//    신체 활동만 1~2분 조각으로도 축적된다.
//
//  ⚠️ 이 파일은 iOS('욕망의 무지개')와 macOS('무지개 공방') 두 레포에 **같은 내용으로**
//     복제돼 있다. 한쪽을 고치면 다른 쪽도 반드시 같이 고칠 것.
//

import Foundation

// MARK: - 단계의 성질

/// 이 단계를 언제 하는 게 맞는가.
enum ChunkKind: String {
    /// 조각 — 5~15분이 생기면 바로 집어서 끝낼 수 있다.
    case fragment
    /// 짧은 덩어리 — 앉아야 하지만 한 자리에서 끝난다.
    case short
    /// 덩어리 — 시동 비용이 커서 지킨 시간에 배정해야 한다.
    case block

    var label: String {
        switch self {
        case .fragment: return "조각"
        case .short:    return "짧은 덩어리"
        case .block:    return "덩어리"
        }
    }

    /// 목록에서 "지금 5분 있는데 뭘 하지"에 답할 수 있는 단계인가.
    var isPickableInFragment: Bool { self == .fragment }
}

// MARK: - 조각에 넣어도 되는지를 가르는 두 질문

/// 판정을 사람이 따라올 수 있는 두 물음으로 쪼갠 것.
///
/// 예전에는 '바로/펼치고/몰입해서' 같은 이름표 하나로 답을 줬는데, 그 이름표가
/// 무슨 뜻인지가 안 통했다. 이름표를 없앤 자리에 **묻는 문장 그대로**를 둔다.
/// 답은 앱이 먼저 적어두고, 사용자는 틀렸을 때만 뒤집는다 (→ FragmentPick).
enum FragmentQuestion: String, CaseIterable, Identifiable {
    /// 하나 — 시동 없이 바로 시작할 수 있는가.
    case start
    /// 둘 — 조각 안에서 완전히 끝나는가.
    case closing

    var id: String { rawValue }

    /// 화면에 그대로 나가는 물음.
    var text: String {
        switch self {
        case .start:   return "시동 없이 바로 시작되나요?"
        case .closing: return "5분 안에 끝까지 가나요?"
        }
    }

    /// 왜 이걸 묻는지 한 줄. (물음 아래 작게)
    var why: String {
        switch self {
        case .start:
            return "맥락을 다시 읽어 와야 하는 일은 조각에서 시동만 걸다 끝납니다."
        case .closing:
            return "끝나지 않은 일은 잔여물이 되어 그다음 덩어리 시간까지 갉아먹습니다."
        }
    }

    /// 근거 표기.
    var source: String {
        switch self {
        case .start:   return "Mark 2008"
        case .closing: return "Leroy 2009"
        }
    }
}

/// 사용자가 두 질문에 직접 답한 것. 비어 있으면 앱 판정을 그대로 쓴다.
///
/// 저장은 `BacklogItem.fragmentPick` (→ BacklogItem+Fragment.swift). 여기서는
/// 저장 방식을 모르는 순수 값으로만 다룬다.
struct FragmentPick: Equatable {
    /// 질문 하나에 대한 사용자의 답. nil이면 앱 판정을 쓴다.
    var start: Bool?
    /// 질문 둘에 대한 사용자의 답. nil이면 앱 판정을 쓴다.
    var closing: Bool?

    static let none = FragmentPick(start: nil, closing: nil)

    var isSet: Bool { start != nil || closing != nil }

    func answer(to question: FragmentQuestion) -> Bool? {
        switch question {
        case .start:   return start
        case .closing: return closing
        }
    }

    mutating func set(_ value: Bool?, for question: FragmentQuestion) {
        switch question {
        case .start:   start = value
        case .closing: closing = value
        }
    }
}

/// 단계 하나에 대한 조언.
struct StepAdvice {
    let kind: ChunkKind
    /// 왜 그렇게 봤는지 한 줄. 없으면 시간만 보고 판단한 것.
    let reason: String?
    /// 이 단계에 붙는 경고 (있으면 화면에서 눈에 띄게).
    let warning: Warning?
    /// 질문 하나 — 시동 없이 바로 시작할 수 있는가.
    let start: Answer
    /// 질문 둘 — 조각 안에서 완전히 끝나는가.
    let closing: Answer

    struct Warning {
        let message: String
        /// 근거 표기 ("Mark 2008" 등).
        let source: String
    }

    /// 두 질문 각각에 대한 답. 앱이 먼저 답하고, 사용자가 뒤집으면 `isUserSet`이 된다.
    struct Answer {
        let isYes: Bool
        /// 왜 그렇게 봤는지 한 줄. 사용자가 읽고 틀렸다고 판단할 수 있어야 한다.
        let reason: String
        /// 사용자가 직접 답한 것인가.
        var isUserSet: Bool = false
    }

    func answer(to question: FragmentQuestion) -> Answer {
        switch question {
        case .start:   return start
        case .closing: return closing
        }
    }

    /// 두 질문에 모두 '예'인 단계만 조각이다.
    var isFragment: Bool { kind.isPickableInFragment }

    /// 판정 결과를 한 줄로. (시트 아래, 목록 표식의 말)
    var verdict: String {
        switch kind {
        case .fragment:
            return "조각입니다. 5분이 나면 이걸 집으면 됩니다."
        case .short:
            return "짧은 덩어리입니다. 앉아야 하지만 한 자리에서 끝납니다."
        case .block:
            return "덩어리입니다. 지켜 둔 시간에 두세요."
        }
    }
}

/// 할 일 전체 구성에 대한 조언.
struct SplitHint: Identifiable {
    enum Tone { case good, caution, info }

    let id = UUID()
    /// 조언 종류를 가리키는 고정된 이름. 화면에는 안 나오고 팁 id로 쓴다 —
    /// 사용자가 한 종류를 닫으면 그 종류만 다시 안 뜨게 하기 위해서.
    let code: String
    let tone: Tone
    let title: String
    let detail: String
    /// 근거 표기. 없으면 앱의 규칙.
    let source: String?
}

// MARK: - 판정기

enum TodoSplitAdvisor {

    /// 조각으로 쳐주는 최대 시간 (15분).
    static let fragmentMaxHours = 0.25
    /// 여기부터는 지킨 시간이 필요한 덩어리 (45분).
    static let blockMinHours = 0.75
    /// 한 단계가 이보다 크면 한 자리에서 안 닫힌다 (2시간).
    static let tooBigHours = 2.0

    // 제목에서 성질을 읽어내는 낱말들. 완벽한 분류가 목적이 아니라,
    // 사용자가 스스로 알아채도록 건드리는 게 목적이다.

    /// 시동 비용이 큰 일 — 조각에 넣으면 시동만 걸다 끝난다.
    static let blockWords = [
        "쓰기", "작성", "글", "원고", "구현", "코딩", "개발", "설계", "리팩터", "리팩토링",
        "디자인", "기획", "전략", "분석", "조사", "학습", "공부", "이해", "정리하기",
        "녹화", "편집", "만들기", "제작", "번역", "논문", "발표자료", "기능"
    ]

    /// 결과가 정해져 있어 바로 닫히는 일.
    static let fragmentWords = [
        "보내기", "발송", "제출", "발행", "업로드", "공유하기", "답장", "회신", "승인",
        "예약", "확인", "체크", "결제", "신청", "등록", "캡처", "메모", "적기", "기록",
        "복습", "암기", "카드", "고르기", "선택", "전화", "문자", "주문",
        "올리기", "게시", "포스팅", "모아두기", "챙기기"
    ]

    /// 몸으로 하는 일 — 조각으로도 실제로 축적된다 (VILPA).
    static let bodyWords = [
        "운동", "스트레칭", "걷기", "산책", "계단", "달리기", "러닝", "요가", "청소",
        "설거지", "빨래", "정리정돈", "환기"
    ]

    /// 탐색이 필요해 조각 안에서 닫히지 않는 일.
    static let decisionWords = [
        "정하기", "결정", "고민", "검토", "판단", "선정", "구상", "아이디어 내기"
    ]

    /// 일이 아니라 조각이 새는 곳.
    static let drainWords = [
        "sns", "유튜브", "인스타", "피드", "쇼츠", "릴스", "스크롤", "웹서핑", "눈팅"
    ]

    /// 끝을 닫는 마감 동작 — 마지막 단계에 이게 있으면 잔여물이 남지 않는다.
    static let closingWords = [
        "보내기", "발송", "제출", "발행", "업로드", "공유하기", "배포", "커밋", "머지",
        "마무리", "제출하기", "회신", "답장", "결제", "청구", "올리기", "게시", "포스팅"
    ]

    // MARK: 단계 하나 판정

    /// 단계 하나를 두 질문으로 판정한다.
    ///
    /// `pick`은 사용자가 직접 뒤집은 답(→ `BacklogItem.fragmentPick`). 앱의 판정보다 세다 —
    /// 낱말 사전은 남의 일에 대해서는 자주 틀리고, 틀린 판정을 못 고치면 판정 전체를 안 믿게 된다.
    static func advice(title: String,
                       durationHours: Double,
                       pick: FragmentPick = .none) -> StepAdvice
    {
        let text = normalize(title)

        let looksDrain    = contains(text, drainWords)
        let looksBody     = contains(text, bodyWords)
        let looksBlock    = contains(text, blockWords)
        let looksFragment = contains(text, fragmentWords)
        let looksDecision = contains(text, decisionWords)
        let looksClosing  = contains(text, closingWords)

        // 질문 하나 — 시동 없이 바로 시작할 수 있는가.
        var start: StepAdvice.Answer = {
            if looksDecision {
                return .init(isYes: false, reason: "안 정한 것이 먼저 막고 있습니다.")
            }
            if looksBlock {
                return .init(isYes: false, reason: "어디까지 했는지 다시 읽어 와야 시작됩니다.")
            }
            if looksBody {
                return .init(isYes: true, reason: "몸으로 하는 일이라 시동이 없습니다.")
            }
            if looksFragment || looksClosing {
                return .init(isYes: true, reason: "할 것이 정해져 있어 바로 손이 갑니다.")
            }
            return .init(isYes: true, reason: "앞에서 막고 있는 것이 안 보입니다.")
        }()

        // 질문 둘 — 조각 안에서 완전히 끝나는가.
        var closing: StepAdvice.Answer = {
            // 몸으로 하는 일만은 나눠 해도 쌓인다 (VILPA). 크기로 자르지 않는다.
            if looksBody {
                return .init(isYes: true, reason: "몸으로 하는 일은 나눠 해도 쌓입니다.")
            }
            if looksDrain {
                return .init(isYes: false, reason: "끝이 정해져 있지 않아 안 닫힙니다.")
            }
            if durationHours >= tooBigHours {
                return .init(isYes: false, reason: "\(formatHours(durationHours))짜리입니다. 한 자리에서도 안 닫힙니다.")
            }
            if durationHours > fragmentMaxHours {
                return .init(isYes: false, reason: "\(formatHours(durationHours))짜리라 조각에 안 들어갑니다.")
            }
            if looksBlock {
                return .init(isYes: false, reason: "짧게 잡아 두어도 여기서 끝나지는 않습니다.")
            }
            if looksDecision {
                return .init(isYes: false, reason: "뭘 할지 고르는 동안 조각이 끝납니다.")
            }
            if looksClosing || looksFragment {
                return .init(isYes: true, reason: "끝이 정해져 있어 여기서 닫힙니다.")
            }
            if durationHours <= 0 {
                return .init(isYes: true, reason: "시간을 안 잡은 줄이라 조각에 들어갑니다.")
            }
            return .init(isYes: true, reason: "\(formatHours(durationHours))짜리라 조각 안에 들어갑니다.")
        }()

        // 사용자가 답한 것이 있으면 그 자리만 갈아 끼운다.
        if let yes = pick.start {
            start = .init(isYes: yes, reason: "직접 정한 답입니다.", isUserSet: true)
        }
        if let yes = pick.closing {
            closing = .init(isYes: yes, reason: "직접 정한 답입니다.", isUserSet: true)
        }

        let kind = self.kind(start: start, closing: closing, durationHours: durationHours)
        let reason = self.reason(kind: kind, start: start, closing: closing)

        return StepAdvice(kind: kind,
                          reason: reason,
                          warning: warning(kind: kind,
                                           durationHours: durationHours,
                                           looksDrain: looksDrain,
                                           looksBlock: looksBlock,
                                           looksDecision: looksDecision,
                                           pick: pick),
                          start: start,
                          closing: closing)
    }

    /// 두 질문의 답에서 성질이 나온다. **둘 다 '예'여야 조각이다.**
    private static func kind(start: StepAdvice.Answer,
                             closing: StepAdvice.Answer,
                             durationHours: Double) -> ChunkKind
    {
        if start.isYes && closing.isYes { return .fragment }
        // 시동이 필요하면 크기와 상관없이 지켜 둔 시간에 놓아야 한다.
        if !start.isYes || durationHours >= blockMinHours { return .block }
        return .short
    }

    private static func reason(kind: ChunkKind,
                               start: StepAdvice.Answer,
                               closing: StepAdvice.Answer) -> String?
    {
        switch kind {
        case .fragment: return nil
        case .short, .block: return start.isYes ? closing.reason : start.reason
        }
    }

    /// 경고는 두 답이 갈렸을 때만 낸다. 판정 자체(조각/덩어리)는 표식이 이미 말하고 있다.
    private static func warning(kind: ChunkKind,
                                durationHours: Double,
                                looksDrain: Bool,
                                looksBlock: Bool,
                                looksDecision: Bool,
                                pick: FragmentPick) -> StepAdvice.Warning?
    {
        // 사용자가 직접 답한 자리에는 훈수를 두지 않는다.
        if pick.isSet { return nil }

        if looksDrain {
            return .init(message: "이건 할 일이 아니라 조각이 새어 나가는 곳입니다. 단계로 두면 진행률만 부풉니다.",
                         source: "배수구")
        }
        // 시동 비용이 큰 일을 조각 시간에 욱여넣은 경우.
        if looksBlock && durationHours <= fragmentMaxHours {
            return .init(message: "다시 붙잡는 데만 평균 23분이 듭니다. 조각에 넣으면 시동만 걸다 끝나니, 시간을 늘리거나 덩어리 시간에 두세요.",
                         source: "Mark 2008")
        }
        // 아직 안 정해진 일은 조각 안에서 닫히지 않는다.
        if looksDecision && durationHours < blockMinHours {
            return .init(message: "뭘 할지 고르는 동안 조각이 끝납니다. 결정은 덩어리에서 하고, 정해진 것만 조각 단계로 보내세요.",
                         source: "판정 기준 3")
        }
        // 한 자리에서 안 닫히는 크기.
        if durationHours >= tooBigHours {
            return .init(message: "한 번에 못 끝내는 크기입니다. 끝이 닫히도록 더 쪼개지 않으면 '하다 만 상태'가 다음 시간까지 따라옵니다.",
                         source: "Leroy 2009")
        }
        return nil
    }

    /// 조언 문장에 넣을 시간 표기. (화면의 formatDuration과 달리 로직 파일 안에서 쓴다)
    private static func formatHours(_ hours: Double) -> String {
        let minutes = Int((max(0, hours) * 60).rounded())
        if minutes < 60 { return "\(minutes)분" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h)시간" : "\(h)시간 \(m)분"
    }

    // MARK: 구성 전체 판정

    /// 단계 구성을 보고 주는 조언. `steps`는 잎(실제로 하는 단계)들을 진행 순서대로.
    static func hints(rootTitle: String, steps: [(title: String, hours: Double)]) -> [SplitHint] {
        hints(rootTitle: rootTitle, steps: steps.map { ($0.title, $0.hours, FragmentPick.none) })
    }

    /// 사용자가 뒤집은 답까지 반영해서 보는 판. 구성 조언도 그 답을 따라야 한다 —
    /// 한쪽에서 '조각'이라고 해 놓고 다른 쪽에서 "조각이 없습니다"라고 하면 둘 다 안 믿게 된다.
    static func hints(rootTitle: String,
                      steps: [(title: String, hours: Double, pick: FragmentPick)]) -> [SplitHint]
    {
        guard !steps.isEmpty else {
            return [SplitHint(
                code: "before-split",
                tone: .info,
                title: "쪼개기 전에 한 가지",
                detail: "조각 시간은 총량으로 환산되지 않습니다. 5분 열두 번은 60분이 아닙니다. 그래서 '5분이 생겼을 때 집을 수 있는 단계'와 '지킨 시간에만 하는 단계'를 처음부터 나눠 두는 편이 낫습니다.",
                source: "Schulte 2014 · Whillans 2020")]
        }

        var result: [SplitHint] = []
        let advices = steps.map { advice(title: $0.title, durationHours: $0.hours, pick: $0.pick) }

        // 1. 조각용 단계가 하나도 없다.
        if !advices.contains(where: { $0.kind.isPickableInFragment }) {
            result.append(SplitHint(
                code: "no-fragment",
                tone: .caution,
                title: "5분이 생겼을 때 집을 단계가 없습니다",
                detail: "모든 단계가 자리를 잡아야 하는 크기입니다. 자료 모아두기·한 줄 메모처럼 조각에서 닫히는 단계를 하나 만들어두면, 흘려보내던 틈이 이 할 일에 쓰입니다.",
                source: "Whillans 2020"))
        }

        // 2. 마지막이 닫히지 않는다.
        if let last = steps.last, !contains(normalize(last.title), closingWords) {
            result.append(SplitHint(
                code: "no-closing",
                tone: .caution,
                title: "마지막을 닫는 단계가 없습니다",
                detail: "'보내기·발행하기·제출하기'처럼 끝을 닫는 단계를 마지막에 두세요. 90% 끝난 일의 마지막 10%는 조각의 가장 좋은 용도이고, 닫아두면 그 뒤의 덩어리 시간까지 깨끗해집니다.",
                source: "Leroy 2009"))
        }

        // 3. 한 자리에서 안 닫히는 단계.
        let tooBig = steps.filter { $0.hours >= tooBigHours }
        if let first = tooBig.first {
            result.append(SplitHint(
                code: "too-big",
                tone: .caution,
                title: "‘\(first.title)’은(는) 한 번에 안 끝납니다",
                detail: tooBig.count > 1
                    ? "\(tooBig.count)개 단계가 2시간을 넘습니다. 끝이 닫히는 크기로 더 쪼개세요. 하다 만 단계는 다음 시간까지 주의를 끌고 갑니다."
                    : "끝이 닫히는 크기로 더 쪼개세요. 하다 만 단계는 다음 시간까지 주의를 끌고 갑니다.",
                source: "Leroy 2009"))
        }

        // 4. 시동 비용 경고 (개별 단계에서 이미 뜨지만, 개수가 많으면 구성 문제다).
        let startupIssues = zip(steps, advices).filter { $0.1.warning?.source == "Mark 2008" }
        if startupIssues.count >= 2 {
            result.append(SplitHint(
                code: "startup-cost",
                tone: .caution,
                title: "짧게 잡힌 덩어리 작업이 \(startupIssues.count)개 있습니다",
                detail: "글쓰기·구현·설계처럼 맥락을 다시 불러와야 하는 일은 조각 크기로 잡아두면 시동만 걸다 끝납니다. 시간을 늘리거나, 그 앞에 '준비' 조각 단계를 따로 두세요.",
                source: "Mark 2008"))
        }

        // 5. 결정이 안 끝난 채로 작업이 먼저 온다.
        if let decisionIndex = steps.firstIndex(where: { contains(normalize($0.title), decisionWords) }),
           let workIndex = steps.firstIndex(where: { contains(normalize($0.title), blockWords) }),
           decisionIndex > workIndex {
            result.append(SplitHint(
                code: "decision-late",
                tone: .caution,
                title: "결정이 작업 뒤에 있습니다",
                detail: "‘\(steps[decisionIndex].title)’이(가) ‘\(steps[workIndex].title)’보다 뒤입니다. 정해지지 않은 채 시작한 작업은 조각에서도 덩어리에서도 닫히지 않습니다. 결정 단계를 앞으로 옮기세요.",
                source: "판정 기준 3"))
        }

        // 6. 잘 쪼갠 경우엔 그렇다고 말해준다.
        if result.isEmpty {
            let fragmentCount = advices.filter { $0.kind.isPickableInFragment }.count
            result.append(SplitHint(
                code: "well-split",
                tone: .good,
                title: "조각과 덩어리가 나뉘어 있습니다",
                detail: "조각에서 집을 수 있는 단계가 \(fragmentCount)개, 지킨 시간에 할 단계가 \(advices.count - fragmentCount)개입니다. 5분이 생기면 조각 단계를, 확보한 시간에는 덩어리 단계를 하시면 됩니다.",
                source: nil))
        }

        return result
    }

    // MARK: 쪼개기 도우미 (기본 뼈대)

    struct TemplateStep {
        let title: String
        let note: String
    }

    /// 아직 단계가 없을 때 제안하는 기본 뼈대.
    /// 일이 굴러가는 순서대로다 — 정하고 → 펼치고 → 몰입해서 → 바로.
    static func template(for rootTitle: String) -> [TemplateStep] {
        let name = rootTitle.trimmingCharacters(in: .whitespaces)
        let subject = name.isEmpty ? "이 일" : name
        return [
            TemplateStep(title: "무엇을 할지 정하기",
                         note: "안 정해진 게 남아 있으면 아래 단계가 전부 안 열립니다."),
            TemplateStep(title: "필요한 것 모아두기",
                         note: "링크·자료를 펼쳐만 둡니다. 본 작업의 시동 비용을 여기서 미리 냅니다."),
            TemplateStep(title: "\(subject) 실제로 하기",
                         note: "끊기면 다시 올라와야 합니다. 방해 없는 시간에 두세요."),
            TemplateStep(title: "마무리해서 보내기",
                         note: "끝을 닫는 단계. 짬이 나면 바로 집을 수 있습니다."),
        ]
    }

    // MARK: 내부

    private static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private static func contains(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0.replacingOccurrences(of: " ", with: "")) }
    }
}
