import AppKit
import SwiftUI

@MainActor
final class RecordingOverlayState: ObservableObject, @unchecked Sendable {
    @Published var phase: RecordingPhase = .idle
    @Published var rmsLevel: Double = 0
    @Published var liveTranscriptVisible = false
    @Published var liveFinalizedText = ""
    @Published var livePartialText = ""
    @Published var liveStatusMessage: String?

    func resetLiveTranscript(visible: Bool) {
        liveTranscriptVisible = visible
        liveFinalizedText = ""
        livePartialText = ""
        liveStatusMessage = visible ? "Listening..." : nil
    }

    func applyLiveTranscript(_ snapshot: LiveTranscriptSnapshot) {
        liveFinalizedText = snapshot.finalizedText
        livePartialText = snapshot.partialText
        liveStatusMessage = snapshot.statusMessage
    }
}

@MainActor
final class RecordingOverlayController {
    private static let panelSize = NSSize(width: 150, height: 33)
    private static let transcriptPanelSize = NSSize(width: 520, height: 164)
    private static let bottomInset: CGFloat = 28
    private static let transcriptSpacing: CGFloat = 10

    private let state: RecordingOverlayState
    private var panel: NSPanel?
    private var transcriptPanel: NSPanel?

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

        if state.liveTranscriptVisible, transcriptPanel == nil {
            let transcriptPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: Self.transcriptPanelSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            transcriptPanel.level = .floating
            transcriptPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            transcriptPanel.isOpaque = false
            transcriptPanel.backgroundColor = .clear
            transcriptPanel.hasShadow = true
            transcriptPanel.contentView = NSHostingView(
                rootView: LiveTranscriptOverlayView(state: state)
                    .frame(width: Self.transcriptPanelSize.width, height: Self.transcriptPanelSize.height)
            )
            transcriptPanel.ignoresMouseEvents = true
            self.transcriptPanel = transcriptPanel
        }

        if let screen = targetScreen, let panel {
            let frame = screen.visibleFrame
            let compactOrigin = NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.minY + Self.bottomInset
            )
            panel.setFrameOrigin(compactOrigin)
            if state.liveTranscriptVisible, let transcriptPanel {
                transcriptPanel.setFrameOrigin(
                    NSPoint(
                        x: frame.midX - transcriptPanel.frame.width / 2,
                        y: compactOrigin.y + panel.frame.height + Self.transcriptSpacing
                    )
                )
                transcriptPanel.orderFrontRegardless()
            }
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
        transcriptPanel?.orderOut(nil)
    }

    private var targetScreen: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            NSMouseInRect(mouseLocation, screen.frame, false)
        } ?? NSScreen.main
    }
}

private struct LiveTranscriptOverlayView: View {
    @ObservedObject var state: RecordingOverlayState

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Live Transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if state.liveFinalizedText.isEmpty && state.livePartialText.isEmpty {
                            Text(state.liveStatusMessage ?? "Listening...")
                                .foregroundStyle(.secondary)
                        } else {
                            if !state.liveFinalizedText.isEmpty {
                                Text(state.liveFinalizedText)
                                    .foregroundStyle(.primary)
                                    .textSelection(.disabled)
                            }
                            if !state.livePartialText.isEmpty {
                                Text(state.livePartialText)
                                    .foregroundStyle(.secondary)
                                    .italic()
                                    .textSelection(.disabled)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .font(.callout)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .onChange(of: state.liveFinalizedText) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: state.livePartialText) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
    }
}

struct RecordingOverlayView: View {
    @ObservedObject var state: RecordingOverlayState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.phase == .recording ? "mic.fill" : "waveform")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.phase == .recording ? .red : .accentColor)
                .frame(width: 14, height: 14)

            if state.phase == .recording {
                WaveformView(level: state.rmsLevel)
                    .frame(width: 104, height: 14)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 104, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
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
                let normalizedLevel = min(1, max(0, level))
                let response = pow(normalizedLevel, 0.7)
                for index in 0..<bars {
                    let wave = (sin(t * 6 + Double(index) * 0.72) + 1) / 2
                    let shape = 0.35 + wave * 0.65
                    let amplitude = min(1, 0.08 + response * shape)
                    let height = size.height * amplitude
                    let x = CGFloat(index) * spacing + spacing * 0.2
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: spacing * 0.45, height: height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(.accentColor))
                }
            }
        }
    }
}
