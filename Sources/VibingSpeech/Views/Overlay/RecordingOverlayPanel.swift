//
//  RecordingOverlayPanel.swift
//  VibingSpeech
//
//  Created by Shuichi on 2026/04/12.
//  Copyright © 2026 Shuichi. All rights reserved.
//

import AppKit
import SwiftUI

class RecordingOverlayPanel: NSPanel {
    private var hostingView: NSHostingView<RecordingOverlayView>?

    var recordingState: AppState.RecordingState = .idle {
        didSet {
            hostingView?.rootView.recordingState = recordingState
        }
    }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.ignoresMouseEvents = false

        let overlayView = RecordingOverlayView(recordingState: .idle)
        self.hostingView = NSHostingView(rootView: overlayView)
        self.contentView = hostingView

        // Position at bottom right of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - frame.width - 20
            let y = screenFrame.minY + 20
            setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    func showOverlay() {
        orderFront(nil)
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 1
        }
    }

    func hideOverlay() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            self.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                self.orderOut(nil)
            }
        })
    }
}

struct RecordingOverlayView: View {
    var recordingState: AppState.RecordingState

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .background(
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                        .clipShape(Circle())
                )
                .frame(width: 60, height: 60)
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)

            if recordingState == .transcribing {
                ProgressView()
                    .controlSize(.large)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
                    .scaleEffect(isPulsing ? 1.1 : 1.0)
                    .opacity(isPulsing ? 1.0 : 0.7)
                    .animation(
                        isPulsing
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isPulsing
                    )
            }
        }
        .onAppear {
            if recordingState == .recording {
                isPulsing = true
            }
        }
        .onChange(of: recordingState) { _, newState in
            isPulsing = (newState == .recording)
        }
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
