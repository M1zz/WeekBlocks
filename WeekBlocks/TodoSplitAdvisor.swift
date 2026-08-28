//
//  TodoSplitAdvisor.swift
//
//  할 일을 단계로 쪼갤 때 옆에서 훈수를 두는 순수 로직.
//
//  근거는 조각 시간(fragmented time) 연구들이다. 사용자가 감으로 쪼개는 대신
//  "이 단계는 5분에 집을 수 있는가 / 덩어리를 지켜야 하는가"를 앱이 말해준다.
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

/// 단계 하나에 대한 조언.
struct StepAdvice {
    let kind: ChunkKind
    /// 왜 그렇게 봤는지 한 줄. 없으면 시간만 보고 판단한 것.
    let reason: String?
    /// 이 단계에 붙는 경고 (있으면 화면에서 눈에 띄게).
    let warning: Warning?

    struct Warning {
        let message: String
        /// 근거 표기 ("Mark 2008" 등).
        let source: String
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
        "복습", "암기", "카드", "고르기", "선택", "전화", "문자", "주문"
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
        "마무리", "제출하기", "회신", "답장", "결제", "청구"
    ]

    // MARK: 단계 하나 판정

    static func advice(title: String, durationHours: Double) -> StepAdvice {
        let text = normalize(title)

        if contains(text, drainWords) {
            return StepAdvice(
                kind: .fragment,
                reason: "조각이 새는 곳",
                warning: .init(message: "이건 할 일이 아니라 조각이 새어 나가는 곳입니다. 단계로 두면 진행률만 부풀립니다.",
                               source: "배수구")
            )
        }

        if contains(text, bodyWords) {
            return StepAdvice(
                kind: .fragment,
                reason: "몸으로 하는 일",
                warning: nil
            )
        }

        let looksBlock = contains(text, blockWords)
        let looksFragment = contains(text, fragmentWords)
        let looksDecision = contains(text, decisionWords)

        // 시동 비용이 큰 일을 조각 시간에 욱여넣은 경우.
        if looksBlock && durationHours <= fragmentMaxHours {
            return StepAdvice(
                kind: .block,
                reason: "시동 비용이 큰 일",
                warning: .init(message: "다시 붙잡는 데만 평균 23분이 듭니다. 조각에 넣으면 시동만 걸다 끝나니, 시간을 늘리거나 덩어리 시간에 두세요.",
                               source: "Mark 2008")
            )
        }

        // 아직 안 정해진 일은 조각 안에서 닫히지 않는다.
        if looksDecision && durationHours < blockMinHours {
            return StepAdvice(
                kind: .short,
                reason: "결정이 필요한 일",
                warning: .init(message: "뭘 할지 고르는 동안 조각이 끝납니다. 결정은 덩어리에서 하고, 정해진 것만 조각 단계로 보내세요.",
                               source: "판정 기준 3")
            )
        }

        // 한 자리에서 안 닫히는 크기.
        if durationHours >= tooBigHours {
            return StepAdvice(
                kind: .block,
                reason: nil,
                warning: .init(message: "한 번에 못 끝내는 크기입니다. 끝이 닫히도록 더 쪼개지 않으면 '하다 만 상태'가 다음 시간까지 따라옵니다.",
                               source: "Leroy 2009")
            )
        }

        if looksFragment && durationHours <= blockMinHours {
            return StepAdvice(kind: .fragment, reason: "결과가 정해진 일", warning: nil)
        }
        if looksBlock {
            return StepAdvice(kind: .block, reason: "시동 비용이 큰 일", warning: nil)
        }

        // 낱말로 못 읽으면 시간만 본다.
        if durationHours <= fragmentMaxHours { return StepAdvice(kind: .fragment, reason: nil, warning: nil) }
        if durationHours >= blockMinHours { return StepAdvice(kind: .block, reason: nil, warning: nil) }
        return StepAdvice(kind: .short, reason: nil, warning: nil)
    }

    // MARK: 구성 전체 판정

