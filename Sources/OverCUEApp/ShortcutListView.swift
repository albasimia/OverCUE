import OverCUECore
import SwiftUI

struct ShortcutListView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @StateObject private var genericHIDModel = GenericHIDShortcutCaptureModel()
    @EnvironmentObject private var localization: AppLocalization
    @State private var expandedCategories: Set<RekordboxShortcutCategory> = [.deck1]
    @State private var isOverCUEExpanded = true
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
        .onAppear {
            genericHIDModel.reload(shortcutModel: model)
        }
        .onChange(of: model.selectedGroup) { _ in
            // Learn pins the editor Preset selected at session start.
            guard !genericHIDModel.isCapturing else { return }
            genericHIDModel.reload(shortcutModel: model)
        }
        .onChange(of: model.selectedEntryID) { newValue in
            guard let newValue,
                  let entry = model.entries.first(where: { $0.id == newValue })
            else {
                return
            }
            expandedCategories.insert(.category(for: entry.commandID))
        }
        .onDisappear {
            if genericHIDModel.isCapturing {
                genericHIDModel.cancelUnifiedCapture(shortcutModel: model)
            }
        }
    }

    @ViewBuilder
    private var captureStatus: some View {
        if model.isCapturing || genericHIDModel.isCapturing {
            HStack(spacing: 10) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .foregroundStyle(.secondary)
                Text(genericHIDModel.captureMessage ?? model.captureMessage ?? L10n.text("message.waitingInput"))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                Spacer()
                Button(localization.text("common.cancel")) {
                    if genericHIDModel.isCapturing {
                        genericHIDModel.cancelUnifiedCapture(shortcutModel: model)
                    } else {
                        model.cancelCapture()
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 42)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else if let error = genericHIDModel.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localization.text("shortcuts.title"))
                .font(.largeTitle.bold())
                .lineLimit(1)

            HStack(alignment: .center, spacing: 14) {
                Spacer()

                HStack(spacing: 8) {
                    Text(localization.text("shortcuts.mode"))
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

                Button {
                    model.reloadAndRestartBridge()
                    genericHIDModel.reload(shortcutModel: model)
                } label: {
                    Label(localization.text("shortcuts.reload"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(localization.text("shortcuts.reload.help"))
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(localization.text("shortcuts.search"), text: $model.searchText)
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
            Text(localization.text("shortcuts.count", model.entries.count))
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
                    if !model.filteredInternalEntries.isEmpty {
                        overCUESection
                    }

                    if model.sections.isEmpty, model.filteredInternalEntries.isEmpty,
                       model.errorMessage == nil {
                        VStack(spacing: 12) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 34))
                                .foregroundStyle(.secondary)
                            Text(localization.text("shortcuts.empty"))
                                .font(.headline)
                            Text(localization.text("shortcuts.empty.help"))
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

    private var overCUESection: some View {
        let isExpanded = !model.searchText.isEmpty || isOverCUEExpanded
        return VStack(spacing: 0) {
            Button {
                isOverCUEExpanded.toggle()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 14)
                    Image(systemName: "slider.horizontal.3")
                    Text(localization.text("shortcuts.overcue"))
                        .font(.headline)
                    Text("\(model.filteredInternalEntries.count)")
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
                ForEach(model.filteredInternalEntries) { entry in
                    shortcutRow(entry)
                        .id(entry.id)
                }
            }
            Divider()
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
                    Text(categoryName(section.category))
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
            Text(localization.text("shortcuts.column.function"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(localization.text("shortcuts.column.rekordbox"))
                .frame(width: 150, alignment: .leading)
            Text("INPUT")
                .frame(width: 270, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .frame(height: 32)
        .background(Color.white.opacity(0.035))
    }

    private func shortcutRow(_ entry: RekordboxShortcutEntry) -> some View {
        let ack05Configured = model.isConfigured(entry)
        let genericConfigured = genericHIDModel.isConfigured(entry)
        let configured = ack05Configured || genericConfigured
        let labels = (model.bindingLabels(for: entry) + genericHIDModel.labels(for: entry))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let selected = model.selectedEntryID == entry.id

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
                    Text(localization.text("common.unassigned"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(labels, id: \.self) { label in
                            Text(label)
                                .font(.caption.monospaced().weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.18))
                                .clipShape(Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
                Button {
                    genericHIDModel.beginUnifiedCapture(for: entry, shortcutModel: model)
                } label: {
                    Image(systemName:
                        genericHIDModel.captureEntryID == entry.id || model.editingEntryID == entry.id
                            ? "keyboard.badge.ellipsis"
                            : "square.and.pencil")
                        .foregroundStyle(
                            genericHIDModel.captureEntryID == entry.id || model.editingEntryID == entry.id
                                ? Color.orange
                                : Color.accentColor
                        )
                }
                .buttonStyle(.plain)
                .help(localization.text("shortcuts.edit.help"))

                Button {
                    genericHIDModel.removeBindings(for: entry, shortcutModel: model)
                    model.removeBindings(for: entry)
                    genericHIDModel.reload(shortcutModel: model)
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(configured ? Color.red : Color.secondary.opacity(0.35))
                }
                .buttonStyle(.plain)
                .disabled(!configured)
                .help(localization.text("shortcuts.remove.help"))
            }
            .frame(width: 270, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .frame(minHeight: 52)
        .padding(.vertical, labels.count > 1 ? 4 : 0)
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

    private func categoryName(_ category: RekordboxShortcutCategory) -> String {
        let key: String
        switch category {
        case .browse: key = "category.browse"
        case .deck1: key = "category.deck1"
        case .deck2: key = "category.deck2"
        case .deck3: key = "category.deck3"
        case .deck4: key = "category.deck4"
        case .allDecks: key = "category.allDecks"
        case .sampler: key = "category.sampler"
        case .recordings: key = "category.recordings"
        case .general: key = "category.general"
        case .view: key = "category.view"
        case .playlist: key = "category.playlist"
        case .other: key = "category.other"
        }
        return localization.text(key)
    }
}
