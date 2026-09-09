import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .japanese: "日本語"
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }
}

@MainActor
final class AppLocalization: ObservableObject {
    static let shared = AppLocalization()

    @Published private(set) var language: AppLanguage
    private var tables: [AppLanguage: [String: String]] = [:]

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage")
        language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .japanese
        for language in AppLanguage.allCases {
            tables[language] = Self.load(language: language)
        }
    }

    func setLanguage(_ language: AppLanguage) {
        guard self.language != language else { return }
        self.language = language
        UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        let format = tables[language]?[key]
            ?? tables[.english]?[key]
            ?? key
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }

    /// The Web UI consumes the same localization table as SwiftUI. A small set
    /// of Web-only UI labels is merged here so translated copy remains owned by
    /// the native localization boundary rather than duplicated in Vue.
    var currentTable: [String: String] {
        var table = tables[language] ?? tables[.english] ?? [:]
        let additions = Self.webInterfaceAdditions[language]
            ?? Self.webInterfaceAdditions[.english]
            ?? [:]
        table.merge(additions) { _, webValue in webValue }
        return table
    }

    private static let webInterfaceAdditions: [AppLanguage: [String: String]] = [
        .japanese: [
            "app.localAPI": "Local API",
            "common.close": "閉じる",
            "common.savingOrder": "並び順を保存中…",
            "common.active": "有効",
            "common.activate": "有効にする",
            "devices.connection": "接続",
            "groupPreset.assignments": "%d台のデバイス",
            "preset.reorder": "プリセットを並び替え",
            "preset.reorder.help": "ハンドルをドラッグしてプリセット順を変更します。",
            "shortcuts.learn": "Learn",
            "shortcuts.actions": "%d actions",
            "shortcuts.column.input": "入力",
        ],
        .english: [
            "app.localAPI": "Local API",
            "common.close": "Close",
            "common.savingOrder": "Saving order…",
            "common.active": "Active",
            "common.activate": "Activate",
            "devices.connection": "Connection",
            "groupPreset.assignments": "%d device assignments",
            "preset.reorder": "Reorder Presets",
            "preset.reorder.help": "Drag the handles to change Preset order.",
            "shortcuts.learn": "Learn",
            "shortcuts.actions": "%d actions",
            "shortcuts.column.input": "Input",
        ],
        .simplifiedChinese: [
            "app.localAPI": "Local API",
            "common.close": "关闭",
            "common.savingOrder": "正在保存顺序…",
            "common.active": "已启用",
            "common.activate": "启用",
            "devices.connection": "连接",
            "groupPreset.assignments": "%d 个设备分配",
            "preset.reorder": "重新排序预设",
            "preset.reorder.help": "拖动手柄以更改预设顺序。",
            "shortcuts.learn": "Learn",
            "shortcuts.actions": "%d 个操作",
            "shortcuts.column.input": "输入",
        ],
    ]

    private static func load(language: AppLanguage) -> [String: String] {
        let url = AppResources.bundle.url(
            forResource: language.rawValue,
            withExtension: "json",
            subdirectory: "Localization"
        ) ?? AppResources.bundle.url(forResource: language.rawValue, withExtension: "json")
        guard let url,
        let data = try? Data(contentsOf: url),
        let table = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            assertionFailure("Missing localization file for \(language.rawValue)")
            return [:]
        }
        return table
    }
}

@MainActor
enum L10n {
    static func text(_ key: String, _ arguments: CVarArg...) -> String {
        AppLocalization.shared.text(key, arguments)
    }
}

private extension AppLocalization {
    func text(_ key: String, _ arguments: [CVarArg]) -> String {
        let format = tables[language]?[key]
            ?? tables[.english]?[key]
            ?? key
        guard !arguments.isEmpty else { return format }
        return String(
            format: format,
            locale: Locale(identifier: language.rawValue),
            arguments: arguments
        )
    }
}
