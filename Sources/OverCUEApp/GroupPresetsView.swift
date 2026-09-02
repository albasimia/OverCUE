import OverCUECore
import SwiftUI

struct GroupPresetsView: View {
    @ObservedObject var deviceModel: DeviceManagementModel
    @StateObject private var groupPresetModel = GroupPresetManagementModel()
    @EnvironmentObject private var localization: AppLocalization

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localization.text("groupPreset.title"))
                        .font(.largeTitle.bold())
                    Text(localization.text("groupPreset.help"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                GroupPresetSelectorView(model: groupPresetModel)

                Divider()

                if deviceModel.devices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.badge.person.crop")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text(localization.text("devices.empty"))
                            .font(.headline)
                        Text(localization.text("devices.empty.help"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        assignmentHeader

                        ForEach(deviceModel.devices) { device in
                            GroupPresetOverviewDeviceRow(
                                model: groupPresetModel,
                                device: device
                            )
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 980, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            deviceModel.reload()
            groupPresetModel.reload()
        }
    }

    private var assignmentHeader: some View {
        HStack(spacing: 20) {
            Text(localization.text("devices.logicalDevice"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(localization.text("groupPreset.includeDevice"))
                .frame(width: 150, alignment: .center)
            Text(localization.text("groupPreset.preset"))
                .frame(width: 260, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
    }
}

private struct GroupPresetOverviewDeviceRow: View {
    @ObservedObject var model: GroupPresetManagementModel
    let device: LogicalDeviceRow
    @EnvironmentObject private var localization: AppLocalization
    @State private var operationError: String?

    private var presets: [OverCUEPresetGroup] {
        model.availablePresets(for: device.id)
    }

    private var isIncluded: Bool {
        model.isIncluded(logicalDeviceID: device.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Label(device.profileName, systemImage: "person.crop.square")
                            .labelStyle(.titleAndIcon)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(device.isConnected ? Color.green : Color.secondary.opacity(0.5))
                                .frame(width: 7, height: 7)
                            Text(device.isConnected
                                ? localization.text("devices.connected")
                                : localization.text("devices.disconnected"))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(
                    localization.text("groupPreset.includeDevice"),
                    isOn: Binding(
                        get: { isIncluded },
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
                .labelsHidden()
                .frame(width: 150)

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
                .frame(width: 260, alignment: .leading)
                .disabled(!isIncluded || presets.isEmpty)
                .opacity(isIncluded ? 1 : 0.35)
            }

            if let operationError {
                Text(operationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
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
