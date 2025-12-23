# Catlock

![Catlock](catlock.png)

A macOS menu bar utility that blocks all keyboard and mouse input—perfect for when your cat decides to take a nap on your keyboard.

## Download

**[Download Catlock v1.0.0](https://github.com/ehamiter/Catlock/releases/tag/v1.0.0)**

## Features

- **Complete input blocking**: Blocks keyboard, mouse, trackpad, and scroll wheel
- **Menu bar only**: No dock icon, minimal footprint
- **Safe toggle hotkey**: `Escape` + `Delete` (hard for cats to press)
- **Emergency unlock**: `Fn` + `Escape` **always** unlocks, no matter what
- **Auto-timeout**: Automatically unlocks after 10 minutes (safety feature)
- **Failsafe**: Always starts unlocked, even after crashes

## Installation

1. Download and unzip `Catlock.zip` from the [latest release](https://github.com/ehamiter/Catlock/releases/tag/v1.0.0)
2. Move `Catlock.app` to Applications
3. Launch and grant **Accessibility** permission when prompted
4. Restart the app after granting permission

> **Note**: The app is signed and notarized by Apple, so it should open without any Gatekeeper warnings.

## Permissions

Catlock requires **Accessibility** permission to intercept input events.

On first launch:
1. You'll see a permission prompt
2. Go to **System Settings → Privacy & Security → Accessibility**
3. Enable **Catlock** in the list
4. Restart the app

> **Why Accessibility?** CGEventTap requires this permission to intercept events from other applications. Without it, the app cannot block input.

## Usage

### Hotkeys

| Action | Hotkey |
|--------|--------|
| Toggle lock | `Escape` + `Delete` |
| **Emergency unlock** | `Fn` + `Escape` (always works) |

### Menu Bar
Click the cat icon in the menu bar to enable/disable Catlock.

### Visual Indicators (SF Symbols)
- Cat outline = Unlocked (normal operation)
- Filled cat = Locked (input blocked)

## Testing Safely

1. Launch the app (you'll see a cat icon in the menu bar)
2. Open a text editor
3. Press `Escape` + `Delete` to enable Catlock
4. Try typing—nothing should happen
5. Press `Escape` + `Delete` again to disable
6. Verify typing works again

**Tip**: If anything goes wrong, `Fn` + `Escape` will always unlock.

## Requirements

- macOS 13 Ventura or later
- Accessibility permission

## Building from Source

1. Open `Catlock/Catlock.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run (⌘R)

## Technical Details

### Event Types Blocked
- Keyboard: `keyDown`, `keyUp`, `flagsChanged`
- Mouse: `mouseMoved`, all click events, drag events
- Scroll: `scrollWheel`

### Architecture
- `EventTapManager.swift`: CGEventTap handling, hotkey detection
- `AppDelegate.swift`: Menu bar UI, app lifecycle
- `Info.plist`: LSUIElement (menu bar only), accessibility description
- `main.swift`: App entry point with MainActor isolation

### Security Notes
- Signed and notarized by Apple
- App Sandbox is **disabled** (required for CGEventTap)
- Hardened Runtime is enabled
- No private APIs used
- Distributed outside Mac App Store

## Troubleshooting

### "Failed to create event tap"
- Ensure Accessibility permission is granted
- Restart the app after granting permission
- Check System Settings → Privacy & Security → Accessibility

### Hotkey not working
- Use the failsafe: `Fn` + `Escape`
- Check if another app is capturing these keys
- Relaunch the app

### Stuck in locked state
1. Press `Fn` + `Escape` (always works)
2. Wait 10 minutes (auto-timeout)
3. If all else fails: hold power button to restart

## License

MIT
