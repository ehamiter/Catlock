import Cocoa
import Carbon.HIToolbox

/// EventTapManager handles all CGEventTap operations for Catlock.
/// It intercepts keyboard, mouse, and scroll events system-wide.
///
/// Key design decisions:
/// - Uses CGEventTapCreate with kCGHIDEventTap to intercept events at the lowest level
/// - Runs on a dedicated CFRunLoop thread to avoid blocking the main thread
/// - Toggle hotkey (Escape + Delete) is checked BEFORE blocking, ensuring it always works
/// - Fn + Escape ALWAYS forces unlock as a failsafe
///
/// Accessibility permission is required because CGEventTap needs to intercept
/// events from other applications. Without this permission, the tap won't receive events.

final class EventTapManager {
    
    // MARK: - Singleton
    static let shared = EventTapManager()
    
    // MARK: - Properties
    
    /// Whether Catlock is currently active (blocking input)
    private(set) var isLocked = false
    
    /// Callback when lock state changes
    var onLockStateChanged: ((Bool) -> Void)?
    
    /// Auto-timeout timer (optional safety feature)
    private var timeoutTimer: Timer?
    
    /// Auto-timeout duration in seconds (0 = disabled)
    var autoTimeoutSeconds: TimeInterval = 600 // 10 minutes default
    
    // MARK: - Event Tap
    
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    
    // MARK: - Keycodes
    
    /// Escape key - Keycode 53
    fileprivate let escapeKeycode: CGKeyCode = 53
    
    /// Delete/Backspace key - Keycode 51
    fileprivate let deleteKeycode: CGKeyCode = 51
    
    /// Track if escape is currently held down
    fileprivate var isEscapeHeld = false
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Check if we have Accessibility permissions
    func checkAccessibilityPermissions() -> Bool {
        let trusted = AXIsProcessTrusted()
        return trusted
    }
    
    /// Prompt user to grant Accessibility permissions
    func promptForAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    
    /// Start the event tap (must have Accessibility permissions first)
    func startEventTap() -> Bool {
        guard eventTap == nil else { return true }
        
        // Events we want to intercept
        var eventMask: CGEventMask = 0
        
        // Keyboard events
        eventMask |= (1 << CGEventType.keyDown.rawValue)
        eventMask |= (1 << CGEventType.keyUp.rawValue)
        eventMask |= (1 << CGEventType.flagsChanged.rawValue)
        
        // Mouse movement
        eventMask |= (1 << CGEventType.mouseMoved.rawValue)
        
        // Left mouse button
        eventMask |= (1 << CGEventType.leftMouseDown.rawValue)
        eventMask |= (1 << CGEventType.leftMouseUp.rawValue)
        eventMask |= (1 << CGEventType.leftMouseDragged.rawValue)
        
        // Right mouse button
        eventMask |= (1 << CGEventType.rightMouseDown.rawValue)
        eventMask |= (1 << CGEventType.rightMouseUp.rawValue)
        eventMask |= (1 << CGEventType.rightMouseDragged.rawValue)
        
        // Other mouse buttons
        eventMask |= (1 << CGEventType.otherMouseDown.rawValue)
        eventMask |= (1 << CGEventType.otherMouseUp.rawValue)
        eventMask |= (1 << CGEventType.otherMouseDragged.rawValue)
        
        // Scroll wheel
        eventMask |= (1 << CGEventType.scrollWheel.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Catlock: Failed to create event tap")
            return false
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        tapThread = Thread { [weak self] in
            guard let self = self, let source = self.runLoopSource else { return }
            
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            CFRunLoopRun()
        }
        tapThread?.name = "EventTapThread"
        tapThread?.start()
        
        NSLog("Catlock: Event tap started")
        return true
    }
    
    /// Stop the event tap
    func stopEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
        }
        
        tapThread?.cancel()
        
        eventTap = nil
        runLoopSource = nil
        tapThread = nil
        
        if isLocked {
            forceUnlock()
        }
        
        NSLog("Catlock: Event tap stopped")
    }
    
    /// Toggle Catlock on/off
    func toggleLock() {
        isLocked.toggle()
        
        if isLocked {
            startAutoTimeout()
        } else {
            cancelAutoTimeout()
        }
        
        notifyStateChange()
        NSLog("Catlock: Toggled to \(isLocked ? "LOCKED" : "UNLOCKED")")
    }
    
    /// Force unlock - ALWAYS unlocks, used by Fn+Escape failsafe
    fileprivate func forceUnlock() {
        NSLog("Catlock: FORCE UNLOCK triggered")
        isLocked = false
        isEscapeHeld = false
        cancelAutoTimeout()
        notifyStateChange()
    }
    
    private func notifyStateChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.onLockStateChanged?(self.isLocked)
        }
    }
    
    // MARK: - Auto Timeout
    
    private func startAutoTimeout() {
        cancelAutoTimeout()
        
        guard autoTimeoutSeconds > 0 else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.timeoutTimer = Timer.scheduledTimer(withTimeInterval: self.autoTimeoutSeconds, repeats: false) { [weak self] _ in
                guard let self = self, self.isLocked else { return }
                NSLog("Catlock: Auto-timeout triggered")
                self.forceUnlock()
            }
        }
    }
    
    private func cancelAutoTimeout() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
}

// MARK: - Event Tap Callback

private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    
    // Handle tap disabled events
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passRetained(event)
    }
    
    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }
    
    let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
    
    // CRITICAL: Check for Fn+Escape FIRST - this ALWAYS unlocks
    if type == .keyDown {
        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Fn + Escape = ALWAYS force unlock
        if keycode == manager.escapeKeycode && flags.contains(.maskSecondaryFn) {
            manager.forceUnlock()
            return nil
        }
    }
    
    // Track escape key state for Escape+Delete hotkey
    if type == .keyDown || type == .keyUp {
        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        
        if keycode == manager.escapeKeycode {
            manager.isEscapeHeld = (type == .keyDown)
        }
        
        // Check for Escape + Delete toggle hotkey
        if keycode == manager.deleteKeycode && type == .keyDown && manager.isEscapeHeld {
            manager.toggleLock()
            return nil
        }
    }
    
    // If not locked, pass all events through normally
    guard manager.isLocked else {
        return Unmanaged.passRetained(event)
    }
    
    // === CAT LOCK IS ENABLED - BLOCK EVENTS ===
    
    switch type {
    case .keyDown, .keyUp, .flagsChanged:
        return nil
        
    case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
        return nil
        
    case .leftMouseDown, .leftMouseUp,
         .rightMouseDown, .rightMouseUp,
         .otherMouseDown, .otherMouseUp:
        return nil
        
    case .scrollWheel:
        return nil
        
    default:
        return Unmanaged.passRetained(event)
    }
}
