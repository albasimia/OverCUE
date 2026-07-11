import OverCUECore
import SwiftUI

struct ShortcutListView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var expandedCategories: Set<RekordboxShortcutCategory> = [.deck1]
    private let modeOrder: [RekordboxMappingMode] = [.export, .performance]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            searchField
            captureStatus
            mappingSummary
            shortcutList
        }
        .padding(28)
        .onChange(of: model.selectedEntryID) { newValue in
            guard let newValue,
                  let entry = model.entries.first(where: { $0.id == newValue })
            else {
                return
            }
            expandedCategories.insert(.category(for: entry.commandID))
        }
    }

    @ViewBuilder
    private var captureStatus: some View {
        if let message = model.captureMessage {
            HStack(spacing: 10) {
                Image(systemName: model.isCapturing ? "keyboard.badge.ellipsis" : "checkmark.circle.fill")
                    .foregroundStyle(model.isCapturing ? Color.orange : Color.green)
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
                if model.isCapturing {
                    Button("キャンセル", action: model.cancelCapture)
                        .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 42)
            .background((model.isCapturing ? Color.orange : Color.green).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if let error = model.captureError {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .font(.subheadline)
                    .lineLimit(3)
                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 42)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ショートカット設定")
                .font(.largeTitle.bold())
                .lineLimit(1)

            HStack(alignment: .center, spacing: 14) {
                Spacer()

                HStack(spacing: 8) {
                    Text("モード")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Picker(
                        "",
                        selection: Binding(
                            get: { model.mode },
                            set: { newMode in model.setMode(newMode) }
                        )
                    ) {
                        ForEach(modeOrder) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                }

                Button(action: model.reloadAndRestartBridge) {
                    Label("再読み込み", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help("rekordboxのキーマッピングXMLを再読み込み")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("機能、キー、commandIdを検索", text: $model.searchText)
                .textFieldStyle(.plain)
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .frame(height: 40)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }

    private var mappingSummary: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.errorMessage == nil ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(model.mappingName)
                .font(.subheadline.weight(.semibold))
            Text("\(model.entries.count)件")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if let mappingURL = model.mappingURL {
                Text(mappingURL.lastPathComponent)
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var shortcutList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    if model.sections.isEmpty, model.errorMessage == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text("該当するショートカットがありません")
                                .font(.headline)
                            Text("検索条件を変更してください。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                    }

                    ForEach(model.sections) { section in
                        categorySection(section)
                    }
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            }
            .onChange(of: model.selectedEntryID) { selectedID in
                guard let selectedID else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }

    private func categorySection(_ section: ShortcutSection) -> some View {
        let isExpanded = !model.searchText.isEmpty || expandedCategories.contains(section.category)

        return VStack(spacing: 0) {
            Button {
                if expandedCategories.contains(section.category) {
                    expandedCategories.remove(section.category)
                } else {
                    expandedCategories.insert(section.category)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 14)
                    Text(section.category.rawValue)
                        .font(.headline)
                    Text("\(section.entries.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 16)
                .frame(height: 44)
            }
            .buttonStyle(.plain)

            if isExpanded {
                columnHeader
                ForEach(section.entries) { entry in
                    shortcutRow(entry)
                        .id(entry.id)
                }
            }

            Divider()
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 16) {
            Text("機能")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("rekordbox")
                .frame(width: 150, alignment: .leading)
            Text("ACK05 キーマップ")
                .frame(width: 190, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .frame(height: 32)
        .background(Color.white.opacity(0.035))
    }

    private func shortcutRow(_ entry: RekordboxShortcutEntry) -> some View {
        let selected = model.selectedEntryID == entry.id
        let configured = model.isConfigured(entry)
        let labels = model.bindingLabels(for: entry)

        return HStack(spacing: 16) {
            Button {
                model.select(entry)
            } label: {
                HStack(spacing: 16) {
                    HStack(spacing: 10) {
                        Image(systemName: configured ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(configured ? Color.accentColor : Color.secondary.opacity(0.35))
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.description.trimmingCharacters(in: .whitespacesAndNewlines))
                                .lineLimit(1)
                            Text(entry.commandID)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(entry.shortcut)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 7) {
                if labels.isEmpty {
                    Text("未設定")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ForEach(labels, id: \.self) { label in
                        Text(label)
                            .font(.caption.monospaced().weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                Spacer(minLength: 0)
                Button {
                    model.beginCapture(for: entry)
                } label: {
                    Image(systemName: model.editingEntryID == entry.id ? "keyboard.badge.ellipsis" : "square.and.pencil")
                        .foregroundStyle(model.editingEntryID == entry.id ? Color.orange : Color.accentColor)
                }
                .buttonStyle(.plain)
                .help("ACK05から入力してキーマップを変更")

                Button {
                    model.removeBindings(for: entry)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(configured ? Color.red : Color.secondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(!configured)
                .help("ACK05キーマップから削除")
            }
            .frame(width: 190, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .frame(height: 52)
        .contentShape(Rectangle())
        .background {
            if selected {
                Color.accentColor.opacity(0.24)
            } else if configured {
                Color.accentColor.opacity(0.075)
            } else {
                Color.clear
            }
        }
    }
}
