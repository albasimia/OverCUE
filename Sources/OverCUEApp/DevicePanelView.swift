import OverCUECore
import SwiftUI

struct DevicePanelView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @EnvironmentObject private var localization: AppLocalization
    @State private var presetEditor: PresetEditorMode?
    @State private var presetNameDraft = ""
    @State private var presetError: String?
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACK05")
                        .font(.title2.bold())
                    Text(localization.text("device.map"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Text(localization.text("device.group"))
                        .font(.headline)
                    Picker(
                        localization.text("device.group"),
                        selection: Binding(
                            get: { model.selectedGroup },
                            set: { model.setGroup($0) }
                        )
                    ) {
                        ForEach(Array(model.availablePresetGroups.enumerated()), id: \.element.id) { index, preset in
                            Text(preset.name).tag(index + 1)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)

                    Button {
                        beginAddPreset()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .help(localization.text("preset.add"))
                    .disabled(model.availablePresetGroups.count >= OverCUEPresetGroup.maximumCount)

                    Menu {
                        Button(localization.text("preset.rename")) {
                            beginRenamePreset()
                        }
                        .disabled(selectedPreset == nil)

                        Divider()

                        Button(localization.text("preset.delete"), role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(
                            selectedPreset == nil
                                || model.selectedGroup == 1
                                || model.availablePresetGroups.count <= 1
                        )
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help(localization.text("preset.manage"))
                }

                if let presetError {
                    Text(presetError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.selectedGroup == 1, model.availablePresetGroups.count > 1 {
                    Text(localization.text("preset.first.help"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            ZStack(alignment: .topTrailing) {
                ACK05DeviceMap(
                    rotationQuarterTurns: model.rotationQuarterTurns,
                    highlightedKeys: model.highlightedKeys,
                    highlightedDialDirections: model.highlightedDialDirections,
                    pressedKeys: model.pressedDeviceKeys,
                    activeDialDirection: model.activeDialDirection,
                    selectedKey: model.selectedDeviceKey,
                    selectedDialDirection: model.selectedDialDirection,
                    assignmentForKey: model.deviceAssignment(to:),
                    dialAssignment: model.dialAssignment(_:),
                    onSelectKey: model.selectDeviceKey,
                    onSelectDial: model.selectDial
                )

                Button(action: model.rotateDevice) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .help(localization.text("device.rotate"))
                .padding(6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                if let direction = model.selectedDialDirection {
                    Text(direction.displayName)
                        .font(.headline)
                    Text(
                        model.dialAssignment(direction)?.functionName
                            ?? localization.text("common.unassigned")
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let key = model.selectedDeviceKey {
                    Text(key.rawValue.uppercased())
                        .font(.headline)
                    Text(
                        model.deviceAssignment(to: key)?.functionName
                            ?? localization.text("common.unassigned")
                    )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(localization.text("device.select"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 42, alignment: .topLeading)
        }
        .padding(28)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.45))
        .sheet(item: $presetEditor) { editor in
            presetEditorSheet(editor)
        }
        .alert(localization.text("preset.delete.title"), isPresented: $showDeleteConfirmation) {
            Button(localization.text("common.cancel"), role: .cancel) {}
            Button(localization.text("preset.delete"), role: .destructive) {
                deleteSelectedPreset()
            }
        } message: {
            Text(localization.text("preset.delete.message", selectedPreset?.name ?? ""))
        }
    }

    private var selectedPreset: OverCUEPresetGroup? {
        guard model.availablePresetGroups.indices.contains(model.selectedGroup - 1) else { return nil }
        return model.availablePresetGroups[model.selectedGroup - 1]
    }

    private func beginAddPreset() {
        presetError = nil
        presetNameDraft = localization.text("preset.defaultName", model.availablePresetGroups.count + 1)
        presetEditor = .add
    }

    private func beginRenamePreset() {
        guard let selectedPreset else { return }
        presetError = nil
        presetNameDraft = selectedPreset.name
        presetEditor = .rename(id: selectedPreset.id)
    }

    @ViewBuilder
    private func presetEditorSheet(_ editor: PresetEditorMode) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editor.isAdd
                ? localization.text("preset.add.title")
                : localization.text("preset.rename.title"))
                .font(.title2.bold())

            TextField(localization.text("preset.name"), text: $presetNameDraft)
                .textFieldStyle(.roundedBorder)

            if let presetError {
                Text(presetError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(localization.text("common.cancel")) {
                    presetEditor = nil
                    presetError = nil
                }
                Button(editor.isAdd
                    ? localization.text("preset.add")
                    : localization.text("common.save")) {
                    savePresetEditor(editor)
                }
                .buttonStyle(.borderedProminent)
                .disabled(presetNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func savePresetEditor(_ editor: PresetEditorMode) {
        do {
            switch editor {
            case .add:
                let result = try PresetGroupStore.add(name: presetNameDraft, mode: model.mode)
                presetEditor = nil
                presetError = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    model.setGroup(result.index)
                }
            case let .rename(id):
                try PresetGroupStore.rename(id: id, name: presetNameDraft)
                presetEditor = nil
                presetError = nil
            }
        } catch {
            presetError = error.localizedDescription
        }
    }

    private func deleteSelectedPreset() {
        guard let selectedPreset else { return }
        do {
            _ = try PresetGroupStore.delete(id: selectedPreset.id)
            presetError = nil
        } catch {
            presetError = error.localizedDescription
        }
    }
}

private enum PresetEditorMode: Identifiable {
    case add
    case rename(id: String)

    var id: String {
        switch self {
        case .add: "add"
        case let .rename(id): "rename-\(id)"
        }
    }

    var isAdd: Bool {
        if case .add = self { return true }
        return false
    }
}

private struct ACK05DeviceMap: View {
    let rotationQuarterTurns: Int
    let highlightedKeys: Set<ACK05Key>
    let highlightedDialDirections: Set<DialDirection>
    let pressedKeys: Set<ACK05Key>
    let activeDialDirection: DialDirection?
    let selectedKey: ACK05Key?
    let selectedDialDirection: DialDirection?
    let assignmentForKey: (ACK05Key) -> ACK05DeviceAssignment?
    let dialAssignment: (DialDirection) -> ACK05DeviceAssignment?
    let onSelectKey: (ACK05Key) -> Void
    let onSelectDial: (DialDirection) -> Void

    private var angle: Angle {
        .degrees(Double(rotationQuarterTurns * 90))
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 760, geometry.size.height / 760)

            ZStack {
                deviceBody
                    .frame(width: 720, height: 430)
                    .rotationEffect(angle)
            }
            .frame(width: 760, height: 760)
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("device.accessibility"))
    }

    private var deviceBody: some View {
        ZStack {
            ACK05BodyShape()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay {
                    ACK05BodyShape()
                        .stroke(Color.white.opacity(0.22), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.35), radius: 16, y: 10)

            dial
                .offset(x: -222, y: -72)

            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 5, height: 28)
                .offset(x: -309, y: 104)

            ForEach(ACK05Key.allCases, id: \.self) { key in
                let layout = layout(for: key)
                keyButton(key, size: layout.size)
                    .offset(x: layout.x, y: layout.y)
            }
        }
    }

    private var dial: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.5))
                .frame(width: 244, height: 244)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.2), lineWidth: 2)
                }
            Circle()
                .fill(Color(nsColor: .darkGray))
                .frame(width: 84, height: 84)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
            HStack(spacing: 0) {
                dialLabel(.counterclockwise, symbol: "←")
                Spacer(minLength: 0)
                dialLabel(.clockwise, symbol: "→")
            }
            .frame(width: 232)
            .rotationEffect(.degrees(Double(-rotationQuarterTurns * 90)))
        }
    }

    private func dialLabel(_ direction: DialDirection, symbol: String) -> some View {
        let assignment = dialAssignment(direction)
        let isHighlighted = highlightedDialDirections.contains(direction)
            || selectedDialDirection == direction
        let isActive = activeDialDirection == direction
        return Button {
            onSelectDial(direction)
        } label: {
            VStack(spacing: 1) {
                Text(symbol)
                    .font(.caption.bold())
                Text(assignment?.functionName ?? L10n.text("common.unassigned"))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 82, height: 72)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isActive
                            ? Color.green.opacity(0.46)
                            : isHighlighted
                                ? Color.accentColor.opacity(0.38)
                                : Color.clear
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isActive
                            ? Color.green
                            : isHighlighted
                                ? Color.accentColor
                                : Color.clear,
                        lineWidth: isActive || isHighlighted ? 3 : 1
                    )
            }
            .shadow(
                color: isActive
                    ? Color.green.opacity(0.6)
                    : isHighlighted
                        ? Color.accentColor.opacity(0.55)
                        : .clear,
                radius: 8
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(assignment == nil ? Color.secondary : Color.primary)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(assignment.map {
            let shortcut = $0.shortcut.map { " [\($0)]" } ?? ""
            return "\(direction.displayName): \($0.functionName)\(shortcut)"
        } ?? L10n.text("common.unassigned"))
        .accessibilityLabel(direction.displayName)
        .accessibilityValue(assignment?.functionName ?? L10n.text("common.unassigned"))
    }

    private func keyButton(_ key: ACK05Key, size: CGSize) -> some View {
        let isHighlighted = highlightedKeys.contains(key)
        let isSelected = selectedKey == key
        let isPressed = pressedKeys.contains(key)
        let assignment = assignmentForKey(key)

        return Button {
            onSelectKey(key)
        } label: {
            VStack(spacing: 4) {
                Text(key.rawValue.uppercased())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if let assignment {
                    Text(assignment.functionName)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
            }
            .rotationEffect(.degrees(Double(-rotationQuarterTurns * 90)))
            .frame(width: size.width, height: size.height)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        isPressed
                            ? Color.green.opacity(0.46)
                            : isHighlighted || isSelected
                                ? Color.accentColor.opacity(0.38)
                                : Color.black.opacity(0.28)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isPressed
                            ? Color.green
                            : isHighlighted || isSelected
                                ? Color.accentColor
                                : Color.white.opacity(0.14),
                        lineWidth: isPressed || isHighlighted || isSelected ? 3 : 1
                    )
            }
            .shadow(
                color: isPressed
                    ? Color.green.opacity(0.6)
                    : isHighlighted || isSelected
                        ? Color.accentColor.opacity(0.55)
                        : .clear,
                radius: 8
            )
        }
        .buttonStyle(.plain)
        .help(assignment.map {
            let shortcut = $0.shortcut.map { " [\($0)]" } ?? ""
            return "\(key.rawValue.uppercased()): \($0.functionName)\(shortcut)"
        } ?? L10n.text("common.unassigned"))
        .accessibilityLabel(key.rawValue.uppercased())
        .accessibilityValue(assignment?.functionName ?? L10n.text("common.unassigned"))
    }

    private func layout(for key: ACK05Key) -> KeyLayout {
        switch key {
        case .k1: KeyLayout(x: -22, y: -88, width: 84, height: 82)
        case .k2: KeyLayout(x: 76, y: -88, width: 84, height: 82)
        case .k3: KeyLayout(x: 174, y: -88, width: 84, height: 82)
        case .k4: KeyLayout(x: -22, y: 8, width: 84, height: 82)
        case .k5: KeyLayout(x: 76, y: 8, width: 84, height: 82)
        case .k6: KeyLayout(x: 174, y: 8, width: 84, height: 82)
        case .k7: KeyLayout(x: 272, y: -40, width: 84, height: 178)
        case .k8: KeyLayout(x: -22, y: 106, width: 84, height: 82)
        case .k9: KeyLayout(x: 125, y: 106, width: 182, height: 82)
        case .k10: KeyLayout(x: 272, y: 106, width: 84, height: 82)
        }
    }
}

private struct KeyLayout {
    let x: CGFloat
    let y: CGFloat
    let size: CGSize

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        size = CGSize(width: width, height: height)
    }
}

