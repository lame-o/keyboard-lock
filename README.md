# Keyboard Lock

A tiny macOS menu bar app that ignores every key press while the screen keeps playing. Made for cats who walk across laptops during cat videos.

- Blocks all keys, including Space, Escape, media/volume/brightness keys, Caps Lock, fn/Globe and ⌘Tab
- Leaves the screen, trackpad and mouse working, so you unlock it from the menu bar
- Native look: a Wi-Fi-style switch in the menu, and a glass HUD when you lock or unlock
- About 450 KB on disk, ~14 MB of memory, 0% CPU when idle; it only watches the keyboard while locked
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

A single Swift file (`Sources/main.swift`) sets up a `CGEventTap` at the HID level while the lock is on. The tap drops key-down, key-up and modifier events, plus the system-defined events that media keys send. Turning the lock off removes the tap completely.

It can't block the power / Touch ID button, which the system handles itself.

## License

MIT
