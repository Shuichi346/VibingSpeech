import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayState: ObservableObject {
    @Published var phase: RecordingPhase = .idle
    @Published var rmsLevel: Double = 0
}

@MainActor
final class RecordingOverlayController {
    private static let panelSize = NSSize(width: 150, height: 33)
    private static let bottomInset: CGFloat = 28

    private let state: RecordingOverlayState
    private var panel: NSPanel?

    init(state: RecordingOverlayState) {
        self.state = state
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.panelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(
                rootView: RecordingOverlayView(state: state)
                    .frame(width: Self.panelSize.width, height: Self.panelSize.height)
            )
            panel.ignoresMouseEvents = true
            self.panel = panel
        }

        if let screen = targetScreen, let panel {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(
                NSPoint(
                    x: frame.midX - panel.frame.width / 2,
                    y: frame.minY + Self.bottomInset
                )
            )
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private var targetScreen: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var state: RecordingOverlayState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state.phase == .recording ? "mic.fill" : "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.phase == .recording ? .red : .accentColor)
                .frame(width: 16, height: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.phase == .recording ? "Recording" : "Transcribing")
                    .font(.system(size: 8, weight: .semibold))
                if state.phase == .recording {
                    WaveformView(level: state.rmsLevel)
                        .frame(width: 98, height: 8)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 98, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(.white.opacity(0.25), lineWidth: 1)
        )
    }
}

private struct WaveformView: View {
    let level: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Canvas { context, size in
                let bars = 18
                let spacing = size.width / CGFloat(bars)
                let t = timeline.date.timeIntervalSinceReferenceDate
                for index in 0..<bars {
                    let wave = (sin(t * 6 + Double(index) * 0.72) + 1) / 2
                    let amplitude = max(0.16, min(1, level + wave * 0.45))
                    let height = size.height * amplitude
                    let x = CGFloat(index) * spacing + spacing * 0.2
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: spacing * 0.45, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.accentColor))
                }
            }
        }
    }
}
