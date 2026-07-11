import OverCUECore
import SwiftUI

struct DevicePanelView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @EnvironmentObject private var localization: AppLocalization

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

            HStack {
                Text(localization.text("device.group"))
                    .font(.headline)
                Picker(
                    localization.text("device.group"),
                    selection: Binding(
                        get: { model.selectedGroup },
                        set: { model.setGroup($0) }
                    )
                ) {
                    ForEach(1...4, id: \.self) { group in
                        Text("\(group)").tag(group)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }

            ZStack(alignment: .topTrailing) {
                ACK05DeviceMap(
                    rotationQuarterTurns: model.rotationQuarterTurns,
                    highlightedKeys: model.highlightedKeys,
                    selectedKey: model.selectedDeviceKey,
                    assignmentForKey: model.deviceAssignment(to:),
                    dialAssignment: model.dialAssignment(_:),
                    onSelectKey: model.selectDeviceKey
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
                if let key = model.selectedDeviceKey {
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
    }

}

private struct ACK05DeviceMap: View {
    let rotationQuarterTurns: Int
    let highlightedKeys: Set<ACK05Key>
    let selectedKey: ACK05Key?
    let assignmentForKey: (ACK05Key) -> ACK05DeviceAssignment?
    let dialAssignment: (DialDirection) -> ACK05DeviceAssignment?
    let onSelectKey: (ACK05Key) -> Void

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
        return VStack(spacing: 1) {
            Text(symbol)
                .font(.caption.bold())
            Text(assignment?.functionName ?? L10n.text("common.unassigned"))
                .font(.system(size: 8, weight: .medium, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 82)
        .foregroundStyle(assignment == nil ? Color.secondary : Color.primary)
    }

    private func keyButton(_ key: ACK05Key, size: CGSize) -> some View {
        let isHighlighted = highlightedKeys.contains(key)
        let isSelected = selectedKey == key
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
                    .fill(isHighlighted || isSelected ? Color.accentColor.opacity(0.38) : Color.black.opacity(0.28))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isHighlighted || isSelected ? Color.accentColor : Color.white.opacity(0.14),
                        lineWidth: isHighlighted || isSelected ? 3 : 1
                    )
            }
            .shadow(
                color: isHighlighted || isSelected ? Color.accentColor.opacity(0.55) : .clear,
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

        // Keep the enclosure contour concentric with the dial. The map is drawn
        // horizontally and then rotated, so this arc becomes the top/right
        // shoulder visible around the dial in the normal vertical orientation.
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
