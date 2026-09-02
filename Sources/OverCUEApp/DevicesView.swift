import OverCUECore
import SwiftUI

struct DevicesView: View {
    @ObservedObject var deviceModel: DeviceManagementModel
    @ObservedObject var shortcutModel: ShortcutSettingsModel
    @StateObject private var groupPresetModel = GroupPresetManagementModel()
    @EnvironmentObject private var localization: AppLocalization
    @State private var nameDraft = ""
    @State private var operationError: String?
    @State private var showForgetConfirmation = false
    @State private var restoreBridgeAfterIdentify = false

    var body: some View {
        HStack(spacing: 0) {
            deviceList
                .frame(width: 340)
            Divider()
            deviceDetail
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            deviceModel.reload()
            groupPresetModel.reload()
            syncNameDraft()
        }
        .onChange(of: deviceModel.selectedLogicalDeviceID) { _ in
            syncNameDraft()
        }
        .onChange(of: deviceModel.isIdentifying) { identifying in
            guard !identifying else { return }
            restoreRuntimeIfNeeded()
        }
        .onDisappear {
            if deviceModel.isIdentifying {
                deviceModel.cancelIdentify()
            }
            restoreRuntimeIfNeeded()
        }
        .alert(localization.text("devices.forget.title"), isPresented: $showForgetConfirmation) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("devices.forget.action"), role: .destructive) {
                guard let id = deviceModel.selectedLogicalDeviceID else { return }
                perform { try deviceModel.forgetBinding(logicalDeviceID: id) }
            }
        } message: {
            Text(localization.text("devices.forget.message"))
        }
    }

    private var deviceList: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(localization.text("devices.title"))
                        .font(.largeTitle.bold())
                    Text(localization.text("devices.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            GroupPresetSelectorView(model: groupPresetModel)

            Divider()

            Button {
                beginIdentify { try deviceModel.beginAddACK05() }
            } label: {
                Label(localization.text("devices.addAck05"), systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(deviceModel.isIdentifying)

            Button {
                beginIdentify { try deviceModel.beginAddGenericHID() }
            } label: {
                Label(localization.text("devices.addGeneric"), systemImage: "plus.square.dashed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(deviceModel.isIdentifying)

            if deviceModel.devices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.2.square")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(localization.text("devices.empty"))
                        .font(.headline)
                    Text(localization.text("devices.empty.help"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(deviceModel.devices) { device in
                            deviceRow(device)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if let operationError {
                Text(operationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let error = deviceModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
    }

    private func deviceRow(_ device: LogicalDeviceRow) -> some View {
        let selected = deviceModel.selectedLogicalDeviceID == device.id
        return Button {
            deviceModel.selectedLogicalDeviceID = device.id
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.07))
                        .frame(width: 40, height: 40)
                    Image(systemName: "dial.medium")
                        .font(.system(size: 18, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(device.name)
                        .font(.headline)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(device.isConnected ? Color.green : Color.secondary.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(device.isConnected
                            ? localization.text("devices.connected")
                            : localization.text("devices.disconnected"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if device.binding == nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help(localization.text("devices.binding.missing"))
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(selected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? Color.accentColor.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var deviceDetail: some View {
        if let device = deviceModel.selectedDevice {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(device.name)
                                .font(.largeTitle.bold())
                            Text(localization.text("devices.logicalDevice"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        connectionBadge(device)
                    }

                    if deviceModel.isIdentifying {
                        identifyPanel
                    }

                    detailSection(localization.text("devices.section.identity")) {
                        VStack(alignment: .leading, spacing: 14) {
                            detailRow(
                                localization.text("devices.logicalId"),
                                value: device.id
                            )
                            detailRow(
                                localization.text("devices.hardware"),
                                value: hardwareLabel(device)
                            )
                            detailRow(
                                localization.text("devices.pairingId"),
                                value: pairingLabel(device)
                            )
                            Text(localization.text("devices.pairing.help"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    detailSection(localization.text("devices.section.settings")) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack(spacing: 12) {
                                Text(localization.text("devices.name"))
                                    .frame(width: 110, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                TextField(localization.text("devices.name"), text: $nameDraft)
                                    .textFieldStyle(.roundedBorder)
                                Button(localization.text("common.save")) {
                                    perform {
                                        try deviceModel.rename(
                                            logicalDeviceID: device.id,
                                            name: nameDraft
                                        )
                                    }
                                }
                                .disabled(nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }

                            HStack(spacing: 12) {
                                Text(localization.text("devices.profile"))
                                    .frame(width: 110, alignment: .leading)
                                    .foregroundStyle(.secondary)
                                Picker(
                                    localization.text("devices.profile"),
                                    selection: Binding(
                                        get: { device.profileName },
                                        set: { profile in
                                            perform {
                                                try deviceModel.assignProfile(
                                                    logicalDeviceID: device.id,
                                                    profileName: profile
                                                )
                                            }
                                        }
                                    )
                                ) {
                                    ForEach(deviceModel.profileNames, id: \.self) { profile in
                                        Text(profile).tag(profile)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: 300, alignment: .leading)
                                Spacer()
                            }
                        }
                    }

                    detailSection(localization.text("groupPreset.title")) {
                        GroupPresetDeviceAssignmentView(
                            model: groupPresetModel,
                            device: device
                        )
                    }

                    detailSection(localization.text("devices.section.binding")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(device.binding == nil
                                ? localization.text("devices.binding.missing.help")
                                : localization.text("devices.binding.ok.help"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if device.binding == nil {
                                HStack(spacing: 10) {
                                    Button {
                                        beginIdentify {
                                            try deviceModel.beginRebind(
                                                logicalDeviceID: device.id,
                                                kind: .ack05
                                            )
                                        }
                                    } label: {
                                        Label(
                                            localization.text("devices.identify.ack05.action"),
                                            systemImage: "scope"
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(deviceModel.isIdentifying)

                                    Button {
                                        beginIdentify {
                                            try deviceModel.beginRebind(
                                                logicalDeviceID: device.id,
                                                kind: .genericHID
                                            )
                                        }
                                    } label: {
                                        Label(
                                            localization.text("devices.identify.generic.action"),
                                            systemImage: "scope"
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(deviceModel.isIdentifying)
                                }
                            } else {
                                HStack(spacing: 10) {
                                    Button {
                                        beginIdentify {
                                            try deviceModel.beginRebind(logicalDeviceID: device.id)
                                        }
                                    } label: {
                                        Label(
                                            localization.text("devices.rebind.action"),
                                            systemImage: "scope"
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(deviceModel.isIdentifying)

                                    Button(role: .destructive) {
                                        showForgetConfirmation = true
                                    } label: {
                                        Label(localization.text("devices.forget.action"), systemImage: "link.badge.minus")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(deviceModel.isIdentifying)
                                }
                            }
                        }
                    }

                    if let message = deviceModel.statusMessage {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.medium))
                    }
                    if let error = deviceModel.errorMessage ?? operationError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(32)
                .frame(maxWidth: 820, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.and.hand.point.up.left")
                    .font(.system(size: 38))
                    .foregroundStyle(.secondary)
                Text(localization.text("devices.select"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var identifyPanel: some View {
        HStack(spacing: 16) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text(localization.text("devices.identify.title"))
                    .font(.headline)
                Text(localization.text("devices.identify.prompt"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(localization.text("devices.identify.candidates", deviceModel.identifyCandidateCount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(localization.text("common.cancel")) {
                deviceModel.cancelIdentify()
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
        }
    }

    private func connectionBadge(_ device: LogicalDeviceRow) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(device.isConnected ? Color.green : Color.secondary.opacity(0.55))
                .frame(width: 8, height: 8)
            Text(device.isConnected
                ? localization.text("devices.connected")
                : localization.text("devices.disconnected"))
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 11)
        .frame(height: 28)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func hardwareLabel(_ device: LogicalDeviceRow) -> String {
        switch device.binding?.kind {
        case .ack05:
            "ACK05"
        case .genericHID:
            "Generic HID"
        case nil:
            localization.text("devices.binding.none")
        }
    }

    private func pairingLabel(_ device: LogicalDeviceRow) -> String {
        guard let binding = device.binding else {
            return localization.text("devices.binding.none")
        }
        switch binding.kind {
        case .ack05:
            return binding.serialNumber
                ?? binding.legacyDeviceIdentifier
                ?? localization.text("devices.binding.none")
        case .genericHID:
            return binding.serialNumber ?? localization.text("devices.binding.none")
        }
    }

    private func syncNameDraft() {
        nameDraft = deviceModel.selectedDevice?.name ?? ""
        operationError = nil
    }

    private func beginIdentify(_ action: () throws -> Void) {
        operationError = nil
        let wasEnabled = shortcutModel.isBridgeEnabled
        restoreBridgeAfterIdentify = wasEnabled
        if wasEnabled {
            shortcutModel.pauseRuntimeForDeviceIdentification()
        }
        do {
            try action()
        } catch {
            operationError = error.localizedDescription
            restoreRuntimeIfNeeded()
        }
    }

    private func restoreRuntimeIfNeeded() {
        guard restoreBridgeAfterIdentify else { return }
        restoreBridgeAfterIdentify = false
        shortcutModel.resumeRuntimeAfterDeviceIdentification()
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
