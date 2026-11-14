// Keyboard Lock — a tiny menu bar utility that swallows keyboard input
// (including media and function keys) while leaving the screen, trackpad
// and mouse untouched. Built for cats who walk on laptops.

import AppKit
import ApplicationServices
import ServiceManagement

// MARK: - Event tap

/// The live tap, read from the C callback so it can re-enable itself if the
/// system disables it. Only touched on the main thread (the tap's run loop).
nonisolated(unsafe) private var liveTap: CFMachPort?

/// NX_SYSDEFINED: carries media keys (volume, brightness, play/pause, …).
private let systemDefinedType: UInt32 = 14
/// NX_SUBTYPE_AUX_CONTROL_BUTTONS: the media/function key subtype.
private let auxControlButtonsSubtype: Int16 = 8

private let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let liveTap { CGEvent.tapEnable(tap: liveTap, enable: true) }
        return Unmanaged.passUnretained(event)
    case .keyDown, .keyUp, .flagsChanged:
        return nil
    default:
        if type.rawValue == systemDefinedType,
           let nsEvent = NSEvent(cgEvent: event),
           nsEvent.subtype.rawValue == auxControlButtonsSubtype {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

@MainActor
final class KeyboardBlocker {
    private(set) var isActive = false
    private var runLoopSource: CFRunLoopSource?

    /// Returns false when the system refuses the tap (no Accessibility access).
    func start() -> Bool {
        guard !isActive else { return true }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << systemDefinedType)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        liveTap = tap
        runLoopSource = source
        isActive = true
        return true
    }

    func stop() {
        guard isActive else { return }
        if let liveTap {
            CGEvent.tapEnable(tap: liveTap, enable: false)
            CFMachPortInvalidate(liveTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        liveTap = nil
        runLoopSource = nil
        isActive = false
    }
}

// MARK: - Menu header row (title + switch, like the Wi-Fi and Bluetooth menus)

@MainActor
final class LockRowView: NSView {
    var onChange: ((Bool) -> Void)?

    private let toggle = NSSwitch()
    private let titleLabel = NSTextField(labelWithString: "Keyboard Lock")
    private let detailLabel = NSTextField(labelWithString: "")

    init(width: CGFloat) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        titleLabel.textColor = .labelColor

        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(switchFlipped)
        toggle.setAccessibilityLabel("Keyboard Lock")

        for view in [titleLabel, detailLabel, toggle] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            detailLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
        update(locked: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(locked: Bool) {
        toggle.state = locked ? .on : .off
        detailLabel.stringValue = locked
            ? "Keys are ignored. Turn off to type again."
            : "Ignore keys while the screen keeps playing."
        let width = frame.width
        frame.size = NSSize(width: width, height: fittingSize.height)
    }

    @objc private func switchFlipped() {
        onChange?(toggle.state == .on)
    }

    // Clicking anywhere on the row flips the switch, as in system menus.
    override func mouseUp(with event: NSEvent) {
        toggle.state = toggle.state == .on ? .off : .on
        switchFlipped()
    }
}

// MARK: - HUD (a small glass bezel under the menu bar item)

@MainActor
final class HUD {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(symbol: String, text: String, below anchor: NSStatusBarButton?) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        icon.contentTintColor = .labelColor

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 18)

        let glass = NSGlassEffectView()
        glass.cornerRadius = 20
        glass.contentView = stack

        let size = stack.fittingSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = glass

        // Center under the menu bar icon; fall back to the top of the main screen.
        let screen = anchor?.window?.screen ?? NSScreen.main
        if let screen {
            let visible = screen.visibleFrame
            var midX = visible.midX
            if let anchor, let window = anchor.window {
                midX = window.convertToScreen(anchor.convert(anchor.bounds, to: nil)).midX
            }
            let x = min(max(midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: visible.maxY - size.height - 8))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, let self, self.panel === panel else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated { panel.orderOut(nil) }
            })
        }
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let blocker = KeyboardBlocker()
    private let hud = HUD()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let lockRow = LockRowView(width: 280)
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "Allow Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = .terminationOnRemoval
        refreshIcon()

        lockRow.onChange = { [weak self] on in self?.setLocked(on) }
        let rowItem = NSMenuItem()
        rowItem.view = lockRow
        menu.addItem(rowItem)
        menu.addItem(.separator())
        loginItem.target = self
        accessItem.target = self
        menu.addItem(accessItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Keyboard Lock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        // Never leave the keyboard blocked behind a lock screen or a switched-out session.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(forceUnlock), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(forceUnlock), name: NSWorkspace.willSleepNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(forceUnlock), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(forceUnlock), name: .init("com.apple.screensaver.didstart"), object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        blocker.stop()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        lockRow.update(locked: blocker.isActive)
        accessItem.isHidden = AXIsProcessTrusted()
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func openAccessibilitySettings() {
        promptForAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Locking

    private func setLocked(_ locked: Bool) {
        if locked {
            guard blocker.start() else {
                lockRow.update(locked: false)
                menu.cancelTracking()
                promptForAccess()
                return
            }
            hud.show(symbol: "lock.fill", text: "Keyboard Locked", below: statusItem.button)
        } else {
            blocker.stop()
            hud.show(symbol: "keyboard", text: "Keyboard Unlocked", below: statusItem.button)
        }
        lockRow.update(locked: blocker.isActive)
        refreshIcon()
    }

    @objc private func forceUnlock() {
        guard blocker.isActive else { return }
        blocker.stop()
        lockRow.update(locked: false)
        refreshIcon()
    }

    private func promptForAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func refreshIcon() {
        guard let button = statusItem.button else { return }
        let locked = blocker.isActive
        let image = NSImage(
            systemSymbolName: locked ? "lock.fill" : "keyboard",
            accessibilityDescription: locked ? "Keyboard Locked" : "Keyboard Lock"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = locked ? "Keyboard is locked" : "Keyboard Lock"
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
