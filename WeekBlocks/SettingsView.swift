import SwiftUI
import LeeoKit

/// 설정 화면 — iOS '욕망의 무지개'의 Form + Section 패턴을 macOS로 미러링.
struct SettingsView: View {
    /// 할 일 조언(TipKit) 다시 보기를 눌렀는지.
    @State private var tipsResetDone = false
    @Environment(\.dismiss) private var dismiss

    /// 일정 공유 시작·업데이트 시점의 최신 스냅숏을 만들어주는 클로저.
    var scheduleSnapshots: () -> [SharedScheduleSnapshot] = { [] }

    /// '처음 안내 다시 보기' — 부르는 쪽이 설정을 닫고 온보딩을 연다.
    var onReplayOnboarding: () -> Void = { }

    @AppStorage("hideSleepInTimeline") private var hideSleepInTimeline = false

    /// '지금 맞춰보기'를 눌렀는가 (한 번 누르면 더 누를 일이 없다).
    @State private var matchDone = false
    /// '다시 받아오기'가 예약됐는가. 실제 지우기는 다음 실행 때 일어난다.
    @State private var refetchArmed = false
    @State private var showingRefetchAlert = false

    /// 산 것을 되찾는 자리 (→ PaywallView.swift).
    @State private var purchases = PurchaseManager.shared
    @State private var showingPaywall = false

    /// 스토어를 세는 일은 화면을 그릴 때마다 할 일이 아니다 — 열 때 한 번, 누른 뒤 한 번.
    @State private var todoCount = 0
    @State private var categoryCount = 0

    private func refreshCounts() {
        todoCount = TodoStore.shared.allItems().count
        categoryCount = TodoStore.shared.categories().count
    }

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
                        refreshCounts()
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

                purchaseSection

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
                        onReplayOnboarding()
                    } label: {
                        Label("처음 안내 다시 보기", systemImage: "sparkles")
                    }

                    Text("한 주를 짜는 순서(고정 루틴 → 할 일 → 요일에 올리기)를 처음부터 다시 봅니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
        .task { refreshCounts() }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
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

    /// **지금 무엇을 쓰고 있는가, 그리고 산 것을 되찾는 자리.**
    ///
    /// 등급은 팔기 전에도 **언제나 보인다.** "내가 프로인가 무료인가"는 살 수 있는지와
    /// 상관없이 사람이 늘 궁금해하는 것이고, 문의가 왔을 때 서로 가리킬 자리도 필요하다.
    /// 살 수 있을 때만 사고·되찾는 단추가 붙는다 — 살 수도 없는 것의 단추는 고장으로 읽힌다.
    private var purchaseSection: some View {
        Section {
            HStack {
                Image(systemName: isPro ? "checkmark.seal.fill" : "leaf")
                    .foregroundStyle(isPro ? (Color(hex: Rainbow.indigo) ?? .indigo)
                                           : (Color(hex: Rainbow.green) ?? .green))
                Text("버전")
                Spacer()
                Text(isPro ? "프로" : "무료")
                    .foregroundStyle(isPro ? .primary : .secondary)
                    .fontWeight(isPro ? .semibold : .regular)
            }

            // ⚠️ 여기 거는 값은 `canEdit`이 아니라 **`canSync`**다.
            //    적기는 언제나 무료라 `canEdit`은 늘 참이고, 그걸 걸면 무료 사용자에게도
            //    영영 '열림'이라고만 말한다 (→ TodoAccess.swift).
            HStack {
                Text("아이폰으로 건너가기")
                Spacer()
                Text(TodoAccess.canSync ? "열림" : "잠김")
                    .foregroundStyle(.secondary)
            }

            if MacEntitlement.sellsAccess && !isPro {
                Button {
                    showingPaywall = true
                } label: {
                    Label("프로로 열기", systemImage: "arrow.left.arrow.right")
                }
            }

            if MacEntitlement.sellsAccess {
                Button {
                    Task { await purchases.restore() }
                } label: {
                    Label("구매 복원", systemImage: "arrow.clockwise")
                }
                .disabled(purchases.isWorking)

                if let message = purchases.failureMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Text(tierNote)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("함께 쓰기")
        }
    }

    /// 값을 치렀는가. `sellsAccess`가 꺼진 무료 개방 기간에는 건너가기가 열려 있어도
    /// 프로가 아니다 (→ MacEntitlement.swift의 `hasPurchased`).
    private var isPro: Bool { purchases.hasPurchased }

    private var tierNote: String {
        if isPro {
            return "여기서 적은 할 일이 아이폰에도 보입니다. 같은 Apple 계정의 다른 맥에서도 열립니다."
        }
        if MacEntitlement.sellsAccess {
            return "적는 데는 아무 지장이 없습니다. 주간 계획·루틴도, 아이폰에서 온 할 일을 보는 것도 무료입니다. 여기서 적은 것이 아이폰으로 건너가는 것만 프로입니다. 기기를 바꿨다면 복원으로 되찾습니다 — 다시 사지 않아도 됩니다."
        }
        return "지금은 모든 기능이 열려 있습니다. 판매를 시작해도 적는 것은 계속 무료이고, 여기서 적은 것이 아이폰으로 건너가는 것만 프로가 됩니다."
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
