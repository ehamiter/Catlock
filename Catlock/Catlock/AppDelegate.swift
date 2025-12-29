import Cocoa

/// AppDelegate manages the menu bar application lifecycle.
/// This is a menu bar–only app (no dock icon, no main window).
///
/// Design decisions:
/// - Uses NSStatusBar for menu bar presence
/// - Catlock state is clearly visible via icon change
/// - Failsafe: Catlock is always disabled on app launch

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // MARK: - Properties
    
    /// Status bar item (menu bar icon)
    private var statusItem: NSStatusItem!
    
    /// The menu shown when clicking the status bar icon
    private var statusMenu: NSMenu!
    
    /// Menu item for toggling Catlock
    private var toggleMenuItem: NSMenuItem!
    
    /// Menu item showing current status
    private var statusMenuItem: NSMenuItem!
    
    /// Reference to EventTapManager
    private let eventTapManager = EventTapManager.shared
    
    // MARK: - Icons (SF Symbols)
    
    /// Icon when Catlock is disabled
    private let iconUnlocked = "cat"
    
    /// Icon when Catlock is enabled
    private let iconLocked = "cat.fill"
    
    // MARK: - App Lifecycle
    
    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Failsafe: ensure Catlock is disabled on launch
        // This prevents being locked out if the app crashed while locked
        
        NSLog("Catlock: applicationDidFinishLaunching called")
        
        setupStatusBar()
        setupEventTap()
        
        NSLog("Catlock started. Use Escape + Delete to toggle.")
        NSLog("Failsafe: Fn + Escape ALWAYS unlocks")
    }
    
    @MainActor
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up: ensure Catlock is disabled and tap is stopped
        eventTapManager.stopEventTap()
    }
    
    // MARK: - Status Bar Setup
    
    @MainActor
    private func setupStatusBar() {
        NSLog("Catlock: Setting up status bar")
        
        // Create status bar item with variable width
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set initial icon using SF Symbol
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: iconUnlocked, accessibilityDescription: "Catlock")
            button.image?.isTemplate = true
            button.toolTip = "Catlock - Click for options"
            NSLog("Catlock: Status bar button configured")
        } else {
            NSLog("Catlock: WARNING - Status bar button is nil")
        }
        
        // Create menu
        statusMenu = NSMenu()
        
        // Status display (disabled, just for info)
        statusMenuItem = NSMenuItem(title: "Status: Unlocked", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenu.addItem(statusMenuItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Toggle item with SF Symbol icon
        toggleMenuItem = NSMenuItem(
            title: "Enable Catlock",
            action: #selector(toggleCatLock),
            keyEquivalent: ""
        )
        toggleMenuItem.target = self
        toggleMenuItem.image = NSImage(systemSymbolName: iconLocked, accessibilityDescription: nil)
        statusMenu.addItem(toggleMenuItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Hotkey help
        let hotkeyHelp = NSMenuItem(title: "Toggle: Esc + Delete", action: nil, keyEquivalent: "")
        hotkeyHelp.isEnabled = false
        statusMenu.addItem(hotkeyHelp)
        
        let escapeHelp = NSMenuItem(title: "Emergency: Fn + Escape", action: nil, keyEquivalent: "")
        escapeHelp.isEnabled = false
        statusMenu.addItem(escapeHelp)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Timeout setting
        let timeoutItem = NSMenuItem(
            title: "Auto-timeout: 10 min",
            action: nil,
            keyEquivalent: ""
        )
        timeoutItem.isEnabled = false
        statusMenu.addItem(timeoutItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // Quit item
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        statusMenu.addItem(quitItem)
        
        statusItem.menu = statusMenu
        NSLog("Catlock: Menu bar setup complete")
    }
    
    // MARK: - Event Tap Setup
    
    @MainActor
    private func setupEventTap() {
        NSLog("Catlock: Setting up event tap")
        
        // Check for Accessibility permissions
        if !eventTapManager.checkAccessibilityPermissions() {
            NSLog("Catlock: No accessibility permissions")
            showAccessibilityAlert()
            return
        }
        
        NSLog("Catlock: Accessibility permissions OK")
        
        // Start the event tap
        if !eventTapManager.startEventTap() {
            NSLog("Catlock: Failed to start event tap")
            showEventTapFailedAlert()
            return
        }
        
        NSLog("Catlock: Event tap started successfully")
        
        // Listen for lock state changes
        eventTapManager.onLockStateChanged = { [weak self] isLocked in
            self?.updateUI(isLocked: isLocked)
        }
    }
    
    // MARK: - UI Updates
    
    @MainActor
    private func updateUI(isLocked: Bool) {
        // Update menu bar icon using SF Symbol
        if let button = self.statusItem.button {
            let symbolName = isLocked ? self.iconLocked : self.iconUnlocked
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Catlock")
            button.image?.isTemplate = true
        }
        
        // Update toggle menu item with SF Symbol icon
        let toggleSymbol = isLocked ? iconUnlocked : iconLocked
        toggleMenuItem.image = NSImage(systemSymbolName: toggleSymbol, accessibilityDescription: nil)
        toggleMenuItem.title = isLocked ? "Disable Catlock" : "Enable Catlock"
        
        // Update status text
        statusMenuItem.title = isLocked ? "Status: LOCKED" : "Status: Unlocked"
    }
    
    // MARK: - Actions
    
    @MainActor
    @objc private func toggleCatLock() {
        eventTapManager.toggleLock()
    }
    
    @MainActor
    @objc private func quitApp() {
        // Ensure we're unlocked before quitting
        if eventTapManager.isLocked {
            eventTapManager.toggleLock()
        }
        eventTapManager.stopEventTap()
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - Alerts
    
    @MainActor
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Catlock needs Accessibility permission to intercept keyboard and mouse input.
            
            Please go to:
            System Settings → Privacy & Security → Accessibility
            
            Then add and enable Catlock.
            
            After granting permission, please restart the app.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Continue Anyway")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Open Accessibility settings
            eventTapManager.promptForAccessibilityPermissions()
        }
        
        // Update menu to show permission needed
        statusMenuItem.title = "⚠️ Permission Required"
        toggleMenuItem.title = "Grant Permission..."
        toggleMenuItem.action = #selector(openAccessibilitySettings)
    }
    
    @MainActor
    @objc private func openAccessibilitySettings() {
        eventTapManager.promptForAccessibilityPermissions()
    }
    
    @MainActor
    private func showEventTapFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Failed to Start Event Tap"
        alert.informativeText = """
            Could not create the event tap. This usually means:
            
            1. Accessibility permission is not granted
            2. Another app is blocking event taps
            3. System security settings are preventing access
            
            Please check System Settings → Privacy & Security → Accessibility
            """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Continue Anyway")
        
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            eventTapManager.promptForAccessibilityPermissions()
        }
        
        // Update menu to show permission needed
        statusMenuItem.title = "⚠️ Permission Required"
        toggleMenuItem.title = "Grant Permission..."
        toggleMenuItem.action = #selector(openAccessibilitySettings)
    }
}
