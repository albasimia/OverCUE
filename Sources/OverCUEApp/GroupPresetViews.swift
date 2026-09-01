import OverCUECore
import SwiftUI

struct GroupPresetSelectorView: View {
    @ObservedObject var model: GroupPresetManagementModel
    @EnvironmentObject private var localization: AppLocalization
    @State private var editor: GroupPresetEditorMode?
    @State private var nameDraft = ""
    @State private var operationError: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(localization.text("groupPreset.title"))
                    .font(.headline)

                if model.groupPresets.isEmpty {
                    Text(localization.text("groupPreset.none"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Picker(
                        localization.text("groupPreset.title"),
                        selection: Binding(
                            get: { model.activeGroupPresetID ?? model.groupPresets.first?.id ?? "" },
                            set: { id in perform { try model.activate(id: id) } }
                        )
                    ) {
                        ForEach(model.groupPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                }

                Button {
                    nameDraft = localization.text("groupPreset.defaultName", model.groupPresets.count + 1)
                    editor = .add
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .help(localization.text("groupPreset.add"))

                Menu {
                    Button(localization.text("groupPreset.rename")) {
                        guard let active = model.activeGroupPreset else { return }
                        nameDraft = active.name
                        editor = .rename(id: active.id)
                    }
                    .disabled(model.activeGroupPreset == nil)

                    Divider()

                    Button(localization.text("groupPreset.delete"), role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(model.activeGroupPreset == nil || model.groupPresets.count <= 1)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(localization.text("groupPreset.manage"))
            }

            Text(localization.text("groupPreset.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let error = operationError ?? model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(item: $editor) { editor in
            editorSheet(editor)
        }
        .alert(localization.text("groupPreset.delete.title"), isPresented: $showDeleteConfirmation) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("groupPreset.delete"), role: .destructive) {
                guard let id = model.activeGroupPresetID else { return }
                perform { try model.delete(id: id) }
            }
        } message: {
            Text(localization.text(
                "groupPreset.delete.message",
                model.activeGroupPreset?.name ?? ""
            ))
        }
    }

    @ViewBuilder
    private func editorSheet(_ editor: GroupPresetEditorMode) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editor.isAdd
                ? localization.text("groupPreset.add.title")
                : localization.text("groupPreset.rename.title"))
                .font(.title2.bold())

            TextField(localization.text("groupPreset.name"), text: $nameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)

            HStack {
                Spacer()
                Button(localization.text("common.cancel")) {
                    self.editor = nil
                }
                Button(localization.text("common.save")) {
                    perform {
                        switch editor {
                        case .add:
                            _ = try model.add(name: nameDraft)
                        case let .rename(id):
                            try model.rename(id: id, name: nameDraft)
                        }
                    }
                    if operationError == nil { self.editor = nil }
                }
                .buttonStyle(.borderedProminent)
                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
    }

    private func perform(_ action: () throws -> Void) {
        operationError = nil
        do {
            try action()
        } catch {
            operationError = error.localizedDescription
        }
    }
}

struct GroupPresetDeviceAssignmentView: View {
    @ObservedObject var model: GroupPresetManagementModel
    let device: LogicalDeviceRow
    @EnvironmentObject private var localization: AppLocalization
    @State private var operationError: String?

    private var presets: [OverCUEPresetGroup] {
        model.availablePresets(for: device.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(
                localization.text("groupPreset.includeDevice"),
                isOn: Binding(
                    get: { model.isIncluded(logicalDeviceID: device.id) },
                    set: { included in
                        perform {
                            try model.setIncluded(
                                logicalDeviceID: device.id,
                                included: included
                            )
                        }
                    }
                )
            )

            if model.isIncluded(logicalDeviceID: device.id) {
                HStack(spacing: 12) {
                    Text(localization.text("groupPreset.preset"))
                        .frame(width: 110, alignment: .leading)
                        .foregroundStyle(.secondary)

                    Picker(
                        localization.text("groupPreset.preset"),
                        selection: Binding(
                            get: {
                                model.assignedPresetID(logicalDeviceID: device.id)
                                    ?? presets.first?.id
                                    ?? ""
                            },
                            set: { presetID in
                                perform {
                                    try model.assignPreset(
                                        logicalDeviceID: device.id,
                                        presetID: presetID
                                    )
                                }
                            }
                        )
                    ) {
                        ForEach(presets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 300, alignment: .leading)
                    .disabled(presets.isEmpty)
                    Spacer()
                }
            }

            Text(localization.text("groupPreset.device.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let operationError {
                Text(operationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func perform(_ action: () throws -> Void) {
        operationError = nil
        do {
            try action()
        } catch {
            operationError = error.localizedDescription
        }
    }
}

private enum GroupPresetEditorMode: Identifiable {
    case add
    case rename(id: String)

    var id: String {
        switch self {
        case .add: "add"
        case let .rename(id): "rename:\(id)"
        }
    }

    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}
