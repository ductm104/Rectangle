/// SpaceNumberOSD.swift

import Cocoa

/// Briefly shows the number of the Space just switched to. Without the slide
/// animation there's otherwise little sign of where you've landed.
/// Adapted from InstantSpaceSwitcher's OSDWindow.
class SpaceNumberOSD {
    static let shared = SpaceNumberOSD()

    private let size: CGFloat = 140
    private let duration: TimeInterval = 0.5
    private var window: NSWindow?
    private var label: NSTextField?
    private var hideTimer: Timer?

    private init() {}

    func show(spaceNumber: Int) {
        guard Defaults.showSpaceNumberOnSwitch.enabled,
              !iss_is_mission_control_active()
        else { return }

        hideTimer?.invalidate()
        hideTimer = nil

        if window == nil {
            createWindow()
        }
        guard let window, let label else { return }

        label.stringValue = "\(spaceNumber)"

        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: visibleFrame.midX - size / 2, y: visibleFrame.midY - size / 2))
        }

        window.alphaValue = 1
        window.orderFrontRegardless()

        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    private func createWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false

        let visualEffect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 18
        visualEffect.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 48, weight: .medium)
        label.textColor = .labelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(label)
        window.contentView = visualEffect

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: visualEffect.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor)
        ])

        self.window = window
        self.label = label
    }

    private func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window?.animator().alphaValue = 0
        }
    }
}
