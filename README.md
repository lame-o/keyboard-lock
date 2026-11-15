# Keyboard Lock

A tiny macOS menu bar app that ignores every key press while the screen keeps playing. Made for cats who walk across laptops during cat videos.

- Blocks all keys, including Space, Escape, media/volume/brightness keys, Caps Lock, fn/Globe and ⌘Tab
- Optional **Trackpad Lock** that ignores clicks, scrolling, gestures and pointer movement
- A keyboard shortcut (⌃⌥⌘L by default, change it in **Lock Shortcut…**) locks and unlocks from anywhere. It's the way out when the trackpad is locked
- Native look: a Wi-Fi-style switch in the menu, and a glass HUD when you lock or unlock
- About 450 KB on disk, ~14 MB of memory, 0% CPU when idle; it only watches input while locked
- Unlocks automatically when the Mac locks, sleeps or starts the screensaver, so you can always type your password

## Install

Needs macOS 26 or later and Xcode (or the Command Line Tools).

```sh
git clone https://github.com/lame-o/keyboard-lock.git
cd keyboard-lock
./build.sh --install
```

The first time you turn the lock on, macOS asks you to allow **Accessibility** access for Keyboard Lock in System Settings → Privacy & Security. The build is ad-hoc signed, so after each rebuild you need to allow access again.

## How it works

A single Swift file (`Sources/main.swift`) sets up a `CGEventTap` at the HID level while a lock is on. The tap drops key-down, key-up and modifier events, plus the system-defined events that media keys send. With Trackpad Lock on, it also drops mouse, scroll and gesture events and holds the cursor in place. Turning everything off removes the tap completely. While nothing is locked, the shortcut is a regular system hotkey, which costs nothing.

It can't block the power / Touch ID button, which the system handles itself.

## License

MIT
