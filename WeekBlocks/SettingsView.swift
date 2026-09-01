import SwiftUI
import LeeoKit

/// 설정 화면 — iOS '욕망의 무지개'의 Form + Section 패턴을 macOS로 미러링.
struct SettingsView: View {
    /// 할 일 조언(TipKit) 다시 보기를 눌렀는지.
    @State private var tipsResetDone = false
    @Environment(\.dismiss) private var dismiss

    /// 일정 공유 시작·업데이트 시점의 최신 스냅숏을 만들어주는 클로저.
    var scheduleSnapshots: () -> [SharedScheduleSnapshot] = { [] }

    @AppStorage("hideSleepInTimeline") private var hideSleepInTimeline = false

    /// '지금 맞춰보기'를 눌렀는가 (한 번 누르면 더 누를 일이 없다).
    @State private var matchDone = false
    /// '다시 받아오기'가 예약됐는가. 실제 지우기는 다음 실행 때 일어난다.
    @State private var refetchArmed = false
    @State private var showingRefetchAlert = false

    private var todoCount: Int { TodoStore.shared.allItems().count }
    private var categoryCount: Int { TodoStore.shared.categories().count }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("설정")
                    .font(.title3.weight(.medium))
                Spacer()
            }
            .padding(20)

            Divider()

            NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("주 시작")
                        Spacer()
                        Text("월요일")
                            .foregroundStyle(.secondary)
                    }
                    Text("ISO 8601 기준으로 주를 계산합니다. 지역 설정이 바뀌어도 월요일 시작이 유지됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("주간 계획")
                }

                Section {
                    Toggle("타임라인에서 수면 시간 숨기기", isOn: $hideSleepInTimeline)
                } header: {
                    Text("요일별 하루")
                } footer: {
                    Text("하루 양끝의 수면 시간을 잘라내 남은 시간을 더 넓게 봅니다. 이름에 '수면·잠·취침'이 들어간 고정 루틴을 수면으로 봅니다. 잘라낼 자리에 다른 일정이 걸쳐 있으면 그 일정이 보이도록 범위를 도로 넓힙니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        ruleRow("활동", "3자 이상")
                        ruleRow("성공 기준", "10자 이상 · 모호한 표현 금지")
                        ruleRow("산출물", "5자 이상")
                    }
                    .padding(.vertical, 2)
                } header: {
                    Text("구체성 검사")
                } footer: {
                    Text("💡 세 가지를 모두 통과해야 블록을 저장할 수 있습니다.")
                }

                Section {
                    HStack {
                        Image(systemName: "icloud")
                            .foregroundStyle(Color(hex: Rainbow.blue) ?? .blue)
                        Text("iCloud 동기화")
                        Spacer()
                        Text("켜짐")
                            .foregroundStyle(.secondary)
                    }
                    Text("같은 iCloud 계정의 기기끼리 자동으로 동기화됩니다. (공유 컨테이너: ScheduleDensity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // 자동 동기화가 조용히 멈추는 일이 있다. 그때 손으로 당길 길을 둔다.
                    HStack {
                        Text("지금 할 일")
                        Spacer()
                        Text("\(todoCount)개 · 분류 \(categoryCount)개")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    Button {
                        TodoStore.shared.reconcileWithArchive()
                        matchDone = true
                    } label: {
                        Label(matchDone ? "맞춰봤습니다" : "지금 맞춰보기", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(matchDone)

                    Text("떠 둔 벌과 iCloud가 준 벌 중 **더 최근에 손댄 쪽**을 세웁니다. 겹친 할 일도 함께 정리합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button(role: .destructive) {
                        showingRefetchAlert = true
                    } label: {
                        Label("iCloud에서 다시 받아오기", systemImage: "icloud.and.arrow.down")
                    }
                    .disabled(refetchArmed)

                    Text(refetchArmed
                         ? "앱을 다시 켜면 iCloud에서 처음부터 받아옵니다."
                         : "이 기기의 사본을 버리고 iCloud에 있는 것을 처음부터 다시 받습니다. 루틴·계획도 함께 다시 받습니다. 버리기 전에 지금 할 일을 파일로 떠 두므로, iCloud에 없는 할 일은 뒤이어 되살아납니다.")
                        .font(.caption)
                        .foregroundStyle(refetchArmed ? Color.orange : .secondary)
                } header: {
                    Text("iCloud")
                }

                ScheduleShareSettingsSection(snapshotsProvider: scheduleSnapshots)

                Section {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("패밀리")
                        Spacer()
                        Text("욕망의 무지개 · 무지개 공방")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("정보")
                }

                Section {
                    Button {
                        TodoTips.resetAll()
                        tipsResetDone = true
                    } label: {
                        Label(tipsResetDone ? "다시 보기로 바꿨습니다" : "할 일 조언 다시 보기",
                              systemImage: tipsResetDone ? "checkmark.circle.fill" : "lightbulb")
                    }
                    .disabled(tipsResetDone)

                    Text("할 일 화면에서 닫았던 조언(라벨·비중·쪼개기 팁)을 처음부터 다시 봅니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("조언")
                }

                DeveloperContactSection()

                Section {
                    LeeoSupportSection<WeekBlocksSpec>()
                } header: {
                    Text("피드백 & 리뷰")
                }
            }
            .formStyle(.grouped)
            }

            Divider()

            HStack {
                Spacer()
                Button("완료") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(minWidth: 460, minHeight: 540)
        .alert("iCloud에서 다시 받아올까요?", isPresented: $showingRefetchAlert) {
            Button("취소", role: .cancel) { }
            Button("다시 받아오기", role: .destructive) {
                TodoStore.shared.requestRefetchFromCloud()
                refetchArmed = true
            }
        } message: {
            Text("이 기기의 사본(루틴·계획·할 일)을 버리고 iCloud에 있는 것을 처음부터 받습니다.\n버리기 전에 지금 할 일을 파일로 떠 두므로, iCloud에 없는 할 일은 다음 실행에서 되살아납니다.\n\n앱을 다시 켜야 실제로 받아옵니다.")
        }
    }

    private func ruleRow(_ field: String, _ rule: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(field)
                .font(.callout.weight(.medium))
                .frame(width: 72, alignment: .leading)
            Text(rule)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 개발자 문의
struct DeveloperContactSection: View {
    var body: some View {
        Section {
            Link(destination: URL(string: "mailto:leeo@kakao.com")!) {
                Label("이메일로 문의하기", systemImage: "envelope")
            }
            Link(destination: URL(string: "https://instagram.com/lee25_ios")!) {
                Label("인스타그램 DM (@lee25_ios)", systemImage: "paperplane")
            }
        } header: {
            Text("개발자에게 문의")
        } footer: {
            Text("버그 제보와 기능 제안을 환영합니다.")
        }
    }
}