private struct ACK05BodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let left = rect.minX + rect.width * 0.075
        let top = rect.minY + rect.height * 0.10
        let right = rect.minX + rect.width * 0.99
        let bottom = rect.minY + rect.height * 0.92
        let cornerRadius = min(rect.width * 0.04, rect.height * 0.06)

        let dialCenter = CGPoint(
            x: rect.midX - rect.width * (222.0 / 720.0),
            y: rect.midY - rect.height * (72.0 / 430.0)
        )
        let shoulderRadius = min(
            rect.width * (124.0 / 720.0),
            rect.height * (124.0 / 430.0)
        )
        let leftOffset = dialCenter.x - left
        let leftIntersectionOffset = sqrt(max(0, shoulderRadius * shoulderRadius - leftOffset * leftOffset))
        let shoulderStart = CGPoint(x: left, y: dialCenter.y + leftIntersectionOffset)

        let topOffset = dialCenter.y - top
        let topIntersectionOffset = sqrt(max(0, shoulderRadius * shoulderRadius - topOffset * topOffset))
        let shoulderEnd = CGPoint(x: dialCenter.x + topIntersectionOffset, y: top)

        let startAngle = Angle(radians: atan2(
            Double(shoulderStart.y - dialCenter.y),
            Double(shoulderStart.x - dialCenter.x)
        ))
        var endRadians = atan2(
            Double(shoulderEnd.y - dialCenter.y),
            Double(shoulderEnd.x - dialCenter.x)
        )
        if endRadians < startAngle.radians {
            endRadians += Double.pi * 2
        }

        var path = Path()

        path.move(to: shoulderEnd)
        path.addLine(to: CGPoint(x: right - cornerRadius, y: top))
        path.addQuadCurve(
            to: CGPoint(x: right, y: top + cornerRadius),
            control: CGPoint(x: right, y: top)
        )
        path.addLine(to: CGPoint(x: right, y: bottom - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: right - cornerRadius, y: bottom),
            control: CGPoint(x: right, y: bottom)
        )
        path.addLine(to: CGPoint(x: left + cornerRadius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom - cornerRadius),
            control: CGPoint(x: left, y: bottom)
        )
        path.addLine(to: shoulderStart)
        path.addArc(
            center: dialCenter,
            radius: shoulderRadius,
            startAngle: startAngle,
            endAngle: Angle(radians: endRadians),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
