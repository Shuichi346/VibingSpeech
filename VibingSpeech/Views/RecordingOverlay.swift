import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayState: ObservableObject {
    @Published var phase: RecordingPhase = .idle
    @Published var rmsLevel: Double = 0
}

@MainActor
final class RecordingOverlayController {
    private let state: RecordingOverlayState
    private var panel: NSPanel?

    init(state: RecordingOverlayState) {
        self.state = state
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 300, height: 74),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: RecordingOverlayView(state: state))
            panel.ignoresMouseEvents = true
            self.panel = panel
        }

        if let screen = NSScreen.main, let panel {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - 130))
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var state: RecordingOverlayState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.phase == .recording ? "mic.fill" : "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(state.phase == .recording ? .red : .accentColor)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 7) {
                Text(state.phase == .recording ? "Recording" : "Transcribing")
                    .font(.headline)
                if state.phase == .recording {
                    WaveformView(level: state.rmsLevel)
                        .frame(width: 190, height: 18)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 190, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
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

