// Keyboard Lock — a tiny menu bar utility that swallows keyboard input
// (including media and function keys) and, optionally, the trackpad,
// while the screen keeps playing. Built for cats who walk on laptops.

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Shortcut

/// A key plus at least one of ⌘ ⌥ ⌃ (⇧ optional), saved in UserDefaults.
struct Shortcut: Equatable {
    var keyCode: UInt16
    var modifiers: NSEvent.ModifierFlags
    var keyName: String

    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let standard = Shortcut(keyCode: UInt16(kVK_ANSI_L), modifiers: [.control, .option, .command], keyName: "L")

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyName: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.relevantModifiers)
        self.keyName = keyName
    }

    /// nil when the event has no ⌘/⌥/⌃, so a stray paw can't trigger it.
    init?(event: NSEvent) {
        let mods = event.modifierFlags.intersection(Self.relevantModifiers)
        guard !mods.isDisjoint(with: [.command, .option, .control]) else { return nil }
        self.init(keyCode: event.keyCode, modifiers: mods, keyName: Self.name(for: event))
    }

    static func modifierSymbols(_ mods: NSEvent.ModifierFlags) -> String {
        var s = ""
        if mods.contains(.control) { s += "⌃" }
        if mods.contains(.option) { s += "⌥" }
        if mods.contains(.shift) { s += "⇧" }
        if mods.contains(.command) { s += "⌘" }
        return s
    }

    var displayString: String { Self.modifierSymbols(modifiers) + keyName }

    var carbonModifiers: UInt32 {
        var m: UInt32 = 0
        if modifiers.contains(.command) { m |= UInt32(cmdKey) }
        if modifiers.contains(.option) { m |= UInt32(optionKey) }
        if modifiers.contains(.control) { m |= UInt32(controlKey) }
        if modifiers.contains(.shift) { m |= UInt32(shiftKey) }
        return m
    }

    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if modifiers.contains(.command) { f.insert(.maskCommand) }
        if modifiers.contains(.option) { f.insert(.maskAlternate) }
        if modifiers.contains(.control) { f.insert(.maskControl) }
        if modifiers.contains(.shift) { f.insert(.maskShift) }
        return f
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫",
        kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    private static func name(for event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        let base = event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers ?? ""
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? "Key \(event.keyCode)" : trimmed
    }

    // Persistence
    private enum Key {
        static let code = "shortcutKeyCode", mods = "shortcutModifiers", name = "shortcutKeyName"
    }

    static func load() -> Shortcut {
        let d = UserDefaults.standard
        guard d.object(forKey: Key.code) != nil, let name = d.string(forKey: Key.name) else { return .standard }
        let s = Shortcut(
            keyCode: UInt16(d.integer(forKey: Key.code)),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: Key.mods))),
            keyName: name
        )
        return s.modifiers.isDisjoint(with: [.command, .option, .control]) ? .standard : s
    }

    func save() {
        let d = UserDefaults.standard
        d.set(Int(keyCode), forKey: Key.code)
        d.set(Int(modifiers.rawValue), forKey: Key.mods)
        d.set(keyName, forKey: Key.name)
    }
}

// MARK: - Global hotkey (turns the lock on; no permission needed, free when idle)

private let hotKeyCallback: EventHandlerUPP = { _, _, userData in
    guard let userData else { return noErr }
    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated { hotKey.onPress?() }
    return noErr
}

@MainActor
final class GlobalHotKey {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Returns false if another app already owns this combination.
    @discardableResult
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4B4C_434B) /* 'KLCK' */, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}

// MARK: - Event tap
// State read from the C callback. Only touched on the main thread (the tap's run loop).

nonisolated(unsafe) private var liveTap: CFMachPort?
nonisolated(unsafe) private var blockKeys = false
nonisolated(unsafe) private var blockPointer = false
nonisolated(unsafe) private var unlockKeyCode: Int64 = -1
nonisolated(unsafe) private var unlockFlags: CGEventFlags = []
nonisolated(unsafe) private var frozenCursor: CGPoint = .zero
nonisolated(unsafe) private var onUnlockShortcut: (@MainActor @Sendable () -> Void)?

