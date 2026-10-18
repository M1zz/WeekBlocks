//
//  PreflightReportView.swift
//  WeekBlocks (무지개 공방)
//
//  **개발자 화면 ▸ Preflight.** LeeoKit 이 계약(`WeekBlocksSpec`)을 읽어 출시하면 안 되는 상태를
//  찾아 준다 — 파는데 페이월로 갈 길이 없음, https 아닌 정책 주소, 분석 싱크 없음, 부트스트랩 안 부름,
//  원격 스위치 없음 같은 것. 단위 시험(`WeekBlocksSpecTests`)이 같은 것을 지키지만, 시험은 개발 맥에서만
//  돈다. 이 화면은 **실제로 깔린 빌드**(TestFlight·심사판)가 무엇을 켰는지까지 본다(`runtimeAudit`).
//
//  설정 ▸ 사용 통계에서 개발자 모드(버전 일곱 번 누르기)를 켠 사람에게만 보인다.
//  개발자만 읽는 화면이라 번역하지 않는다 — LeeoKit 의 진단 문구도 한 언어다.
//

import SwiftUI
import LeeoKit

struct PreflightReportView: View {
    @State private var issues: [LeeoPreflightIssue] = []

    var body: some View {
        Form {
            Section {
                Label {
                    Text(verbatim: issues.isReleasable ? "Releasable" : "Not releasable — \(issues.errors.count) error(s)")
                        .font(.headline)
                } icon: {
                    Image(systemName: issues.isReleasable ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(issues.isReleasable ? Color.green : Color.red)
                }
            }
            Section {
                if issues.isEmpty {
                    Text(verbatim: "No issues")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: "\(issue.severity.symbol) \(issue.code)")
                            .font(.callout.monospaced().weight(.semibold))
                        Text(verbatim: issue.message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text(verbatim: "LeeoPreflight.runtimeAudit")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text(verbatim: "Preflight"))
        .task { issues = LeeoPreflight.runtimeAudit(WeekBlocksSpec.self) }
    }
}
