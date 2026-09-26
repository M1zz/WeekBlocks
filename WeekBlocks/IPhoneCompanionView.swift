//
//  IPhoneCompanionView.swift
//  WeekBlocks
//
//  아이폰 '욕망의 무지개'를 소개하는 한 장 — 설정의 권유에서 들어온다.
//
//  맥은 **짜는 곳**, 아이폰은 **들여다보는 곳**이다. 한 주는 넓은 화면에서 짜지만,
//  "다음 일정이 뭐였지"는 대개 맥 앞이 아닐 때 궁금하다. 그때 같은 계획이 주머니에
//  이미 있다는 걸 알려 주는 자리다.
//
//  ⚠️ 아이폰 쪽 짝은 MacCompanionView(맥 앱 소개)다. 말투와 네 가지 짜임을 맞춰 둔다.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

struct IPhoneCompanionView: View {
    /// 아이폰 App Store의 '욕망의 무지개'.
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6755280882")!

    private static let accent = Color.indigo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                hero

                VStack(alignment: .leading, spacing: 24) {
                    ForEach(points) { point in
                        pointRow(point)
                    }
                }

                getIt
            }
            .padding(24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("아이폰에서 확인하기")
        // 스스로 들어와 읽었으면 설정 위의 권유는 할 일을 다 했다.
        .onAppear {
            IPhoneNudge.dismissed = true
            IPhoneNudge.bannerDismissed = true
        }
    }

    // MARK: - 머리

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Self.accent)
                .accessibilityHidden(true)

            Text("짜는 건 맥에서,\n확인은 아이폰에서")
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)

            Text("아이폰 앱 ‘욕망의 무지개’는 여기서 짠 한 주를 그대로 열어, 맥 앞이 아닐 때도 오늘 무엇이 남았는지 보여 줍니다.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 네 가지

    private struct Point: Identifiable {
        let icon: String
        let heading: String
        let body: String
        var id: String { icon }
    }

    private var points: [Point] {
        [
            Point(
                icon: "calendar.day.timeline.left",
                heading: String(localized: "주머니 속 오늘"),
                body: String(localized: "밖에 있을 때 다음 일정이 몇 시인지, 오늘 남은 시간이 얼마인지 아이폰을 꺼내 바로 봅니다.")
            ),
            Point(
                icon: "square.grid.2x2",
                heading: String(localized: "위젯으로 한눈에"),
                body: String(localized: "홈 화면과 잠금 화면 위젯에 지금 할 일과 번개 단계가 섭니다. 앱을 열지 않아도 됩니다. (아이폰 Pro)")
            ),
            Point(
                icon: "bolt.fill",
                heading: String(localized: "틈에는 번개"),
                body: String(localized: "5분이면 끝나는 단계는 아이폰의 번개로 바로 끝냅니다. 한쪽에서 끝내면 양쪽에서 끝납니다.")
            ),
            Point(
                icon: "icloud",
                heading: String(localized: "옮겨 적을 것이 없습니다"),
                body: String(localized: "같은 iCloud 계정이면 루틴·계획·할 일이 아이폰에 그대로 나타납니다.")
            )
        ]
    }

    private func pointRow(_ point: Point) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: point.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Self.accent)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(point.heading)
                    .font(.headline)
                Text(point.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 받는 법

    /// 아이폰 앱은 맥에서 설치할 수 없다. 그래서 **아이폰 카메라로 비추는** 문을 먼저 둔다 —
    /// 맥 화면 앞에서 아이폰을 들면 그대로 App Store가 열린다. 링크를 보내는 문은 그다음이다.
    private var getIt: some View {
        HStack(alignment: .center, spacing: 20) {
            if let qr = Self.qrImage {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 132, height: 132)
                    .padding(10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1))
                    )
                    .accessibilityLabel(Text("App Store로 가는 QR 코드"))
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("아이폰 카메라로 QR 코드를 비추거나, 링크를 아이폰으로 보내세요.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ShareLink(item: Self.appStoreURL) {
                    Label("아이폰으로 링크 보내기", systemImage: "square.and.arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Self.accent)

                Link(destination: Self.appStoreURL) {
                    Label("App Store에서 보기", systemImage: "arrow.up.right.square")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(Self.accent)
            }
        }
        .padding(.top, 4)
    }

    /// App Store 링크의 QR. 한 번 만들어 두고 쓴다.
    private static let qrImage: NSImage? = {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(appStoreURL.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width, height: output.extent.height))
    }()
}