/// NX_SYSDEFINED: carries media keys (volume, brightness, play/pause, …).
private let systemDefinedType: UInt32 = 14
/// NX_SUBTYPE_AUX_CONTROL_BUTTONS: the media/function key subtype.
private let auxControlButtonsSubtype: Int16 = 8
private let shortcutModifierMask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

private let keyboardTypes: [UInt32] = [
    CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue, CGEventType.flagsChanged.rawValue, systemDefinedType,
]
private let cursorMoveTypes: Set<UInt32> = [
    CGEventType.mouseMoved.rawValue, CGEventType.leftMouseDragged.rawValue,
    CGEventType.rightMouseDragged.rawValue, CGEventType.otherMouseDragged.rawValue,
]
/// Clicks, scrolling, tablet events and trackpad gestures (rotate 18, begin/end
/// gesture 19/20, gesture 29, magnify 30, swipe 31, smart magnify 32, pressure 34).
private let pointerTypes: Set<UInt32> = cursorMoveTypes.union([
    CGEventType.leftMouseDown.rawValue, CGEventType.leftMouseUp.rawValue,
    CGEventType.rightMouseDown.rawValue, CGEventType.rightMouseUp.rawValue,
    CGEventType.otherMouseDown.rawValue, CGEventType.otherMouseUp.rawValue,
    CGEventType.scrollWheel.rawValue, CGEventType.tabletPointer.rawValue,
    CGEventType.tabletProximity.rawValue, 18, 19, 20, 29, 30, 31, 32, 34,
])

private let tapCallback: CGEventTapCallBack = { _, type, event, _ in
    let pass = Unmanaged.passUnretained(event)
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let liveTap { CGEvent.tapEnable(tap: liveTap, enable: true) }
        return pass
    case .keyDown:
        // The unlock shortcut works whatever is locked, and is never passed on.
        if event.getIntegerValueField(.keyboardEventKeycode) == unlockKeyCode,
           event.flags.intersection(shortcutModifierMask) == unlockFlags {
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0, let handler = onUnlockShortcut {
                Task { @MainActor in handler() }
            }
            return nil
        }
        return blockKeys ? nil : pass
    case .keyUp, .flagsChanged:
        return blockKeys ? nil : pass
    default:
        let raw = type.rawValue
        if raw == systemDefinedType {
            if blockKeys, let nsEvent = NSEvent(cgEvent: event),
               nsEvent.subtype.rawValue == auxControlButtonsSubtype {
                return nil
            }
            return pass
        }
        if blockPointer, pointerTypes.contains(raw) {
            // Belt and braces: if the cursor slipped anyway, put it back.
            if cursorMoveTypes.contains(raw) {
                let p = event.location
                if abs(p.x - frozenCursor.x) > 0.5 || abs(p.y - frozenCursor.y) > 0.5 {
                    CGWarpMouseCursorPosition(frozenCursor)
                }
            }
            return nil
        }
        return pass
    }
}

@MainActor
final class InputBlocker {
    private(set) var keyboardLocked = false
    private(set) var pointerLocked = false
    var isActive: Bool { keyboardLocked || pointerLocked }
    private var runLoopSource: CFRunLoopSource?

    func setUnlockShortcut(_ shortcut: Shortcut) {
        unlockKeyCode = Int64(shortcut.keyCode)
        unlockFlags = shortcut.cgFlags
    }