    /// 단계 구성을 보고 주는 조언. `steps`는 잎(실제로 하는 단계)들을 진행 순서대로.
    ///
    /// `label`은 **사용자가 직접 고른 착수 조건**이다. 조각이냐 덩어리냐, 결정이 어디에
    /// 있느냐는 이 값이 정한다 — 제목 낱말로 다시 짐작하지 않는다.
    /// 고르라고 해놓고 앱이 낱말 사전으로 뒤엎으면, '바로'라고 말해 둔 단계를 앞에 두고도
    /// "5분에 집을 단계가 없습니다"라는 소리를 듣게 된다.
    ///
    /// 낱말 사전은 이제 **경고**에만 쓴다 — 제목과 시간이 서로 어긋날 때
    /// ("원고 쓰기"에 15분처럼) 알려주는 자리다. 그건 라벨이 답할 수 없는 물음이라서다.
    static func hints(rootTitle: String,
                      steps: [(title: String, hours: Double, label: TodoLabel)]) -> [SplitHint] {
        guard !steps.isEmpty else {
            return [SplitHint(
                code: "before-split",
                tone: .info,
                title: "쪼개기 전에 한 가지",
                detail: "조각 시간은 총량으로 환산되지 않습니다. 5분 열두 번은 60분이 아닙니다. 그래서 '5분이 생겼을 때 집을 수 있는 단계'와 '지킨 시간에만 하는 단계'를 처음부터 나눠 두는 편이 낫습니다.",
                source: "Schulte 2014 · Whillans 2020")]
        }

        var result: [SplitHint] = []
        // 낱말 판정은 경고에만 쓴다 (아래 4번). 조각/덩어리 구분은 라벨이 이미 답했다.
        let advices = steps.map { advice(title: $0.title, durationHours: $0.hours) }

        // 1. 조각용 단계가 하나도 없다. (판정은 사용자가 고른 조건으로 — '기다림'은 빼고)
        if !steps.contains(where: { $0.label.isPickableInFragment }) {
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
        //    '정하고'·'몰입해서'를 고른 자리가 먼저다. 라벨을 안 고른 옛 항목만 낱말로 짚는다.
        let decisionIndex = steps.firstIndex { $0.label == .decide }
            ?? steps.firstIndex { contains(normalize($0.title), decisionWords) }
        let workIndex = steps.firstIndex { $0.label == .deep }
            ?? steps.firstIndex { contains(normalize($0.title), blockWords) }
        if let decisionIndex, let workIndex, decisionIndex > workIndex {
            result.append(SplitHint(
                code: "decision-late",
                tone: .caution,
                title: "결정이 작업 뒤에 있습니다",
                detail: "‘\(steps[decisionIndex].title)’이(가) ‘\(steps[workIndex].title)’보다 뒤입니다. 정해지지 않은 채 시작한 작업은 조각에서도 덩어리에서도 닫히지 않습니다. 결정 단계를 앞으로 옮기세요.",
                source: "판정 기준 3"))
        }

        // 6. 잘 쪼갠 경우엔 그렇다고 말해준다.
        if result.isEmpty {
            let fragmentCount = steps.filter { $0.label.isPickableInFragment }.count
            result.append(SplitHint(
                code: "well-split",
                tone: .good,
                title: "조각과 덩어리가 나뉘어 있습니다",
                detail: "조각에서 집을 수 있는 단계가 \(fragmentCount)개, 지킨 시간에 할 단계가 \(steps.count - fragmentCount)개입니다. 5분이 생기면 조각 단계를, 확보한 시간에는 덩어리 단계를 하시면 됩니다. 두 몫은 서로 환산되지 않으니 더해서 보지 마세요.",
                source: nil))
        }

        return result
    }

    // MARK: 쪼개기 도우미 (기본 뼈대)

    struct TemplateStep {
        let title: String
        /// 이 단계의 착수 조건. 시간에서 짐작하지 않고 여기서 못박는다 —
        /// 뼈대는 각 단계가 무슨 성격인지 이미 알고 있고, 시간으로 되짚으면
        /// "무엇을 할지 정하기"에 '펼치고'가 붙는 식으로 어긋난다.
        let label: TodoLabel
        let note: String
    }

    /// 아직 단계가 없을 때 제안하는 기본 뼈대.
    /// 일이 굴러가는 순서대로다 — 정하고 → 펼치고 → 몰입해서 → 바로.
    static func template(for rootTitle: String) -> [TemplateStep] {
        let name = rootTitle.trimmingCharacters(in: .whitespaces)
        let subject = name.isEmpty ? "이 일" : name
        return [
            TemplateStep(title: "무엇을 할지 정하기",
                         label: .decide,
                         note: "안 정해진 게 남아 있으면 아래 단계가 전부 안 열립니다."),
            TemplateStep(title: "필요한 것 모아두기",
                         label: .setup,
                         note: "링크·자료를 펼쳐만 둡니다. 본 작업의 시동 비용을 여기서 미리 냅니다."),
            TemplateStep(title: "\(subject) 실제로 하기",
                         label: .deep,
                         note: "끊기면 다시 올라와야 합니다. 방해 없는 시간에 두세요."),
            TemplateStep(title: "마무리해서 보내기",
                         label: .ready,
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

// MARK: - 라벨 (일을 적을 때 고르는 타입)

/// 할 일·단계를 적으면서 한 번에 고르는 '이건 어떤 타입인가'.
///
/// 묻는 것은 '얼마나 걸리나'가 아니라 **'지금 시작할 수 있나'**다.
/// 단계를 실제로 하느냐 마느냐를 가르는 건 그 단계가 전체의 몇 %냐가 아니라,
/// 손을 대기 전에 남아 있는 것이 무엇이냐이기 때문이다.
///
/// - 바로     GTD의 next action 4조건을 통과한 상태 — 물리적 동작이고, 한 번에 닫히고,
///           구체적이고, 먼저 해야 할 것이 없다.
/// - 펼치고   활성화 에너지. 시작에 드는 힘이 이어가는 힘보다 크다.
/// - 몰입해서 재개 지연(평균 23분). 비용은 방해 자체가 아니라 맥락 재구성이다.
/// - 정하고   "정하다"는 next action이 아니다. 안 닫힌 결정이 다음 단계를 막는다.
/// - 기다림   기다림은 막힘이 아니다. 내 손을 떠난 일은 내 목록에서 주의를 갉으면 안 된다.
///
/// 고르는 순간 예상 시간도 함께 정해진다 — 시간을 따로 묻지 않고도 모든 단계가
/// 시간을 갖게 하는 장치다. 상위 할 일의 시간은 단계들의 합이다 (→ TodoTree.swift).
enum TodoLabel: String, CaseIterable, Identifiable, Sendable {
    /// 지금 손에 잡히는 것만으로 끝난다. 먼저 해야 할 것도, 정할 것도 남아 있지 않다.
    case ready
    /// 자료·도구를 펼쳐야 시작된다. 시작만 하면 쉬운데, 그 시작이 무겁다.
    case setup
    /// 끊기면 처음부터 다시 올라와야 한다. 조각 시간에 집으면 수확이 없다.
    case deep
    /// 아직 정하지 않은 것이 있어 손이 안 나간다. 정하는 것 자체가 이 단계의 일이다.
    case decide
    /// 내 손을 떠나 있다. 상대의 답이 와야 움직인다.
    case waiting

    var id: String { rawValue }

    /// 칩에 쓰는 이름.
    ///
    /// **조건을 그대로 말한다.** 예전에는 "바로 / 펼치고 / 몰입해서"처럼 동사 토막이었는데,
    /// 옆에 시간이 붙으면 "바로 15분"이 되어 무슨 말인지 알 수 없었다. 쪼개는 사람이
    /// 골라야 하는 건 '지금 시작할 수 있느냐'이므로, 그 답을 문장으로 적는다.
    var name: String {
        switch self {
        case .ready:   return "바로 가능"
        case .setup:   return "준비가 필요"
        case .deep:    return "몰입이 필요"
        case .decide:  return "결정이 필요"
        case .waiting: return "답을 기다림"
        }
    }

    /// 이름만으로 부족할 때 한 줄 더. 고르는 자리(메뉴·공유 시트)에서 쓴다.
    var pickHint: String {
        switch self {
        case .ready:   return "지금 손에 잡히는 것만으로 끝나요"
        case .setup:   return "자료·도구를 펼쳐야 시작돼요"
        case .deep:    return "끊기면 처음부터 다시 올라와야 해요"
        case .decide:  return "아직 안 정한 게 있어 손이 안 나가요"
        case .waiting: return "내 손을 떠나 있어요"
        }
    }

    /// 왜 그 속성인지 한 줄.
    var hint: String {
        switch self {
        case .ready:   return "지금 손에 잡히는 것만으로 끝납니다. 짬이 나면 집으세요."
        case .setup:   return "자료·도구를 펼쳐야 시작됩니다. 시작만 하면 쉽습니다."
        case .deep:    return "끊기면 처음부터 다시 올라와야 합니다. 방해 없는 시간에 두세요."
        case .decide:  return "아직 정하지 않은 것이 있어 시작이 안 됩니다. 이 단계의 일은 정하는 것입니다."
        case .waiting: return "내 손을 떠나 있습니다. 상대의 답이 와야 움직입니다."
        }
    }

    /// 이 속성을 고르면 잡히는 예상 시간.
    /// '기다림'은 0이다 — 달력에서 시간이 흐를 뿐 내가 쓰는 시간이 아니다.
    var defaultHours: Double {
        switch self {
        case .ready:   return 0.25
        case .setup:   return 0.5
        case .deep:    return 1
        case .decide:  return 0.5
        case .waiting: return 0
        }
    }

    /// 내 시간을 쓰는 단계인가. '기다림'만 아니다.
    var costsMyTime: Bool { self != .waiting }

    /// **언제 하면 되는가.** 속성을 고르는 값어치가 여기 있다 —
    /// "이건 펼치고 30분짜리"라는 사실 자체는 쓸모가 없고,
    /// "준비할 짬이 났을 때 하세요"가 되어야 손이 움직인다.
    var whenToDo: String {
        switch self {
        case .ready:   return "짬이 나면 바로"
        case .setup:   return "자료를 펼칠 짬이 났을 때"
        case .deep:    return "방해 없는 시간이 잡혔을 때"
        case .decide:  return "머리가 맑을 때 먼저"
        case .waiting: return "상대의 답이 오면"
        }
    }

    var symbol: String {
        switch self {
        case .ready:   return "bolt.fill"
        case .setup:   return "folder.fill"
        case .deep:    return "scope"
        case .decide:  return "arrow.triangle.branch"
        case .waiting: return "hourglass"
        }
    }

    /// 조각이냐 덩어리냐 — 기존 판정기와 이어 붙이는 자리.
    var kind: ChunkKind {
        switch self {
        case .ready:           return .fragment
        case .setup, .decide:  return .short
        case .deep:            return .block
        case .waiting:         return .fragment   // 내 시간을 안 쓰므로 언제든 걸쳐 둘 수 있다
        }
    }

    /// 5분이 생겼을 때 집을 수 있는 속성인가.
    var isPickableInFragment: Bool { self == .ready }

    /// 저장된 값에서 속성을 읽는다.
    ///
    /// 속성이 '얼마나 걸리나'(지금 바로 / 앉아서 한 번 / 집중 한 판 / 시간 잡고 / 반나절)였던
    /// 시절의 값도 여기서 받아 준다. 그때 값은 크기만 말했으므로 착수 조건으로 옮겨 읽는다.
    /// 실제 배정 시간은 `durationHours`에 따로 들어 있어 이 변환으로 사라지지 않는다.
    static func resolve(_ raw: String) -> TodoLabel? {
        if let value = TodoLabel(rawValue: raw) { return value }
        switch raw {
        case "now":                       return .ready
        case "sit":                       return .setup
        case "focus", "block", "halfDay": return .deep
        default:                          return nil
        }
    }

    /// 예상 시간에서 가장 가까운 속성. 속성을 고르기 전에 만들어진 옛 데이터를 위해.
    /// '기다림'은 시간이 0이라 시간만으로는 짐작할 수 없으므로 후보에서 뺀다.
    static func nearest(toHours hours: Double) -> TodoLabel {
        allCases
            .filter(\.costsMyTime)
            .min { abs($0.defaultHours - hours) < abs($1.defaultHours - hours) } ?? .deep
    }
}
