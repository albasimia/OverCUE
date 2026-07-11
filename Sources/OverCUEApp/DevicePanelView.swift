import OverCUECore
import SwiftUI

struct DevicePanelView: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ACK05")
                        .font(.title2.bold())
                    Text("デバイスマップ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            HStack {
                Text("グループ")
                    .font(.headline)
                Picker("グループ", selection: $model.selectedGroup) {
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
                    shortcutForKey: model.shortcutAssigned(to:),
                    onSelectKey: model.selectDeviceKey
                )

                Button(action: model.rotateDevice) {
                    Image(systemName: "rotate.right")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .help("筐体を90°回転")
                .padding(6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                if let key = model.selectedDeviceKey {
                    Text(key.rawValue.uppercased())
                        .font(.headline)
                    Text(model.shortcutAssigned(to: key)?.description ?? "未割り当て")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("ボタンまたはショートカットを選択")
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
    let shortcutForKey: (ACK05Key) -> RekordboxShortcutEntry?
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
        .accessibilityLabel("ACK05ボタン配置")
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
                .offset(x: -356, y: 104)

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
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 3, height: 20)
                .offset(y: -106)
        }
    }

    private func keyButton(_ key: ACK05Key, size: CGSize) -> some View {
        let isHighlighted = highlightedKeys.contains(key)
        let isSelected = selectedKey == key
        let entry = shortcutForKey(key)

        return Button {
            onSelectKey(key)
        } label: {
            VStack(spacing: 4) {
                Text(key.rawValue.uppercased())
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if let entry {
                    Text(entry.shortcut)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .lineLimit(1)
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
        .help(entry.map { "\(key.rawValue.uppercased()): \($0.description) [\($0.shortcut)]" } ?? "未割り当て")
        .accessibilityLabel(key.rawValue.uppercased())
        .accessibilityValue(entry?.description ?? "未割り当て")
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
        let x = rect.minX
        let y = rect.minY
        let width = rect.width
        let height = rect.height
        var path = Path()

        path.move(to: CGPoint(x: x + width * 0.31, y: y + height * 0.10))
        path.addLine(to: CGPoint(x: x + width * 0.955, y: y + height * 0.10))
        path.addQuadCurve(
            to: CGPoint(x: x + width * 0.99, y: y + height * 0.17),
            control: CGPoint(x: x + width * 0.99, y: y + height * 0.10)
        )
        path.addLine(to: CGPoint(x: x + width * 0.99, y: y + height * 0.86))
        path.addQuadCurve(
            to: CGPoint(x: x + width * 0.95, y: y + height * 0.92),
            control: CGPoint(x: x + width * 0.99, y: y + height * 0.92)
        )
        path.addLine(to: CGPoint(x: x + width * 0.10, y: y + height * 0.92))
        path.addQuadCurve(
            to: CGPoint(x: x + width * 0.075, y: y + height * 0.86),
            control: CGPoint(x: x + width * 0.075, y: y + height * 0.92)
        )
        path.addLine(to: CGPoint(x: x + width * 0.075, y: y + height * 0.48))
        path.addCurve(
            to: CGPoint(x: x + width * 0.075, y: y + height * 0.22),
            control1: CGPoint(x: x + width * 0.01, y: y + height * 0.39),
            control2: CGPoint(x: x + width * 0.02, y: y + height * 0.27)
        )
        path.addCurve(
            to: CGPoint(x: x + width * 0.31, y: y + height * 0.10),
            control1: CGPoint(x: x + width * 0.12, y: y - height * 0.02),
            control2: CGPoint(x: x + width * 0.25, y: y + height * 0.01)
        )
        path.closeSubpath()
        return path
    }
}
