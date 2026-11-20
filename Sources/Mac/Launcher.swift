import AppKit
import SwiftUI

@main enum Launcher {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = GameDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor private final class GameDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(), application = NSMenuItem()
        menu.addItem(application)
        let actions = NSMenu()
        actions.addItem(withTitle: "Quit Bannerfall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = actions
        let edit = NSMenuItem(); menu.addItem(edit)
        let editing = NSMenu(title: "Edit")
        editing.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editing.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editing.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editing.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editing; NSApp.mainMenu = menu
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width:1280,height:800)
        let width = min(1160,screen.width-36), height = min(760,screen.height-38)
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),
                              styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "Bannerfall"
        window.minSize = NSSize(width:900,height:650)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:GameView(game:GameStore()))
        window.center(); window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps:true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