// MARK: - 설정의 권유

/// 설정 위에 서는 한 줄 권유 — "아이폰에서 더 편하게 확인하세요".
///
/// 닫거나 소개 장을 한 번 읽으면 더 안 선다. 소개 장으로 가는 길은 '정보' 칸에 늘 남는다.
enum IPhoneNudge {
    static let dismissedKey = "iphoneNudge.dismissed"
    /// 쓰는 중에 서는 배너를 닫았는가. 설정의 줄과 따로 둔다 — 배너를 닫은 사람도 설정에서는 다시 찾을 수 있다.
    static let bannerDismissedKey = "iphoneNudge.bannerDismissed"

    static var dismissed: Bool {
        get { UserDefaults.standard.bool(forKey: dismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: dismissedKey) }
    }

    static var bannerDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: bannerDismissedKey) }
        set { UserDefaults.standard.set(newValue, forKey: bannerDismissedKey) }
    }

    /// 이만큼 계획을 세워 본 뒤에야 권한다. 처음 온 사람에게 다른 앱 이야기부터 하면 광고로 읽힌다 —
    /// 한 주를 몇 칸 채워 본 사람에게는 "이걸 밖에서도 보고 싶다"가 이미 생긴 뒤다.
    static let minPlannedBlocks = 5

    /// 쓰는 중에 배너를 세울 때인가.
    ///
    /// 이 설치본이 아닌 곳에서 적힌 계획·할 일이 하나라도 보이면 이미 아이폰(또는 다른 기기)을
    /// 쓰는 사람이라 권하지 않는다 (→ TodoSharing.installID). 스키마 표본은 사람의 기록이 아니다.
    static func shouldShowBanner(blocks: [PlanBlock], todos: [BacklogItem]) -> Bool {
        let me = TodoSharing.installID
        func fromElsewhere(_ id: String) -> Bool { !id.isEmpty && id != me && id != "schema-sample-install" }
        if blocks.contains(where: { fromElsewhere($0.originInstallID) })
            || todos.contains(where: { fromElsewhere($0.originInstallID) }) { return false }
        return blocks.count >= minPlannedBlocks
    }
}

/// **쓰는 중에 한 번 서는 권유.** 계획을 몇 칸 세운 뒤, 이 한 주를 아이폰에서도 볼 수 있다고 알린다.
struct IPhoneNudgeBanner: View {
    let onLearnMore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundStyle(Color.indigo)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("밖에서는 아이폰으로 더 쉽게 확인하세요")
                    .font(.headline)
                Text("짜 둔 이 한 주가 아이폰 앱 ‘욕망의 무지개’에 그대로 나타납니다. 다음 일정이 몇 시인지 주머니에서 바로 봅니다.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("알아보기", action: onLearnMore)
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(String(localized: "권유 닫기"))
            .accessibilityLabel(Text("권유 닫기"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.indigo.opacity(0.08), in: .soft(Corner.card))
    }
}

/// 배너의 '알아보기'로 여는 시트. 설정 밖이라 닫는 단추를 따로 단다.
struct IPhoneCompanionSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            IPhoneCompanionView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
        .frame(minWidth: 560, minHeight: 640)
    }
}

struct IPhoneNudgeRow: View {
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundStyle(Color.indigo)
                .frame(width: 32)
                .accessibilityHidden(true)

            NavigationLink {
                IPhoneCompanionView()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("아이폰에서 일정을 더 편하게 확인하세요")
                        .font(.body.weight(.semibold))
                    Text("여기서 짠 한 주가 아이폰 앱 ‘욕망의 무지개’에 그대로 나타납니다.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(String(localized: "권유 닫기"))
            .accessibilityLabel(Text("권유 닫기"))
        }
        .padding(.vertical, 4)
    }
}
