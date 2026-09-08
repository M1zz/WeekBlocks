import Foundation

struct ConcretenessIssue: Identifiable, Hashable {
    let id = UUID()
    let message: String
}

enum ConcretenessChecker {

    /// Vague tokens that block a "pass". Match as substrings since Korean
    /// doesn't have word boundaries the way English does.
    private static let vagueTokens: [String] = [
        "열심히", "노력", "대충", "적당히", "조금", "많이", "그냥", "어느 정도"
    ]

    /// The same idea in English. Written in lower case — the text is folded
    /// before matching. Wrapped in spaces at match time so "some" doesn't
    /// fire on "something".
    private static let vagueWordsEN: [String] = [
        "hard", "properly", "well", "a bit", "a little", "a lot", "some",
        "roughly", "somewhat", "better", "more", "improve", "just", "try",
        "as much as possible", "enough", "decent", "good"
    ]

    /// "잘" is tricky because "잘하다" / "잘 보내다" are vague but "잘못", "잘라",
    /// "잘하는 사람" might be legitimate compounds. Treat "잘" as vague only when
    /// it stands alone as a particle (followed by space/punct/end).
    private static let standaloneJal = #"잘(?=\s|[.,!?]|$)"#

    static func validate(title: String,
                         successCriteria: String,
                         deliverable: String) -> [ConcretenessIssue]
    {
        var issues: [ConcretenessIssue] = []
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = successCriteria.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = deliverable.trimmingCharacters(in: .whitespacesAndNewlines)

        if t.count < 3 {
            issues.append(.init(message: String(localized: "활동을 좀 더 구체적으로 적어 주세요. (\"공부\"보다 \"Combine 학습\"처럼)")))
        }

        if c.count < 10 {
            issues.append(.init(message: String(localized: "성공 기준이 너무 짧습니다. 무엇으로 측정할지 적어 주세요.")))
        } else if let vague = firstVagueToken(in: c) {
            issues.append(.init(message: String(localized: "성공 기준에 \"\(vague)\" 같은 모호한 표현이 있습니다. 측정 가능한 문장으로 적어 주세요.")))
        }

        if d.count < 5 {
            issues.append(.init(message: String(localized: "산출물 — 끝났을 때 손에 남는 것 — 을 적어 주세요.")))
        }

        return issues
    }

    private static func firstVagueToken(in text: String) -> String? {
        for token in vagueTokens where text.contains(token) {
            return token
        }
        if text.range(of: standaloneJal, options: .regularExpression) != nil {
            return "잘"
        }
        // 영어로 적은 문장도 같은 잣대로 본다. 낱말 경계를 붙여야
        // "some"이 "something"에, "well"이 "wellness"에 걸리지 않는다.
        let padded = " " + text.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current) + " "
        for word in vagueWordsEN where padded.contains(" \(word) ") {
            return word
        }
        return nil
    }
}
