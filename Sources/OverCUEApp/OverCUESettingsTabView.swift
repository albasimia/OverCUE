import SwiftUI

struct OverCUESettingsTabView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @EnvironmentObject private var localization: AppLocalization

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Text(localization.text("settings.title"))
                    .font(.largeTitle.bold())

                settingsSection(localization.text("settings.input.title")) {
                    Toggle(
                        localization.text("app.input.enable"),
                        isOn: Binding(
                            get: { model.isBridgeEnabled },
                            set: { model.setBridgeEnabled($0) }
                        )
                    )
                    Text(localization.text("settings.input.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsSection(localization.text("settings.language")) {
                    Picker(
                        localization.text("settings.language"),
                        selection: Binding(
                            get: { localization.language },
                            set: { localization.setLanguage($0) }
                        )
                    ) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.nativeName).tag(language)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    Text(localization.text("settings.language.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                settingsSection(localization.text("settings.rekordbox.title")) {
                    Button(action: model.reloadAndRestartBridge) {
                        Label(localization.text("shortcuts.reload"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    Text(localization.text("shortcuts.reload.help"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(32)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }
}