    /// Returns false when the system refuses the tap (no Accessibility access).
    func set(keyboard: Bool, pointer: Bool) -> Bool {
        guard keyboard != keyboardLocked || pointer != pointerLocked else { return true }
        removeTap()
        if keyboard || pointer {
            // Keyboard events are always watched so the shortcut can unlock.
            // Pointer events are only watched while the trackpad is locked.
            var types = keyboardTypes
            if pointer { types += pointerTypes }
            let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1)) }
            guard let tap = CGEvent.tapCreate(
                tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: tapCallback, userInfo: nil
            ) else {
                setPointerFrozen(false)
                keyboardLocked = false
                pointerLocked = false
                blockKeys = false
                blockPointer = false
                return false
            }
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            liveTap = tap
            runLoopSource = source
        }
        setPointerFrozen(pointer)
        keyboardLocked = keyboard
        pointerLocked = pointer
        blockKeys = keyboard
        blockPointer = pointer
        return true
    }

    private func setPointerFrozen(_ frozen: Bool) {
        guard frozen != pointerLocked else { return }
        if frozen { frozenCursor = CGEvent(source: nil)?.location ?? .zero }
        CGAssociateMouseAndMouseCursorPosition(frozen ? 0 : 1)
    }

    private func removeTap() {
        if let liveTap {
            CGEvent.tapEnable(tap: liveTap, enable: false)
            CFMachPortInvalidate(liveTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        liveTap = nil
        runLoopSource = nil
    }
}

// MARK: - Menu toggle row (title + switch, like the Wi-Fi and Bluetooth menus)

@MainActor
final class ToggleRowView: NSView {
    var onChange: ((Bool) -> Void)?

    private let toggle = NSSwitch()
    private let titleLabel: NSTextField
    private let detailLabel = NSTextField(labelWithString: "")

    init(title: String, width: CGFloat) {
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 10))

        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .bold)
        titleLabel.textColor = .labelColor

        detailLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        toggle.controlSize = .mini
        toggle.target = self
        toggle.action = #selector(switchFlipped)
        toggle.setAccessibilityLabel(title)

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(on: Bool, detail: String) {
        toggle.state = on ? .on : .off
        detailLabel.stringValue = detail
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

    func show(symbol: String, text: String, detail: String? = nil, below anchor: NSStatusBarButton?) {
        hideTask?.cancel()
        panel?.orderOut(nil)

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        icon.contentTintColor = .labelColor

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor

        let textStack = NSStackView(views: [label])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1
        if let detail {
            let sub = NSTextField(labelWithString: detail)
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = .secondaryLabelColor
            textStack.addArrangedSubview(sub)
        }

        let stack = NSStackView(views: [icon, textStack])
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

        let visibleFor: Duration = detail == nil ? .seconds(1.4) : .seconds(2.4)
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: visibleFor)
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

// MARK: - Shortcut recorder (click, then type the new combination)

@MainActor
final class ShortcutRecorder: NSButton {
    var shortcut: Shortcut { didSet { refreshTitle() } }
    var onChange: ((Shortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private(set) var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            refreshTitle()
            onRecordingChange?(isRecording)
        }
    }

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        bezelStyle = .push
        target = self
        action = #selector(clicked)
        setAccessibilityLabel("Lock shortcut")
        refreshTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    func stopRecording() { isRecording = false }

    @objc private func clicked() {
        isRecording.toggle()
        if isRecording { window?.makeFirstResponder(self) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        let held = Shortcut.modifierSymbols(event.modifierFlags.intersection(Shortcut.relevantModifiers))
        title = held.isEmpty ? "Type Shortcut…" : held
    }

    private func record(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(Shortcut.relevantModifiers)
        if event.keyCode == UInt16(kVK_Escape), mods.isEmpty {
            isRecording = false
            return
        }
        guard let new = Shortcut(event: event) else {
            NSSound.beep()   // needs ⌘, ⌥ or ⌃
            return
        }
        shortcut = new
        isRecording = false
        onChange?(new)
    }

    private func refreshTitle() {
        title = isRecording ? "Type Shortcut…" : shortcut.displayString
    }
}

// MARK: - Settings window

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    let recorder: ShortcutRecorder
    private let trackpadBox = NSButton(checkboxWithTitle: "Shortcut also locks the trackpad", target: nil, action: nil)
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    var onTrackpadOptionChange: ((Bool) -> Void)?

    init(shortcut: Shortcut, shortcutLocksTrackpad: Bool) {
        recorder = ShortcutRecorder(shortcut: shortcut)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
            styleMask: [.titled, .closable], backing: .buffered, defer: true
        )
        window.title = "Keyboard Lock Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let shortcutLabel = NSTextField(labelWithString: "Lock shortcut:")
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true

        trackpadBox.state = shortcutLocksTrackpad ? .on : .off
        trackpadBox.target = self
        trackpadBox.action = #selector(trackpadBoxChanged)

        noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.preferredMaxLayoutWidth = 220
        showDefaultNote()

        let grid = NSGridView(views: [
            [shortcutLabel, recorder],
            [NSGridCell.emptyContentView, trackpadBox],
            [NSGridCell.emptyContentView, noteLabel],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.cell(for: recorder)?.xPlacement = .leading
        grid.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        window.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        if window?.isVisible != true { window?.center() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
    }

    func showDefaultNote() {
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.stringValue = "Press it again to unlock. Use ⌘, ⌥ or ⌃ so a paw can’t press it by accident."
    }

    func showConflict(_ shortcut: Shortcut) {
        noteLabel.textColor = .systemRed
        noteLabel.stringValue = "\(shortcut.displayString) is already used by another app. Try a different shortcut."
    }

    @objc private func trackpadBoxChanged() {
        onTrackpadOptionChange?(trackpadBox.state == .on)
    }

    func windowWillClose(_ notification: Notification) {
        recorder.stopRecording()
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let blocker = InputBlocker()
    private let hotKey = GlobalHotKey()
    private let hud = HUD()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let keyboardRow = ToggleRowView(title: "Keyboard Lock", width: 280)
    private let trackpadRow = ToggleRowView(title: "Trackpad Lock", width: 280)
    private let shortcutItem = NSMenuItem(title: "Shortcut…", action: #selector(openSettings), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "Allow Accessibility Access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private var settings: SettingsWindowController?
    private var pendingLock: Task<Void, Never>?

    private var shortcut = Shortcut.load()
    private var shortcutLocksTrackpad: Bool {
        get { UserDefaults.standard.bool(forKey: "shortcutLocksTrackpad") }
        set { UserDefaults.standard.set(newValue, forKey: "shortcutLocksTrackpad") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = .terminationOnRemoval

        keyboardRow.onChange = { [weak self] on in self?.keyboardSwitchFlipped(on) }
        trackpadRow.onChange = { [weak self] on in self?.trackpadSwitchFlipped(on) }
        for row in [keyboardRow, trackpadRow] {
            let item = NSMenuItem()
            item.view = row
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for item in [shortcutItem, accessItem, loginItem] { item.target = self }
        menu.addItem(shortcutItem)
        menu.addItem(.separator())
        menu.addItem(accessItem)
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Keyboard Lock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu

        blocker.setUnlockShortcut(shortcut)
        hotKey.onPress = { [weak self] in self?.shortcutPressedWhileUnlocked() }
        hotKey.register(shortcut)
        onUnlockShortcut = { [weak self] in self?.apply(keyboard: false, pointer: false) }
        refreshUI()

        // Never leave input blocked behind a lock screen or a switched-out session.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(forceUnlock), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(forceUnlock), name: NSWorkspace.willSleepNotification, object: nil)
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(forceUnlock), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(forceUnlock), name: .init("com.apple.screensaver.didstart"), object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        _ = blocker.set(keyboard: false, pointer: false)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshUI()
        accessItem.isHidden = AXIsProcessTrusted()
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func keyboardSwitchFlipped(_ on: Bool) {
        apply(keyboard: on, pointer: blocker.pointerLocked)
    }

    private func trackpadSwitchFlipped(_ on: Bool) {
        guard on else { return apply(keyboard: blocker.keyboardLocked, pointer: false) }
        // Close the menu and let the click finish before the pointer freezes.
        menu.cancelTracking()
        pendingLock?.cancel()
        pendingLock = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            self.pendingLock = nil
            self.apply(keyboard: self.blocker.keyboardLocked, pointer: true)
        }
    }

    @objc private func openSettings() {
        if settings == nil {
            let controller = SettingsWindowController(shortcut: shortcut, shortcutLocksTrackpad: shortcutLocksTrackpad)
            controller.recorder.onRecordingChange = { [weak self] recording in
                guard let self else { return }
                // Don't fire the old shortcut while typing the new one.
                if recording { self.hotKey.unregister() } else { self.hotKey.register(self.shortcut) }
            }
            controller.recorder.onChange = { [weak self] new in self?.shortcutChanged(to: new) }
            controller.onTrackpadOptionChange = { [weak self] on in self?.shortcutLocksTrackpad = on }
            settings = controller
        }
        settings?.show()
    }

    private func shortcutChanged(to new: Shortcut) {
        let old = shortcut
        guard hotKey.register(new) else {
            settings?.showConflict(new)
            settings?.recorder.shortcut = old
            hotKey.register(old)
            NSSound.beep()
            return
        }
        settings?.showDefaultNote()
        shortcut = new
        new.save()
        blocker.setUnlockShortcut(new)
        refreshUI()
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

    /// The global hotkey only fires while nothing is locked; once locked, the
    /// event tap catches the shortcut itself and unlocks.
    private func shortcutPressedWhileUnlocked() {
        if blocker.isActive { return apply(keyboard: false, pointer: false) }
        guard pendingLock == nil else { return }
        let held = shortcut
        let alsoTrackpad = shortcutLocksTrackpad
        // Wait for the keys to come up first, or the swallowed key-ups would
        // leave ⌘/⌥/⌃ looking held down to the rest of the system.
        pendingLock = Task { [weak self] in
            let deadline = ContinuousClock.now + .seconds(2)
            while ContinuousClock.now < deadline, Self.keysStillDown(held) {
                try? await Task.sleep(for: .milliseconds(20))
            }
            guard !Task.isCancelled, let self else { return }
            self.pendingLock = nil
            self.apply(keyboard: true, pointer: alsoTrackpad)
        }
    }

    private static func keysStillDown(_ s: Shortcut) -> Bool {
        let flags = CGEventSource.flagsState(.hidSystemState).intersection(shortcutModifierMask)
        return !flags.isEmpty || CGEventSource.keyState(.hidSystemState, key: CGKeyCode(s.keyCode))
    }

    private func apply(keyboard: Bool, pointer: Bool, announce: Bool = true) {
        let before = (keyboard: blocker.keyboardLocked, pointer: blocker.pointerLocked)
        guard blocker.set(keyboard: keyboard, pointer: pointer) else {
            refreshUI()
            menu.cancelTracking()
            promptForAccess()
            return
        }
        refreshUI()
        guard announce else { return }

        func names(keyboard k: Bool, pointer p: Bool) -> String {
            [k ? "Keyboard" : nil, p ? "Trackpad" : nil].compactMap { $0 }.joined(separator: " & ")
        }
        let gained = names(keyboard: keyboard && !before.keyboard, pointer: pointer && !before.pointer)
        let lost = names(keyboard: !keyboard && before.keyboard, pointer: !pointer && before.pointer)
        if !gained.isEmpty {
            hud.show(symbol: "lock.fill", text: "\(names(keyboard: keyboard, pointer: pointer)) Locked",
                     detail: "Press \(shortcut.displayString) to unlock", below: statusItem.button)
        } else if !lost.isEmpty {
            hud.show(symbol: "lock.open.fill", text: "\(lost) Unlocked", below: statusItem.button)
        }
    }

    @objc private func forceUnlock() {
        pendingLock?.cancel()
        pendingLock = nil
        guard blocker.isActive else { return }
        apply(keyboard: false, pointer: false, announce: false)
    }

    private func promptForAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func refreshUI() {
        let key = shortcut.displayString
        keyboardRow.update(
            on: blocker.keyboardLocked,
            detail: blocker.keyboardLocked ? "Keys are ignored. Press \(key) to unlock." : "Ignore keys while the screen keeps playing."
        )
        trackpadRow.update(
            on: blocker.pointerLocked,
            detail: blocker.pointerLocked ? "Pointer is frozen. Press \(key) to unlock." : "Ignore clicks, scrolls and gestures."
        )
        shortcutItem.attributedTitle = Self.menuTitle("Lock Shortcut…", trailing: key)

        guard let button = statusItem?.button else { return }
        let locked = blocker.isActive
        let image = NSImage(
            systemSymbolName: locked ? "lock.fill" : "keyboard",
            accessibilityDescription: locked ? "Input Locked" : "Keyboard Lock"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = locked ? "Locked — press \(key) to unlock" : "Keyboard Lock (\(key))"
    }

    /// A menu title with the shortcut right-aligned, like a key equivalent,
    /// without making it one (so typing it in the open menu doesn't fire it).
    private static func menuTitle(_ title: String, trailing: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: 236)]
        let font = NSFont.menuFont(ofSize: 0)
        let s = NSMutableAttributedString(string: "\(title)\t", attributes: [.font: font, .paragraphStyle: style])
        s.append(NSAttributedString(string: trailing, attributes: [
            .font: font, .paragraphStyle: style, .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return s
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
