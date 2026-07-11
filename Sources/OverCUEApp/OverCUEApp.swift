import ApplicationServices
import AppKit
import SwiftUI

private final class OverCUEApplicationDelegate: NSObject, NSApplicationDelegate {
    var shutdownHandler: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        requestAccessibilityPermissionIfNeeded()
        activateMainWindow()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        activateMainWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdownHandler?()
    }

    private func requestAccessibilityPermissionIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func activateMainWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct OverCUEApp: App {
    @NSApplicationDelegateAdaptor(OverCUEApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model = ShortcutSettingsModel()

    var body: some Scene {
        WindowGroup("OverCUE", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 1_080, minHeight: 720)
                .preferredColorScheme(.dark)
                .onAppear {
                    applicationDelegate.shutdownHandler = { model.shutdown() }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("rekordbox設定を再読み込み") {
                    model.reloadAndRestartBridge()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(nsImage: MenuBarGhostIcon.image)
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var model: ShortcutSettingsModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("OverCUEを表示") {
            openWindow(id: "main")
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
            }
        }

        Divider()

        Toggle(
            "ACK05入力を有効にする",
            isOn: Binding(
                get: { model.isBridgeEnabled },
                set: { enabled in model.setBridgeEnabled(enabled) }
            )
        )

        Text(model.bridgeStatus.displayText)

        Divider()

        Button("終了") {
            model.shutdown()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

private struct ContentView: View {
    @ObservedObject var model: ShortcutSettingsModel

    var body: some View {
        VStack(spacing: 0) {
            applicationHeader
            Divider()
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    DevicePanelView(model: model)
                        .frame(width: max(480, geometry.size.width * 0.46))

                    Divider()

                    ShortcutListView(model: model)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var applicationHeader: some View {
        HStack(spacing: 12) {
            Group {
                if let url = AppResources.bundle.url(forResource: "OverCUEIcon", withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "headphones")
                        .resizable()
                        .scaledToFit()
                        .padding(7)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

            Text("OverCUE")
                .font(.system(size: 24, weight: .bold, design: .rounded))

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(bridgeStatusColor)
                    .frame(width: 8, height: 8)
                Text(model.bridgeStatus.displayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 62)
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.72))
    }

    private var bridgeStatusColor: Color {
        switch model.bridgeStatus {
        case .running: .green
        case .starting: .orange
        case .stopped: .secondary
        case .failed: .red
        }
    }
}

private enum MenuBarGhostIcon {
    static let image: NSImage = {
        let output = NSImage(size: NSSize(width: 18, height: 18))
        output.lockFocus()

        let body = NSBezierPath()
        body.move(to: NSPoint(x: 3, y: 3.1))
        body.line(to: NSPoint(x: 3, y: 9.2))
        body.curve(
            to: NSPoint(x: 9, y: 16.4),
            controlPoint1: NSPoint(x: 3, y: 13.8),
            controlPoint2: NSPoint(x: 5.4, y: 16.4)
        )
        body.curve(
            to: NSPoint(x: 15, y: 9.2),
            controlPoint1: NSPoint(x: 12.6, y: 16.4),
            controlPoint2: NSPoint(x: 15, y: 13.8)
        )
        body.line(to: NSPoint(x: 15, y: 3.1))
        body.curve(
            to: NSPoint(x: 12, y: 3.1),
            controlPoint1: NSPoint(x: 14.2, y: 1.9),
            controlPoint2: NSPoint(x: 12.8, y: 1.9)
        )
        body.curve(
            to: NSPoint(x: 9, y: 3.1),
            controlPoint1: NSPoint(x: 11.2, y: 4.3),
            controlPoint2: NSPoint(x: 9.8, y: 4.3)
        )
        body.curve(
            to: NSPoint(x: 6, y: 3.1),
            controlPoint1: NSPoint(x: 8.2, y: 1.9),
            controlPoint2: NSPoint(x: 6.8, y: 1.9)
        )
        body.curve(
            to: NSPoint(x: 3, y: 3.1),
            controlPoint1: NSPoint(x: 5.2, y: 4.3),
            controlPoint2: NSPoint(x: 3.8, y: 4.3)
        )
        body.close()
        NSColor.white.setFill()
        body.fill()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.white.setFill()
        NSColor.white.setStroke()

        let headband = NSBezierPath()
        headband.move(to: NSPoint(x: 4.7, y: 10.8))
        headband.curve(
            to: NSPoint(x: 13.3, y: 10.8),
            controlPoint1: NSPoint(x: 4.9, y: 15.5),
            controlPoint2: NSPoint(x: 13.1, y: 15.5)
        )
        headband.lineWidth = 1.45
        headband.lineCapStyle = .round
        headband.stroke()

        NSBezierPath(
            roundedRect: NSRect(x: 3.1, y: 8.7, width: 2.2, height: 3.6),
            xRadius: 0.8,
            yRadius: 0.8
        ).fill()
        NSBezierPath(
            roundedRect: NSRect(x: 12.7, y: 8.7, width: 2.2, height: 3.6),
            xRadius: 0.8,
            yRadius: 0.8
        ).fill()
        NSBezierPath(ovalIn: NSRect(x: 6.1, y: 9.5, width: 1.8, height: 2.2)).fill()
        NSBezierPath(ovalIn: NSRect(x: 10.1, y: 9.5, width: 1.8, height: 2.2)).fill()
        NSBezierPath(
            roundedRect: NSRect(x: 7.1, y: 6.4, width: 3.8, height: 1.8),
            xRadius: 0.9,
            yRadius: 0.9
        ).fill()

        NSGraphicsContext.restoreGraphicsState()
        output.unlockFocus()
        output.isTemplate = true
        return output
    }()
}

private enum AppResources {
    static let bundle: Bundle = {
        if let resourcesURL = Bundle.main.resourceURL,
           let packagedBundle = Bundle(
               url: resourcesURL.appendingPathComponent("OverCUE_OverCUEApp.bundle")
           ) {
            return packagedBundle
        }
        return .module
    }()
}
