import AppKit

/// A short, large message that fades after a moment: "Copied." Segue waits
/// for it before quitting, so it is used only when there is nothing else on
/// screen to confirm what happened.
@MainActor
enum Toast {
    private static var panel: NSPanel?

    static func show(_ text: String, seconds: Double = 1.4, completion: (@MainActor @Sendable () -> Void)? = nil) {
        panel?.orderOut(nil)
        let label = NSTextField(labelWithString: text)
        label.font = Design.font(20, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center
        label.sizeToFit()
        let size = NSSize(width: label.frame.width + 48, height: label.frame.height + 28)
        label.frame = NSRect(x: 24, y: 14, width: label.frame.width, height: label.frame.height)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = Design.increaseContrast ? .windowBackground : .hudWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.addSubview(label)
        p.contentView = effect

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let v = screen?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: v.midX - size.width / 2, y: v.minY + v.height * 0.12))
        }
        p.orderFrontRegardless()
        panel = p
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            if Design.reduceMotion {
                p.orderOut(nil)
                completion?()
            } else {
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    p.animator().alphaValue = 0
                }, completionHandler: {
                    Task { @MainActor in
                        p.orderOut(nil)
                        completion?()
                    }
                })
            }
        }
    }
}
