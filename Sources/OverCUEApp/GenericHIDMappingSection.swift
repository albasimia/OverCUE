import OverCUECore
import SwiftUI

struct GenericHIDMappingSection: View {
    let device: LogicalDeviceRow
    @ObservedObject var shortcutModel: ShortcutSettingsModel
    @StateObject private var model = GenericHIDMappingModel()
    @EnvironmentObject private var localization: AppLocalization
    @State private var showActionPicker = false
    @State private var actionSearch = ""
    @State private var restoreBridgeAfterLearn = false
    @State private var pendingLearnTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(localization.text("genericHID.preset"))
                    .foregroundStyle(.secondary)
                Picker(
                    localization.text("genericHID.preset"),
                    selection: Binding(
                        get: { model.selectedPresetID ?? "" },
                        set: { model.selectedPresetID = $0.isEmpty ? nil : $0 }
                    )
                ) {
                    ForEach(model.presetOptions) { preset in
                        Text(preset.name).tag(preset.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280, alignment: .leading)
                Spacer()
                Button {
                    actionSearch = ""
                    showActionPicker = true
                } label: {
                    Label(localization.text("genericHID.learn"), systemImage: "waveform.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLearning || pendingLearnTask != nil || model.selectedPresetID == nil)
            }

            if model.rows.isEmpty {
                Text(localization.text("genericHID.empty"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(row.input.overCUEDisplayName)
                                    .font(.system(.body, design: .monospaced).weight(.medium))
                                Text(row.targetName)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                model.remove(row)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(localization.text("genericHID.remove"))
                            .disabled(model.isLearning || pendingLearnTask != nil)
                        }
                        .padding(.vertical, 9)
                        if row.id != model.rows.last?.id {
                            Divider()
                        }
                    }
                }
            }

            if pendingLearnTask != nil || model.isLearning {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(localization.text("genericHID.learn.prompt"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(localization.text("common.cancel")) {
                        pendingLearnTask?.cancel()
                        pendingLearnTask = nil
                        model.cancelLearn()
                        restoreRuntimeIfNeeded()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else if let message = model.message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            model.configure(device: device)
        }
        .onChange(of: device.id) { _ in
            pendingLearnTask?.cancel()
            pendingLearnTask = nil
            restoreRuntimeIfNeeded()
            model.configure(device: device)
        }
        .onChange(of: model.isLearning) { learning in
            guard !learning, pendingLearnTask == nil else { return }
            restoreRuntimeIfNeeded()
        }
        .onDisappear {
            pendingLearnTask?.cancel()
            pendingLearnTask = nil
            model.cancelLearn()
            restoreRuntimeIfNeeded()
        }
        .sheet(isPresented: $showActionPicker) {
            actionPicker
        }
    }

    private var filteredChoices: [GenericHIDActionChoice] {
        let query = actionSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.actionChoices }
        return model.actionChoices.filter {
            $0.searchText.localizedCaseInsensitiveContains(query)
        }
    }

    private var actionPicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("genericHID.learn.title"))
                        .font(.title2.bold())
                    Text(localization.text("genericHID.learn.actionHelp"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(localization.text("common.cancel")) {
                    showActionPicker = false
                }
            }

            TextField(localization.text("genericHID.learn.search"), text: $actionSearch)
                .textFieldStyle(.roundedBorder)

            List(filteredChoices) { choice in
                Button {
                    showActionPicker = false
                    beginLearn(choice)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(choice.name)
                                .foregroundStyle(.primary)
                            HStack(spacing: 8) {
                                Text(choice.category)
                                if let shortcut = choice.shortcut, !shortcut.isEmpty {
                                    Text(shortcut)
                                        .font(.system(.caption, design: .monospaced))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.inset)
        }
        .padding(22)
        .frame(width: 620, height: 560)
    }

    private func beginLearn(_ choice: GenericHIDActionChoice) {
        pendingLearnTask?.cancel()
        let wasEnabled = shortcutModel.isBridgeEnabled
        restoreBridgeAfterLearn = wasEnabled
        if wasEnabled {
            shortcutModel.setBridgeEnabled(false)
        }

        // The normal Generic HID runtime opens registered devices with
        // kIOHIDOptionsTypeSeizeDevice so Consumer Control inputs do not leak to
        // macOS. IOHIDManagerClose is synchronous at our API boundary, but the
        // kernel can briefly keep the exclusive claim while the close propagates.
        // Give that claim time to drain before Learn opens the same device shared.
        pendingLearnTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            pendingLearnTask = nil
            do {
                try model.beginLearn(target: choice.target)
            } catch {
                restoreRuntimeIfNeeded()
            }
        }
    }

    private func restoreRuntimeIfNeeded() {
        guard restoreBridgeAfterLearn else { return }
        restoreBridgeAfterLearn = false
        shortcutModel.setBridgeEnabled(true)
    }
}
