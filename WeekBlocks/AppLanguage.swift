//
//  AppLanguage.swift
//  WeekBlocks
//
//  **앱 안에서 고르는 언어.**
//
//  맥은 시스템 설정 > 일반 > 언어 및 지역 > 응용 프로그램에서 앱마다 언어를 고를 수 있지만,
//  거기까지 찾아가는 사람은 드물다. 한국어를 못 읽는 사람이 한국어 화면에 떨어지면 설정 단추조차
//  못 읽는다 — "Default Korean, cannot find an option to select English." 그래서 앱 안에 두고,
//  **글자는 늘 여러 말로** 적는다 (Language · 언어 · 語言). 무엇을 고르는 자리인지 어느 쪽이든 읽혀야 한다.
//  語言은 번체지만 간체를 쓰는 사람도 읽는다 — 글자를 더 늘리면 메뉴가 길어진다.
//  고르는 목록의 언어 이름은 저마다 그 언어로 적는다(Deutsch, 日本語 …). 1.1.10 부터 23개.
//
//  고른 값은 시스템 설정의 앱별 언어와 **같은 자리**(이 앱의 AppleLanguages)에 적는다.
//  그래서 어느 쪽에서 바꿔도 서로 맞는다. 언어는 앱이 켜질 때 정해지므로 다시 열어야 바뀐다.
//

import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case korean = "ko"
    case chineseTraditional = "zh-Hant"
    case chineseSimplified = "zh-Hans"
    case japanese = "ja"
    case german = "de"
    case spanish = "es"
    case french = "fr"
    case italian = "it"
    case portugueseBrazil = "pt-BR"
    case russian = "ru"
    case czech = "cs"
    case danish = "da"
    case greek = "el"
    case finnish = "fi"
    case indonesian = "id"
    case norwegian = "nb"
    case dutch = "nl"
    case polish = "pl"
    case swedish = "sv"
    case thai = "th"
    case turkish = "tr"
    case vietnamese = "vi"

    var id: String { rawValue }

    /// 각 언어는 **그 언어로** 적는다 — 번역하면 못 읽는 사람이 자기 말을 못 찾는다.
    var name: String {
        switch self {
        case .system:  "System · 시스템 설정"
        case .english: "English"
        case .korean:  "한국어"
        case .chineseTraditional: "繁體中文"
        case .chineseSimplified:  "简体中文"
        case .japanese:   "日本語"
        case .german:     "Deutsch"
        case .spanish:    "Español"
        case .french:     "Français"
        case .italian:    "Italiano"
        case .portugueseBrazil: "Português (Brasil)"
        case .russian:    "Русский"
        case .czech:      "Čeština"
        case .danish:     "Dansk"
        case .greek:      "Ελληνικά"
        case .finnish:    "Suomi"
        case .indonesian: "Bahasa Indonesia"
        case .norwegian:  "Norsk bokmål"
        case .dutch:      "Nederlands"
        case .polish:     "Polski"
        case .swedish:    "Svenska"
        case .thai:       "ไทย"
        case .turkish:    "Türkçe"
        case .vietnamese: "Tiếng Việt"
        }
    }

    private static let key = "AppleLanguages"

    /// 이 앱에 따로 골라 둔 언어. 없으면 시스템을 따른다.
    static var chosen: AppLanguage {
        let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
        guard let first = (domain?[key] as? [String])?.first else { return .system }
        // 시스템 설정의 앱별 언어는 zh-TW·zh-HK·zh-CN·pt-BR·nb-NO 처럼 지역을 붙여 적기도 한다.
        if ["zh-Hant", "zh-TW", "zh-HK", "zh-MO"].contains(where: first.hasPrefix) { return .chineseTraditional }
        if ["zh-Hans", "zh-CN", "zh-SG"].contains(where: first.hasPrefix) { return .chineseSimplified }
        if first.hasPrefix("pt") { return .portugueseBrazil }
        if first.hasPrefix("nb") || first.hasPrefix("no") || first.hasPrefix("nn") { return .norwegian }
        let language = first.split(separator: "-").first.map(String.init) ?? first
        if let match = AppLanguage(rawValue: language), match != .system { return match }
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
            Label { Text(verbatim: "Language · 언어 · 語言") } icon: { Image(systemName: "globe") }
        }
    }
}
