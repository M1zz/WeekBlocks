//
//  AppLanguage.swift
//  WeekBlocks
//
//  **앱 안에서 고르는 언어.**
//
//  맥은 시스템 설정 > 일반 > 언어 및 지역 > 응용 프로그램에서 앱마다 언어를 고를 수 있지만,
//  거기까지 찾아가는 사람은 드물다. 한국어를 못 읽는 사람이 한국어 화면에 떨어지면 설정 단추조차
//  못 읽는다 — "Default Korean, cannot find an option to select English." 그래서 앱 안에 두고,
//  **글자는 늘 두 말로** 적는다 (Language · 언어). 무엇을 고르는 자리인지 어느 쪽이든 읽혀야 한다.
//
//  고른 값은 시스템 설정의 앱별 언어와 **같은 자리**(이 앱의 AppleLanguages)에 적는다.
//  그래서 어느 쪽에서 바꿔도 서로 맞는다. 언어는 앱이 켜질 때 정해지므로 다시 열어야 바뀐다.
//

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"

    var id: String { rawValue }

    /// 각 언어는 **그 언어로** 적는다 — 번역하면 못 읽는 사람이 자기 말을 못 찾는다.
    var name: String {
        switch self {
        case .system:  "System · 시스템 설정"
        case .english: "English"
        case .korean:  "한국어"
        }
    }

    private static let key = "AppleLanguages"

    /// 이 앱에 따로 골라 둔 언어. 없으면 시스템을 따른다.
    static var chosen: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let first = (domain?[key] as? [String])?.first else { return .system }
        if first.hasPrefix("ko") { return .korean }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// 고르고 곧바로 다시 연다. 반쯤 바뀐 화면(메뉴는 영어, 창은 한국어)을 보여 주지 않는다.
    func applyAndRelaunch() {
        guard self != Self.chosen else { return }
        switch self {
        case .system: UserDefaults.standard.removeObject(forKey: Self.key)
        default:      UserDefaults.standard.set([rawValue], forKey: Self.key)
        }
        UserDefaults.standard.synchronize()

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// 메뉴 막대(앱 이름 메뉴)와 설정이 함께 쓰는 고르개.
/// 설정 단추를 못 읽는 사람도 맥 앱이면 늘 있는 앱 메뉴는 연다.
struct AppLanguageMenu: View {
    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    lang.applyAndRelaunch()
                } label: {
                    if lang == AppLanguage.chosen {
                        Label(lang.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: lang.name)
                    }
                }
            }
        } label: {
            Label { Text(verbatim: "Language · 언어") } icon: { Image(systemName: "globe") }
        }
    }
}
