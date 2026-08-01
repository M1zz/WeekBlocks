import Foundation
import SwiftData

// MARK: - 전파 계약을 가질 수 있는 것
//
// 백로그 항목(BacklogItem)과 계획 블록(PlanBlock) 둘 다 전파 계약을 가진다.
// 백로그 항목을 요일에 드롭하면 블록으로 바뀌는데, 그때 계약이 사라지면
// 대상·두 날짜·넘길 형태·이미 보낸 시점 기록이 전부 날아가고 복구할 방법이 없다.
// 그래서 양쪽이 같은 필드를 갖고, 계산 로직은 이 파일 한 곳에만 둔다.
//
// SwiftData는 저장 프로퍼티를 클래스 본체에 요구하므로 필드 선언 자체는 양쪽에 있지만,
// 접근자·플래너 연결·검사는 전부 아래 익스텐션이 담당한다. (구현이 갈라지지 않게)

protocol BroadcastContractHolder: PersistentModel {
    var title: String { get }
    /// 착수 시점 — 역산의 출발점.
    var createdAt: Date { get }
    /// 이 항목이 속한 주 (월요일 00:00). 데드라인 초기값 제안에 쓴다.
    var weekStartDate: Date { get }

    var needsBroadcast: Bool { get set }
    var deadline: Date? { get set }
    var broadcastAudienceRaw: String { get set }
    var broadcastRecipient: String { get set }
    var handoffForm: String { get set }
    var earliestDate: Date? { get set }
    var latestDate: Date? { get set }
    var broadcastConfidenceRaw: String { get set }
    var openVariable: String { get set }
    var variableResolveDate: Date? { get set }
    var noSignalRuleAgreed: Bool { get set }
    var broadcastContractVerified: Bool { get set }
    var sentCheckpointsRaw: String { get set }
}

// MARK: 접근자 (양쪽 공용)

extension BroadcastContractHolder {

    var broadcastAudience: BroadcastAudience {
        get { BroadcastAudience(rawValue: broadcastAudienceRaw) ?? .decisionMaker }
        set { broadcastAudienceRaw = newValue.rawValue }
    }

    var broadcastConfidence: BroadcastConfidence {
        get { BroadcastConfidence(rawValue: broadcastConfidenceRaw) ?? .medium }
        set { broadcastConfidenceRaw = newValue.rawValue }
    }

    /// 이미 보낸 전파 시점들.
    var doneCheckpointTokens: Set<String> {
        get {
            Set(sentCheckpointsRaw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        }
        set { sentCheckpointsRaw = newValue.sorted().joined(separator: ",") }
    }

    func markCheckpoint(_ token: String, done: Bool) {
        var tokens = doneCheckpointTokens
        if done { tokens.insert(token) } else { tokens.remove(token) }
        doneCheckpointTokens = tokens
    }

    /// 이 항목의 전파 계약을 플래너 입력으로 변환.
    var broadcastContract: BroadcastPlanner.Contract {
        BroadcastPlanner.Contract(
            title: title,
            audience: broadcastAudience,
            recipient: broadcastRecipient,
            handoffForm: handoffForm,
            deadline: deadline,
            earliest: earliestDate,
            latest: latestDate,
            confidence: broadcastConfidence,
            openVariable: openVariable,
            variableResolveDate: variableResolveDate,
            noSignalRuleAgreed: noSignalRuleAgreed,
            startedAt: createdAt
        )
    }

    /// 데드라인에서 역산한 전파 시점들.
    var broadcastCheckpoints: [BroadcastCheckpoint] {
        guard needsBroadcast else { return [] }
        return BroadcastPlanner.checkpoints(for: broadcastContract, doneTokens: doneCheckpointTokens)
    }

    /// 아직 보내지 않은 가장 이른 전파 시점.
    var nextBroadcastCheckpoint: BroadcastCheckpoint? {
        broadcastCheckpoints.first { !$0.isDone }
    }

    /// 전파 계약 전처리를 아직 통과하지 못했는가.
    var broadcastContractIncomplete: Bool {
        needsBroadcast && !BroadcastContractChecker.validate(broadcastContract).isEmpty
    }

    /// 오늘 또는 이미 지난 전파 시점이 있는가 — 배지 판단용.
    var hasBroadcastActionDue: Bool {
        guard let next = nextBroadcastCheckpoint else { return false }
        return BroadcastPlanner.dayCount(from: Date(), to: next.date) <= 0
    }

    /// 계약 내용을 다른 소유자에게 그대로 넘긴다.
    /// 백로그 항목 → 계획 블록 변환에서 쓴다. 보낸 시점 기록까지 함께 옮겨야
    /// 이미 보낸 전파를 다시 보내라고 하지 않는다.
    func copyBroadcastContract(to other: some BroadcastContractHolder) {
        other.needsBroadcast = needsBroadcast
        other.deadline = deadline
        other.broadcastAudienceRaw = broadcastAudienceRaw
        other.broadcastRecipient = broadcastRecipient
        other.handoffForm = handoffForm
        other.earliestDate = earliestDate
        other.latestDate = latestDate
        other.broadcastConfidenceRaw = broadcastConfidenceRaw
        other.openVariable = openVariable
        other.variableResolveDate = variableResolveDate
        other.noSignalRuleAgreed = noSignalRuleAgreed
        other.broadcastContractVerified = broadcastContractVerified
        other.sentCheckpointsRaw = sentCheckpointsRaw
    }

    /// 드롭 경고에 쓸 요약 — 무엇이 함께 옮겨지는지 사람이 읽는 문장.
    var broadcastCarryOverSummary: String {
        var parts: [String] = []
        let who = broadcastRecipient.trimmingCharacters(in: .whitespaces)
        parts.append(who.isEmpty ? broadcastAudience.shortLabel : "\(who) (\(broadcastAudience.shortLabel))")
        if let promise = BroadcastPlanner.promiseDate(broadcastContract) {
            parts.append("약속 \(BroadcastPlanner.dateLabel(promise))")
        }
        let sentCount = doneCheckpointTokens.count
        let remaining = broadcastCheckpoints.filter { !$0.isDone }.count
        if sentCount > 0 { parts.append("보낸 전파 \(sentCount)건") }
        if remaining > 0 { parts.append("남은 전파 \(remaining)건") }
        if !broadcastContractVerified { parts.append("계약 미확정") }
        return parts.joined(separator: " · ")
    }
}
