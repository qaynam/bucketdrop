//
//  BucketDropApp.swift
//  BucketDrop
//
//  Created by Fayaz Ahmed Aralikatti on 12/01/26.
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Popover Background View
class PopoverBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.set()
        dirtyRect.fill()
    }
}

@main
struct BucketDropApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([UploadedFile.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
        .modelContainer(sharedModelContainer)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var modelContainer: ModelContainer?
    var settingsWindow: NSWindow?
    var errorDetailWindow: NSWindow?
    var toastWindow: NSWindow?
    var popoverBackgroundView: PopoverBackgroundView?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Setup model container
        let schema = Schema([UploadedFile.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        modelContainer = try? ModelContainer(for: schema, configurations: [modelConfiguration])
        
        // Setup status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "BucketDrop")
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Setup popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .semitransient
        popover?.animates = true
        
        let contentView = ContentView()
            .modelContainer(modelContainer!)
            .environment(\.openSettingsAction, OpenSettingsAction { [weak self] in
                self?.openSettings()
            })
            .environment(\.openErrorDetailAction, OpenErrorDetailAction { [weak self] message in
                self?.openErrorDetail(message)
            })
            .environment(\.showToastAction, ShowToastAction { [weak self] message in
                self?.showToast(message)
            })
        popover?.contentViewController = NSHostingController(rootView: contentView)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Clean up the temporary cache folder used by older versions (and any scratch files)
        let cacheDir = FileManager.default.temporaryDirectory.appendingPathComponent("BucketDrop")
        try? FileManager.default.removeItem(at: cacheDir)
    }

    @objc func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            
            // Add solid white background to popover (including the arrow/notch)
            if let contentView = popover.contentViewController?.view,
               let frameView = contentView.window?.contentView?.superview {
                // Check if background view already exists
                if popoverBackgroundView == nil || popoverBackgroundView?.superview == nil {
                    let bgView = PopoverBackgroundView(frame: frameView.bounds)
                    bgView.autoresizingMask = [.width, .height]
                    frameView.addSubview(bgView, positioned: .below, relativeTo: frameView)
                    popoverBackgroundView = bgView
                }
            }
        }
    }
    
    func openSettings() {
        // Close popover first
        popover?.performClose(nil)
        
        // Check if settings window already exists
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create settings window
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        
        let window = NSWindow(contentViewController: hostingController)
        window.title = "BucketDrop Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        
        // Center the window on screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
        
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openErrorDetail(_ message: String) {
        // Reuse the existing window if it's still open
        if let window = errorDetailWindow, window.isVisible {
            window.contentViewController = NSHostingController(rootView: ErrorDetailView(message: message))
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingController = NSHostingController(rootView: ErrorDetailView(message: message))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Error Details"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowSize = window.frame.size
            let x = screenFrame.origin.x + (screenFrame.width - windowSize.width) / 2
            let y = screenFrame.origin.y + (screenFrame.height - windowSize.height) / 2
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        errorDetailWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showToast(_ message: String) {
        // Replace any existing toast
        toastWindow?.close()
        toastWindow = nil

        let hosting = NSHostingView(rootView: ToastView(message: message))
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Must be false: we manage the window's lifetime via `toastWindow` (ARC).
        // Leaving the default (true) causes a release-on-close double-free → EXC_BAD_ACCESS.
        window.isReleasedWhenClosed = false
        window.level = .statusBar
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = hosting

        // Position near the bottom-center of the active screen (Raycast-style)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.midX - size.width / 2
            let y = visible.minY + 100
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.alphaValue = 0
        window.orderFrontRegardless()
        toastWindow = window

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 1
        }

        // Auto-dismiss after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, self.toastWindow == window else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                window.animator().alphaValue = 0
            }, completionHandler: {
                window.close()
                if self.toastWindow == window {
                    self.toastWindow = nil
                }
            })
        }
    }
}

// Custom environment key for opening settings
struct OpenSettingsAction {
    let action: () -> Void
    
    func callAsFunction() {
        action()
    }
}

struct OpenSettingsActionKey: EnvironmentKey {
    static let defaultValue = OpenSettingsAction { }
}

// Custom environment key for opening the error detail window
struct OpenErrorDetailAction {
    let action: (String) -> Void

    func callAsFunction(_ message: String) {
        action(message)
    }
}

struct OpenErrorDetailActionKey: EnvironmentKey {
    static let defaultValue = OpenErrorDetailAction { _ in }
}

// Custom environment key for showing a toast
struct ShowToastAction {
    let action: (String) -> Void

    func callAsFunction(_ message: String) {
        action(message)
    }
}

struct ShowToastActionKey: EnvironmentKey {
    static let defaultValue = ShowToastAction { _ in }
}

extension EnvironmentValues {
    var openSettingsAction: OpenSettingsAction {
        get { self[OpenSettingsActionKey.self] }
        set { self[OpenSettingsActionKey.self] = newValue }
    }

    var openErrorDetailAction: OpenErrorDetailAction {
        get { self[OpenErrorDetailActionKey.self] }
        set { self[OpenErrorDetailActionKey.self] = newValue }
    }

    var showToastAction: ShowToastAction {
        get { self[ShowToastActionKey.self] }
        set { self[ShowToastActionKey.self] = newValue }
    }
}
