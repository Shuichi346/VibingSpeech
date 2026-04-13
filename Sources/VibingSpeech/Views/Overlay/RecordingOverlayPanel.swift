//
//  RecordingOverlayPanel.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import AppKit
import SwiftUI
import Combine

// MARK: - Observable state object owned by NSPanel

@MainActor
final class OverlayState: ObservableObject {
    @Published var recordingState: AppState.RecordingState = .idle
    @Published var barHeights: [CGFloat]

    let barCount: Int
    private let minBarHeight: CGFloat = 3.0
    private let maxBarHeight: CGFloat = 28.0  // capsule内部高さギリギリまで

    private var _animationTimer: Timer?
    private var audioLevelProvider: (() -> Float)?

    private var smoothedLevel: CGFloat = 0

    init(barCount: Int = 20) {
        self.barCount = barCount
        self.barHeights = Array(repeating: 3.0, count: barCount)
    }

    func setAudioLevelProvider(_ provider: @escaping () -> Float) {
        self.audioLevelProvider = provider
    }

    func startAnimating() {
        stopAnimating()
        _animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateBars()
            }
        }
    }

    func stopAnimating() {
        _animationTimer?.invalidate()
        _animationTimer = nil
        barHeights = Array(repeating: minBarHeight, count: barCount)
        smoothedLevel = 0
    }

    private func updateBars() {
        let rawLevel = CGFloat(audioLevelProvider?() ?? 0)

        // Fast attack, slow decay
        if rawLevel > smoothedLevel {
            smoothedLevel = smoothedLevel * 0.1 + rawLevel * 0.9
        } else {
            smoothedLevel = smoothedLevel * 0.75 + rawLevel * 0.25
        }

        // 超アグレッシブな増幅: 0~0.15 → 0~1.0 にマッピング
        // 通常の発話(0.05~0.15)で天井に届く
        let amplified = min(pow(smoothedLevel * 8.0, 0.8), 1.0)

        // 無音でも微小な動きを保証
        let level = max(amplified, 0.1)

        let center = CGFloat(barCount - 1) / 2.0
        var newHeights = [CGFloat]()

        for i in 0..<barCount {
            let distanceFromCenter = abs(CGFloat(i) - center) / center

            // 中央が最も高く、端に向かって急激に下がるエンベロープ
            let envelope = 1.0 - pow(distanceFromCenter, 1.3) * 0.65

            // バーごとのランダム揺らぎ
            let randomFactor = CGFloat.random(in: 0.55...1.0)

            let target = minBarHeight + (maxBarHeight - minBarHeight) * level * envelope * randomFactor
            let clamped = min(max(target, minBarHeight), maxBarHeight)

            let previous = i < barHeights.count ? barHeights[i] : minBarHeight
            newHeights.append(previous * 0.25 + clamped * 0.75)
        }

        barHeights = newHeights
    }

    deinit {
        _animationTimer?.invalidate()
    }
}

// MARK: - NSPanel

class RecordingOverlayPanel: NSPanel {
    private var hostingView: NSHostingView<RecordingOverlayView>?
    private let overlayState = OverlayState()

    private let panelWidth: CGFloat = 160
    private let panelHeight: CGFloat = 36

    var recordingState: AppState.RecordingState = .idle {
        didSet {
            overlayState.recordingState = recordingState
            switch recordingState {
            case .recording:
                overlayState.startAnimating()
            case .transcribing, .idle:
                overlayState.stopAnimating()
            }
        }
    }

    func setAudioLevelProvider(_ provider: @escaping () -> Float) {
        overlayState.setAudioLevelProvider(provider)
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.ignoresMouseEvents = false

        let view = RecordingOverlayView(state: overlayState)
        let hosting = NSHostingView(rootView: view)
        self.hostingView = hosting
        self.contentView = hosting

        positionAtBottomCenter()
    }

    private func positionAtBottomCenter() {
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.minY + 12
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func showOverlay() {
        positionAtBottomCenter()
        orderFront(nil)
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 1
        }
    }

    func hideOverlay() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            self.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
            }
        })
    }
}

// MARK: - SwiftUI View (pure rendering only)

struct RecordingOverlayView: View {
    @ObservedObject var state: OverlayState

    private let barWidth: CGFloat = 2.5
    private let barSpacing: CGFloat = 2.0
    private let capsuleHeight: CGFloat = 32
    private let horizontalPadding: CGFloat = 14

    var body: some View {
        ZStack {
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 1)

            if state.recordingState == .transcribing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
            } else {
                HStack(alignment: .center, spacing: barSpacing) {
                    ForEach(0..<state.barCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: barWidth / 2)
                            .fill(Color.black.opacity(barOpacity(for: index)))
                            .frame(
                                width: barWidth,
                                height: state.barHeights.indices.contains(index)
                                    ? state.barHeights[index]
                                    : 3.0
                            )
                            .animation(.easeOut(duration: 0.06), value: state.barHeights)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
        .frame(height: capsuleHeight)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func barOpacity(for index: Int) -> Double {
        let center = CGFloat(state.barCount) / 2.0
        let distance = abs(CGFloat(index) - center) / center
        return 1.0 - (distance * 0.25)
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
